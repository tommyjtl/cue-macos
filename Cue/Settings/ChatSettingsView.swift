import SwiftUI

struct ChatSettingsView: View {
    var body: some View {
        SettingsDetailScaffold(title: "Chat") {
            VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                ChatActiveModeSection()
                PrivateModeConfigurationSection()
                CloudModeConfigurationSection()
            }
        }
    }
}

// MARK: - Active Mode

private struct ChatActiveModeSection: View {
    @Environment(AppModel.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: "Active Mode")

            SettingsCard {
                SettingsCardBody {
                    SettingsFieldGroup(label: "Mode") {
                        Picker("Mode", selection: appState.conversationConfigurationBinding(for: \.provider)) {
                            ForEach(ConversationProvider.allCases) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            SettingsFootnote("Cue uses the selected mode when sending chat messages. Configure each mode below.")
        }
    }
}

// MARK: - Private Mode

private struct PrivateModeConfigurationSection: View {
    @Environment(AppModel.self) private var appState
    @State private var availableOllamaModels = OllamaModelCatalog.fallbackOptions
    @State private var isRefreshingOllamaModels = false
    @State private var ollamaModelsStatus: String?

    private let ollamaModelDiscoveryService = OllamaModelDiscoveryService()

    private var isActive: Bool {
        appState.conversationConfiguration.provider == .ollama
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: isActive ? "Private Mode (Active)" : "Private Mode")

            SettingsCard {
                SettingsCardBody {
                    SettingsFieldGroup(label: "Base URL") {
                        TextField("http://localhost:11434", text: appState.conversationConfigurationBinding(for: \.ollamaBaseURL))
                            .textFieldStyle(.roundedBorder)
                    }

                    SettingsFieldGroup(label: "Model") {
                        Picker("Model", selection: appState.conversationConfigurationBinding(for: \.ollamaModel)) {
                            ForEach(availableOllamaModels) { option in
                                Text(option.pickerTitle).tag(option.modelName)
                            }
                        }
                        .labelsHidden()

                        HStack {
                            Button(isRefreshingOllamaModels ? "Refreshing..." : "Refresh Models") {
                                Task {
                                    await refreshOllamaModels()
                                }
                            }
                            .disabled(isRefreshingOllamaModels)

                            Spacer()

                            Text(selectedOllamaModelOption.source == .installed ? "Installed via /api/tags" : "Curated fallback")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }

                    ollamaThinkingControl

                    SettingsFieldGroup(label: "API Key") {
                        SecureField("Ollama API Key", text: appState.conversationConfigurationBinding(for: \.ollamaAPIKey))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                SettingsRowDivider()

                SettingsToggleRow(
                    title: "Web Search",
                    subtitle: "Use Ollama hosted web search and fetch tools for current information.",
                    isOn: appState.conversationConfigurationBinding(for: \.ollamaUseWebSearch)
                )

                SettingsRowDivider()

                SettingsToggleRow(
                    title: "OCR images before sending",
                    subtitle: ocrSubtitle,
                    isOn: ocrImagesBinding
                )
            }

            providerFootnotes([
                "API keys are stored in UserDefaults for the prototype. Move this to Keychain before shipping.",
                selectedOllamaModelOption.summary,
                selectedOllamaModelOption.thinkingSupport.statusDescription,
                ollamaModelsStatus,
                "When OCR is enabled, attached images are run through Apple Vision and sent as structured text instead of raw image data."
            ])
        }
        .onAppear {
            availableOllamaModels = OllamaModelCatalog.mergedOptions(
                OllamaModelCatalog.fallbackOptions,
                currentModelName: appState.conversationConfiguration.ollamaModel
            )
            normalizeOllamaThinkingMode()

            Task {
                await refreshOllamaModels()
            }
        }
        .onChange(of: appState.conversationConfiguration.ollamaModel, initial: false) { _, _ in
            normalizeOllamaThinkingMode()
        }
    }

    @ViewBuilder
    private var ollamaThinkingControl: some View {
        switch selectedOllamaModelOption.thinkingSupport {
        case .unsupported:
            SettingsFieldGroup(label: "Thinking") {
                Text("Unavailable for this model")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        case .toggle:
            SettingsFieldGroup(label: "Thinking") {
                Toggle("Enable extended reasoning for supported Ollama models.", isOn: ollamaThinkingToggleBinding)
            }
        case let .levels(modes):
            SettingsFieldGroup(label: "Thinking") {
                Picker("Thinking", selection: appState.conversationConfigurationBinding(for: \.ollamaThinkingMode)) {
                    ForEach(modes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private var ocrSubtitle: String {
        if appState.ocrImagesForLocalModels {
            "On — images are converted to text before sending."
        } else {
            "Off — images are sent directly to the model."
        }
    }

    private var ocrImagesBinding: Binding<Bool> {
        Binding(
            get: { appState.ocrImagesForLocalModels },
            set: { appState.updateOCRImagesForLocalModels($0) }
        )
    }

    private var selectedOllamaModelOption: OllamaModelOption {
        availableOllamaModels.first(where: { $0.modelName == appState.conversationConfiguration.ollamaModel })
            ?? OllamaModelCatalog.option(for: appState.conversationConfiguration.ollamaModel, source: .current)
    }

    private var ollamaThinkingToggleBinding: Binding<Bool> {
        Binding(
            get: { appState.conversationConfiguration.ollamaThinkingMode == .on },
            set: { isEnabled in
                var configuration = appState.conversationConfiguration
                configuration.ollamaThinkingMode = isEnabled ? .on : .off
                appState.updateConversationConfiguration(configuration)
            }
        )
    }

    @MainActor
    private func refreshOllamaModels() async {
        isRefreshingOllamaModels = true
        defer { isRefreshingOllamaModels = false }

        do {
            let discoveredModels = try await ollamaModelDiscoveryService.fetchAvailableModels(
                baseURL: appState.conversationConfiguration.ollamaBaseURL
            )
            availableOllamaModels = OllamaModelCatalog.mergedOptions(
                discoveredModels,
                currentModelName: appState.conversationConfiguration.ollamaModel
            )
            ollamaModelsStatus = discoveredModels.isEmpty
                ? "No installed Ollama models were returned. Showing the current configuration only."
                : "Loaded \(discoveredModels.count) installed model(s) from Ollama."
        } catch {
            availableOllamaModels = OllamaModelCatalog.mergedOptions(
                OllamaModelCatalog.fallbackOptions,
                currentModelName: appState.conversationConfiguration.ollamaModel
            )
            ollamaModelsStatus = "Could not load installed Ollama models. Showing curated model options instead."
        }

        normalizeOllamaThinkingMode()
    }

    private func normalizeOllamaThinkingMode() {
        var configuration = appState.conversationConfiguration
        let normalizedMode = selectedOllamaModelOption.thinkingSupport.normalized(configuration.ollamaThinkingMode)
        guard configuration.ollamaThinkingMode != normalizedMode else {
            return
        }
        configuration.ollamaThinkingMode = normalizedMode
        appState.updateConversationConfiguration(configuration)
    }
}

// MARK: - Cloud Mode

private struct CloudModeConfigurationSection: View {
    @Environment(AppModel.self) private var appState

    private var isActive: Bool {
        appState.conversationConfiguration.provider == .openAI
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionHeader(title: isActive ? "Cloud Mode (Active)" : "Cloud Mode")

            SettingsCard {
                SettingsCardBody {
                    SettingsFieldGroup(label: "Model") {
                        HStack {
                            TextField("gpt-5.4", text: appState.conversationConfigurationBinding(for: \.openAIModel))
                                .textFieldStyle(.roundedBorder)

                            SettingsChangeButton("Reset") {
                                appState.resetConversationConfiguration()
                            }
                        }
                    }

                    SettingsFieldGroup(label: "API Key") {
                        SecureField("OpenAI API Key", text: appState.conversationConfigurationBinding(for: \.openAIAPIKey))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                SettingsRowDivider()

                SettingsToggleRow(
                    title: "Web Search",
                    subtitle: "Use the OpenAI Responses API web search tool for current information.",
                    isOn: appState.conversationConfigurationBinding(for: \.openAIUseWebSearch)
                )
            }

            providerFootnotes([
                "API keys are stored in UserDefaults for the prototype. Move this to Keychain before shipping."
            ])
        }
    }
}

// MARK: - Shared

@ViewBuilder
private func providerFootnotes(_ notes: [String?]) -> some View {
    ForEach(notes.compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { note in
        SettingsFootnote(note)
    }
}
