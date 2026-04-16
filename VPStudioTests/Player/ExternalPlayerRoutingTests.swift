import Foundation
import Testing
@testable import VPStudio

@Suite("External Player Routing")
struct ExternalPlayerRoutingTests {
    struct PresetCase: Sendable {
        let app: ExternalPlayerApp
        let expectedPrefix: String
    }

    private let streamURL = URL(string: "https://cdn.example.com/video.m3u8?token=abc&lang=en")!

    private static let presetCases: [PresetCase] = [
        PresetCase(app: .infuse, expectedPrefix: "infuse://x-callback-url/play?url="),
        PresetCase(app: .skybox, expectedPrefix: "skybox://open?url="),
        PresetCase(app: .moonPlayer, expectedPrefix: "moonplayer://open?url="),
        PresetCase(app: .vlc, expectedPrefix: "vlc-x-callback://x-callback-url/stream?url="),
    ]

    @Test
    func appParsingDefaultsToBuiltInForUnknownValues() {
        #expect(ExternalPlayerApp.fromStoredValue(nil) == .builtIn)
        #expect(ExternalPlayerApp.fromStoredValue("  ") == .builtIn)
        #expect(ExternalPlayerApp.fromStoredValue("unknown") == .builtIn)
        #expect(ExternalPlayerApp.fromStoredValue("VLC") == .vlc)
    }

    @Test
    func builtInPlayerDoesNotGenerateLaunchURL() {
        let url = ExternalPlayerRouting.launchURL(for: streamURL, app: .builtIn)
        #expect(url == nil)
    }

    @Test(arguments: presetCases)
    func presetAppsGenerateExpectedLaunchURLs(data: PresetCase) {
        let url = ExternalPlayerRouting.launchURL(for: streamURL, app: data.app)

        let expected = data.expectedPrefix + encoded(streamURL.absoluteString)
        #expect(url?.absoluteString == expected)
    }

    @Test
    func customTemplateReplacesEncodedPlaceholder() {
        let template = "myplayer://open?source={url}"
        let url = ExternalPlayerRouting.launchURL(for: streamURL, app: .custom, customURLTemplate: template)
        let expected = "myplayer://open?source=\(encoded(streamURL.absoluteString))"
        #expect(url?.absoluteString == expected)
    }

    @Test
    func customTemplateReplacesRawPlaceholder() {
        let sourceURL = URL(string: "https://cdn.example.com/video.m3u8?token=abc")!
        let template = "myplayer://open?source={raw_url}"
        let url = ExternalPlayerRouting.launchURL(for: sourceURL, app: .custom, customURLTemplate: template)
        let expected = "myplayer://open?source=\(encoded(sourceURL.absoluteString))"
        #expect(url?.absoluteString == expected)
    }

    @Test
    func customTemplateWithoutPlaceholderAppendsEncodedStreamURL() {
        let template = "myplayer://open?source="
        let url = ExternalPlayerRouting.launchURL(for: streamURL, app: .custom, customURLTemplate: template)
        let expected = "myplayer://open?source=\(encoded(streamURL.absoluteString))"
        #expect(url?.absoluteString == expected)
    }

    @Test
    func customTemplateRequiresNonEmptyValue() {
        let nilTemplate = ExternalPlayerRouting.launchURL(for: streamURL, app: .custom, customURLTemplate: nil)
        let emptyTemplate = ExternalPlayerRouting.launchURL(for: streamURL, app: .custom, customURLTemplate: "   ")
        #expect(nilTemplate == nil)
        #expect(emptyTemplate == nil)
    }

    @Test
    func customTemplateRejectsUnsupportedPlaceholders() {
        let url = ExternalPlayerRouting.launchURL(
            for: streamURL,
            app: .custom,
            customURLTemplate: "myplayer://open?source={token}"
        )
        #expect(url == nil)
        #expect(
            ExternalPlayerRouting.validationResult(forCustomTemplate: "myplayer://open?source={token}")
                == .invalid("Unsupported placeholder {token}. Use {url}.")
        )
    }

    @Test
    func customTemplateRequiresAScheme() {
        let url = ExternalPlayerRouting.launchURL(
            for: streamURL,
            app: .custom,
            customURLTemplate: "open?source={url}"
        )
        #expect(url == nil)
        #expect(
            ExternalPlayerRouting.validationResult(forCustomTemplate: "open?source={url}")
                == .invalid("Template must start with a URL scheme such as player://")
        )
    }

    @Test
    func settingsLoaderReadsExternalPlayerValues() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("external-player-settings.sqlite").path
        let database = try DatabaseManager(path: dbPath)
        try await database.migrate()

        let settings = SettingsManager(database: database, secretStore: TestSecretStore())
        try await settings.setString(key: SettingsKeys.externalPlayerApp, value: ExternalPlayerApp.vlc.rawValue)
        try await settings.setString(
            key: SettingsKeys.externalPlayerURLTemplate,
            value: " custom://play?url={raw_url} "
        )

        let preference = await ExternalPlayerSettings.loadPreference(from: settings)
        #expect(preference.app == .vlc)
        #expect(preference.customURLTemplate == "custom://play?url={url}")
    }

    private func encoded(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
