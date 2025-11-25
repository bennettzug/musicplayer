import Foundation
import AppKit
import CryptoKit

struct LastFMClient {
    // Prefer injecting via init; defaults resolve from a local plist (ignored) or env, then placeholders.
    static let defaultAPIKey = SecretsLoader.apiKey
    static let defaultAPISecret = SecretsLoader.apiSecret

    /// Last.fm strongly prefers an identifiable User-Agent on all API calls.
    /// Change this to whatever makes sense for your app.
    static let userAgent = "LocalAlbumPlayer/1.0 (macOS; scrobbler)"

    private let baseURL: URL
    private let apiKey: String
    private let apiSecret: String
    private let session: URLSession

    init(
        apiKey: String = LastFMClient.defaultAPIKey,
        apiSecret: String = LastFMClient.defaultAPISecret,
        baseURL: URL = URL(string: "https://ws.audioscrobbler.com/2.0/")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.baseURL = baseURL
        self.session = session
    }

    struct Session: Codable {
        let key: String
        let username: String
    }

    // MARK: - Public API

    func beginAuthFlow() async throws -> String {
        let token = try await requestToken()
        if let url = authURL(token: token) {
            NSWorkspace.shared.open(url)
        }
        return token
    }

    func completeAuth(token: String) async throws -> Session {
        let params: [String: String] = [
            "api_key": apiKey,
            "method": "auth.getSession",
            "token": token,
            "format": "json"
        ]

        let apiSig = sign(params: params)
        var body = params
        body["api_sig"] = apiSig

        let data = try await post(body: body)
        let decoded = try JSONDecoder().decode(SessionResponse.self, from: data)
        return Session(key: decoded.session.key, username: decoded.session.name)
    }

    /// track.updateNowPlaying
    /// Used as soon as a user starts listening to a track. :contentReference[oaicite:4]{index=4}
    func updateNowPlaying(sessionKey: String, track: Track, album: Album) async {
        var params: [String: String] = [
            "api_key": apiKey,
            "method": "track.updateNowPlaying",
            "artist": track.artist,
            "track": track.title,
            "sk": sessionKey,
            "format": "json"
        ]

        // Optional metadata per API docs.
        if !album.title.isEmpty {
            params["album"] = album.title
        }
        if track.duration > 0 {
            params["duration"] = "\(Int(track.duration))"
        }

        let apiSig = sign(params: params)
        var body = params
        body["api_sig"] = apiSig

        _ = try? await post(body: body)
    }

    /// track.scrobble
    /// Called when the track has satisfied the scrobble conditions. :contentReference[oaicite:5]{index=5}
    func scrobble(sessionKey: String, track: Track, album: Album, startDate: Date) async {
        let timestamp = Int(startDate.timeIntervalSince1970)

        var params: [String: String] = [
            "api_key": apiKey,
            "method": "track.scrobble",
            "artist": track.artist,
            "track": track.title,
            "timestamp": "\(timestamp)",
            "sk": sessionKey,
            "format": "json"
        ]

        // Optional fields as per track.scrobble docs.
        if !album.title.isEmpty {
            params["album"] = album.title
        }
        if track.duration > 0 {
            params["duration"] = "\(Int(track.duration))"
        }

        // For a single scrobble, array notation (artist[0], etc.) can be omitted. :contentReference[oaicite:6]{index=6}

        let apiSig = sign(params: params)
        var body = params
        body["api_sig"] = apiSig

        _ = try? await post(body: body)
    }

    // MARK: - Helpers

    private func requestToken() async throws -> String {
        let params: [String: String] = [
            "api_key": apiKey,
            "method": "auth.getToken",
            "format": "json"
        ]

        let apiSig = sign(params: params)
        var body = params
        body["api_sig"] = apiSig

        let data = try await post(body: body)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return decoded.token
    }

    private func authURL(token: String) -> URL? {
        var comps = URLComponents(string: "https://www.last.fm/api/auth")
        comps?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return comps?.url
    }

    /// Shared POST for all write methods (auth + scrobbling).
    private func post(body: [String: String]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Last.fm JSON error shape: { "error": <Int>, "message": <String> }
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                throw NSError(
                    domain: "LastFM",
                    code: http.statusCode,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "\(apiError.message) (code \(apiError.error))"
                    ]
                )
            }
            throw NSError(
                domain: "LastFM",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"]
            )
        }

        // For now we return raw data; callers can choose to inspect lfm status if needed.
        return data
    }

    /// Build api_sig according to Last.fm auth spec:
    /// sort param names, concatenate name+value, append shared secret, MD5. :contentReference[oaicite:7]{index=7}
    private func sign(params: [String: String]) -> String {
        // Exclude non-signed parameters per Last.fm spec.
        let filtered = params.filter { key, _ in
            key != "format" && key != "callback"
        }

        let sortedKeys = filtered.keys.sorted()
        var concatenated = ""
        for key in sortedKeys {
            if let value = filtered[key] {
                concatenated += key + value
            }
        }
        concatenated += apiSecret

        return md5(concatenated)
    }

    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Encoding helpers

    /// Encode parameters as application/x-www-form-urlencoded (UTF-8).
    private static func formURLEncoded(_ params: [String: String]) -> Data {
        // Deterministic ordering is not required by the API for the body,
        // but it makes debugging easier.
        let keys = params.keys.sorted()
        let pairs: [String] = keys.compactMap { key in
            guard let value = params[key] else { return nil }
            let encodedKey = percentEncode(key)
            let encodedValue = percentEncode(value)
            return "\(encodedKey)=\(encodedValue)"
        }
        // Safe to force-unwrap; UTF-8 encoding of ASCII-safe form data cannot fail.
        return pairs.joined(separator: "&").data(using: .utf8)!
    }

    /// RFC 3986-style percent-encoding suitable for form bodies.
    private static func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        // Remove characters that must be encoded in application/x-www-form-urlencoded.
        allowed.remove(charactersIn: "&=+?")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Responses

    private struct TokenResponse: Codable {
        let token: String
    }

    private struct SessionResponse: Codable {
        let session: SessionData

        struct SessionData: Codable {
            let key: String
            let name: String
            // "subscriber" exists but is not needed here.
        }
    }

    private struct APIError: Codable {
        let error: Int
        let message: String
    }

    private enum SecretsLoader {
        static var apiKey: String {
            load(key: "LASTFM_API_KEY") ?? "YOUR_API_KEY"
        }

        static var apiSecret: String {
            load(key: "LASTFM_API_SECRET") ?? "YOUR_API_SECRET"
        }

        private static func load(key: String) -> String? {
            // 1) Explicit path via env
            if let path = ProcessInfo.processInfo.environment["LASTFM_SECRETS_PATH"],
               let value = plistValue(at: URL(fileURLWithPath: path), key: key) {
                return value
            }

            // 2) App Support
            if let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
                let url = appSupport.appendingPathComponent("MusicPlayer/LastFMSecrets.plist")
                if let value = plistValue(at: url, key: key) { return value }
            }

            // 3) Bundle resources
            if let url = Bundle.main.url(forResource: "LastFMSecrets", withExtension: "plist"),
               let value = plistValue(at: url, key: key) { return value }

            // 4) Adjacent to executable
            if let execURL = Bundle.main.executableURL {
                let sibling = execURL.deletingLastPathComponent().appendingPathComponent("LastFMSecrets.plist")
                if let value = plistValue(at: sibling, key: key) { return value }
            }

            // 5) Current working directory
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("LastFMSecrets.plist")
            if let value = plistValue(at: cwd, key: key) { return value }

            // 6) Env vars
            if let env = ProcessInfo.processInfo.environment[key] {
                return env
            }

            return nil
        }

        private static func plistValue(at url: URL, key: String) -> String? {
            guard
                let data = try? Data(contentsOf: url),
                let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                let value = dict[key] as? String,
                !value.isEmpty
            else { return nil }
            return value
        }
    }
}
