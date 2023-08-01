import RealityKit
import ARKit
import Foundation

/// /Documents/hogeディレクトリ内の操作用
struct HogeFileOperator {
    private let fileManager = FileManager.default
    private let rootDirectory = NSHomeDirectory() + "/Documents/"

    init() {
        createDirectory(atPath: "")// ルートディレクトリを作成する
    }

    private func convertPath(_ path: String) -> String {
        if path.hasPrefix("/") {
            return rootDirectory + path
        }
        return rootDirectory + "/" + path
    }

    // ディレクトリを作成する
    func createDirectory(atPath path: String) {
        if fileExists(atPath: path) {
            return
        }
        do {
           try fileManager.createDirectory(atPath: convertPath(path), withIntermediateDirectories: false, attributes: nil)
        } catch let error {
            print(error.localizedDescription)
        }
    }

    // ファイル作成
    func createFile(atPath path: String, contents: Data?) {
        if !fileManager.createFile(atPath: convertPath(path), contents: contents, attributes: nil) {
            print("Create file error")
        }
    }

    //ファイル存在確認
    func fileExists(atPath path: String) -> Bool {
        return fileManager.fileExists(atPath: convertPath(path))
    }

    // 対象パスがディレクトリか確認
    func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: convertPath(path), isDirectory: &isDirectory)
        return isDirectory.boolValue
    }

    // ファイルを移動
    func moveItem(atPath srcPath: String, toPath dstPath: String) {
        // 移動先に同名ファイルが存在する場合はエラー
        do {
           try fileManager.moveItem(atPath: convertPath(srcPath), toPath: convertPath(dstPath))
        } catch let error {
            print(error.localizedDescription)
        }
    }

    // ファイルをコピーする
    func copyItem(atPath srcPath: String, toPath dstPath: String) {
        // コピー先に同名ファイルが存在する場合はエラー
        do {
           try fileManager.copyItem(atPath: convertPath(srcPath), toPath: convertPath(dstPath))
        } catch let error {
            print(error.localizedDescription)
        }
    }

    // ファイルを削除
    func removeItem(atPath path: String) {
        do {
           try fileManager.removeItem(atPath: convertPath(path))
        } catch let error {
            print(error.localizedDescription)
        }
    }

    // ファイルをリネーム
    func renameItem(atPath path: String, to newName: String) {
        let srcPath = path
        let dstPath = NSString(string: NSString(string: srcPath).deletingLastPathComponent).appendingPathComponent(newName)
        moveItem(atPath: srcPath, toPath: dstPath)
    }

    // ディレクトリ内のアイテムのパスを取得
    func contentsOfDirectory(atPath path: String) -> [String] {
        do {
           return try fileManager.contentsOfDirectory(atPath: convertPath(path))
        } catch let error {
            print(error.localizedDescription)
            return []
        }
    }

    // ディレクトリ内のアイテムのパスを再帰的に取得
    func subpathsOfDirectory(atPath path: String) -> [String] {
        do {
           return try fileManager.subpathsOfDirectory(atPath: convertPath(path))
        } catch let error {
            print(error.localizedDescription)
            return []
        }
    }

    // ファイル情報を取得
    func attributesOfItem(atPath path: String) -> [FileAttributeKey : Any] {
        do {
           return try fileManager.attributesOfItem(atPath: convertPath(path))
        } catch let error {
            print(error.localizedDescription)
            return [:]
        }
    }
}

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var hideMeshButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!
    @IBOutlet weak var planeDetectionButton: UIButton!
    
    let coachingOverlay = ARCoachingOverlayView()
    
    // Cache for 3D text geometries representing the classification values.
    var modelsForClassification: [ARMeshClassification: ModelEntity] = [:]
    
    /// - Tag: ViewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        arView.session.delegate = self
        
        setupCoachingOverlay()
        
        arView.environment.sceneUnderstanding.options = []
        
        // Turn on occlusion from the scene reconstruction's mesh.
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        
        // Turn on physics for the scene reconstruction's mesh.
        arView.environment.sceneUnderstanding.options.insert(.physics)
        
        // Display a debug visualization of the mesh.
        arView.debugOptions.insert(.showSceneUnderstanding)
        
        // For performance, disable render options that are not required for this app.
        arView.renderOptions = [.disablePersonOcclusion, .disableDepthOfField, .disableMotionBlur]
        
        // Manually configure what kind of AR session to run since
        // ARView on its own does not turn on mesh classification.
        arView.automaticallyConfigureSession = false//ARセッションを手動設定モードに変更しないようにする．
        let configuration = ARWorldTrackingConfiguration()//ARコンテンツインスタンス生成．
        configuration.sceneReconstruction = .meshWithClassification//シーン再構築オプションを設定
        
        configuration.environmentTexturing = .automatic
        arView.session.run(configuration)//ARセッションを開始
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))//タップ時に呼び出す関数設定
        arView.addGestureRecognizer(tapRecognizer)
    }
    
    //デバイスがスリープ状態になるのを防ぐ
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Prevent the screen from being dimmed to avoid interrupting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    //ホームインジケータを自動的に非表示にする
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
    
    //ステータスバーを非表示にする
    override var prefersStatusBarHidden: Bool {
        return true
    }
    

    //タップ時に実行される関数
    @objc
    func handleTap(_ sender: UITapGestureRecognizer) {
        let tapLocation = sender.location(in: arView)//ユーザーがタップした場所（2Dの画面座標）を取得
        
        //ユーザーがタップした位置からのレイキャストを実行．タップ位置からの最近傍面(ポリゴン)取得
        if let result = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any).first {
            print(result)
            let resultAnchor = AnchorEntity(world: result.worldTransform)//ARアンカー作成
            resultAnchor.addChild(sphere(radius: 0.01, color: .lightGray))
            arView.scene.addAnchor(resultAnchor, removeAfter: 3)//アンカーをARシーンに追加
            
            //非同期処理
            nearbyFaceWithClassification(to: result.worldTransform.position) { (centerOfFace, classification, NMeshPos) in
                DispatchQueue.main.async {
                    //テキスト設置3D座標計算
                    let rayDirection = normalize(result.worldTransform.position - self.arView.cameraTransform.translation)
                    let textPositionInWorldCoordinates = result.worldTransform.position - (rayDirection * 0.1)
                    
                    //メッシュ面の分類結果を表示するための3Dテキストを作成
                    let textEntity = self.model(for: classification)
                    
                    //テキストのサイズ調整
                    let raycastDistance = distance(result.worldTransform.position, self.arView.cameraTransform.translation)
                    textEntity.scale = .one * raycastDistance
                    
                    //計算した位置にテキストを配置
                    var resultWithCameraOrientation = self.arView.cameraTransform
                    resultWithCameraOrientation.translation = textPositionInWorldCoordinates
                    let textAnchor = AnchorEntity(world: resultWithCameraOrientation.matrix)
                    textAnchor.addChild(textEntity)
                    self.arView.scene.addAnchor(textAnchor, removeAfter: 3)
                    
                    //タップされた面の中心を視覚化
                    if let centerOfFace = centerOfFace {
                        print(centerOfFace)
                        print(type(of: centerOfFace))
                        let faceAnchor = AnchorEntity(world: centerOfFace)
                        faceAnchor.addChild(self.sphere(radius: 0.01, color: classification.color))
                        self.arView.scene.addAnchor(faceAnchor, removeAfter: 3)
                    }
                    
                    //タップした位置に一番近い面の3頂点に赤い球を置く．
                    for vertex in NMeshPos {
                        let faceAnchor = AnchorEntity(world: vertex)
                        faceAnchor.addChild(self.sphere(radius: 0.005, color: .red))
                        self.arView.scene.addAnchor(faceAnchor, removeAfter: 3)
                    }
                }
            }
        }
    }
    
    //リセットボタンの関数設定
    @IBAction func resetButtonPressed(_ sender: Any) {
        if let configuration = arView.session.configuration {
            arView.session.run(configuration, options: .resetSceneReconstruction)
        }
    }
    
    //メッシュ表示切替ボタンの関数設定
    @IBAction func toggleMeshButtonPressed(_ button: UIButton) {
        let isShowingMesh = arView.debugOptions.contains(.showSceneUnderstanding)
        if isShowingMesh {
            arView.debugOptions.remove(.showSceneUnderstanding)
            button.setTitle("Show Mesh", for: [])
        } else {
            arView.debugOptions.insert(.showSceneUnderstanding)
            button.setTitle("Hide Mesh", for: [])
        }
    }

    //点，面，法線のリストを生成，ワールド座標で取得
    func generateGeometryData_world(anchor: ARMeshAnchor, completion: @escaping ([SIMD3<Float>], [[UInt32]], [SIMD3<Float>]) -> Void) {
        
        var verticesList = [SIMD3<Float>]()//点リスト初期化
        var facesList = [[UInt32]]()//面リスト初期化
        var normalsList = [SIMD3<Float>]()//法線リスト
        
        // ARMeshGeometryの取得
        let geometry = anchor.geometry
        DispatchQueue.main.async {
            // 頂点情報の取得
            let vertices = geometry.vertices
            print("点数:\(vertices.count)")
            for index in 0..<vertices.count{
                let vertex_pos = geometry.vertex(at: UInt32(index))
                
                //SIMD3<Float>のワールド座標に変換
                var LocalTransform = matrix_identity_float4x4
                LocalTransform.columns.3 = SIMD4<Float>(vertex_pos.0, vertex_pos.1, vertex_pos.2, 1)//SIMD3<Float>に変換
                let WorldPosition = (anchor.transform * LocalTransform).position//ワールド座標に変換
                verticesList.append(WorldPosition)
            }
            
            //面リスト生成
            let faces = geometry.faces
            print("面数:\(faces.count)")
            for index in 0..<faces.count {
                var face_point_index = geometry.vertexIndicesOf(faceWithIndex: index)//面を構成する3頂点を取得
                facesList.append(face_point_index)
            }

            //点法線リスト生成
            let normals = geometry.normals//点の法線
            print("点法線数:\(normals.count)")
            for index in 0..<normals.count {
                let normalPointer = normals.buffer.contents().advanced(by: normals.offset + (normals.stride * index))
                let normal = normalPointer.assumingMemoryBound(to: (simd_float3).self).pointee
                
                //SIMD3<Float>のワールド座標に変換
                var LocalTransform = matrix_identity_float4x4
                LocalTransform.columns.3 = SIMD4<Float>(normal.x, normal.y, normal.z, 1)//SIMD3<Float>に変換
                let WorldPosition = (anchor.transform * LocalTransform).position//ワールド座標に変換

                normalsList.append(WorldPosition)
            }
            completion(verticesList, facesList, normalsList)
        }
    }
    
    //objファイルを出力
    func exportOBJ(verticesList: [SIMD3<Float>], to path: String) {
        var objFileContent = ""
        
        // 頂点座標記述
        for vertex in verticesList {
            objFileContent += "v \(vertex.x) \(vertex.y) \(vertex.z)\n"
        }

        // objファイル出力
        do {
            try objFileContent.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write OBJ file: \(error)")
        }
    }
    
    // .objFileを出力するボタン設定
    @IBOutlet weak var exportButton: UIButton!
    
    //  .objFileを出力するボタン設定
    @IBAction func exportButtonPressed(_ sender: Any) {
        guard let frame = arView.session.currentFrame else { return }
        let meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor })//最適化されたメッシュデータ取得
        
        //フォルダ操作
        let hoge = HogeFileOperator()
        print("フォルダ削除")
        hoge.removeItem(atPath: "ObjFile")//ファイル・フォルダ削除
        print("フォルダ作成")
        hoge.createDirectory(atPath: "ObjFile")//フォルダ作成
        
        //全点が入るリスト
        var all_vertex = [SIMD3<Float>]()//点リスト初期化
        // 分類ごとのリスト準備
        var classifications: [String: [SIMD3<Float>]] = [
            "Ceiling": [],
            "Door": [],
            "Floor": [],
            "Seat": [],
            "Table": [],
            "Wall": [],
            "Window": [],
            "None": []
        ]

        // 非同期処理
        DispatchQueue.global().async {
            print("メッシュ数:\(meshAnchors.count)")
            for anchor in meshAnchors {
                let geometry = anchor.geometry
                print("面数:\(geometry.faces.count)")
                
                for index in 0..<geometry.faces.count {
                    let classificationDescription = geometry.classificationOf(faceWithIndex: index).description//分類
                    let localPositionList = geometry.verticesOf(faceWithIndex: index)//面を構成する3頂点の3次元ローカルFloat座標を取得
                    
                    for localPosition in localPositionList {
                        var localTransform = matrix_identity_float4x4
                        localTransform.columns.3 = SIMD4<Float>(localPosition.0, localPosition.1, localPosition.2, 1)
                        let worldPosition = (anchor.transform * localTransform).position//3次元ワールドFloat座標に変換
                        
                        //分類ごとにリストに座標を格納．
                        if let list = classifications[classificationDescription]  {
                            if !list.contains(worldPosition){//すでにリスト内に同じ点がある場合は追加しない
                                classifications[classificationDescription]?.append(worldPosition)
                            }
                        } else {
                            print("分類なし")
                        }
                    }
                }
                
                // 頂点情報の取得，全点取得
                let vertices = geometry.vertices
                for index in 0..<vertices.count{
                    let vertex_pos = geometry.vertex(at: UInt32(index))
                    //SIMD3<Float>のワールド座標に変換
                    var LocalTransform = matrix_identity_float4x4
                    LocalTransform.columns.3 = SIMD4<Float>(vertex_pos.0, vertex_pos.1, vertex_pos.2, 1)//SIMD3<Float>に変換
                    let WorldPosition = (anchor.transform * LocalTransform).position//ワールド座標に変換
                    all_vertex.append(WorldPosition)
                }
            }
            let all_vertex_path = NSHomeDirectory() + "/Documents/ObjFile/allVertex.obj"
            self.exportOBJ(verticesList: all_vertex, to : all_vertex_path)//全てのobjファイル作成
            //分類ごとにobjファイルを出力
            for (classification, positions) in classifications {
                print("Classification: \(classification)")
                let path = NSHomeDirectory() + "/Documents/ObjFile/\(classification).obj"
                print(path)
                self.exportOBJ(verticesList: positions, to : path)//各分類毎にobjファイル作成
                
                let fileManager = FileManager.default
                
                if fileManager.fileExists(atPath: path) {
                    print("File exists")
                } else {
                    print("File does not exist")
                }
            }
        }
    }
    
    //ユーザーが平面検出切替ボタンの関数設定
    @IBAction func togglePlaneDetectionButtonPressed(_ button: UIButton) {
        guard let configuration = arView.session.configuration as? ARWorldTrackingConfiguration else {
            return
        }
        if configuration.planeDetection == [] {
            configuration.planeDetection = [.horizontal, .vertical]
            button.setTitle("Stop Plane Detection", for: [])
        } else {
            configuration.planeDetection = []
            button.setTitle("Start Plane Detection", for: [])
        }
        arView.session.run(configuration)
    }
    
    //最近傍面の3頂点を取得
    func getNeighborhoodMesh(location: SIMD3<Float>, meshAnchors: [ARMeshAnchor])->([SIMD3<Float>]){
        var minDistance: Float = .infinity//最小距離
        var minPos = [SIMD3<Float>(-0.014329165, -0.63967997, -0.43687505), SIMD3<Float>(-0.014545478, -0.6398963, -0.43687665), SIMD3<Float>(-0.014467686, -0.6398963, -0.41866124)]//適当に初期値をいれただけ，意味はない
        
        for anchor in meshAnchors {
            for index in 0..<anchor.geometry.faces.count {
                let geometricCenterOfFace = anchor.geometry.centerOf(faceWithIndex: index)//面の中心座標(3次元Float型)取得
                
                //中心をワールド座標系に変換
                var centerLocalTransform = matrix_identity_float4x4
                centerLocalTransform.columns.3 = SIMD4<Float>(geometricCenterOfFace.0, geometricCenterOfFace.1, geometricCenterOfFace.2, 1)
                let centerWorldPosition = (anchor.transform * centerLocalTransform).position//SIMD3<Float>に変換
                
                //この面の中心とタップされた位置(location)までの距離を計算
                let distanceToFace = distance(centerWorldPosition, location)
                if distanceToFace < minDistance{
                    minDistance = distanceToFace//最小距離更新
                    
                    //面の中心ローカル座標(geometricCenterOfFace)を取得
                    let posVertexOfPolygon = anchor.geometry.verticesOf(faceWithIndex: index)
                    
                    //中心座標をワールド座標系に変換
                    for vertex in 0..<posVertexOfPolygon.count{//ポリゴンの3頂点も変換
                        var posLocalTransform = matrix_identity_float4x4
                        posLocalTransform.columns.3 = SIMD4<Float>(posVertexOfPolygon[vertex].0, posVertexOfPolygon[vertex].1, posVertexOfPolygon[vertex].2, 1)
                        minPos[vertex] = (anchor.transform * posLocalTransform).position
                    }
                }
            }
        }
        return minPos
    }
    
    //分類非同期関数
    func nearbyFaceWithClassification(to location: SIMD3<Float>, completionBlock: @escaping (SIMD3<Float>?, ARMeshClassification, [SIMD3<Float>]) -> Void) {
        guard let frame = arView.session.currentFrame else {
            completionBlock(nil, .none, [])
            return
        }
        
        var meshAnchors = frame.anchors.compactMap({ $0 as? ARMeshAnchor })
        
        //特定の位置から4メートル以上離れたアンカーを除去
        let cutoffDistance: Float = 4.0
        meshAnchors.removeAll { distance($0.transform.position, location) > cutoffDistance }
        meshAnchors.sort { distance($0.transform.position, location) < distance($1.transform.position, location) }
        
        // 非同期処理
        DispatchQueue.global().async {
            let NMeshPos = self.getNeighborhoodMesh(location: location, meshAnchors: meshAnchors)//タップ位置の最近傍面の3頂点座標を取得
            for anchor in meshAnchors {
                for index in 0..<anchor.geometry.faces.count {
                    //面の中心ローカル座標(geometricCenterOfFace)を取得
                    let geometricCenterOfFace = anchor.geometry.centerOf(faceWithIndex: index)
                    //中心をワールド座標系に変換
                    var centerLocalTransform = matrix_identity_float4x4
                    centerLocalTransform.columns.3 = SIMD4<Float>(geometricCenterOfFace.0, geometricCenterOfFace.1, geometricCenterOfFace.2, 1)
                    let centerWorldPosition = (anchor.transform * centerLocalTransform).position//SIMD3<Float>に変換
                    
                    //この面の中心とタップされた位置(location)までの距離を計算
                    let distanceToFace = distance(centerWorldPosition, location)
                    //距離が5cm以内なら，その面の分類(classification)を取得し、この分類と面の中心のワールド座標をコールバック関数で返して処理を終了
                    if distanceToFace <= 0.05 {
                        //選択された面（面がARメッシュ内で何を表しているかを示す）に対応するセマンティックな分類（classification）を取得
                        let classification: ARMeshClassification = anchor.geometry.classificationOf(faceWithIndex: index)
                        completionBlock(centerWorldPosition, classification, NMeshPos)
                        return
                    }
                }
            }
            completionBlock(nil, .none, [])
        }
    }
    
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            // Present an alert informing about the error that has occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetButtonPressed(self)
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func model(for classification: ARMeshClassification) -> ModelEntity {
        // Return cached model if available
        if let model = modelsForClassification[classification] {
            model.transform = .identity
            return model.clone(recursive: true)
        }
        
        // Generate 3D text for the classification
        let lineHeight: CGFloat = 0.05
        let font = MeshResource.Font.systemFont(ofSize: lineHeight)
        let textMesh = MeshResource.generateText(classification.description, extrusionDepth: Float(lineHeight * 0.1), font: font)
        let textMaterial = SimpleMaterial(color: classification.color, isMetallic: true)
        let model = ModelEntity(mesh: textMesh, materials: [textMaterial])
        // Move text geometry to the left so that its local origin is in the center
        model.position.x -= model.visualBounds(relativeTo: nil).extents.x / 2
        // Add model to cache
        modelsForClassification[classification] = model
        return model
    }
    
    func sphere(radius: Float, color: UIColor) -> ModelEntity {
        let sphere = ModelEntity(mesh: .generateSphere(radius: radius), materials: [SimpleMaterial(color: color, isMetallic: false)])
        // Move sphere up by half its diameter so that it does not intersect with the mesh
        sphere.position.y = radius
        return sphere
    }
}
