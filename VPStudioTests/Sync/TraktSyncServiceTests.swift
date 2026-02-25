import Testing
import Foundation
@testable import VPStudio

// MARK: - Stub Session Helper

private func makeTraktStubSession(
    handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
) -> URLSession {
    URLProtocolHarness.makeSession(handler: handler)
}

// MARK: - TraktSyncService – addRating

@Suite("TraktSyncService - addRating")
struct TraktAddRatingTests {

    @Test func addRatingSendsCorrectBody() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedBody: [String: Any]?
            var capturedPath: String?
            var capturedMethod: String?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            state.capturedPath = request.url?.path
            state.capturedMethod = request.httpMethod
            if let body = request.httpBody ?? readStream(request.httpBodyStream) {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = #"{"added":{"movies":1,"shows":0,"episodes":0}}"#
            return (response, Data(payload.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.addRating(imdbId: "tt1234567", rating: 8, type: .movie)

        #expect(state.capturedPath?.hasSuffix("/sync/ratings") == true)
        #expect(state.capturedMethod == "POST")

        // Verify the movies array contains the imdb id and rating
        let movies = state.capturedBody?["movies"] as? [[String: Any]]
        #expect(movies?.count == 1)
        let firstMovie = movies?[0]
        let ids = firstMovie?["ids"] as? [String: String]
        #expect(ids?["imdb"] == "tt1234567")
        #expect(firstMovie?["rating"] as? Int == 8)
    }

    @Test func addRatingForShowSendsShowsKey() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedBody: [String: Any]?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            if let body = request.httpBody ?? readStream(request.httpBodyStream) {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = #"{"added":{"movies":0,"shows":1,"episodes":0}}"#
            return (response, Data(payload.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.addRating(imdbId: "tt0903747", rating: 10, type: .series)

        let shows = state.capturedBody?["shows"] as? [[String: Any]]
        #expect(shows?.count == 1)
        #expect(shows?[0]["rating"] as? Int == 10)
        let ids = shows?[0]["ids"] as? [String: String]
        #expect(ids?["imdb"] == "tt0903747")
    }

    @Test func addRatingThrowsNotConnectedWithoutToken() async {
        let service = TraktSyncService(clientId: "client", clientSecret: "secret")
        do {
            try await service.addRating(imdbId: "tt1234567", rating: 5, type: .movie)
            Issue.record("Expected TraktError.notConnected")
        } catch let error as TraktError {
            if case .notConnected = error { /* OK */ }
            else { Issue.record("Unexpected TraktError: \(error)") }
        } catch { Issue.record("Unexpected error: \(error)") }
    }
}

// MARK: - TraktSyncService – Token Refresh Callback

@Suite("TraktSyncService - Token Refresh Callback")
struct TraktTokenRefreshCallbackTests {

    @Test func onTokensRefreshedCalledAfterExchangeCode() async throws {
        final class CallbackState: @unchecked Sendable {
            var refreshedAccess: String?
            var refreshedRefresh: String?
        }
        let callbackState = CallbackState()

        let session = makeTraktStubSession { request in
            let url = request.url!
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = """
            {"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":7776000,"created_at":1600000000}
            """
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(
            clientId: "client",
            clientSecret: "secret",
            session: session,
            onTokensRefreshed: { access, refresh in
                callbackState.refreshedAccess = access
                callbackState.refreshedRefresh = refresh
            }
        )

        try await service.exchangeCode("code-123")

        #expect(callbackState.refreshedAccess == "new-access")
        #expect(callbackState.refreshedRefresh == "new-refresh")
    }

    @Test func onTokensRefreshedCalledAfter401Refresh() async throws {
        final class CallbackState: @unchecked Sendable {
            var refreshedAccess: String?
            var callCount = 0
            var getCallCount = 0
        }
        let callbackState = CallbackState()

        let session = makeTraktStubSession { request in
            let url = request.url!
            let path = url.path

            // Token refresh endpoint
            if request.httpMethod == "POST" && path.hasSuffix("/oauth/token") {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                let body = #"{"access_token":"refreshed-token","refresh_token":"refreshed-refresh"}"#
                return (response, Data(body.utf8))
            }

            // GET endpoint: first call 401, second call success
            callbackState.getCallCount += 1
            if callbackState.getCallCount == 1 {
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }

            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(
            clientId: "client",
            clientSecret: "secret",
            session: session,
            onTokensRefreshed: { access, refresh in
                callbackState.refreshedAccess = access
                callbackState.callCount += 1
            }
        )

        await service.setTokens(access: "expired-token", refresh: "valid-refresh")
        let _: [TraktItem] = try await service.getWatchlist(type: .movie)

        #expect(callbackState.callCount == 1)
        #expect(callbackState.refreshedAccess == "refreshed-token")
    }
}

// MARK: - TraktSyncService – History Pagination

@Suite("TraktSyncService - History Pagination")
struct TraktHistoryPaginationTests {

    @Test func getHistoryIncludesPageParam() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        let _ = try await service.getHistory(type: .movie, page: 3)

        let urlString = state.capturedURL?.absoluteString ?? ""
        #expect(urlString.contains("page=3"))
        #expect(urlString.contains("limit=50"))
    }

    @Test func getHistoryDefaultsToPage1() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedURL: URL?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            state.capturedURL = request.url
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        let _ = try await service.getHistory(type: .series)

        let urlString = state.capturedURL?.absoluteString ?? ""
        #expect(urlString.contains("page=1"))
    }

    @Test func getHistoryShowsUsesShowsPath() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedPath: String?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            state.capturedPath = request.url?.path
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("[]".utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        let _ = try await service.getHistory(type: .series)

        #expect(state.capturedPath?.contains("/sync/history/shows") == true)
    }
}

// MARK: - TraktSyncService – addToWatchlist Body

@Suite("TraktSyncService - addToWatchlist Body Verification")
struct TraktAddToWatchlistBodyTests {

    @Test func addToWatchlistMovieSendsMoviesArray() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedBody: [String: Any]?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            if let body = request.httpBody ?? readStream(request.httpBodyStream) {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"added":{"movies":1,"shows":0,"episodes":0}}"#.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.addToWatchlist(imdbId: "tt9876543", type: .movie)

        let movies = state.capturedBody?["movies"] as? [[String: Any]]
        #expect(movies?.count == 1)
        let ids = movies?[0]["ids"] as? [String: String]
        #expect(ids?["imdb"] == "tt9876543")
        #expect(state.capturedBody?["shows"] == nil)
    }

    @Test func addToWatchlistShowSendsShowsArray() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedBody: [String: Any]?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            if let body = request.httpBody ?? readStream(request.httpBodyStream) {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"added":{"movies":0,"shows":1,"episodes":0}}"#.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        await service.setTokens(access: "token", refresh: nil)
        try await service.addToWatchlist(imdbId: "tt0903747", type: .series)

        let shows = state.capturedBody?["shows"] as? [[String: Any]]
        #expect(shows?.count == 1)
        let ids = shows?[0]["ids"] as? [String: String]
        #expect(ids?["imdb"] == "tt0903747")
        #expect(state.capturedBody?["movies"] == nil)
    }
}

// MARK: - TraktSyncService – Device Code Flow

@Suite("TraktSyncService - Device Code Flow")
struct TraktDeviceCodeFlowTests {

    @Test func requestDeviceCodeSendsClientId() async throws {
        final class CapturedState: @unchecked Sendable {
            var capturedBody: [String: Any]?
            var capturedPath: String?
        }
        let state = CapturedState()

        let session = makeTraktStubSession { request in
            state.capturedPath = request.url?.path
            if let body = request.httpBody ?? readStream(request.httpBodyStream) {
                state.capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"device_code":"dev123","user_code":"ABCD1234","verification_url":"https://trakt.tv/activate","expires_in":600,"interval":5}
            """
            return (response, Data(payload.utf8))
        }

        let service = TraktSyncService(clientId: "my-client", clientSecret: "my-secret", session: session)
        let deviceCode = try await service.requestDeviceCode()

        #expect(state.capturedPath?.hasSuffix("/oauth/device/code") == true)
        #expect(state.capturedBody?["client_id"] as? String == "my-client")
        #expect(deviceCode.deviceCode == "dev123")
        #expect(deviceCode.userCode == "ABCD1234")
        #expect(deviceCode.verificationUrl == "https://trakt.tv/activate")
        #expect(deviceCode.expiresIn == 600)
        #expect(deviceCode.interval == 5)
    }

    @Test func pollDeviceTokenReturnsPendingOn400() async throws {
        let session = makeTraktStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        let result = try await service.pollDeviceToken(deviceCode: "dev123")

        if case .pending = result { /* OK */ }
        else { Issue.record("Expected .pending, got \(result)") }
    }

    @Test func pollDeviceTokenReturnsSlowDownOn429() async throws {
        let session = makeTraktStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        let result = try await service.pollDeviceToken(deviceCode: "dev123")

        if case .slowDown = result { /* OK */ }
        else { Issue.record("Expected .slowDown, got \(result)") }
    }

    @Test func pollDeviceTokenReturnsSuccessOn200() async throws {
        let session = makeTraktStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"access_token":"acc-tok","refresh_token":"ref-tok","token_type":"Bearer","expires_in":7776000,"created_at":1600000000}"#
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        let result = try await service.pollDeviceToken(deviceCode: "dev123")

        if case .success(let access, let refresh) = result {
            #expect(access == "acc-tok")
            #expect(refresh == "ref-tok")
        } else {
            Issue.record("Expected .success, got \(result)")
        }
    }

    @Test func pollDeviceTokenThrowsExpiredOn410() async {
        let session = makeTraktStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 410, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        do {
            _ = try await service.pollDeviceToken(deviceCode: "dev123")
            Issue.record("Expected TraktError.deviceCodeExpired")
        } catch let error as TraktError {
            if case .deviceCodeExpired = error { /* OK */ }
            else { Issue.record("Unexpected error: \(error)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func pollDeviceTokenThrowsDeniedOn418() async {
        let session = makeTraktStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 418, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let service = TraktSyncService(clientId: "client", clientSecret: "secret", session: session)
        do {
            _ = try await service.pollDeviceToken(deviceCode: "dev123")
            Issue.record("Expected TraktError.deviceCodeDenied")
        } catch let error as TraktError {
            if case .deviceCodeDenied = error { /* OK */ }
            else { Issue.record("Unexpected error: \(error)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func pollDeviceTokenCallsOnTokensRefreshed() async throws {
        final class CallbackState: @unchecked Sendable {
            var refreshedAccess: String?
        }
        let callbackState = CallbackState()

        let session = makeTraktStubSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"access_token":"dev-access","refresh_token":"dev-refresh"}"#
            return (response, Data(body.utf8))
        }

        let service = TraktSyncService(
            clientId: "client",
            clientSecret: "secret",
            session: session,
            onTokensRefreshed: { access, _ in
                callbackState.refreshedAccess = access
            }
        )

        let result = try await service.pollDeviceToken(deviceCode: "dev123")
        if case .success = result {
            #expect(callbackState.refreshedAccess == "dev-access")
        } else {
            Issue.record("Expected .success")
        }
    }
}

// MARK: - TraktError Tests

@Suite("TraktError — Device Code")
struct TraktErrorDeviceCodeTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [TraktError] = [
            .invalidURL,
            .httpError(500),
            .unauthorized,
            .notConnected,
            .deviceCodeExpired,
            .deviceCodeDenied,
            .deviceCodeInvalid,
            .deviceCodeAlreadyUsed,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - DeviceCodeResponse Tests

@Suite("DeviceCodeResponse")
struct DeviceCodeResponseTests {

    @Test func decodesFromJSON() throws {
        let json = """
        {"device_code":"abc","user_code":"XYZ","verification_url":"https://trakt.tv/activate","expires_in":600,"interval":5}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(DeviceCodeResponse.self, from: data)
        #expect(response.deviceCode == "abc")
        #expect(response.userCode == "XYZ")
        #expect(response.verificationUrl == "https://trakt.tv/activate")
        #expect(response.expiresIn == 600)
        #expect(response.interval == 5)
    }
}

// MARK: - TraktDefaults Tests

@Suite("TraktDefaults")
struct TraktDefaultsTests {

    @Test func placeholderCredentialsReturnNil() {
        let result = TraktDefaults.resolvedCredentials(userClientId: nil, userClientSecret: nil)
        #expect(result == nil)
    }

    @Test func userOverrideUsedWhenProvided() {
        let result = TraktDefaults.resolvedCredentials(
            userClientId: "my-id",
            userClientSecret: "my-secret"
        )
        #expect(result?.clientId == "my-id")
        #expect(result?.clientSecret == "my-secret")
    }

    @Test func emptyUserOverrideFallsThroughToDefaults() {
        // With placeholders, should return nil
        let result = TraktDefaults.resolvedCredentials(userClientId: "", userClientSecret: "")
        #expect(result == nil)
    }

    @Test func hasBundledCredentialsIsFalseWithPlaceholders() {
        // Static check — placeholders should not count as bundled
        #expect(TraktDefaults.hasBundledCredentials == false)
    }

    @Test func partialUserOverrideWithOnlyClientIdReturnsNil() {
        let result = TraktDefaults.resolvedCredentials(userClientId: "my-id", userClientSecret: nil)
        #expect(result == nil)
    }

    @Test func partialUserOverrideWithOnlySecretReturnsNil() {
        let result = TraktDefaults.resolvedCredentials(userClientId: nil, userClientSecret: "my-secret")
        #expect(result == nil)
    }
}

// MARK: - Helper

/// Reads all bytes from an InputStream (handles cases where httpBody is nil but httpBodyStream is present).
private func readStream(_ stream: InputStream?) -> Data? {
    guard let stream else { return nil }
    stream.open()
    defer { stream.close() }

    var output = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        if read <= 0 { break }
        output.append(buffer, count: read)
    }
    return output
}
