//
//  VideoWriter.swift
//  ObjectDetection
//
//  Created by Jenny Yao on 2022/7/20.
//  Copyright © 2022 MachineThink. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

enum VideoWriterError: Error {
    case mediaConnotAdded
}

class VideoWriter {
    
    private var url: URL
    private var assetWriter: AVAssetWriter
    private var info: VideoInfo
    private let timeScale: Float = 600
    
    init(url: URL, info: VideoInfo) throws {
        self.url = url
        self.assetWriter = try AVAssetWriter(url: url, fileType: .mp4)
        self.info = info
    }
    
    func writeOutput(frameCount: Int, complete: @escaping (Bool) -> Void) throws {
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        
        let assetWriter = try AVAssetWriter(url: url, fileType: .mp4)
        let settings: [String : Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                        AVVideoWidthKey: info.videoSize.width,
                                       AVVideoHeightKey: info.videoSize.height]
        
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: info.videoSize.width,
            kCVPixelBufferHeightKey as String: info.videoSize.height,
            ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput,
                                                                      sourcePixelBufferAttributes: attributes)
        
        guard assetWriter.canAdd(writerInput) else {
            throw VideoWriterError.mediaConnotAdded
        }
        
        assetWriter.add(writerInput)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
                    
        let queue = DispatchQueue(label: "com.videoWriter")
        writerInput.requestMediaDataWhenReady(on: queue) {
            var success = false
            for frame in 0..<frameCount {
                guard writerInput.isReadyForMoreMediaData else {
                    debugPrint("isReadyForMoreMediaData == false")
                    success = false
                    break
                }
                guard let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool else {
                    continue
                }
                guard let image = VideoFileHelper.getImageFromDisk(name: frame + 1) else {
                    success = false
                    break
                }
                let pixelBuffer = self.pixelBufferFromImage(image: image,
                                                            pixelBufferPool: pixelBufferPool,
                                                            size: CGSize(width: self.info.videoSize.width,
                                                                         height: self.info.videoSize.height))
                
                let frameDuration = CMTimeMake(value: Int64(self.timeScale / self.info.fps),
                                               timescale: Int32(self.timeScale))
                let presentationTime = CMTimeMultiply(frameDuration, multiplier: Int32(frame))
                pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                success = true
            }
            writerInput.markAsFinished()
            assetWriter.finishWriting {
                complete(success)
            }
        }
    }
    
    private func pixelBufferFromImage(image: UIImage, pixelBufferPool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer {

        var pixelBufferOut: CVPixelBuffer?

        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBufferOut)
        guard status == kCVReturnSuccess else {
            fatalError("CVPixelBufferPoolCreatePixelBuffer() failed \(status)")
        }

        let pixelBuffer = pixelBufferOut!

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        let data = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: data,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                space: rgbColorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        
        context!.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        let horizontalRatio = size.width / image.size.width
        let verticalRatio = size.height / image.size.height
        let aspectRatio = min(horizontalRatio, verticalRatio)
        let newSize = CGSize(width: image.size.width * aspectRatio, height: image.size.height * aspectRatio)

        let x = newSize.width < size.width ? (size.width - newSize.width) / 2 : 0
        let y = newSize.height < size.height ? (size.height - newSize.height) / 2 : 0

        context!.draw(image.cgImage!, in: CGRect(x: x, y: y, width: newSize.width, height: newSize.height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        return pixelBuffer
    }
}
