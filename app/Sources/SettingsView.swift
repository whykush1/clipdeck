import SwiftUI
import ServiceManagement
import KeyboardShortcuts

enum AppMode: String, CaseIterable, Identifiable {
    case menuBar = "Menu Bar"
    case dock = "Dock Window"
    
    var id: String { self.rawValue }
}

struct SettingsView: View {
    @AppStorage("historyLimit") private var historyLimit: Int = 0
    @AppStorage("excludedApps") private var excludedAppsData: Data = Data()
    @AppStorage("playSoundOnCopy") private var playSoundOnCopy: Bool = false
    @AppStorage("ignoreImages") private var ignoreImages: Bool = false
    @AppStorage("ignoreFiles") private var ignoreFiles: Bool = false
    @AppStorage("appMode") private var appMode: AppMode = .menuBar
    
    @State private var launchAtLogin = false
    @State private var excludedApps: [String] = []
    
    var body: some View {
        TabView {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 12) {
                    Text("App Mode")
                        .font(.headline)
                    HStack(spacing: 16) {
                        ModeCardView(
                            title: "Menu Bar",
                            icon: "menubar.rectangle",
                            isSelected: appMode == .menuBar
                        ) {
                            appMode = .menuBar
                            NSApp.setActivationPolicy(.accessory)
                        }
                        
                        ModeCardView(
                            title: "Dock Window",
                            icon: "macwindow",
                            isSelected: appMode == .dock
                        ) {
                            appMode = .dock
                            NSApp.setActivationPolicy(.regular)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 16)
                
                Divider()
                
                Form {
                
                KeyboardShortcuts.Recorder("Global Hotkey:", name: .togglePopover)
                
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update launch at login status: \(error)")
                            launchAtLogin = !newValue
                        }
                    }
                
                Picker("History Limit:", selection: $historyLimit) {
                    Text("50 items").tag(50)
                    Text("100 items").tag(100)
                    Text("500 items").tag(500)
                    Text("Infinite").tag(0)
                }
                .pickerStyle(.menu)
                
                Toggle("Play Sound on Copy", isOn: $playSoundOnCopy)
                Toggle("Ignore Images", isOn: $ignoreImages)
                Toggle("Ignore Files", isOn: $ignoreFiles)
                
                Text("Changes to the history limit take effect immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            Form {
                Text("Excluded Apps")
                    .font(.headline)
                Text("ClipDeck will not save clipboard history when these apps are active.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(excludedApps, id: \.self) { app in
                        Text(app)
                    }
                    .onDelete { indexSet in
                        excludedApps.remove(atOffsets: indexSet)
                        saveExcludedApps()
                    }
                }
                .frame(height: 100)
                .border(Color.secondary.opacity(0.2))
                
                HStack {
                    Button("Add App...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.application]
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        panel.directoryURL = URL(fileURLWithPath: "/Applications")
                        
                        if panel.runModal() == .OK {
                            for url in panel.urls {
                                if let bundle = Bundle(url: url), let bundleIdentifier = bundle.bundleIdentifier {
                                    if !excludedApps.contains(bundleIdentifier) {
                                        excludedApps.append(bundleIdentifier)
                                    }
                                } else {
                                    let name = url.deletingPathExtension().lastPathComponent
                                    if !excludedApps.contains(name) {
                                        excludedApps.append(name)
                                    }
                                }
                            }
                            saveExcludedApps()
                        }
                    }
                    Spacer()
                }
            }
            .padding()
            .onAppear {
                loadExcludedApps()
            }
            .tabItem {
                Label("Exclusions", systemImage: "nosign")
            }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
    
    private func loadExcludedApps() {
        if let decoded = try? JSONDecoder().decode([String].self, from: excludedAppsData) {
            excludedApps = decoded
        }
    }
    
    private func saveExcludedApps() {
        if let encoded = try? JSONEncoder().encode(excludedApps) {
            excludedAppsData = encoded
        }
    }
}

struct ModeCardView: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(width: 120, height: 80)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            .foregroundColor(isSelected ? .accentColor : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 2)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
