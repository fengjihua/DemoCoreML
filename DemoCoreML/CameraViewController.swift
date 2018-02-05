//
//  CameraViewController.swift
//  DemoCoreML
//
//  Created by Michael Feng on 2018/1/27.
//  Copyright © 2018年 FiDensity Inc. All rights reserved.
//

import UIKit
import AVFoundation
import CoreML
import Vision

class CameraViewController: UIViewController {
    
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var labelBlur: UILabel!
    @IBOutlet weak var labelFps: UILabel!
    @IBOutlet weak var labelClassification: UILabel!
    
    /// Data source for the picker.
    let pickerDataSource = PickerDataSource()
    @IBOutlet weak var pickerCloser: UIButton!
    @IBOutlet weak var pickerView: UIPickerView! {
        didSet {
            print("pickerView")
            pickerView.delegate = self
            pickerView.dataSource = pickerDataSource
            
//            pickerView.selectRow(3, inComponent: 0, animated: false)
//            pickerView.selectRow(3, inComponent: 1, animated: false)
        }
    }
    var pipelineVision: Int! = 0
    var pipelineModel: Int! = 0
    var pipelineFpsRun: Bool!
    var pipelineStartTime: Double!
    var pipelineEndTime: Double!
    
    var session: AVCaptureSession!
    var device: AVCaptureDevice!
    var cameraBack: AVCaptureDevice!    // 后置摄像头
    var cameraFront: AVCaptureDevice!   // 前置摄像头
    var input: AVCaptureDeviceInput!
    var output: AVCaptureVideoDataOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var usePreviewLayer: Bool!
    
    var opencv: OpencvViewController!
    var classificationRequest: VNCoreMLRequest!
    var semaphore: DispatchSemaphore!
    
    var thresholdBlur: Int!
    var thresholdPropability: Float!
    var classificationObject: String!
    var thresholdBest: CVPixelBuffer!
    var isBestImageExists: Bool!
    var isYolo: Bool!

    /*
    ** MARK: - Override
     */
    override func viewDidLoad() {
        print("camera viewDidLoad", self.view.frame)
        super.viewDidLoad()
        self.setupPicker()
        self.setupOpenCV()
        self.setupCoreML()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        print("camera viewWillAppear")
        super.viewWillAppear(animated)
        self.setup()
        self.setupView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        print("camera viewDidAppear")
        super.viewDidAppear(animated)
        self.setupCamera()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("camera viewWillDisappear")
        self.session.stopRunning()
        super.viewWillDisappear(animated)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        print("prepare for segue")
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        if segue.identifier == "CameraToBestImage" {
            let controller = segue.destination as! BestImageViewController
            let image = sender as! UIImage
            controller.image = self.fixImageOrientagion(image: image)
        }
    }
    
    /*
     ** MARK: - Setup
     */
    func setup() -> Void {
        self.usePreviewLayer = false
        self.pipelineFpsRun = true
        
        if self.semaphore == nil {
            self.semaphore = DispatchSemaphore(value: 2)
        }
        
        self.thresholdBlur = 40
        self.thresholdPropability = 0.10
        self.classificationObject = "monitor"
        self.isBestImageExists = false
    }
    
    func setupView() -> Void {
        print("setup view")
        self.navigationController?.isNavigationBarHidden = true
        self.imageView.isHidden = self.usePreviewLayer
        self.imageView.contentMode = .scaleAspectFit
    }
    
    func setupPicker() -> Void {
        self.pickerView.isHidden = true
        self.pickerCloser.isHidden = true
    }
    
    func setupOpenCV() -> Void {
        print("setup opencv")
        self.opencv = OpencvViewController()
    }
    
    
    /*
     ** MARK: - Camera
     */
    func setupCamera() -> Void {
        print("setup camera")
        
        // 相机权限
        let authStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch authStatus {
            case .authorized:   // 已经授权
                print("camera authorized")
                self.initCamera()
                break
            
            case .notDetermined:    // 未检测授权，申请权限
                AVCaptureDevice.requestAccess(for: .video, completionHandler: {(granted: Bool) -> Void in
                    print("camera granted: ", granted)
                    if (granted) {
                        // Pipeline
                        self.initCamera()
                    } else {
                        // 退出
                        exit(0)
                    }
                })
                break
            
            case .restricted, .denied:  // 受限或拒绝授权，引导授权
                print("camera restricted or denied")
                let alert = UIAlertController(title: "提示",
                                              message: "摄像头权限未开启",
                                              preferredStyle: UIAlertControllerStyle.alert)
                let cancelAction = UIAlertAction(title: "知道了", style: .cancel, handler: {
                    (action: UIAlertAction) -> Void in
                    /**
                     写取消后操作
                     */
                })
                let okAction = UIAlertAction(title: "去设置", style: .default, handler: {
                    (action: UIAlertAction) -> Void in
                    /**
                     写确定后操作
                     */
                    let settingsURL = URL(string:UIApplicationOpenSettingsURLString)!
                    print(settingsURL)
                    UIApplication.shared.open(settingsURL,
                                              options: [:],
                                              completionHandler: {
                                                (success: Bool) -> Void in
                                                print("open settings:", success)
                    })
                })
                alert.addAction(cancelAction)
                alert.addAction(okAction)
                self.present(alert, animated: true, completion: nil)
                
                break
        }
    }
    
    
    /*
     ** Init Camera
     */
    func initCamera() -> Void {
        print("init camera")
        let devicesIOS10 = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                       mediaType: .video,
                                                       position: AVCaptureDevice.Position.unspecified)
        let devices = devicesIOS10.devices
//        let devices = AVCaptureDevice.devices(for: .video)
        for device in devices {
            if device.position == AVCaptureDevice.Position.back {
                self.cameraBack = device
            }
            else if device.position == AVCaptureDevice.Position.front {
                self.cameraFront = device
            }
        }
        
        
        self.session = AVCaptureSession()
        if (self.usePreviewLayer) {
            self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
            self.previewLayer.videoGravity = AVLayerVideoGravity.resizeAspect
            self.previewLayer.connection?.videoOrientation = .portrait
            self.previewLayer.frame = self.view.bounds
            self.previewLayer.backgroundColor = UIColor.black.cgColor
            self.view.layer.addSublayer(self.previewLayer)
            self.previewLayer.zPosition = -99
        }
        
        self.session.beginConfiguration()
//        self.device = AVCaptureDevice.default(for: AVMediaType.video)
        self.device = self.cameraFront
        self.configCamera()
        self.session.commitConfiguration()
        
        self.session.startRunning()
    }
    
    
    /*
     ** Camera Configuration
     */
    func configCamera() -> Void {
        do {
            try self.device.lockForConfiguration()
            if (self.device.isFocusModeSupported(.continuousAutoFocus)) {
                self.device.focusMode = .continuousAutoFocus
            }
            self.device.whiteBalanceMode = .continuousAutoWhiteBalance
            self.device.unlockForConfiguration()
        } catch let error as NSError {
            print(error)
        }
        
        self.output = AVCaptureVideoDataOutput()
        do {
            try self.input = AVCaptureDeviceInput(device: self.device)
        } catch let error as NSError {
            print(error)
        }
        
        if (self.session.canAddInput(self.input)) {
            self.session.addInput(self.input)
        }
        if (self.session.canAddOutput(self.output)) {
            self.session.addOutput(self.output)
        }
        
        self.session.sessionPreset = AVCaptureSession.Preset.photo
        let queue = DispatchQueue(label: "queue.SampleBuffer")
        self.output.setSampleBufferDelegate(self, queue: queue)
        self.output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)]
        self.output.alwaysDiscardsLateVideoFrames = true
    }
    
    
    /*
     ** Camera Back/Front Switch
     */
    @IBAction func cameraSwitch() -> Void {
        print("camera switch", self.device)
        if self.device == self.cameraFront {
            self.device = self.cameraBack
        }
        else if self.device == self.cameraBack {
            self.device = cameraFront
        }
        
        self.session.beginConfiguration()
        self.session.removeInput(self.input)
        self.session.removeOutput(self.output)
        self.configCamera()
        self.session.commitConfiguration()
    }
    
    
    /*
     ** Camera Flash Light Switch
     */
    @IBAction func cameraLight() -> Void {
        print("camera light", self.device)
        if self.device == self.cameraBack {
            do {
                try self.device.lockForConfiguration()
                if (self.device.torchMode == .on) {
                    self.device.torchMode = .off
                } else if (self.device.torchMode == .off) {
                    self.device.torchMode = .on
                }
                self.device.unlockForConfiguration()
            } catch let error as NSError {
                print(error)
            }
        }
    }
    
    
    /*
     ** MARK: - Picker
     */
    @IBAction func pickerShow() -> Void {
        self.pickerView.isHidden = false;
        self.pickerCloser.isHidden = false
    }
    
    @IBAction func pickerHide() -> Void {
        self.pickerView.isHidden = true;
        self.pickerCloser.isHidden = true
    }
    
    
    /*
     ** MARK: - CoreML
     */
    func setupCoreML() -> Void {
        do {
            /*
             Use the Swift class `MobileNet` Core ML generates from the model.
             To use a different Core ML classifier model, add it to the project
             and replace `MobileNet` with that model's generated Swift class.
             */
            var model: VNCoreMLModel
            switch self.pipelineModel {
            case 0: model = try VNCoreMLModel(for: MobileNet().model)
            case 2: model = try VNCoreMLModel(for: SqueezeNet().model)
            case 3: model = try VNCoreMLModel(for: GoogLeNetPlaces().model)
            case 4: model = try VNCoreMLModel(for: Inceptionv3().model)
            case 5: model = try VNCoreMLModel(for: Resnet50().model)
            case 6: model = try VNCoreMLModel(for: TinyYOLO().model)
            default: model = try VNCoreMLModel(for: SqueezeNet().model)
            }
            
            if self.pipelineModel == 6 {
                self.isYolo = true
                YOLO.setup()
                // Add the bounding box layers to the UI, on top of the video preview.
                for box in YOLO.boundingBoxes {
                    if self.usePreviewLayer {
//                        box.addToLayer(self.previewLayer)
                        box.addToLayer(self.view.layer)
                    } else {
                        box.addToLayer(self.imageView.layer)
                    }
                }
            } else {
                self.isYolo = false
            }
            
            self.classificationRequest = VNCoreMLRequest(model: model, completionHandler: predictDidComplete)
            self.classificationRequest.imageCropAndScaleOption = .centerCrop
            if self.isYolo {
                self.classificationRequest.imageCropAndScaleOption = .scaleFill
            }
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }
    
    func predictClassification(image: UIImage) {
        semaphore.wait()
        print("CoreML Classifying...")
        
        guard let ciImage = CIImage(image: image) else { fatalError("Unable to create \(CIImage.self) from \(image).") }

        guard let orientation = CGImagePropertyOrientation(rawValue: UInt32(image.imageOrientation.rawValue)) else { fatalError("Unable to create orientation from \(image.imageOrientation).") }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(ciImage: ciImage, orientation: orientation)
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                /*
                 This handler catches general image processing errors. The `classificationRequest`'s
                 completion handler `processClassifications(_:error:)` catches errors specific
                 to processing that request.
                 */
                print("Failed to perform classification.\n\(error.localizedDescription)")
            }
        }
    }
    
    func predictClassification(pixelBuffer: CVPixelBuffer) {
        semaphore.wait()
        print("CoreML Classifying...")
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            do {
                try handler.perform([self.classificationRequest])
            } catch {
                print("Failed to perform classification.\n\(error.localizedDescription)")
            }
        }
    }
    
    func predictDidComplete(request: VNRequest, error: Error?) {
        DispatchQueue.main.async {
            print("== DispatchQueue.main.async CoreML")
            guard let results = request.results else {
                self.labelClassification.text = "Unable to classify image."
                print("Unable to classify image.")
                return
            }
            
            if self.isYolo {
                // YOLO `results` will be `VNCoreMLFeatureValueObservation`
                let featureValues = results as! [VNCoreMLFeatureValueObservation]
                if featureValues.isEmpty {
                    print("Nothing recognized.")
                } else {
                    guard let features = featureValues.first?.featureValue.multiArrayValue else {
                        print("Unable to classify image.")
                        return
                    }
                    let predictions = YOLO.computePredictions(features: features)
                    for i in 0..<YOLO.boundingBoxes.count {
                        if i < predictions.count {
                            let prediction = predictions[i]
                            
//                            print("YOLO image:", self.imageView.bounds, self.imageView.image!.size.width, self.imageView.image!.size.height)
//                            print("YOLO predi:", prediction)
                            
                            // The predicted bounding box is in the coordinate space of the input
                            // image, which is a square image of 416x416 pixels. We want to show it
                            // on the video preview, which is as wide as the screen and has a 4:3
                            // aspect ratio. The video preview also may be letterboxed at the top
                            // and bottom.
                            /*
                             ** YOLO Coordinate
                             */
                            let heightYolo = self.imageView.bounds.width
                            let widthYolo = heightYolo * 4 / 3
                            let scaleXYolo = widthYolo / CGFloat(YOLO.inputWidth)
                            let scaleYYolo = heightYolo / CGFloat(YOLO.inputHeight)
                            
                            // Translate and scale the rectangle.
                            var rectYolo = prediction.rect
                            rectYolo.origin.x *= scaleXYolo
                            rectYolo.origin.y *= scaleYYolo
                            rectYolo.size.width *= scaleXYolo
                            rectYolo.size.height *= scaleYYolo
                            
                            /*
                             ** iPhone Coordinate
                             */
                            let width = heightYolo
                            let height = widthYolo
//                            let scaleX = scaleYYolo
//                            let scaleY = scaleXYolo
                            let top = (self.imageView.bounds.height - height) / 2
//                            print("YOLO scale:", width, height, top, scaleX, scaleY)
                            
                            var rect = prediction.rect
                            rect.origin.x = width - rectYolo.origin.y - rectYolo.size.height
                            rect.origin.y = rectYolo.origin.x
                            rect.origin.y += top
                            rect.size.width = rectYolo.size.height
                            rect.size.height = rectYolo.size.width
//                            print("YOLO rect:", rectYolo)
//                            print("YOLO rect:", rect)
                            
                            // Show the bounding box.
                            let label = String(format: "%@ %.1f", YOLO.labels[prediction.classIndex], prediction.score * 100)
                            let color = YOLO.colors[prediction.classIndex]
                            YOLO.boundingBoxes[i].show(frame: rect, label: label, color: color)
                        } else {
                            YOLO.boundingBoxes[i].hide()
                        }
                    }
//                    let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
//                    showOnMainThread(boundingBoxes, elapsed)
                }
            } else {
                // The `results` will always be `VNClassificationObservation`s, as specified by the Core ML model in this project.
                let classifications = results as! [VNClassificationObservation]
                if classifications.isEmpty {
//                self.labelClassification.text = "Nothing recognized."
                    print("Nothing recognized.")
                } else {
                    // Display top classifications ranked by confidence in the UI.
                    let topClassifications = classifications.prefix(3)
                    let descriptions = topClassifications.map { classification in
                        // Formats the classification for display; e.g. "(0.37) cliff, drop, drop-off".
                        return String(format: "(%.2f)  %@", classification.confidence, classification.identifier)
                    }
                    self.labelClassification.text = descriptions.joined(separator: "\n")
                    print("Classification:\n" + descriptions.joined(separator: "\n"))
                    
                    // Auto Capture Best UIImage
                    if !self.isBestImageExists {
                        for classification in topClassifications {
                            if (classification.identifier.contains(self.classificationObject)
                                && classification.confidence >= self.thresholdPropability) {
                                print(classification.confidence, classification.identifier)
                                guard let bestImage = self.getImageFromPixelBuffer(pixelBuffer: self.thresholdBest) else {
                                    print("could not get UIImage from pixel buffer")
                                    return
                                }
                                
                                self.performSegue(withIdentifier: "CameraToBestImage", sender: bestImage)
                                self.isBestImageExists = true
                            }
                        }
                    }
                }
            }
            
            // Calculate FPS
            self.labelFps.text = String(self.measureFPS())
            self.semaphore.signal()
        }
    }
    
    func measureFPS() -> Int {
        print("measureFPS")
        let interval = NSDate.timeIntervalSinceReferenceDate * 1000 - self.pipelineStartTime;
        let fps = Int(1000 / interval);
        self.pipelineFpsRun = true
        return fps
    }
}


// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("======== captureOutput")
        if (self.pipelineFpsRun) {
            self.pipelineFpsRun = false
            self.pipelineStartTime = NSDate.timeIntervalSinceReferenceDate * 1000
        }
        
        guard case let (capturedImage?, pixelBuffer?) = self.getImageFromBuffer(sampleBuffer: sampleBuffer) else {
            print("could not get UIImage from buffer")
            return
        }
        
        // 调用 OpenCV Pipeline
//        print(self.pipelineVision, self.pipelineModel)
        guard let cvImage = self.opencv.pipeline(capturedImage, withVision: self.pipelineVision, withModel: self.pipelineModel) else {
            print("could not process UIImage from OpenCV")
            return
        }
        let finalImage = self.fixImageOrientagion(image: cvImage)
        
        // 预测分类
        if (self.opencv.blur >= self.thresholdBlur) {
            self.thresholdBest = pixelBuffer
            if self.isYolo {
//                self.predictClassification(image: finalImage)
                self.predictClassification(pixelBuffer: pixelBuffer)
            } else {
                self.predictClassification(pixelBuffer: pixelBuffer)
            }
        }
        
        
//        // GCD 主线程队列中刷新UI
//        dispatch_async(dispatch_get_main_queue()) {
//            () -> Void in
//            self.imageView.image = capturedImage
//        }
        DispatchQueue.main.async {
            print("== DispatchQueue.main.async OpenCV")
            if (!self.usePreviewLayer) {
                self.imageView.image = finalImage
            }
            self.labelBlur.text = String(self.opencv.blur)
            
            if (self.opencv.blur < self.thresholdBlur) {
                self.labelFps.text = String(self.measureFPS())
            }
        }
    }
    
    func fixImageOrientagion(image: UIImage) -> UIImage {
        var orientation = UIImageOrientation.up
        if (self.device == self.cameraFront) {
            orientation = UIImageOrientation.leftMirrored
        } else if (self.device == self.cameraBack) {
            orientation = UIImageOrientation.right
        }
        
        return UIImage(cgImage: image.cgImage!, scale: 1.0, orientation: orientation)
    }
    
    
    /*
     ** Capture Video Buffer to UIImage
     */
    func getImageFromBuffer(sampleBuffer: CMSampleBuffer) -> (UIImage?, CVPixelBuffer?) {
        // 将捕捉到的 image buffer 转换成 UIImage.
        guard let buffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("could not get a pixel buffer")
            return (nil, nil)
        }
        
        let capturedImage: UIImage
        do {
            CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
            }
            let address = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
            let bytes = CVPixelBufferGetBytesPerRow(buffer)
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let color = CGColorSpaceCreateDeviceRGB()
            let bits = 8
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            guard let context = CGContext(data: address, width: width, height: height, bitsPerComponent: bits, bytesPerRow: bytes, space: color, bitmapInfo: info) else {
                print("could not create an CGContext")
                return (nil, nil)
            }
            guard let image = context.makeImage() else {
                print("could not create an CGImage")
                return (nil, nil)
            }
            
            print(width, height)
            capturedImage = UIImage(cgImage: image, scale: 1.0, orientation: UIImageOrientation.up)
            
//            capturedImage = UIImage(cgImage: image, scale: 1.0, orientation: CVPixelBufferGet)
            
            return (capturedImage, buffer)
        }
//        catch let error as NSError {
//            print(error)
//        }
    }
    
    func getImageFromPixelBuffer(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let capturedImage: UIImage
        do {
            CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
            defer {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
            }
            let address = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
            let bytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let color = CGColorSpaceCreateDeviceRGB()
            let bits = 8
            let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            guard let context = CGContext(data: address, width: width, height: height, bitsPerComponent: bits, bytesPerRow: bytes, space: color, bitmapInfo: info) else {
                print("could not create an CGContext")
                return nil
            }
            guard let image = context.makeImage() else {
                print("could not create an CGImage")
                return nil
            }
            capturedImage = UIImage(cgImage: image, scale: 1.0, orientation: UIImageOrientation.up)
            
            return capturedImage
        }
    }
    
}


// MARK: - UIPickerViewDelegate
extension CameraViewController: UIPickerViewDelegate {
    
    /// When values are changed, update the predicted price.
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
//        updatePredictedPrice()
        print("pickerView didSelectRow", row, "inComponent", component)
        switch component {
        case 0:
            self.pipelineVision = row
        case 1:
            self.pipelineModel = row
            self.setupCoreML()
        default:
            return
        }
    }

    /// Accessor for picker values.
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        print("pickerView titleForRow", row, "forComponent", component)
        return self.pickerDataSource.title(for: row, component: component)
    }
}
