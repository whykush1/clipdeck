import Foundation

enum ItemType: String, Codable {
    case text
    case image
    case file
}

struct ClipboardItem: Identifiable, Hashable, Codable {
    let id: UUID
    let type: ItemType
    let content: String? // The text content or the filename for the image/file
    let timestamp: Date
    var isPinned: Bool
    var rtfData: Data? // Stores rich text or HTML if available
    var sourceAppBundleID: String? // Bundle ID of the app it was copied from
    
    var imageURL: URL? {
        guard type == .image, let filename = content else { return nil }
        return StorageManager.shared.imagesDirectory.appendingPathComponent(filename)
    }
    
    var thumbnailURL: URL? {
        guard type == .image, let filename = content else { return nil }
        let thumbFilename = filename.replacingOccurrences(of: ".png", with: "_thumb.jpg")
        return StorageManager.shared.imagesDirectory.appendingPathComponent(thumbFilename)
    }
    
    init(id: UUID = UUID(), type: ItemType, content: String?, isPinned: Bool = false, rtfData: Data? = nil, sourceAppBundleID: String? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = Date()
        self.isPinned = isPinned
        self.rtfData = rtfData
        self.sourceAppBundleID = sourceAppBundleID
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, content, timestamp, isPinned, rtfData, sourceAppBundleID
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ItemType.self, forKey: .type)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        rtfData = try container.decodeIfPresent(Data.self, forKey: .rtfData)
        sourceAppBundleID = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleID)
    }
}
