import Foundation
import CryptoKit
import Cocoa
import ImageIO

class StorageManager {
    static let shared = StorageManager()
    
    private let fileManager = FileManager.default
    
    var appSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("dev.pythogen.ClipDeck")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    var imagesDirectory: URL {
        let dir = appSupportDirectory.appendingPathComponent("Images")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    var historyFileURL: URL {
        appSupportDirectory.appendingPathComponent("history.enc")
    }
    
    func saveHistory(_ items: [ClipboardItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            let key = KeychainHelper.shared.getEncryptionKey()
            let sealedBox = try AES.GCM.seal(data, using: key)
            if let encryptedData = sealedBox.combined {
                try encryptedData.write(to: historyFileURL)
            }
        } catch {
            print("Failed to encrypt and save history: \(error)")
        }
    }
    
    func loadHistory() -> [ClipboardItem] {
        guard let encryptedData = try? Data(contentsOf: historyFileURL) else {
            // Fallback for migration from unencrypted history
            let oldURL = appSupportDirectory.appendingPathComponent("history.json")
            if let oldData = try? Data(contentsOf: oldURL) {
                if let items = try? JSONDecoder().decode([ClipboardItem].self, from: oldData) {
                    try? FileManager.default.removeItem(at: oldURL)
                    saveHistory(items)
                    return items
                }
            }
            return []
        }
        
        do {
            let key = KeychainHelper.shared.getEncryptionKey()
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            let items = try JSONDecoder().decode([ClipboardItem].self, from: decryptedData)
            return items
        } catch {
            print("Failed to decrypt history: \(error)")
            return []
        }
    }
    
    func saveImage(_ data: Data, id: UUID) -> String? {
        let filename = "\(id.uuidString).png"
        let url = imagesDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            
            // Generate thumbnail
            if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 300,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ]
                if let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
                    let thumbNsImage = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
                    if let tiffData = thumbNsImage.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let thumbData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
                        
                        let thumbFilename = "\(id.uuidString)_thumb.jpg"
                        let thumbUrl = imagesDirectory.appendingPathComponent(thumbFilename)
                        try? thumbData.write(to: thumbUrl)
                    }
                }
            }
            
            return filename
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }
}

class KeychainHelper {
    static let shared = KeychainHelper()
    private let keyTag = "dev.pythogen.ClipDeck.encryptionKey".data(using: .utf8)!
    
    func getEncryptionKey() -> SymmetricKey {
        // Try to load existing key
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess, let keyData = item as? Data {
            return SymmetricKey(data: keyData)
        }
        
        // Generate a new 256-bit key
        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data(Array($0)) }
        
        // Save the new key to the keychain
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecValueData as String: newKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        SecItemAdd(addQuery as CFDictionary, nil)
        return newKey
    }
}
