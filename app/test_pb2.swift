import Cocoa

let pb = NSPasteboard.general
if let str = pb.string(forType: .fileURL) {
    if let url = URL(string: str) {
        print("url path:", url.path)
        print("url pathExtension:", url.pathExtension)
        if let resolved = try? URL(resolvingAliasFileAt: url, options: []) {
             print("resolved pathExtension:", resolved.pathExtension)
        }
        let filePathURL = url.standardizedFileURL
        print("standardized path:", filePathURL.path)
        print("standardized ext:", filePathURL.pathExtension)
    }
}
