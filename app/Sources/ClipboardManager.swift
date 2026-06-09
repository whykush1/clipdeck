import Cocoa
import Combine
import SwiftUI
import Aptabase

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardItem] = []
    
    private var pasteboard: NSPasteboard = .general
    private var lastChangeCount: Int
    private var timer: Timer?
    
    init() {
        self.lastChangeCount = pasteboard.changeCount
        self.history = StorageManager.shared.loadHistory()
        startMonitoring()
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkForChanges() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        if let activeApp = NSWorkspace.shared.frontmostApplication {
            let bundleIdentifier = activeApp.bundleIdentifier ?? ""
            let appName = activeApp.localizedName ?? ""
            
            if let excludedData = UserDefaults.standard.data(forKey: "excludedApps"),
               let excludedList = try? JSONDecoder().decode([String].self, from: excludedData) {
                if excludedList.contains(bundleIdentifier) || excludedList.contains(appName) {
                    return
                }
            }
        }
        
        let concealedTypes = ["org.nspasteboard.ConcealedType", "com.agilebits.onepassword", "com.apple.keychain.password"]
        if let types = pasteboard.types {
            for type in types {
                if concealedTypes.contains(type.rawValue) {
                    return
                }
            }
        }
        
        var newItem: ClipboardItem? = nil
        let itemId = UUID()
        
        // Check for file URLs first (e.g. copied from Finder)
        if let types = pasteboard.types, types.contains(.fileURL),
           let urlString = pasteboard.string(forType: .fileURL),
           let url = URL(string: urlString) {
            
            if UserDefaults.standard.bool(forKey: "ignoreFiles") {
                return
            }
            
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp"].contains(ext) {
                if let img = NSImage(contentsOf: url),
                   let tiffData = img.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    if let filename = StorageManager.shared.saveImage(pngData, id: itemId) {
                        newItem = ClipboardItem(id: itemId, type: .image, content: filename)
                    }
                }
            } else {
                newItem = ClipboardItem(id: itemId, type: .file, content: urlString)
            }
        }
        
        // If not a file URL image, check for raw image data
        if newItem == nil, let types = pasteboard.types {
            if types.contains(.png) || types.contains(.tiff) {
                if UserDefaults.standard.bool(forKey: "ignoreImages") {
                    return
                }
                if let img = NSImage(pasteboard: pasteboard),
                   let tiffData = img.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    
                    if let filename = StorageManager.shared.saveImage(pngData, id: itemId) {
                        newItem = ClipboardItem(id: itemId, type: .image, content: filename)
                    }
                }
            }
        }
        
        // Fallback to text
        if newItem == nil, let newString = pasteboard.string(forType: .string) {
            // Avoid adding duplicates if the user copies the exact same text twice in a row
            if let lastItem = history.first, lastItem.type == .text, lastItem.content == newString {
                return
            }
            
            var rtfData: Data? = nil
            if let types = pasteboard.types {
                if types.contains(.rtfd), let data = pasteboard.data(forType: .rtfd) {
                    rtfData = data
                } else if types.contains(.rtf), let data = pasteboard.data(forType: .rtf) {
                    rtfData = data
                } else if types.contains(.html), let data = pasteboard.data(forType: .html) {
                    rtfData = data
                }
            }
            
            newItem = ClipboardItem(id: itemId, type: .text, content: newString, rtfData: rtfData)
        }
        
        if let item = newItem {
            if UserDefaults.standard.bool(forKey: "playSoundOnCopy") {
                playSound("CopySound")
            }
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardActionOccurred"), object: nil)
            DispatchQueue.main.async {
                withAnimation {
                    let pinnedCount = self.history.filter({ $0.isPinned }).count
                    self.history.insert(item, at: pinnedCount)
                    
                    let limit = UserDefaults.standard.integer(forKey: "historyLimit")
                    
                    if limit > 0 && self.history.count > limit {
                        if let lastIndex = self.history.lastIndex(where: { !$0.isPinned }) {
                            self.history.remove(at: lastIndex)
                        }
                    }
                }
                StorageManager.shared.saveHistory(self.history)
            }
        }
    }
    
    func togglePin(_ item: ClipboardItem) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isPinned.toggle()
            if history[index].isPinned {
                NSSound(named: "Glass")?.play()
            } else {
                NSSound(named: "Basso")?.play()
            }
            history.sort {
                if $0.isPinned == $1.isPinned {
                    return $0.timestamp > $1.timestamp
                }
                return $0.isPinned && !$1.isPinned
            }
            StorageManager.shared.saveHistory(history)
        }
    }
    
    private func playSound(_ name: String) {
        NSSound(named: name)?.play()
    }
    func pasteItem(_ item: ClipboardItem) {
        if UserDefaults.standard.bool(forKey: "playSoundOnCopy") {
            playSound("CopySound")
        }
        NotificationCenter.default.post(name: NSNotification.Name("ClipboardActionOccurred"), object: nil)
        // 1. Put it on the pasteboard
        pasteboard.clearContents()
        if item.type == .text, let str = item.content {
            pasteboard.setString(str, forType: .string)
            if let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
            }
        } else if item.type == .image, let url = item.imageURL, let img = NSImage(contentsOf: url) {
            pasteboard.writeObjects([img])
        } else if item.type == .file, let str = item.content, let url = URL(string: str) {
            pasteboard.writeObjects([url as NSURL])
        }
        
        // 2. Hide app or popover to return focus
        let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if mode == "Dock Window" {
            NSApp.hide(nil)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
        }
        
        // 3. Simulate Cmd+V
        simulatePaste()
    }
    
    func pasteItemAsPlainText(_ item: ClipboardItem) {
        if UserDefaults.standard.bool(forKey: "playSoundOnCopy") {
            playSound("CopySound")
        }
        NotificationCenter.default.post(name: NSNotification.Name("ClipboardActionOccurred"), object: nil)
        
        pasteboard.clearContents()
        if item.type == .text, let str = item.content {
            pasteboard.setString(str, forType: .string)
            // Explicitly do not set RTF data
        } else if item.type == .image, let url = item.imageURL, let img = NSImage(contentsOf: url) {
            pasteboard.writeObjects([img])
        } else if item.type == .file, let str = item.content, let url = URL(string: str) {
            pasteboard.writeObjects([url as NSURL])
        }
        
        let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if mode == "Dock Window" {
            NSApp.hide(nil)
        } else {
            NotificationCenter.default.post(name: NSNotification.Name("ClosePopover"), object: nil)
        }
        
        simulatePaste()
    }
    
    private func simulatePaste() {
        // Update lastChangeCount so we don't re-record our own paste
        lastChangeCount = pasteboard.changeCount
        
        // Give it a tiny delay for the window to hide and the previous app to become active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.simulatePasteHotkey()
        }
    }
    
    private func simulatePasteHotkey() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        if !isTrusted {
            print("Accessibility permissions missing")
            return
        }
        
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09 // 'v' key code
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        
        cmdDown?.flags = .maskCommand
        cmdUp?.flags = .maskCommand
        
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    func deleteItem(_ item: ClipboardItem) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                history.remove(at: index)
            }
            StorageManager.shared.saveHistory(history)
            
            if item.type == .image, let url = item.imageURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    func clearUnpinnedHistory() {
        withAnimation {
            let itemsToDelete = history.filter { !$0.isPinned }
            history.removeAll(where: { !$0.isPinned })
            
            for item in itemsToDelete where item.type == .image {
                if let url = item.imageURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        StorageManager.shared.saveHistory(history)
    }
    
    func copyToClipboard(_ item: ClipboardItem) {
        if UserDefaults.standard.bool(forKey: "playSoundOnCopy") {
            playSound("CopySound")
        }
        Aptabase.shared.trackEvent("item_copied")
        NotificationCenter.default.post(name: NSNotification.Name("ClipboardActionOccurred"), object: nil)
        pasteboard.clearContents()
        if item.type == .text, let str = item.content {
            pasteboard.setString(str, forType: .string)
            if let rtf = item.rtfData {
                pasteboard.setData(rtf, forType: .rtf)
            }
        } else if item.type == .image, let url = item.imageURL, let img = NSImage(contentsOf: url) {
            pasteboard.writeObjects([img])
        } else if item.type == .file, let str = item.content, let url = URL(string: str) {
            pasteboard.writeObjects([url as NSURL])
        }
        lastChangeCount = pasteboard.changeCount
    }
}
