import SwiftUI

struct AddModelView: View {
    @Environment(\.dismiss) private var dismiss

    // Account sign-in state (Anthropic + ChatGPT + Google) — mirrors ModelFormView so the
    // manager can tell "Add" is possible once a subscription/account flow is ready.
    @ObservedObject private var claudeOAuth = ClaudeOAuthService.shared
    @ObservedObject private var chatgptOAuth = ChatGPTOAuthService.shared
    @ObservedObject private var googleOAuth = GoogleOAuthService.shared

    @State private var name: String = ""
    @State private var selectedProvider: LLMProvider = .anthropic
    @State private var apiKey: String = ""
    @State private var model: String = LLMProvider.anthropic.defaultModel
    @State private var baseURL: String = LLMProvider.anthropic.defaultBaseURL
    @State private var supportsVision: Bool = true
    @State private var smallContext: Bool = false

    @State private var availableModels: [ModelFetcher.RemoteModel] = []
    @State private var isFetchingModels: Bool = false
    @State private var fetchError: String?
    @State private var keyValidated: Bool = false

    let onAdd: (ModelConfig) -> Void

    var body: some View {
        NavigationStack {
            Form {
                ModelFormView(
                    name: $name,
                    selectedProvider: $selectedProvider,
                    apiKey: $apiKey,
                    model: $model,
                    baseURL: $baseURL,
                    supportsVision: $supportsVision,
                    smallContext: $smallContext,
                    availableModels: $availableModels,
                    isFetchingModels: $isFetchingModels,
                    fetchError: $fetchError,
                    keyValidated: $keyValidated,
                    resetModelOnProviderChange: true
                )
            }
            .ogFormStyle()
            .navigationTitle("Add Model")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                prefillIfExistingKey(for: selectedProvider)
            }
            .onChange(of: selectedProvider) { _, newProvider in
                prefillIfExistingKey(for: newProvider)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let config = ModelConfig(
                            id: UUID().uuidString,
                            name: name.isEmpty ? selectedProvider.displayName : name,
                            provider: selectedProvider.rawValue,
                            apiKey: apiKey,
                            model: model,
                            baseURL: baseURL,
                            supportsVision: supportsVision,
                            smallContext: smallContext
                        )
                        onAdd(config)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
    }

    // MARK: - Pre-fill from existing saved model

    /// Whether the "Add" button may be tapped for the current provider. The old rule
    /// (`apiKey.isEmpty`) permanently disabled the button for the providers that have no API
    /// key to paste — ChatGPT/Gemini-Vertex subscriptions, Apple Intelligence, and `.custom`
    /// local servers whose key is optional — so a ChatGPT subscription model could never be
    /// saved. Per provider: key providers need a key; account providers need the connection;
    /// `.custom`/`.appleOnDevice` need nothing.
    private var canAdd: Bool {
        switch selectedProvider {
        case .local:
            return !model.isEmpty
        case .custom, .appleOnDevice:
            return true
        case .chatgpt:
            return chatgptOAuth.isConnected
        case .geminiVertex:
            return googleOAuth.isConnected
        case .anthropic:
            return !apiKey.isEmpty || claudeOAuth.isConnected
        default:
            return !apiKey.isEmpty
        }
    }

    /// If the user already has a saved model for this provider, pre-fill the API key
    /// and auto-fetch the model list so they don't have to re-enter credentials.
    private func prefillIfExistingKey(for provider: LLMProvider) {
        guard provider != .local, provider != .appleOnDevice,
              let existing = Config.savedModels.first(where: {
                  $0.llmProvider == provider && !$0.apiKey.isEmpty
              }) else { return }
        apiKey = existing.apiKey
        if provider.showBaseURL && !existing.baseURL.isEmpty {
            baseURL = existing.baseURL
        }
        // Run fetch after the current onChange cycle (model list was just reset by ModelFormView)
        Task { await fetchModels() }
    }

    // MARK: - Model Fetching

    private func fetchModels() async {
        isFetchingModels = true
        fetchError = nil
        let models = await ModelFetcher.fetchModels(
            provider: selectedProvider,
            apiKey: apiKey,
            baseURL: baseURL
        )
        isFetchingModels = false
        if models.isEmpty {
            fetchError = "Couldn't find any models. Double-check your API key and try again."
            keyValidated = false
        } else {
            availableModels = models
            keyValidated = true
            if !models.contains(where: { $0.id == model }) {
                model = models.first(where: { $0.id == selectedProvider.defaultModel })?.id
                    ?? models.first?.id ?? model
            }
        }
    }
}
