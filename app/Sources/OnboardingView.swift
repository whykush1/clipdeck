import SwiftUI
import ServiceManagement

enum OnboardingStep {
    case welcome
    case accessibility
    case loginItem
}

struct OnboardingView: View {
    @Binding var isPresented: Bool
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var hasPermissions = false
    
    var body: some View {
        ZStack {
            Color.clear.background(.ultraThinMaterial)
                .ignoresSafeArea()
            
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView(nextAction: moveToNextStep)
                case .accessibility:
                    AccessibilityStepView(
                        hasPermissions: $hasPermissions,
                        nextAction: moveToNextStep
                    )
                case .loginItem:
                    LoginItemStepView(finishAction: {
                        isPresented = false
                    })
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .frame(width: 350, height: 250)
        .onAppear {
            checkPermissions()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if currentStep == .accessibility && !hasPermissions {
                checkPermissions()
            }
        }
    }
    
    private func moveToNextStep() {
        withAnimation {
            switch currentStep {
            case .welcome:
                checkPermissions()
                if hasPermissions {
                    currentStep = .loginItem
                } else {
                    currentStep = .accessibility
                }
            case .accessibility:
                currentStep = .loginItem
            case .loginItem:
                isPresented = false
            }
        }
    }
    
    private func checkPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(options)
        if result != hasPermissions {
            withAnimation {
                hasPermissions = result
                if currentStep == .accessibility && result {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        moveToNextStep()
                    }
                }
            }
        }
    }
}

struct WelcomeStepView: View {
    var nextAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
            
            Text("Welcome to Clipdeck")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            
            Text("Lightweight, organized, and instantly searchable clipboard manager for macOS.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
                .padding(.horizontal)
            
            Spacer()
            
            Button("Get Started") {
                nextAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(30)
    }
}

struct AccessibilityStepView: View {
    @Binding var hasPermissions: Bool
    var nextAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.system(size: 20, weight: .bold))
            
            Text("Please allow the following permission for Clipdeck to function:")
                .font(.body)
                .multilineTextAlignment(.center)
            
            Button("Accessibility settings") {
                openSystemSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            
            Spacer()
            
            Button("Skip for now") {
                nextAction()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
        .padding(30)
    }
    
    private func openSystemSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

struct LoginItemStepView: View {
    var finishAction: () -> Void
    @State private var isEnabled = SMAppService.mainApp.status == .enabled
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Launch at Login")
                .font(.system(size: 20, weight: .bold))
            
            Text("Do you want Clipdeck to start automatically when you turn on your Mac? (You can change this later in Settings)")
                .font(.body)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Button("No, skip") {
                    if isEnabled { toggleLoginItem() } // Ensure it's off
                    finishAction()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button("Yes, start automatically") {
                    if !isEnabled { toggleLoginItem() } // Ensure it's on
                    finishAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.top, 10)
            
            Spacer()
        }
        .padding(30)
    }
    
    private func toggleLoginItem() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
            if isEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    finishAction()
                }
            }
        } catch {
            print("Failed to toggle login item: \(error)")
        }
    }
}
