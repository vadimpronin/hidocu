//
//  OnboardingView.swift
//  HiDocu
//
//  First-launch wizard guiding the user through initial setup.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.container) private var container
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var currentStep = 0
    @State private var storageConfigured = false
    @State private var showAccessError = false
    @State private var accessErrorMessage = ""

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch currentStep {
                case 0:
                    welcomeStep
                case 1:
                    storageStep
                case 2:
                    finishStep
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation footer
            HStack {
                // Step indicators
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                }

                if currentStep < totalSteps - 1 {
                    Button("Continue") {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == 1 && !storageConfigured)
                } else {
                    Button("Get Started") {
                        hasCompletedOnboarding = true
                        AppLogger.ui.info("Onboarding completed")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 400)
        .alert("Access Denied", isPresented: $showAccessError) {
            Button("OK") {}
        } message: {
            Text(accessErrorMessage)
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to HiDocu")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your local-first hub for HiDock recordings.\nManage, transcribe, and organize your audio with full control.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Spacer()
        }
        .padding()
    }

    // MARK: - Step 2: Storage Setup

    private var storageStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            Text("Choose Storage Location")
                .font(.title)
                .fontWeight(.semibold)

            Text("Select where HiDocu should keep your audio recordings.\nYou can change this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            // Current path display
            if let path = container?.fileSystemService.storageDirectory?.path {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 400)
            }

            HStack(spacing: 12) {
                Button("Choose Folder...") {
                    chooseFolder()
                }
                .buttonStyle(.bordered)

                Button("Use Default") {
                    container?.fileSystemService.resetToDefaultDirectory()
                    storageConfigured = true
                    AppLogger.ui.info("Onboarding: using default storage")
                }
                .buttonStyle(.bordered)
            }

            if storageConfigured {
                Label("Storage configured", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Default directory is always available
            if container?.fileSystemService.storageDirectory != nil {
                storageConfigured = true
            }
        }
    }

    // MARK: - Step 3: Finish

    private var finishStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("You're All Set")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Connect your HiDock device via USB to start importing recordings,\nor drag audio files into the app.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "cable.connector", text: "Plug in HiDock and click Import")
                featureRow(icon: "square.and.arrow.down", text: "Drag & drop audio files to import")
                featureRow(icon: "text.bubble", text: "Add transcriptions manually or via AI")
                featureRow(icon: "gear", text: "Configure API keys in Settings later")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer()
        }
        .padding()
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.callout)
        }
    }

    // MARK: - Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a folder for your recordings"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try container?.fileSystemService.setStorageDirectory(url)
            storageConfigured = true
            AppLogger.ui.info("Onboarding: storage set to \(url.path)")
        } catch {
            accessErrorMessage = "Cannot access folder: \(error.localizedDescription)"
            showAccessError = true
        }
    }
}
