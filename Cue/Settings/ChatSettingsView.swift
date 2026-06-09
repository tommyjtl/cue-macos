import SwiftUI

private enum ChatConfigurationAnchor: String, Hashable {
    case privateMode
    case cloudMode
}

struct ChatSettingsView: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsLayout.sectionSpacing) {
                    SettingsPageHeader(title: "Chat")

                    ChatActiveModeSection { provider in
                        let anchor: ChatConfigurationAnchor = switch provider {
                        case .ollama: .privateMode
                        case .openAI: .cloudMode
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    }

                    PrivateModeConfigurationSection()
                        .id(ChatConfigurationAnchor.privateMode)

                    CloudModeConfigurationSection()
                        .id(ChatConfigurationAnchor.cloudMode)
                }
                .padding(SettingsLayout.pagePadding)
                .frame(maxWidth: SettingsLayout.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

// MARK: - Active Mode

private struct ChatActiveModeSection: View {
    @Environment(AppModel.self) private var appState
    let onGoToConfiguration: (ConversationProvider) -> Void

    var body: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a model to chat with")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text("Private mode runs models locally through Ollama. Cloud mode uses OpenAI. Configure each provider in the sections below.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Picker("Mode", selection: appState.conversationConfigurationBinding(for: \.provider)) {
                        ForEach(ConversationProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Button("Go to Configuration") {
                        onGoToConfiguration(appState.conversationConfiguration.provider)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, SettingsLayout.rowHorizontalPadding)
            .padding(.vertical, SettingsLayout.rowVerticalPadding)
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
            ChatModeSectionHeader(
                title: isActive ? "Private Mode (Active)" : "Private Mode"
            )

            SettingsCard {
                SettingsCardBody {
                    SettingsFieldGroup(label: "Base URL") {
                        TextField("http://localhost:11434", text: appState.conversationConfigurationBinding(for: \.ollamaBaseURL))
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Model")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 12)

                            if let modelRowTrailingLabel {
                                Text(modelRowTrailingLabel)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Picker("Model", selection: appState.conversationConfigurationBinding(for: \.ollamaModel)) {
                                ForEach(availableOllamaModels) { option in
                                    Text(option.pickerTitle).tag(option.modelName)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(isRefreshingOllamaModels ? "Refreshing..." : "Refresh Models") {
                                Task {
                                    await refreshOllamaModels()
                                }
                            }
                            .disabled(isRefreshingOllamaModels)
                        }

                        Text(selectedOllamaModelOption.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

    private var modelRowTrailingLabel: String? {
        if isRefreshingOllamaModels {
            return "Refreshing..."
        }

        if let ollamaModelsStatus, !ollamaModelsStatus.isEmpty {
            return ollamaModelsStatus
        }

        return nil
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
            ChatModeSectionHeader(
                title: isActive ? "Cloud Mode (Active)" : "Cloud Mode"
            )

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

private struct ChatModeSectionHeader: View {
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            SettingsSectionHeader(title: title)

            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

@ViewBuilder
private func providerFootnotes(_ notes: [String?]) -> some View {
    ForEach(notes.compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { note in
        SettingsFootnote(note)
    }
}
