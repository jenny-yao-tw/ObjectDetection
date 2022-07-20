//
//  VideoFileHelper.swift
//  ObjectDetection
//
//  Created by Jenny Yao on 2022/7/20.
//  Copyright © 2022 MachineThink. All rights reserved.
//

import UIKit
import Foundation

class VideoFileHelper {
    
    struct Path {
        static let folderRederImages = "RenderedImages"
        static let fileOutputVideo = "output.mp4"
        static func documentDirectory() -> URL? {
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
    }
    
    @discardableResult static func saveImageToDisk(image: UIImage, name: Int) -> Bool {
        do {
            guard let documentURL = Path.documentDirectory() else {
                return false
            }
            let folderURL = documentURL.appendingPathComponent(Path.folderRederImages)
            if false == FileManager.default.fileExists(atPath: folderURL.path) {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            }
            let imageFileURL = folderURL.appendingPathComponent("\(name).png")
            try image.pngData()?.write(to: imageFileURL)
        }
        catch {
            return false
        }
        return true
    }
    
    static func getImageFromDisk(name: Int) -> UIImage? {
        guard let documentURL = Path.documentDirectory() else {
            return nil
        }
        let imageFile = documentURL.appendingPathComponent("\(Path.folderRederImages)/\(name).png")
        return UIImage(contentsOfFile: imageFile.path)
    }
    
    static func outputPath() -> URL? {
        guard let documentURL = Path.documentDirectory() else {
            return nil
        }
        return documentURL.appendingPathComponent(Path.fileOutputVideo)
    }
}
