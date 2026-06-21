import SwiftUI
import KeyboardShortcuts
import Sparkle
import Aptabase

extension KeyboardShortcuts.Name {
    static let togglePopover = Self("togglePopover", default: .init(.v, modifiers: [.command, .shift]))
}

@main
struct ClipdeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class SidebarPanel: NSPanel {
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var sidebarPanel: SidebarPanel!
    var mainWindow: NSWindow!
    var statusBarItem: NSStatusItem!
    var onboardingWindow: NSWindow?
    
    var clipboardManager = ClipboardManager()
    var updaterController: SPUStandardUpdaterController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "historyLimit": 0,
            "playSoundOnCopy": true
        ])
        
        Aptabase.shared.initialize(appKey: "A-EU-8033923024")
        Aptabase.shared.trackEvent("app_launched")
        
        // Enforce Single Instance
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.pythogen.Clipdeck")
        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                existingApp.activate(options: [.activateIgnoringOtherApps])
            }
            NSApp.terminate(nil)
            return
        }
        
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController.updater.checkForUpdatesInBackground()
        
        
        let contentView = ContentView().environmentObject(clipboardManager)
        
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let panelWidth: CGFloat = 400
        
        let panel = SidebarPanel(
            contentRect: NSRect(x: screenRect.maxX - panelWidth, y: screenRect.minY, width: panelWidth, height: screenRect.height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = NSHostingController(rootView: contentView)
        self.sidebarPanel = panel
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Clipdeck"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        self.mainWindow = window
        
        let modeStr = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if modeStr == "Dock Window" {
            NSApp.setActivationPolicy(.regular)
            self.showMainWindow()
        }
        
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        
        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "Clipdeck")
            button.action = #selector(statusBarLeftClicked(_:))
            button.target = self
        }
        
        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
            if mode == "Dock Window" {
                self?.showMainWindow()
            } else {
                self?.toggleSidebar(nil)
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ClosePopover"), object: nil, queue: .main) { [weak self] _ in
            self?.closeSidebar()
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OpenSettings"), object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ClipboardActionOccurred"), object: nil, queue: .main) { [weak self] _ in
            guard let button = self?.statusBarItem?.button else { return }
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Action Completed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "Clipdeck")
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CheckForUpdates"), object: nil, queue: .main) { [weak self] _ in
            self?.updaterController.checkForUpdates(nil)
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("AppModeChanged"), object: nil, queue: .main) { [weak self] notification in
            guard let mode = notification.object as? AppMode else { return }
            if mode == .dock {
                self?.closeSidebar()
                NSApp.setActivationPolicy(.regular)
                self?.showMainWindow()
            } else {
                self?.mainWindow?.orderOut(nil)
                NSApp.setActivationPolicy(.accessory)
            }
        }
        
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showOnboardingWindow()
        }
    }
    
    func showOnboardingWindow() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        
        NSApp.setActivationPolicy(.regular)
        
        let onboardingView = OnboardingView(isPresented: Binding(
            get: { true },
            set: { _ in
                self.onboardingWindow?.close()
                NSApp.setActivationPolicy(.accessory)
            }
        ))
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 250),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.contentView = NSHostingView(rootView: onboardingView)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        window.titlebarAppearsTransparent = true
        self.onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showRightClickMenu(with event: NSEvent) {
        let menu = NSMenu()
        menu.delegate = self
        let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if mode == "Dock Window" {
            menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear Unpinned History", action: #selector(clearHistoryFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Clipdeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        if let button = statusBarItem.button {
            statusBarItem.menu = menu
            button.performClick(nil)
        }
    }

    @objc func statusBarLeftClicked(_ sender: NSStatusBarButton) {
        let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if mode == "Dock Window" {
            showMainWindow()
        } else {
            toggleSidebar(sender)
        }
    }
    
    func menuDidClose(_ menu: NSMenu) {
        statusBarItem.menu = nil
    }
    
    @objc func showMainWindow() {
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func clearHistoryFromMenu() {
        clipboardManager.clearUnpinnedHistory()
    }
    
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    @objc func toggleSidebar(_ sender: AnyObject?) {
        if sidebarPanel.isVisible {
            closeSidebar()
        } else {
            showSidebar()
        }
    }
    
    func showSidebar() {
        guard let screen = NSScreen.main else { return }
        let screenRect = screen.visibleFrame
        let panelWidth: CGFloat = 400
        
        // Start off-screen to the right
        let startFrame = NSRect(x: screenRect.maxX, y: screenRect.minY, width: panelWidth, height: screenRect.height)
        let targetFrame = NSRect(x: screenRect.maxX - panelWidth, y: screenRect.minY, width: panelWidth, height: screenRect.height)
        
        if !sidebarPanel.isVisible {
            sidebarPanel.setFrame(startFrame, display: false)
            sidebarPanel.alphaValue = 0.0
            sidebarPanel.makeKeyAndOrderFront(nil)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sidebarPanel.animator().setFrame(targetFrame, display: true)
            sidebarPanel.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }
    
    func closeSidebar() {
        guard let screen = NSScreen.main else {
            sidebarPanel.orderOut(nil)
            return
        }
        
        let screenRect = screen.visibleFrame
        let panelWidth: CGFloat = 400
        let targetFrame = NSRect(x: screenRect.maxX, y: screenRect.minY, width: panelWidth, height: screenRect.height)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            sidebarPanel.animator().setFrame(targetFrame, display: true)
            sidebarPanel.animator().alphaValue = 0.0
        }, completionHandler: {
            self.sidebarPanel.orderOut(nil)
        })
    }
    
    var settingsWindow: NSWindow?
    
    @objc func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if mode == "Dock Window" {
            showMainWindow()
        } else {
            if !self.sidebarPanel.isVisible {
                showSidebar()
            } else {
                self.sidebarPanel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
}
