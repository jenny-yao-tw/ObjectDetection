//
//  VideoReader.swift
//  ObjectDetection
//
//  Created by Jenny Yao on 2022/7/20.
//  Copyright © 2022 MachineThink. All rights reserved.
//

import Foundation
import AVFoundation

enum VideoReaderError: Error {
    case noVideoAssetFounded
}

class VideoReader {
    
    private var assetReader: AVAssetReader
    private var track: AVAssetTrack
    private var info: VideoInfo
    
    init(url: URL) throws {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoReaderError.noVideoAssetFounded
        }
        self.track = track
        self.info = VideoInfo(fps: track.nominalFrameRate, videoSize: track.naturalSize)
        self.assetReader = try AVAssetReader(asset: asset)
    }
    
    func videoInfo() -> VideoInfo {
        return self.info
    }
    
    func extractBuffer(buffer: @escaping (CMSampleBuffer) -> Void) {
                
        if assetReader.status == .reading {
            self.assetReader.cancelReading()
        }
        
        let settings: [String: Int] = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)

        self.assetReader.add(trackOutput)
        self.assetReader.startReading()

        while assetReader.status == .reading {
            guard let sampleBufferRef = trackOutput.copyNextSampleBuffer() else {
                continue
            }
            buffer(sampleBufferRef)
        }
    }
    
    func cancel() {
        if assetReader.status == .reading {
            self.assetReader.cancelReading()
        }
    }
}
