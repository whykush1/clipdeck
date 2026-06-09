import SwiftUI
import KeyboardShortcuts
import Sparkle
import Aptabase

extension KeyboardShortcuts.Name {
    static let togglePopover = Self("togglePopover", default: .init(.v, modifiers: [.command, .shift]))
}

@main
struct ClipDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var popover: NSPopover!
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
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.pythogen.ClipDeck")
        if runningApps.count > 1 {
            if let existingApp = runningApps.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
                existingApp.activate(options: [.activateIgnoringOtherApps])
            }
            NSApp.terminate(nil)
            return
        }
        
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        updaterController.updater.checkForUpdatesInBackground()
        
        let modeStr = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        if modeStr == "Dock Window" {
            NSApp.setActivationPolicy(.regular)
        }
        
        let contentView = ContentView().environmentObject(clipboardManager)
        
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        self.popover = popover
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "ClipDeck"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        self.mainWindow = window
        
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: CGFloat(NSStatusItem.variableLength))
        
        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipDeck")
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        KeyboardShortcuts.onKeyUp(for: .togglePopover) { [weak self] in
            let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
            if mode == "Dock Window" {
                self?.showMainWindow()
            } else {
                self?.togglePopover(nil)
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ClosePopover"), object: nil, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OpenSettings"), object: nil, queue: .main) { [weak self] _ in
            self?.openSettings()
        }
        
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.performClose(nil)
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ClipboardActionOccurred"), object: nil, queue: .main) { [weak self] _ in
            guard let button = self?.statusBarItem?.button else { return }
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Action Completed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                button.image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipDeck")
            }
        }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("CheckForUpdates"), object: nil, queue: .main) { [weak self] _ in
            self?.updaterController.checkForUpdates(nil)
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
    
    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let mode = UserDefaults.standard.string(forKey: "appMode") ?? "Menu Bar"
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) || mode == "Dock Window" {
            let menu = NSMenu()
            if mode == "Dock Window" {
                menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: ""))
            }
            menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Clear Unpinned History", action: #selector(clearHistoryFromMenu), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit ClipDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            
            statusBarItem.menu = menu
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
        } else {
            togglePopover(sender)
        }
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
    
    @objc func togglePopover(_ sender: AnyObject?) {
        if let button = self.statusBarItem.button {
            if self.popover.isShown {
                self.popover.performClose(sender)
            } else {
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                self.popover.contentViewController?.view.window?.makeKey()
            }
        }
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
            if !self.popover.isShown {
                togglePopover(nil)
            } else {
                self.popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }
}
