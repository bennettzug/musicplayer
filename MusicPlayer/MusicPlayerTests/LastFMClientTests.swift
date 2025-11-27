@testable import MusicPlayer
import XCTest
import CryptoKit

final class LastFMClientTests: XCTestCase {
    private let apiKey = "TEST_KEY"
    private let apiSecret = "TEST_SECRET"
    private let mockHost = "example.com"

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        MockURLProtocol.allowedHost = nil
        super.tearDown()
    }

    @MainActor func testUpdateNowPlayingSignsRequest() async throws {
        let expectation = expectation(description: "updateNowPlaying")
        MockURLProtocol.allowedHost = mockHost
        MockURLProtocol.requestHandler = { request in
            defer { expectation.fulfill() }

            guard let body = Self.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8) else {
                XCTFail("Missing body")
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let params = Self.decodeForm(bodyString)
            XCTAssertEqual(params["albumArtist"], "Album Artist")
            XCTAssertEqual(params["trackNumber"], "1")
            XCTAssertEqual(params["mbid"], "RELEASE_TRACK_MBID")
            let expectedSig = Self.sign(params: params, secret: self.apiSecret)
            XCTAssertEqual(params["api_sig"], expectedSig)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{ "status": "ok" }"#.utf8))
        }

        let session = Self.makeMockSession()
        let client = LastFMClient(apiKey: apiKey, apiSecret: apiSecret, baseURL: URL(string: "https://\(mockHost)")!, session: session)

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Test Song",
            duration: 120,
            trackNumber: 1,
            artist: "Track Artist",
            artistSort: nil,
            musicBrainzTrackID: "TRACK_MBID",
            musicBrainzReleaseTrackID: "RELEASE_TRACK_MBID"
        )
        let album = Album(
            title: "Test Album",
            titleSort: nil,
            artist: "Album Artist",
            artistSort: nil,
            year: "2025",
            originalYear: nil,
            coverData: nil,
            tracks: [track],
            musicBrainzAlbumID: "ALBUM_MBID",
            musicBrainzAlbumArtistID: "ALBUM_ARTIST_MBID",
            musicBrainzArtistID: "ARTIST_MBID",
            musicBrainzReleaseGroupID: "RELEASE_GROUP_MBID"
        )

        await client.updateNowPlaying(sessionKey: "SESSION", track: track, album: album)
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor func testScrobbleDoesNotHitNetwork() async throws {
        let expectation = expectation(description: "scrobble")
        MockURLProtocol.allowedHost = mockHost
        MockURLProtocol.requestHandler = { request in
            expectation.fulfill()
            if let body = Self.bodyData(from: request),
               let bodyString = String(data: body, encoding: .utf8) {
                let params = Self.decodeForm(bodyString)
                XCTAssertEqual(params["albumArtist"], "Album Artist")
                XCTAssertEqual(params["trackNumber"], "2")
                XCTAssertEqual(params["mbid"], "RELEASE_TRACK_MBID")
            } else {
                XCTFail("Missing body")
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{ "status": "ok" }"#.utf8))
        }

        let session = Self.makeMockSession()
        let client = LastFMClient(apiKey: apiKey, apiSecret: apiSecret, baseURL: URL(string: "https://\(mockHost)")!, session: session)

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Test Song",
            duration: 240,
            trackNumber: 2,
            artist: "Track Artist",
            artistSort: nil,
            musicBrainzTrackID: "TRACK_MBID",
            musicBrainzReleaseTrackID: "RELEASE_TRACK_MBID"
        )
        let album = Album(
            title: "Test Album",
            titleSort: nil,
            artist: "Album Artist",
            artistSort: nil,
            year: "2025",
            originalYear: nil,
            coverData: nil,
            tracks: [track],
            musicBrainzAlbumID: "ALBUM_MBID",
            musicBrainzAlbumArtistID: "ALBUM_ARTIST_MBID",
            musicBrainzArtistID: "ARTIST_MBID",
            musicBrainzReleaseGroupID: "RELEASE_GROUP_MBID"
        )

        await client.scrobble(sessionKey: "SESSION", track: track, album: album, startDate: Date(timeIntervalSince1970: 1_700_000_000))
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor func testAlbumArtistOverridesFeaturedTrackArtist() async throws {
        let expectation = expectation(description: "artistOverride")
        MockURLProtocol.allowedHost = mockHost
        MockURLProtocol.requestHandler = { request in
            defer { expectation.fulfill() }
            guard let body = Self.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8) else {
                XCTFail("Missing body")
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let params = Self.decodeForm(bodyString)
            XCTAssertEqual(params["artist"], "slowthai")
            XCTAssertEqual(params["track"], "BBF (feat. James Blake)")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{ "status": "ok" }"#.utf8))
        }

        let session = Self.makeMockSession()
        let client = LastFMClient(apiKey: apiKey, apiSecret: apiSecret, baseURL: URL(string: "https://\(mockHost)")!, session: session)

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "BBF",
            duration: 180,
            trackNumber: 1,
            artist: "slowthai feat. James Blake"
        )
        let album = Album(
            title: "Ugly",
            artist: "slowthai",
            year: "2023",
            coverData: nil,
            tracks: [track]
        )

        await client.updateNowPlaying(sessionKey: "SESSION", track: track, album: album)
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor func testCompilationTrackDoesNotOverrideArtistOrTitle() async throws {
        let expectation = expectation(description: "compilationArtist")
        MockURLProtocol.allowedHost = mockHost
        MockURLProtocol.requestHandler = { request in
            defer { expectation.fulfill() }
            guard let body = Self.bodyData(from: request),
                  let bodyString = String(data: body, encoding: .utf8) else {
                XCTFail("Missing body")
                let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
                return (response, Data())
            }
            let params = Self.decodeForm(bodyString)
            XCTAssertEqual(params["artist"], "DJ Logistik")
            XCTAssertEqual(params["track"], "Logistik est sur le mix")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{ "status": "ok" }"#.utf8))
        }

        let session = Self.makeMockSession()
        let client = LastFMClient(apiKey: apiKey, apiSecret: apiSecret, baseURL: URL(string: "https://\(mockHost)")!, session: session)

        let track = Track(
            url: URL(fileURLWithPath: "/tmp/test.mp3"),
            title: "Logistik est sur le mix",
            duration: 200,
            trackNumber: 4,
            artist: "DJ Logistik"
        )
        let album = Album(
            title: "Les Cool Sessions 2",
            artist: "Jimmy Jay",
            year: "1995",
            coverData: nil,
            tracks: [track]
        )

        await client.updateNowPlaying(sessionKey: "SESSION", track: track, album: album)
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

// MARK: - Test helpers

private extension LastFMClientTests {
    static func makeMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func decodeForm(_ body: String) -> [String: String] {
        var dict: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            dict[key] = value
        }
        return dict
    }

    static func sign(params: [String: String], secret: String) -> String {
        let filtered = params.filter { key, _ in key != "format" && key != "callback" && key != "api_sig" }
        let sortedKeys = filtered.keys.sorted()
        var concatenated = ""
        for key in sortedKeys {
            if let value = filtered[key] {
                concatenated += key + value
            }
        }
        concatenated += secret
        let digest = Insecure.MD5.hash(data: Data(concatenated.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody, !body.isEmpty {
            return body
        }
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read > 0 {
                    data.append(buffer, count: read)
                } else {
                    break
                }
            }
            return data.isEmpty ? nil : data
        }
        return nil
    }
}

// MARK: - Mock URLProtocol

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var allowedHost: String?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        if let allowed = allowedHost {
            return host == allowed
        }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
