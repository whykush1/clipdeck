import SwiftUI

struct ContentView: View {
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var searchText = ""
    @AppStorage("isGridView") private var isGridView = false
    @State private var showingClearAlert = false
    
    var filteredHistory: [ClipboardItem] {
        if searchText.isEmpty {
            return clipboardManager.history
        } else {
            return clipboardManager.history.filter { item in
                item.content?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ClipDeck")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                Button(action: {
                    withAnimation { isGridView.toggle() }
                }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    showingClearAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
                .alert(isPresented: $showingClearAlert) {
                    Alert(
                        title: Text("Clear History?"),
                        message: Text("This will permanently delete all your unpinned items. This action cannot be undone."),
                        primaryButton: .destructive(Text("Clear All")) {
                            clipboardManager.clearUnpinnedHistory()
                        },
                        secondaryButton: .cancel()
                    )
                }
                
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 8)
            }
            .padding()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            ScrollView {
                if filteredHistory.isEmpty {
                    Text(searchText.isEmpty ? "Copy some text to see it here." : "No results found.")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                } else if isGridView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredHistory) { item in
                            ClipboardItemView(item: item, isGrid: true)
                                .onTapGesture { clipboardManager.pasteItem(item) }
                        }
                    }
                    .padding()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredHistory) { item in
                            ClipboardItemView(item: item, isGrid: false)
                                .onTapGesture { clipboardManager.pasteItem(item) }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 400, minHeight: 600)
        // Native macOS material background for a sleek Apple-like design
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow).ignoresSafeArea())
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ClipboardItemView: View {
    let item: ClipboardItem
    var isGrid: Bool = false
    @EnvironmentObject var clipboardManager: ClipboardManager
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if item.type == .image, let url = item.thumbnailURL ?? item.imageURL, let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .cornerRadius(8)
                } else if item.type == .file, let str = item.content, let url = URL(string: str) {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        Text(url.lastPathComponent)
                            .font(.body)
                    }
                } else if let content = item.content {
                    RichPreviewView(content: content)
                }
                
                Spacer()
                
                // Pin Button
                if isHovering || item.isPinned {
                    Button(action: {
                        clipboardManager.togglePin(item)
                    }) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .foregroundColor(item.isPinned ? .accentColor : .secondary)
                            .imageScale(.large)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .transition(.opacity)
                }
            }
            
            Text(item.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(isHovering ? 0.8 : 0.6))
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.isPinned ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .contextMenu {
            if item.type == .text, let str = item.content {
                if let url = URL(string: str), url.scheme != nil, url.host != nil {
                    Button("Open in Browser") {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    Button("Search on Google") {
                        if let encoded = str.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                           let searchUrl = URL(string: "https://www.google.com/search?q=\(encoded)") {
                            NSWorkspace.shared.open(searchUrl)
                        }
                    }
                }
            } else if item.type == .image, let url = item.imageURL {
                Button("Save Image to Desktop") {
                    let dest = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].appendingPathComponent("ClipDeck_\(UUID().uuidString.prefix(8)).png")
                    try? FileManager.default.copyItem(at: url, to: dest)
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            } else if item.type == .file, let str = item.content, let url = URL(string: str) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            
            Divider()
            
            Button("Copy") {
                clipboardManager.copyToClipboard(item)
            }
            Button("Delete") {
                clipboardManager.deleteItem(item)
            }
        }
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovered
            }
            if hovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .contextMenu {
            Button("Copy to Clipboard") {
                clipboardManager.copyToClipboard(item)
            }
            if item.type == .text {
                Button("Paste as Plain Text") {
                    clipboardManager.pasteItem(item)
                }
            }
            Divider()
            Button("Delete") {
                clipboardManager.deleteItem(item)
            }
        }
    }
}

import LinkPresentation

struct CustomLinkCardView: View {
    let url: URL
    @State private var title: String?
    @State private var icon: NSImage?
    
    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
            } else {
                Image(systemName: "link")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? url.host ?? url.absoluteString)
                    .font(.headline)
                    .lineLimit(1)
                Text(url.host ?? url.absoluteString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .onAppear {
            fetchMetadata()
        }
    }
    
    func fetchMetadata() {
        let provider = LPMetadataProvider()
        // Timeout to prevent hanging
        provider.timeout = 5
        provider.startFetchingMetadata(for: url) { metadata, error in
            guard let metadata = metadata else { return }
            DispatchQueue.main.async {
                if let t = metadata.title, !t.isEmpty {
                    self.title = t
                }
            }
            if let iconProvider = metadata.iconProvider {
                iconProvider.loadObject(ofClass: NSImage.self) { image, error in
                    if let image = image as? NSImage {
                        DispatchQueue.main.async {
                            self.icon = image
                        }
                    }
                }
            }
        }
    }
}

struct RichPreviewView: View {
    let content: String
    
    var body: some View {
        if let hex = extractHexColor(from: content) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: hex) ?? .clear)
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(content)
                        .font(.system(.headline, design: .monospaced))
                    Text("Color Code")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else if isURL(content), let url = URL(string: content), url.host != nil {
            CustomLinkCardView(url: url)
                .frame(minHeight: 50, maxHeight: 80)
                .padding(.vertical, 4)
        } else {
            Text(content)
                .font(.body)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
    }
    
    func extractHexColor(from string: String) -> String? {
        let pattern = "^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: string.utf16.count)
        if regex?.firstMatch(in: string, options: [], range: range) != nil {
            return string
        }
        return nil
    }
    
    func isURL(_ string: String) -> Bool {
        if let url = URL(string: string), url.scheme != nil {
            return true
        }
        return false
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        if hexSanitized.count == 6 {
            self.init(red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                      green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                      blue: Double(rgb & 0x0000FF) / 255.0)
        } else if hexSanitized.count == 3 {
            self.init(red: Double((rgb & 0xF00) >> 8) / 15.0,
                      green: Double((rgb & 0x0F0) >> 4) / 15.0,
                      blue: Double(rgb & 0x00F) / 15.0)
        } else {
            return nil
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(ClipboardManager())
    }
}
