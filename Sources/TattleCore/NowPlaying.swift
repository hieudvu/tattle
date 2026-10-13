import Foundation

/// What macOS's Now Playing widget knows about the current media: a title, an
/// artist and which app published it. Browsers publish the page's Media Session,
/// so for a YouTube tab this is the video title and channel.
public struct NowPlayingInfo: Equatable, Codable, Sendable {
    public let title: String
    public let artist: String?
    public let album: String?
    /// The publishing client (for a browser this may be a helper's bundle id).
    public let bundleID: String?
    /// The owning application's bundle id, when the client is a helper.
    public let parentBundleID: String?
    public let isPlaying: Bool

    public init(title: String, artist: String? = nil, album: String? = nil, bundleID: String? = nil, parentBundleID: String? = nil, isPlaying: Bool = true) {
        self.title = title
        self.artist = artist
        self.album = album
        self.bundleID = bundleID
        self.parentBundleID = parentBundleID
        self.isPlaying = isPlaying
    }

    public func withPlaying(_ playing: Bool) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: album, bundleID: bundleID, parentBundleID: parentBundleID, isPlaying: playing)
    }

    /// "Title · Artist", or just the title.
    public var summary: String {
        guard let artist, !artist.isEmpty else { return title }
        return "\(title) · \(artist)"
    }
}

public protocol NowPlayingSource: Sendable {
    func current() -> NowPlayingInfo?
}

public enum NowPlayingParser {
    private struct Wire: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var bundleID: String?
        var parentBundleID: String?
        var rate: Double?
    }

    /// One line of helper output. `null`, blank, malformed or title-less → nil
    /// (nothing is playing, or it isn't media worth naming).
    public static func parse(line: String) -> NowPlayingInfo? {
        guard let data = line.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let title = wire.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        func clean(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
        return NowPlayingInfo(
            title: title, artist: clean(wire.artist), album: clean(wire.album),
            bundleID: clean(wire.bundleID), parentBundleID: clean(wire.parentBundleID),
            isPlaying: (wire.rate ?? 1) > 0
        )
    }
}

public enum NowPlayingMatcher {
    /// The info belongs to `noisemaker` when its app's bundle id is the publisher
    /// (or the publisher's parent app, or a helper whose id extends it).
    /// `bundleID(path)` resolves an `.app` path to its identifier.
    public static func info(for noisemaker: Noisemaker, from info: NowPlayingInfo?, bundleID: (String) -> String?) -> NowPlayingInfo? {
        guard let info, let path = noisemaker.bundlePath, let mine = bundleID(path) else { return nil }
        for candidate in [info.parentBundleID, info.bundleID].compactMap({ $0 }) {
            if candidate == mine || candidate.hasPrefix(mine + ".") { return info }
        }
        return nil
    }
}

/// Transport controls forwarded to whatever app currently owns Now Playing.
public enum NowPlayingCommand: String, Sendable {
    case play, pause, toggle, next, previous
}
