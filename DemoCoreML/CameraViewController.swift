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
    var pipelineFpsRun: Bool! = true
    var pipelineStartTime: Double!
    var pipelineEndTime: Double!
    
    var session: AVCaptureSession!
    var device: AVCaptureDevice!
    var cameraBack: AVCaptureDevice!    // 后置摄像头
    var cameraFront: AVCaptureDevice!   // 前置摄像头
    var input: AVCaptureDeviceInput!
    var output: AVCaptureVideoDataOutput!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var usePreviewLayer: Bool! = false
    
    var opencv: OpencvViewController!
    var classificationRequest: VNCoreMLRequest!
    let semaphore = DispatchSemaphore(value: 2)

    /*
    ** MARK: - Override
     */
    override func viewDidLoad() {
        super.viewDidLoad()
        print("camera viewDidLoad", self.view.frame)
        
        self.setupView()
        self.setupPicker()
        self.setupCamera()
        self.setupOpenCV()
        self.setupCoreML()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        print("camera viewWillAppear")
        super.viewWillAppear(animated)
        self.session.startRunning()
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
    
    
    /*
     ** MARK: - Setup
     */
    func setupView() -> Void {
        print("setup view")
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
                    }
                })
                break
            
            case .restricted, .denied:  // 受限或拒绝授权，引导授权
                print("camera restricted or denied")
                let alert = UIAlertController(title: "提示",
                                              message: "摄像头权限未未开启,点击确认跳转至设置",
                                              preferredStyle: UIAlertControllerStyle.alert)
                let cancelAction = UIAlertAction(title: "取消", style: .cancel, handler: {
                    (action: UIAlertAction) -> Void in
                    /**
                     写取消后操作
                     */
                })
                let okAction = UIAlertAction(title: "好的", style: .default, handler: {
                    (action: UIAlertAction) -> Void in
                    /**
                     写确定后操作
                     */
                    let settingsURL = URL(string:UIApplicationOpenSettingsURLString)!
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
            default: model = try VNCoreMLModel(for: SqueezeNet().model)
            }
//            let model = try VNCoreMLModel(for: MobileNet().model)
//            let model = try VNCoreMLModel(for: SqueezeNet().model)
//            let model = try VNCoreMLModel(for: GoogLeNetPlaces().model)
//            let model = try VNCoreMLModel(for: Inceptionv3().model)
//            let model = try VNCoreMLModel(for: Resnet50().model)
            
            self.classificationRequest = VNCoreMLRequest(model: model, completionHandler: predictDidComplete)
            self.classificationRequest.imageCropAndScaleOption = .centerCrop
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }
    
    func predictClassification(image: UIImage) {
//        self.labelClassification.text = "Classifying..."
        
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
            
//            print(ciImage, orientation, handler)
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
            }
            
            // Calculate FPS
            self.labelFps.text = String(self.measureFPS())
            self.semaphore.signal()
        }
    }
    
    func measureFPS() -> Int {
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
        
        var orientation = UIImageOrientation.up
        if (self.device == self.cameraFront) {
            orientation = UIImageOrientation.leftMirrored
        } else if (self.device == self.cameraBack) {
            orientation = UIImageOrientation.right
        }
        
        let finalImage = UIImage(cgImage: cvImage.cgImage!,
                                 scale: 1.0,
                                 orientation: orientation)
        
        // 预测分类
//        self.predictClassification(image: finalImage)
        self.predictClassification(pixelBuffer: pixelBuffer)
        
        
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
        }
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
            capturedImage = UIImage(cgImage: image, scale: 1.0, orientation: UIImageOrientation.up)
            
            return (capturedImage, buffer)
        }
//        catch let error as NSError {
//            print(error)
//        }
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
