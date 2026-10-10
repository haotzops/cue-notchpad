import AppKit
import Combine
import CueCore
import Foundation

enum CueLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var localizationIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .simplifiedChinese: "zh-Hans"
        }
    }
}

enum CueOverflowBehavior: String, CaseIterable, Identifiable {
    case scrollable
    case growWithContent

    var id: String { rawValue }
}

struct AIServiceStatus: Equatable {
    enum Style: Equatable {
        case information
        case error
    }

    let message: String
    let style: Style
}

final class CueSettings: ObservableObject {
    static let defaultWindowWidth = Double(NotchLayoutConstraints.defaultOpenWidth)
    static let defaultWindowHeight = Double(NotchLayoutConstraints.defaultOpenHeight)
    static let minimumWindowHeight = Double(NotchLayoutConstraints.minimumOpenHeight)
    static let maximumWindowHeight = Double(NotchLayoutConstraints.maximumOpenHeight)
    static let minimumWindowWidth = Double(NotchLayoutConstraints.minimumOpenWidth)
    static let maximumWindowWidth = Double(NotchLayoutConstraints.maximumOpenWidth)
    static let defaultEditorFontSize = 16.0
    static let persistenceSchemaVersion = 1
    static let minimumEditorFontSize = 8.0
    static let maximumEditorFontSize = 72.0
    private let defaults: UserDefaults
    private let aiProviderService: any AIProviderService
    private let piIntegrationService: CuePiIntegrationService
    private var modelRefreshTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var balanceCheckTask: Task<Void, Never>?
    private var isSynchronizingProviderConfiguration = false
    private var isSynchronizingProviderProfile = false

    @Published var language: CueLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    @Published var windowWidth: Double {
        didSet {
            let clamped = min(max(windowWidth, Self.minimumWindowWidth), Self.maximumWindowWidth)
            guard clamped == windowWidth else {
                windowWidth = clamped
                return
            }
            defaults.set(windowWidth, forKey: Keys.windowWidth)
        }
    }

    @Published var windowHeight: Double {
        didSet {
            let clamped = min(max(windowHeight, Self.minimumWindowHeight), Self.maximumWindowHeight)
            guard clamped == windowHeight else {
                windowHeight = clamped
                return
            }
            defaults.set(windowHeight, forKey: Keys.windowHeight)
        }
    }

    @Published var overflowBehavior: CueOverflowBehavior {
        didSet { defaults.set(overflowBehavior.rawValue, forKey: Keys.overflowBehavior) }
    }

    @Published var locksPromptWindow: Bool {
        didSet { defaults.set(locksPromptWindow, forKey: Keys.locksPromptWindow) }
    }

    /// Stored as a PostScript name because it remains stable across localized font display names.
    @Published var editorFontName: String {
        didSet { defaults.set(editorFontName, forKey: Keys.editorFontName) }
    }

    @Published var editorFontSize: Double {
        didSet {
            let clamped = min(max(editorFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
            guard clamped == editorFontSize else {
                editorFontSize = clamped
                return
            }
            defaults.set(editorFontSize, forKey: Keys.editorFontSize)
        }
    }

    @Published var insertsSpacesBetweenChineseAndEnglish: Bool {
        didSet { defaults.set(insertsSpacesBetweenChineseAndEnglish, forKey: Keys.insertsSpacesBetweenChineseAndEnglish) }
    }

    @Published var promptExpansionProvider: CueAIProviderID {
        didSet {
            defaults.set(promptExpansionProvider.rawValue, forKey: Keys.promptExpansionProvider)
            guard promptExpansionProvider != oldValue,
                  !isSynchronizingProviderProfile
            else { return }
            if let profile = providerProfiles.first(where: { $0.providerID == promptExpansionProvider }) {
                if activeProviderProfileID != profile.id {
                    activeProviderProfileID = profile.id
                }
                return
            }
            synchronizeProviderSelection()
        }
    }
    @Published var promptExpansionAPI: CueAIAPI {
        didSet {
            guard !isSynchronizingProviderConfiguration,
                  !isSynchronizingProviderProfile,
                  promptExpansionAPI != oldValue
            else { return }
            defaults.set(promptExpansionAPI.rawValue, forKey: apiKey(for: promptExpansionProvider))
            synchronizeAPISelection()
        }
    }
    @Published var promptExpansionModel: String? {
        didSet {
            let key = modelKey(for: promptExpansionProvider, api: promptExpansionAPI)
            if let promptExpansionModel {
                defaults.set(promptExpansionModel, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
    @Published var providerBaseURL: String {
        didSet {
            guard !isSynchronizingProviderConfiguration else { return }
            defaults.set(
                providerBaseURL,
                forKey: baseURLKey(for: promptExpansionProvider, api: promptExpansionAPI)
            )
            resetProviderTasks()
            refreshProviderConfiguration()
        }
    }
    @Published var promptExpansionInstruction: String {
        didSet { defaults.set(promptExpansionInstruction, forKey: Keys.promptExpansionInstruction) }
    }

    @Published private(set) var availableModels = [String]()
    @Published private(set) var isLoadingModels = false
    @Published private(set) var isTestingConnection = false
    @Published private(set) var providerCredentialSource: CueAPIKeySource?
    @Published private(set) var providerHasStoredCredential = false
    @Published private(set) var aiServiceStatus: AIServiceStatus?
    @Published private(set) var providerProfiles: [CueProviderProfile] = []
    @Published var activeProviderProfileID = CueProviderProfile.defaults[0].id {
        didSet {
            guard !isSynchronizingProviderProfile,
                  activeProviderProfileID != oldValue
            else { return }
            defaults.set(activeProviderProfileID, forKey: Keys.activeProviderProfileID)
            persistProviderProfiles()
            synchronizeActiveProviderProfile()
        }
    }
    @Published private(set) var providerBalance: CueProviderBalance?
    @Published private(set) var isCheckingBalance = false

    @Published private(set) var piIntegrationState: PiIntegrationState = .notInstalled
    @Published private(set) var piIntegrationErrorMessage: String?

    @Published var toggleShortcut: CueShortcut {
        didSet { save(toggleShortcut, key: Keys.toggleShortcut) }
    }
    @Published var previousShortcut: CueShortcut {
        didSet { save(previousShortcut, key: Keys.previousShortcut) }
    }
    @Published var nextShortcut: CueShortcut {
        didSet { save(nextShortcut, key: Keys.nextShortcut) }
    }
    @Published var promptExpansionShortcut: CueShortcut {
        didSet { save(promptExpansionShortcut, key: Keys.promptExpansionShortcut) }
    }

    var localizationIdentifier: String? { language.localizationIdentifier }
    var normalizedWidth: Double { min(max(windowWidth, Self.minimumWindowWidth), Self.maximumWindowWidth) }
    var normalizedHeight: Double { min(max(windowHeight, Self.minimumWindowHeight), Self.maximumWindowHeight) }

    /// Falls back safely if a font selected on another machine is not installed here.
    var editorFont: NSFont {
        NSFont(name: editorFontName, size: CGFloat(editorFontSize))
            ?? .systemFont(ofSize: CGFloat(editorFontSize), weight: .regular)
    }

    func setEditorFont(_ font: NSFont) {
        editorFontName = font.fontName
        editorFontSize = Double(font.pointSize)
    }

    func restoreDefaultEditorFont() {
        editorFontName = Self.defaultEditorFont.fontName
        editorFontSize = Self.defaultEditorFontSize
    }

    func adjustEditorFontSize(by delta: Double) {
        editorFontSize = min(
            max(editorFontSize + delta, Self.minimumEditorFontSize),
            Self.maximumEditorFontSize
        )
    }

    /// Explicitly restores application preferences. API keys and usage history
    /// are separate user data and are intentionally not included.
    func restoreAllSettings() {
        language = .system
        windowWidth = Self.defaultWindowWidth
        windowHeight = Self.defaultWindowHeight
        overflowBehavior = .scrollable
        locksPromptWindow = false
        restoreDefaultEditorFont()
        insertsSpacesBetweenChineseAndEnglish = false
        for provider in CueAIProviderID.allCases {
            let descriptor = provider.descriptor
            for api in descriptor.supportedAPIs {
                defaults.removeObject(forKey: Self.modelKey(for: provider, api: api))
            }
            defaults.removeObject(forKey: Self.apiKey(for: provider))
            for api in descriptor.supportedAPIs {
                defaults.removeObject(forKey: Self.baseURLKey(for: provider, api: api))
            }
        }
        promptExpansionProvider = .deepSeek
        promptExpansionAPI = .openAICompletions
        promptExpansionModel = nil
        providerBaseURL = CueAIProviderID.deepSeek.descriptor.endpoints[0].baseURL!.absoluteString
        promptExpansionInstruction = localizedDefaultPromptInstruction()
        providerProfiles = CueProviderProfile.defaults
        isSynchronizingProviderProfile = true
        activeProviderProfileID = CueProviderProfile.defaults[0].id
        isSynchronizingProviderProfile = false
        persistProviderProfiles()
        synchronizeActiveProviderProfile()
        toggleShortcut = .toggleDefault
        previousShortcut = .previousDefault
        nextShortcut = .nextDefault
        promptExpansionShortcut = .promptExpansionDefault
        aiServiceStatus = nil
    }

    private func localizedDefaultPromptInstruction() -> String {
        Self.defaultPromptInstruction(for: language)
    }

    private static func defaultPromptInstruction(for language: CueLanguage) -> String {
        CueLocalization.string(
            .settingsAIRewriteDefaultPrompt,
            localization: language.localizationIdentifier
        )
    }

    private static var defaultEditorFont: NSFont {
        .systemFont(ofSize: CGFloat(defaultEditorFontSize), weight: .regular)
    }

    init(
        defaults: UserDefaults = .standard,
        aiProviderService: any AIProviderService = HTTPAIProviderService(),
        piIntegrationService: CuePiIntegrationService = .shared
    ) {
        self.defaults = defaults
        self.aiProviderService = aiProviderService
        self.piIntegrationService = piIntegrationService
        if defaults.object(forKey: Keys.schemaVersion) == nil {
            defaults.set(Self.persistenceSchemaVersion, forKey: Keys.schemaVersion)
        }
        defaults.register(defaults: [
            Keys.language: CueLanguage.system.rawValue,
            Keys.windowWidth: Self.defaultWindowWidth,
            Keys.windowHeight: Self.defaultWindowHeight,
            Keys.overflowBehavior: CueOverflowBehavior.scrollable.rawValue,
            Keys.locksPromptWindow: false,
            Keys.editorFontName: Self.defaultEditorFont.fontName,
            Keys.editorFontSize: Self.defaultEditorFontSize,
            Keys.insertsSpacesBetweenChineseAndEnglish: false,
        ])

        let selectedLanguage = CueLanguage(
            rawValue: defaults.string(forKey: Keys.language) ?? CueLanguage.system.rawValue
        ) ?? .system
        language = selectedLanguage
        let storedWidth = defaults.double(forKey: Keys.windowWidth)
        windowWidth = min(max(storedWidth, Self.minimumWindowWidth), Self.maximumWindowWidth)
        let storedHeight = defaults.double(forKey: Keys.windowHeight)
        windowHeight = min(max(storedHeight, Self.minimumWindowHeight), Self.maximumWindowHeight)
        overflowBehavior = CueOverflowBehavior(
            rawValue: defaults.string(forKey: Keys.overflowBehavior) ?? "scrollable"
        ) ?? .scrollable
        locksPromptWindow = defaults.bool(forKey: Keys.locksPromptWindow)
        editorFontName = defaults.string(forKey: Keys.editorFontName) ?? Self.defaultEditorFont.fontName
        let storedFontSize = defaults.double(forKey: Keys.editorFontSize)
        editorFontSize = min(max(storedFontSize, Self.minimumEditorFontSize), Self.maximumEditorFontSize)
        insertsSpacesBetweenChineseAndEnglish = defaults.bool(forKey: Keys.insertsSpacesBetweenChineseAndEnglish)
        let selectedProvider = CueAIProviderID(
            rawValue: defaults.string(forKey: Keys.promptExpansionProvider) ?? CueAIProviderID.deepSeek.rawValue
        ) ?? .deepSeek
        let selectedAPI = Self.storedAPI(in: defaults, for: selectedProvider)
        promptExpansionProvider = selectedProvider
        promptExpansionAPI = selectedAPI
        promptExpansionModel = Self.storedModel(in: defaults, for: selectedProvider, api: selectedAPI)
        providerBaseURL = Self.storedBaseURL(in: defaults, for: selectedProvider, api: selectedAPI)
        // A stored instruction is user data, including a prior default that a
        // user may have edited; never replace it during an application update.
        promptExpansionInstruction = defaults.string(forKey: Keys.promptExpansionInstruction)
            ?? Self.defaultPromptInstruction(for: selectedLanguage)
        toggleShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.toggleShortcut,
            fallback: .toggleDefault
        )
        previousShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.previousShortcut,
            fallback: .previousDefault
        )
        nextShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.nextShortcut,
            fallback: .nextDefault
        )
        promptExpansionShortcut = Self.loadShortcut(
            from: defaults,
            key: Keys.promptExpansionShortcut,
            fallback: .promptExpansionDefault
        )

        let profileDocument = Self.loadProviderProfiles(from: defaults)
        providerProfiles = profileDocument.profiles
        isSynchronizingProviderProfile = true
        activeProviderProfileID = defaults.string(forKey: Keys.activeProviderProfileID)
            ?? profileDocument.activeProfileID
        isSynchronizingProviderProfile = false
        synchronizeActiveProviderProfile()

        piIntegrationState = piIntegrationService.state()
        refreshProviderConfiguration()
    }

    var piIntegrationDirectoryPath: String {
        piIntegrationService.integrationDirectory.path
    }

    func refreshPiIntegrationState() {
        piIntegrationState = piIntegrationService.state()
    }

    func installPiIntegration() {
        runPiIntegrationAction { try piIntegrationService.install() }
    }

    func repairPiIntegration() {
        runPiIntegrationAction { try piIntegrationService.repair() }
    }

    func uninstallPiIntegration() {
        runPiIntegrationAction { try piIntegrationService.uninstall() }
    }

    private func runPiIntegrationAction(_ action: () throws -> Void) {
        do {
            try action()
            piIntegrationErrorMessage = nil
        } catch {
            piIntegrationErrorMessage = error.localizedDescription
        }
        refreshPiIntegrationState()
    }

    var activeProviderProfile: CueProviderProfile {
        providerProfiles.first { $0.id == activeProviderProfileID }
            ?? providerProfiles.first
            ?? CueProviderProfile.defaults[0]
    }

    var selectedProvider: CueAIProvider? {
        let profile = activeProviderProfile
        guard let baseURL = normalizedURL(profile.baseURL) else { return nil }
        let endpoint = CueProviderEndpointCatalog.resolve(for: profile)
        let providerID = profile.providerID ?? .custom
        let authentication = profile.providerID?.descriptor.authentication ?? .apiDefault
        let knownModels = profile.providerID?.descriptor.endpoint(for: profile.api)?.knownModels ?? []
        return CueAIProvider(
            id: providerID,
            name: profile.name,
            api: profile.api,
            baseURL: baseURL,
            authentication: authentication,
            supportsModelDiscovery: endpoint.supportsModelDiscovery,
            knownModels: knownModels,
            modelsURL: endpoint.modelsURL,
            balanceURL: endpoint.balanceURL,
            balanceJSONPointer: endpoint.balanceJSONPointer
        )
    }

    var selectedProviderDescriptor: CueAIProviderDescriptor { activeProviderProfile.providerID?.descriptor ?? CueAIProviderID.custom.descriptor }
    var selectedProviderName: String { activeProviderProfile.name }
    var selectedProviderSupportedAPIs: [CueAIAPI] { [activeProviderProfile.api] }
    var providerAllowsBaseURLOverride: Bool { true }
    var providerCredentialConfigured: Bool { providerCredentialSource != nil }
    var providerCredentialIsRemovable: Bool { providerHasStoredCredential }
    var activeEndpointResolution: CueEndpointResolution {
        CueProviderEndpointCatalog.resolve(for: activeProviderProfile)
    }
    var canCheckBalance: Bool { selectedProvider?.balanceURL != nil }

    var providerConfigurationValid: Bool { normalizedURL(activeProviderProfile.baseURL) != nil }

    func selectProviderProfile(_ id: String) {
        guard providerProfiles.contains(where: { $0.id == id }) else { return }
        activeProviderProfileID = id
    }

    @discardableResult
    func addCustomProviderProfile() -> String {
        let id = "custom-\(UUID().uuidString.lowercased())"
        let profile = CueProviderProfile(
            id: id,
            kind: .custom,
            name: "Custom API",
            providerID: nil,
            api: .openAICompletions,
            baseURL: "https://example.com/v1",
            modelID: nil,
            manualModelsURL: nil,
            manualBalanceURL: nil,
            balanceJSONPointer: "/balance"
        )
        providerProfiles.append(profile)
        persistProviderProfiles()
        activeProviderProfileID = id
        return id
    }

    func updateProviderProfile(_ profile: CueProviderProfile) {
        guard let index = providerProfiles.firstIndex(where: { $0.id == profile.id }) else { return }
        providerProfiles[index] = profile
        persistProviderProfiles()
        if profile.id == activeProviderProfileID {
            synchronizeActiveProviderProfile()
        }
    }

    func removeProviderProfile(_ id: String) {
        guard let profile = providerProfiles.first(where: { $0.id == id }), profile.isCustom else { return }
        providerProfiles.removeAll { $0.id == id }
        try? CueAPIKeyStore.removeAPIKey(forProfileID: profile.credentialID)
        persistProviderProfiles()
        if activeProviderProfileID == id {
            activeProviderProfileID = providerProfiles.first?.id ?? CueProviderProfile.defaults[0].id
        }
    }

    func saveProviderAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setAIServiceStatus(.settingsAPIKeyMissing, style: .error)
            return
        }
        do {
            try CueAPIKeyStore.saveAPIKey(trimmed, forProfileID: activeProviderProfile.credentialID)
            refreshProviderConfiguration()
            setAIServiceStatus(.settingsAPIKeySaved)
            refreshModelsIfPossible()
        } catch {
            setAIServiceStatus(error.localizedDescription, style: .error)
        }
    }

    func checkProviderHealth() {
        guard let provider = selectedProvider,
              let model = promptExpansionModel,
              !isTestingConnection
        else {
            if !providerConfigurationValid {
                setAIServiceStatus(.settingsProviderURLInvalid, style: .error)
            } else if promptExpansionModel == nil {
                setAIServiceStatus(.settingsChooseModel, style: .error)
            }
            return
        }
        let apiKey = try? CueAPIKeyStore.loadAPIKey(forProfileID: activeProviderProfile.credentialID)
        guard apiKey != nil || !activeProviderProfile.requiresAPIKey else {
            setAIServiceStatus(.settingsAPIKeyMissing, style: .error)
            return
        }

        isTestingConnection = true
        setAIServiceStatus(.settingsCheckingServiceHealth)
        let requestedProfileID = activeProviderProfileID
        let requestedAPI = provider.api
        healthCheckTask = Task { @MainActor [weak self] in
            defer {
                if self?.matches(requestedProfileID, api: requestedAPI) == true {
                    self?.isTestingConnection = false
                }
            }
            do {
                guard let service = self?.aiProviderService else { return }
                try await service.validate(provider: provider, apiKey: apiKey, model: model)
                guard self?.matches(requestedProfileID, api: requestedAPI) == true else { return }
                self?.setAIServiceStatus(.settingsServiceHealthy)
            } catch {
                guard self?.matches(requestedProfileID, api: requestedAPI) == true else { return }
                self?.setAIServiceStatus(.settingsAIRewriteUnavailable, style: .error)
            }
        }
    }

    func checkProviderBalance() {
        guard let provider = selectedProvider,
              provider.balanceURL != nil,
              !isCheckingBalance
        else {
            setAIServiceStatus(.settingsBalanceUnavailable, style: .error)
            return
        }
        let apiKey = try? CueAPIKeyStore.loadAPIKey(forProfileID: activeProviderProfile.credentialID)
        guard apiKey != nil || !activeProviderProfile.requiresAPIKey else {
            setAIServiceStatus(.settingsAPIKeyMissing, style: .error)
            return
        }

        isCheckingBalance = true
        setAIServiceStatus(.settingsCheckingBalance)
        let requestedProfileID = activeProviderProfileID
        let requestedAPI = provider.api
        balanceCheckTask = Task { @MainActor [weak self] in
            defer {
                if self?.matches(requestedProfileID, api: requestedAPI) == true {
                    self?.isCheckingBalance = false
                }
            }
            do {
                guard let service = self?.aiProviderService else { return }
                let balance = try await service.balance(provider: provider, apiKey: apiKey)
                guard self?.matches(requestedProfileID, api: requestedAPI) == true else { return }
                self?.providerBalance = balance
                self?.setAIServiceStatus(.settingsBalanceAvailable)
            } catch {
                guard self?.matches(requestedProfileID, api: requestedAPI) == true else { return }
                self?.setAIServiceStatus(.settingsBalanceUnavailable, style: .error)
            }
        }
    }

    func refreshModelsIfPossible() {
        guard let provider = selectedProvider,
              provider.supportsModelDiscovery,
              !isLoadingModels
        else { return }
        let apiKey = try? CueAPIKeyStore.loadAPIKey(forProfileID: activeProviderProfile.credentialID)
        guard apiKey != nil || !activeProviderProfile.requiresAPIKey else { return }

        isLoadingModels = true
        setAIServiceStatus(.settingsLoadingModels)
        let requestedProfileID = activeProviderProfileID
        let requestedAPI = provider.api
        modelRefreshTask = Task { @MainActor [weak self] in
            defer {
                if self?.matches(requestedProfileID, api: requestedAPI) == true {
                    self?.isLoadingModels = false
                }
            }
            do {
                guard let service = self?.aiProviderService else { return }
                var models = try await service.availableModels(provider: provider, apiKey: apiKey)
                guard self?.matches(requestedProfileID, api: requestedAPI) == true else { return }
                if let selectedModel = self?.activeProviderProfile.modelID, !models.contains(selectedModel) {
                    models.insert(selectedModel, at: 0)
                }
                guard !models.isEmpty else {
                    self?.setAIServiceStatus(.settingsAIRewriteUnavailable, style: .error)
                    return
                }
                self?.availableModels = models
                self?.aiServiceStatus = nil
            } catch {
                guard self?.matches(requestedProfileID, api: requestedAPI) == true else { return }
                self?.setAIServiceStatus(.settingsAIRewriteUnavailable, style: .error)
            }
        }
    }

    func removeProviderAPIKey() {
        do {
            try CueAPIKeyStore.removeAPIKey(forProfileID: activeProviderProfile.credentialID)
            refreshProviderConfiguration()
            setAIServiceStatus(.settingsProviderAPIKeyRemoved)
        } catch {
            setAIServiceStatus(error.localizedDescription, style: .error)
        }
    }

    /// Per-provider credential queries for the provider management list.
    func credentialSource(for provider: CueAIProviderID) -> CueAPIKeySource? {
        try? CueAPIKeyStore.source(for: provider)
    }

    func hasStoredCredential(for provider: CueAIProviderID) -> Bool {
        (try? CueAPIKeyStore.hasStoredAPIKey(for: provider)) == true
    }

    /// Removes a provider's stored credential without switching the active
    /// provider, so the management list can clear any provider directly.
    func removeCredential(for provider: CueAIProviderID) {
        do {
            try CueAPIKeyStore.removeAPIKey(for: provider)
            if provider == promptExpansionProvider {
                refreshProviderConfiguration()
            }
            setAIServiceStatus(.settingsProviderAPIKeyRemoved)
        } catch {
            setAIServiceStatus(error.localizedDescription, style: .error)
        }
    }

    func refreshProviderConfiguration() {
        providerCredentialSource = try? CueAPIKeyStore.source(forProfileID: activeProviderProfile.credentialID)
        providerHasStoredCredential = (try? CueAPIKeyStore.hasStoredAPIKey(forProfileID: activeProviderProfile.credentialID)) == true
        guard let provider = selectedProvider else {
            availableModels = []
            return
        }
        availableModels = provider.knownModels
        if (providerCredentialConfigured || !activeProviderProfile.requiresAPIKey)
            && provider.supportsModelDiscovery
        {
            refreshModelsIfPossible()
        }
    }

    func credentialSource(for profile: CueProviderProfile) -> CueAPIKeySource? {
        try? CueAPIKeyStore.source(forProfileID: profile.credentialID)
    }

    func hasStoredCredential(for profile: CueProviderProfile) -> Bool {
        (try? CueAPIKeyStore.hasStoredAPIKey(forProfileID: profile.credentialID)) == true
    }

    func localized(_ key: CueLocalizedKey) -> String {
        CueLocalization.string(key, localization: language.localizationIdentifier)
    }

    func expandPrompt(_ text: String, message: String?) async throws -> String? {
        guard let provider = selectedProvider,
              let model = activeProviderProfile.modelID
        else { return nil }
        let apiKey = try CueAPIKeyStore.loadAPIKey(forProfileID: activeProviderProfile.credentialID)
        guard apiKey != nil || !activeProviderProfile.requiresAPIKey else { return nil }
        do {
            let instruction = PromptRewriteTemplate.render(
                promptExpansionInstruction,
                message: message
            )
            let result = try await aiProviderService.rewritePrompt(
                text,
                instruction: instruction,
                provider: provider,
                model: model,
                apiKey: apiKey
            )
            aiServiceStatus = nil
            return result
        } catch {
            setAIServiceStatus(.settingsAIRewriteUnavailable, style: .error)
            throw error
        }
    }

    private func synchronizeActiveProviderProfile() {
        guard let profile = providerProfiles.first(where: { $0.id == activeProviderProfileID }) else { return }
        resetProviderTasks()
        isSynchronizingProviderProfile = true
        promptExpansionProvider = profile.providerID ?? .custom
        promptExpansionAPI = profile.api
        promptExpansionModel = profile.modelID
        providerBaseURL = profile.baseURL
        isSynchronizingProviderProfile = false
        refreshProviderConfiguration()
    }

    private func persistProviderProfiles() {
        let document = CueProviderProfilesDocument(
            schemaVersion: CueProviderProfilesDocument.currentSchemaVersion,
            activeProfileID: activeProviderProfileID,
            profiles: providerProfiles
        )
        guard let data = try? JSONEncoder().encode(document) else { return }
        defaults.set(data, forKey: Keys.providerProfiles)
    }

    private static func loadProviderProfiles(from defaults: UserDefaults) -> CueProviderProfilesDocument {
        guard let data = defaults.data(forKey: Keys.providerProfiles),
              let document = try? JSONDecoder().decode(CueProviderProfilesDocument.self, from: data),
              document.schemaVersion == CueProviderProfilesDocument.currentSchemaVersion,
              !document.profiles.isEmpty
        else {
            return .defaults
        }
        return document
    }

    private func synchronizeProviderSelection() {
        resetProviderTasks()
        isSynchronizingProviderConfiguration = true
        let api = Self.storedAPI(in: defaults, for: promptExpansionProvider)
        promptExpansionAPI = api
        promptExpansionModel = Self.storedModel(in: defaults, for: promptExpansionProvider, api: api)
        providerBaseURL = Self.storedBaseURL(in: defaults, for: promptExpansionProvider, api: api)
        isSynchronizingProviderConfiguration = false
        refreshProviderConfiguration()
    }

    private func synchronizeAPISelection() {
        resetProviderTasks()
        isSynchronizingProviderConfiguration = true
        promptExpansionModel = Self.storedModel(
            in: defaults,
            for: promptExpansionProvider,
            api: promptExpansionAPI
        )
        providerBaseURL = Self.storedBaseURL(
            in: defaults,
            for: promptExpansionProvider,
            api: promptExpansionAPI
        )
        isSynchronizingProviderConfiguration = false
        refreshProviderConfiguration()
    }

    private func resetProviderTasks() {
        modelRefreshTask?.cancel()
        healthCheckTask?.cancel()
        balanceCheckTask?.cancel()
        availableModels = []
        isLoadingModels = false
        isTestingConnection = false
        isCheckingBalance = false
        providerBalance = nil
        aiServiceStatus = nil
    }

    private func matches(_ profileID: String, api: CueAIAPI) -> Bool {
        activeProviderProfileID == profileID && activeProviderProfile.api == api
    }

    private func modelKey(for provider: CueAIProviderID, api: CueAIAPI) -> String {
        Self.modelKey(for: provider, api: api)
    }

    private static func storedModel(
        in defaults: UserDefaults,
        for provider: CueAIProviderID,
        api: CueAIAPI
    ) -> String? {
        defaults.string(forKey: modelKey(for: provider, api: api))
    }

    private static func modelKey(for provider: CueAIProviderID, api: CueAIAPI) -> String {
        if provider == .deepSeek && api == .openAICompletions {
            return Keys.promptExpansionModel
        }
        let base = "\(Keys.promptExpansionModel).\(provider.rawValue)"
        return api == provider.descriptor.defaultAPI ? base : "\(base).\(api.rawValue)"
    }

    private func apiKey(for provider: CueAIProviderID) -> String {
        Self.apiKey(for: provider)
    }

    private static func storedAPI(in defaults: UserDefaults, for provider: CueAIProviderID) -> CueAIAPI {
        let descriptor = provider.descriptor
        let legacyKey = provider == .custom ? Keys.customProviderAPI : apiKey(for: provider)
        guard let rawValue = defaults.string(forKey: legacyKey),
              let api = CueAIAPI(rawValue: rawValue),
              descriptor.supportedAPIs.contains(api)
        else { return descriptor.defaultAPI }
        return api
    }

    private static func apiKey(for provider: CueAIProviderID) -> String {
        provider == .custom ? Keys.customProviderAPI : "promptExpansionAPI.\(provider.rawValue)"
    }

    private func baseURLKey(for provider: CueAIProviderID, api: CueAIAPI) -> String {
        Self.baseURLKey(for: provider, api: api)
    }

    private static func storedBaseURL(
        in defaults: UserDefaults,
        for provider: CueAIProviderID,
        api: CueAIAPI
    ) -> String {
        let descriptor = provider.descriptor
        let key = baseURLKey(for: provider, api: api)
        if let stored = defaults.string(forKey: key), !stored.isEmpty {
            return stored
        }
        return descriptor.endpoint(for: api)?.baseURL?.absoluteString
            ?? (provider == .custom ? "http://localhost:11434/v1" : "")
    }

    private static func baseURLKey(for provider: CueAIProviderID, api: CueAIAPI) -> String {
        if provider == .custom {
            return Keys.customProviderBaseURL
        }
        return "providerBaseURL.\(provider.rawValue).\(api.rawValue)"
    }

    private var normalizedProviderBaseURL: URL? {
        normalizedURL(activeProviderProfile.baseURL)
    }

    private func normalizedURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil,
              let url = components.url
        else { return nil }
        return url
    }

    private func setAIServiceStatus(
        _ key: CueLocalizedKey,
        style: AIServiceStatus.Style = .information
    ) {
        setAIServiceStatus(localized(key), style: style)
    }

    private func setAIServiceStatus(
        _ message: String,
        style: AIServiceStatus.Style = .information
    ) {
        aiServiceStatus = AIServiceStatus(message: message, style: style)
    }

    private func save(_ shortcut: CueShortcut, key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }

    private static func loadShortcut(
        from defaults: UserDefaults,
        key: String,
        fallback: CueShortcut
    ) -> CueShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(CueShortcut.self, from: data)
        else { return fallback }
        return shortcut
    }

    private enum Keys {
        static let schemaVersion = "cueSettingsSchemaVersion"
        static let language = "language"
        static let windowWidth = "windowWidth"
        static let windowHeight = "windowHeight"
        static let overflowBehavior = "overflowBehavior"
        static let locksPromptWindow = "locksPromptWindow"
        static let editorFontName = "editorFontName"
        static let editorFontSize = "editorFontSize"
        static let insertsSpacesBetweenChineseAndEnglish = "insertsSpacesBetweenChineseAndEnglish"
        static let promptExpansionProvider = "promptExpansionProvider"
        static let promptExpansionModel = "promptExpansionModel"
        static let activeProviderProfileID = "activeProviderProfileID"
        static let providerProfiles = "cueProviderProfiles.v1"
        static let customProviderBaseURL = "customProviderBaseURL"
        static let customProviderAPI = "customProviderAPI"
        static let promptExpansionInstruction = "promptExpansionInstruction"
        static let toggleShortcut = "toggleShortcut"
        static let previousShortcut = "previousShortcut"
        static let nextShortcut = "nextShortcut"
        static let promptExpansionShortcut = "promptExpansionShortcut"
    }
}
