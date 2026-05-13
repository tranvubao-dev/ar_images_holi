import UIKit
import ARKit
import SceneKit
import Flutter
import AVFoundation

protocol ImageRecognitionDelegate: AnyObject {
    func onRecognitionStarted()
    func onRecognitionPaused()
    func onRecognitionResumed()
    func onDetect(imageKey: String)
    func onDetectedImageTapped(imageKey: String)
}

class ARQuidoViewController: UIViewController {
    
    var sceneView: ARSCNView!
    var currentPlayer: AVQueuePlayer?
    var currentPlayerLooper: AVPlayerLooper?
    var currentImageName: String?
    var videoCache: [String: AVPlayerItem] = [:]
    private var playerCache: [String: AVQueuePlayer] = [:]
    
    let updateQueue = DispatchQueue(
        label: Bundle.main.bundleIdentifier! +
        ".serialSceneKitQueue"
    )
    
    var session: ARSession {
        return sceneView.session
    }
    
    private var wasCameraInitialized = false
    private var isResettingTracking = false
    private let referenceImageNames: Array<String>
    private let referenceImageUrl: Array<String>
    private let server: String
    private let methodChannel: FlutterMethodChannel
    private var detectedImageNode: SCNNode?
    
    init(
        referenceImageNames: Array<String>,
        referenceImageUrl: Array<String>,
        server: String,
        methodChannel channel: FlutterMethodChannel
    ) {
        self.referenceImageNames = referenceImageNames
        self.referenceImageUrl = referenceImageUrl
        self.server = server
        self.methodChannel = channel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        
//        print("ARQuidoViewController DEALLOC")
        
        cleanUpAR()
        
        methodChannel.setMethodCallHandler(nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        methodChannel.setMethodCallHandler(
            handleMethodCall(call:result:)
        )
        
        sceneView = ARSCNView(frame: CGRect.zero)
        
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.preferredFramesPerSecond = 30
        sceneView.rendersContinuously = false
        sceneView.antialiasingMode = .none
        
//        let tapGesture = UITapGestureRecognizer(
//            target: self,
//            action: #selector(handleTap(_:))
//        )
//        
//        sceneView.addGestureRecognizer(tapGesture)
        
        view = sceneView
        
        preloadVideos()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        cleanUpAR()
        
        onRecognitionPaused()
    }
    
    private func preloadVideos() {
        DispatchQueue.global(qos: .background).async {
            
            for imageName in self.referenceImageNames {
                
                let videoName =
                    (imageName as NSString)
                    .deletingPathExtension
                
                guard let url = URL(
                    string:
                        "\(self.server)\(videoName).mp4"
                ) else {
                    continue
                }
                
                let asset = AVURLAsset(url: url)
                
                let item = AVPlayerItem(asset: asset)
                
                self.videoCache[imageName] = item
                
//                print("PRELOADED: \(imageName)")
            }
        }
    }
    
    private func cleanUpAR() {
        
//        print("CLEAN UP AR")
        
        // stop AR session
        sceneView.session.pause()
        
        // stop player
        currentPlayer?.pause()
        
        // remove queue items
        currentPlayer?.removeAllItems()
        
        // release looper
        currentPlayerLooper = nil
        
        // release player
        currentPlayer = nil
        
        // remove node
        detectedImageNode?.removeFromParentNode()
        
        detectedImageNode = nil
        
        // clear scene
        sceneView.scene.rootNode.enumerateChildNodes {
            node,
            _ in
            
            node.removeFromParentNode()
        }
        
        // remove anchors
        for anchor in sceneView.session.currentFrame?.anchors ?? [] {
            sceneView.session.remove(anchor: anchor)
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
//            print(error)
        }
        
//        print("AR CLEANED")
    }
    
//    @objc
//    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
//        
//        let location =
//            gestureRecognize.location(in: sceneView)
//        
//        let hitResults =
//            sceneView.hitTest(location, options: [:])
//        
//        if hitResults.count > 0,
//           let tappedImageName = hitResults[0].node.name {
//            
//            onDetectedImageTapped(imageKey: tappedImageName)
//        }
//    }
    
    // MARK: - Session management (Image detection setup)
    
    /// Prevents restarting the session while a restart is in progress.
    
    var isRestartAvailable = true
    
    func resetTracking() {

        if isResettingTracking {
            return
        }

        isResettingTracking = true

        DispatchQueue.global(qos: .userInitiated).async {

            var referenceImages = [ARReferenceImage]()

            for imagePath in self.referenceImageUrl {

//                print("===================================")
//                print("LOADING LOCAL IMAGE:")
//                print(imagePath)

                let fileManager = FileManager.default

                let exists = fileManager.fileExists(
                    atPath: imagePath
                )

//                print("FILE EXISTS: \(exists)")

                if !exists {
                    continue
                }

                guard let image = UIImage(
                    contentsOfFile: imagePath
                ) else {

//                    print("FAILED TO LOAD UIIMAGE")
                    continue
                }

                guard let cgImage = image.cgImage else {

//                    print("CGIMAGE NIL")
                    continue
                }

//                print("IMAGE SIZE:")
//                print("\(cgImage.width)x\(cgImage.height)")

                if cgImage.width < 100 ||
                    cgImage.height < 100 {

//                    print("IMAGE TOO SMALL")
                    continue
                }

                let referenceImage = ARReferenceImage(
                    cgImage,
                    orientation: .up,
                    physicalWidth: 0.21
                )

                referenceImage.name =
                    URL(fileURLWithPath: imagePath)
                        .lastPathComponent

                referenceImages.append(
                    referenceImage
                )

//                print("IMAGE ADDED SUCCESS")
            }

//            print("===================================")
//            print("TOTAL IMAGES:")
//            print(referenceImages.count)

            if referenceImages.isEmpty {

//                print("NO VALID IMAGES")

                DispatchQueue.main.async {
                    self.isResettingTracking = false
                }

                return
            }

            DispatchQueue.main.async {

                let configuration =
                    ARWorldTrackingConfiguration()

                configuration.detectionImages =
                    Set(referenceImages)

                configuration.maximumNumberOfTrackedImages =
                    1

                self.session.run(
                    configuration,
                    options: [
                        .resetTracking,
                        .removeExistingAnchors
                    ]
                )

//                print("AR SESSION STARTED")

                if !self.wasCameraInitialized {
                    self.onRecognitionStarted()
                    self.wasCameraInitialized = true

                } else {
                    self.onRecognitionResumed()
                }

                self.isResettingTracking = false
            }
        }
    }
    
    
}

extension ARQuidoViewController: ARSCNViewDelegate {
    
    func renderer(
        _ renderer: SCNSceneRenderer,
        didAdd node: SCNNode,
        for anchor: ARAnchor
    ) {
        
        guard let imageAnchor =
            anchor as? ARImageAnchor
        else {
            return
        }
        
        let referenceImage =
            imageAnchor.referenceImage
        
        let imageName =
            referenceImage.name ?? ""
        
        if self.currentImageName == imageName {
            return
        }
        
//        print("IMAGE DETECTED: \(imageName)")
        self.currentImageName = imageName
        
        // clear video cũ
//        DispatchQueue.global(qos: .userInitiated).async {
            
            self.currentPlayer?.pause()
            
            self.currentPlayer?.removeAllItems()
            
            self.currentPlayerLooper = nil
            
            self.currentPlayer = nil
            
            self.detectedImageNode?.removeFromParentNode()
            
            self.detectedImageNode = nil
            
//            let videoName =
//                (imageName as NSString)
//                .deletingPathExtension
            
//            guard let videoURL = URL(
//                string:
//                    "\(self.server)\(videoName).mp4"
//            ) else {
//                
////                print("INVALID VIDEO URL")
//                return
//            }
            
//            print("VIDEO URL: \(videoURL)")
            
            // =========================
            // CREATE LOOP PLAYER
            // =========================
            
            // let playerItem = AVPlayerItem(url: videoURL)
            
            guard let cachedItem =
                self.videoCache[imageName]
            else {
                
//                print("VIDEO NOT PRELOADED")
                return
            }
            
            let playerItem =
                cachedItem.copy() as! AVPlayerItem
            
            let queuePlayer = AVQueuePlayer()
//            let queuePlayer = AVQueuePlayer(playerItem: item)

            
            queuePlayer.automaticallyWaitsToMinimizeStalling = false
            
            self.currentPlayerLooper = AVPlayerLooper(
                player: queuePlayer,
                templateItem: playerItem
            )
            
            self.currentPlayer = queuePlayer
            
            // =========================
            // CREATE VIDEO MATERIAL
            // =========================
            
            let videoScene = SKScene(
                size: CGSize(width: 1280, height: 720)
            )
            
            videoScene.scaleMode = .aspectFit
            
            let videoNode = SKVideoNode(
                avPlayer: queuePlayer
            )
            
            videoNode.position = CGPoint(
                x: videoScene.size.width / 2,
                y: videoScene.size.height / 2
            )
            
            videoNode.size = videoScene.size
            
            // fix video bị ngược
            videoNode.yScale = -1
            
            videoScene.addChild(videoNode)
            
            // =========================
            // CREATE PLANE
            // =========================
            
            let plane = SCNPlane(
                width: referenceImage.physicalSize.width,
                height: referenceImage.physicalSize.height
            )
            
            plane.firstMaterial?.diffuse.contents =
                videoScene
            
            plane.firstMaterial?.isDoubleSided = true
            
            plane.firstMaterial?.lightingModel = .constant
            
            let planeNode = SCNNode(geometry: plane)
            
            planeNode.eulerAngles.x = -.pi / 2
            
            DispatchQueue.main.async {
                
                node.addChildNode(planeNode)
                self.detectedImageNode = planeNode
                queuePlayer.play()
                videoNode.play()
            }
            
//            print("VIDEO PLAYING")
            
            self.onDetect(imageKey: imageName)
//        }
    }
    
    func renderer(
        _ renderer: SCNSceneRenderer,
        didUpdate node: SCNNode,
        for anchor: ARAnchor
    ) {
        
        guard let imageAnchor =
            anchor as? ARImageAnchor
        else {
            return
        }
        
        // đang tracking thì bỏ qua
        
        if imageAnchor.isTracked {
            return
        }
        
//        print("IMAGE LOST")
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            // stop current video
            self.currentPlayer?.pause()
            
//            self.currentPlayer?.removeAllItems()
            
            self.currentPlayerLooper = nil
            
            self.currentPlayer = nil
            
            // remove node
            self.detectedImageNode?.removeFromParentNode()
            
            self.detectedImageNode = nil
            
            // reset image name
            self.currentImageName = nil
            
            // remove old anchor
            self.session.remove(anchor: anchor)
            
//            print("READY TO DETECT AGAIN")
        }
    }
    
    var imageHighlightAction: SCNAction {
        
        return .repeatForever(
            .sequence([
                .wait(duration: 0.25),
                .fadeOpacity(to: 0.85, duration: 0.3),
                .fadeOpacity(to: 0.15, duration: 0.3),
            ])
        )
    }
}

extension ARQuidoViewController: ARSessionDelegate {
    
    func session(
        _ session: ARSession,
        didFailWithError error: Error
    ) {
        
        guard error is ARError else {
            return
        }
        
        let errorWithInfo = error as NSError
        
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        let errorMessage =
            messages.compactMap({ $0 })
            .joined(separator: "\n")
        
        DispatchQueue.global(qos: .userInitiated).async {
            
            self.displayErrorMessage(
                title: "The AR session failed.",
                message: errorMessage
            )
        }
    }
    
    func sessionInterruptionEnded(
        _ session: ARSession
    ) {
        restartExperience()
    }
    
    func sessionShouldAttemptRelocalization(
        _ session: ARSession
    ) -> Bool {
        return true
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(
        title: String,
        message: String
    ) {
        
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        let restartAction = UIAlertAction(
            title: "Restart Session",
            style: .default
        ) { _ in
            
            alertController.dismiss(
                animated: true,
                completion: nil
            )
            
            self.resetTracking()
        }
        
        alertController.addAction(restartAction)
        
        present(
            alertController,
            animated: true,
            completion: nil
        )
    }
    
    // MARK: - Interface Actions
    
    func restartExperience() {
        
        guard isRestartAvailable else {
            return
        }
        
        isRestartAvailable = false
        
        resetTracking()
        
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 5.0
        ) {
            self.isRestartAvailable = true
        }
    }
}

// MARK: PlatformView interface implementation

extension ARQuidoViewController {
    
    private func handleMethodCall(
        call: FlutterMethodCall,
        result: FlutterResult
    ) {
        
        if call.method == "scanner#toggleFlashlight" {
            
            let arguments =
                call.arguments as? Dictionary<String, Any?>
            
            let shouldTurnOn =
                (arguments?["shouldTurnOn"] as? Bool)
                ?? false
            
            toggleFlashlight(shouldTurnOn)
            
            result(nil)
            
        } else {
            
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func toggleFlashlight(
        _ shouldTurnOn: Bool
    ) {
        
        guard let camera =
            AVCaptureDevice.default(
                for: AVMediaType.video
            )
        else {
            return
        }
        
        if camera.hasTorch {
            
            do {
                
                try camera.lockForConfiguration()
                
                camera.torchMode =
                    shouldTurnOn ? .on : .off
                
                camera.unlockForConfiguration()
                
            } catch {
                
//                print("Torch could not be used")
            }
            
        } else {
            
//            print("Torch is not available")
        }
    }
}

extension ARQuidoViewController: ImageRecognitionDelegate {
    
    func onRecognitionPaused() {
        
        methodChannel.invokeMethod(
            "scanner#recognitionPaused",
            arguments: nil
        )
    }
    
    func onRecognitionResumed() {
        
        methodChannel.invokeMethod(
            "scanner#recognitionResumed",
            arguments: nil
        )
    }
    
    func onRecognitionStarted() {
        
        methodChannel.invokeMethod(
            "scanner#start",
            arguments: [String:Any]()
        )
    }
    
    func onDetect(imageKey: String) {
        
        methodChannel.invokeMethod(
            "scanner#onImageDetected",
            arguments: [
                "imageName": imageKey
            ]
        )
    }
    
    func onDetectedImageTapped(imageKey: String) {
        
        methodChannel.invokeMethod(
            "scanner#onDetectedImageTapped",
            arguments: [
                "imageName": imageKey
            ]
        )
    }
}
