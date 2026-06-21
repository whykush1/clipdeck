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
                    Picker("", selection: $appMode) {
                        ForEach(AppMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .labelsHidden()
                    .frame(width: 300)
                    .onChange(of: appMode) { newValue in
                        NotificationCenter.default.post(name: NSNotification.Name("AppModeChanged"), object: newValue)
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
                
                Divider()
                
                Button("Check for Updates...") {
                    NotificationCenter.default.post(name: NSNotification.Name("CheckForUpdates"), object: nil)
                }
                .padding(.vertical, 4)
                
                Text("Changes to the history limit take effect immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .formStyle(.grouped)
            .padding()
            }
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            Form {
                Text("Excluded Apps")
                    .font(.headline)
                Text("Clipdeck will not save clipboard history when these apps are active.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(excludedApps, id: \.self) { app in
                        HStack {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text(FileManager.default.displayName(atPath: url.path))
                            } else {
                                Text(app)
                            }
                        }
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
            .formStyle(.grouped)
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
