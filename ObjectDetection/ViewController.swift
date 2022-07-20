import CoreMedia
import CoreML
import UIKit
import Vision
import AVFoundation
import Photos

enum SampleVideo: String {
    case oneByOne = "one-by-one-person-detection"
    case headFemale = "head-pose-face-detection-female-and-male"
    case faceWalkingAndPause = "face-demographics-walking-and-pause"
    case faceWalking = "face-demographics-walking"
    case people = "people-detection"
    case personBicycleCar = "person-bicycle-car-detection"
}

class ViewController: UIViewController {
    
    @IBOutlet var videoPreview: UIView!
    @IBOutlet var label: UILabel!
    
    var currentBuffer: CVPixelBuffer?

    let coreMLModel = MobileNetV2_SSDLite()

    lazy var visionModel: VNCoreMLModel = {
        do {
            return try VNCoreMLModel(for: coreMLModel.model)
        } catch {
            fatalError("Failed to create VNCoreMLModel: \(error)")
        }
    }()

    lazy var visionRequest: VNCoreMLRequest = {
        let request = VNCoreMLRequest(model: visionModel, completionHandler: { [weak self] request, error in
            self?.processObservations(for: request, error: error)
        })
        request.imageCropAndScaleOption = .scaleFill
        return request
    }()

    private var videoReader: VideoReader?
    private var shouldRecord: Bool = false
    private var ciImages = [CIImage]()
    private var savedFrameCount = 0
    private var videoReaderQueue = DispatchQueue(label: "com.videoReader")
    
    private let requiredSeconds = 10
    private var targetIdentifier = "person"
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        startPersonDetect(file: SampleVideo.oneByOne.rawValue)
    }
    
    func startPersonDetect(file name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            /* Implement error handling */
            return
        }
        do {
            self.videoReader = try VideoReader(url: url)
        }
        catch {
            /* Implement error handling */
            debugPrint(error)
            return
        }

        videoReaderQueue.async { [unowned self] in
            // Extract video buffer from sample video
            self.videoReader?.extractBuffer { [unowned self] buffer in
                
                // Process buffer for object detection
                self.predict(sampleBuffer: buffer)
            
                // If a person is detected, start record buffer and add bounding box. Save rendered image to disk.
                if self.shouldRecord, let image = buffer.ciImage() {
                    self.ciImages.append(image)
                }
                
                // Export and saved recorded buffers to photo library
                if self.frameSavedSuccess() {
                    self.videoReader?.cancel()
                    self.exportSampleData()
                }
            }
        }
    }
    
    func frameSavedSuccess() -> Bool {
        guard let info = videoReader?.videoInfo() else {
            return false
        }
        return savedFrameCount == requiredSeconds * Int(info.fps.rounded())
    }

    func predict(sampleBuffer: CMSampleBuffer) {
        if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            currentBuffer = pixelBuffer

            var options: [VNImageOption : Any] = [:]
            if let cameraIntrinsicMatrix = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
                options[.cameraIntrinsics] = cameraIntrinsicMatrix
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: options)
            do {
                try handler.perform([self.visionRequest])
            } catch {
                print("Failed to perform Vision request: \(error)")
            }
            currentBuffer = nil
        }
    }

    func processObservations(for request: VNRequest, error: Error?) {
        
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            DispatchQueue.main.async {
                self.label.text = "No object detected"
            }
            return
        }
        
        if self.shouldRecord == false, self.isPersonDetected(with: results) {
            self.shouldRecord = true
        }
        
        if shouldRecord, ciImages.count > 0 {
            
            let ciImage = ciImages.removeFirst()
            if let image = combineObjectDetectionWithImage(ciImage: ciImage, predictions: results) {
                savedFrameCount += 1
                VideoFileHelper.saveImageToDisk(image: image, name: savedFrameCount)
                
                DispatchQueue.main.async {
                    if let info = self.videoReader?.videoInfo() {
                        self.label.text = "Extracting \(self.savedFrameCount)/\(self.requiredSeconds * Int(info.fps.rounded()))"
                    }
                }
            }
        }
    }
    
    func isPersonDetected(with predictions: [VNRecognizedObjectObservation]) -> Bool {
        return predictions.contains(where: { $0.labels.first?.identifier == targetIdentifier })
    }
    
    func combineObjectDetectionWithImage(ciImage: CIImage, predictions: [VNRecognizedObjectObservation]) -> UIImage? {
        
        guard let info = videoReader?.videoInfo() else {
            return nil
        }
        
        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: info.videoSize.width, height: info.videoSize.height)
        
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            layer.contents = cgImage
        }

        for prediction in predictions {
            guard let label = prediction.labels.first?.identifier, label == targetIdentifier else {
                continue
            }

            let box = BoundingBoxView()
            box.addToLayer(layer)

            let width = layer.bounds.width
            let height = width * info.videoSize.width / info.videoSize.height
            let offsetY = (layer.bounds.height - height) / 2
            let scale = CGAffineTransform.identity.scaledBy(x: width, y: height)
            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -height - offsetY)
            let rect = prediction.boundingBox.applying(scale).applying(transform)
            let bestClass = prediction.labels[0].identifier
            let confidence = prediction.labels[0].confidence
            box.show(frame: rect, label: String(format: "%@ %.1f", bestClass, confidence * 100), color: .red)
        }
        
        let image = imageFromLayer(layer: layer)
        
        layer.contents = nil
        
        return image
    }
    
    func imageFromLayer(layer:CALayer) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(layer.frame.size, layer.isOpaque, 0)
        
        if let context = UIGraphicsGetCurrentContext() {
            layer.render(in: context)
        }

        let outputImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return outputImage
    }

    func exportSampleData() {
        guard let destinationURL = VideoFileHelper.outputPath(), let videoInfo = videoReader?.videoInfo() else {
            return
        }
        do {
            let writer = try VideoWriter(url: destinationURL, info: videoInfo)
            try writer.writeOutput(frameCount: savedFrameCount) { success in
                guard success else {
                    /* Implement error handling */
                    return
                }
                self.saveToCameraRoll(url: destinationURL)
            }
        }
        catch {
            /* Implement error handling */
            debugPrint(error)
        }
    }
    
    func saveToCameraRoll(url: URL) {
        PHPhotoLibrary.requestAuthorization { (status) in
            switch status {
            case .authorized:
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { saved, error in
                    guard error == nil else {
                        /* Implement error handling */
                        return
                    }
                    debugPrint("Successfully saved \(saved)")
                }
                break
            case .denied:
                /* Implement error handling */
                debugPrint("Photo permission denied")
                break
            default:
                break
            }
        }
    }
}

extension CMSampleBuffer {
    func ciImage() -> CIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else {
            return nil
        }
        return CIImage(cvPixelBuffer: imageBuffer)
    }
}
