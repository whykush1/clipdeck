import Cocoa

let pb = NSPasteboard.general
print(pb.types ?? [])
if let str = pb.string(forType: .fileURL) {
    print("fileURL string:", str)
    print("URL parsed:", URL(string: str) ?? "nil")
} else {
    print("no fileURL string")
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
        print("NSURL read:", urls)
    }
}
