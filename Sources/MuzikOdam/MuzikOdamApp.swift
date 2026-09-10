import SwiftUI
import AppKit
@preconcurrency import AVFoundation
import MediaPlayer
import CoreImage
import UniformTypeIdentifiers
import ImageIO

@main
struct MuzikOdamApp: App {
    @StateObject private var player = MusicPlayer()
    var body: some Scene {
        WindowGroup {
            Group {
                if player.hasCompletedOnboarding { ContentView() } else { OnboardingView() }
            }
            .environmentObject(player).preferredColorScheme(player.theme.colorScheme).tint(player.accent.color).frame(minWidth: 780, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Müzik Odam", systemImage: "music.note") {
            MenuBarNowPlayingView().environmentObject(player)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .newItem) {
                Button(player.text("Müzik Ekle…", "Add Music…")) { player.pickFiles() }.keyboardShortcut("o", modifiers: .command)
                Button(player.text("Müzik Klasörünü Seç…", "Choose Music Folder…")) { player.pickLibraryFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(player.isPlaying ? player.text("Duraklat", "Pause") : player.text("Çal", "Play")) { player.togglePlayback() }.keyboardShortcut(.space, modifiers: [])
                Button(player.text("Sonraki Parça", "Next Track")) { player.next() }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button(player.text("Önceki Parça", "Previous Track")) { player.previous() }.keyboardShortcut(.leftArrow, modifiers: [.command])
            }
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case turkish, english
    var id: String { rawValue }
    var title: String { self == .turkish ? "Türkçe" : "English" }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String { switch self { case .system: language == .turkish ? "Sistem" : "System"; case .light: language == .turkish ? "Açık" : "Light"; case .dark: language == .turkish ? "Koyu" : "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
enum Accent: String, CaseIterable, Identifiable {
    case pink, purple, blue, orange
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String { switch self { case .pink: language == .turkish ? "Pembe" : "Pink"; case .purple: language == .turkish ? "Mor" : "Purple"; case .blue: language == .turkish ? "Mavi" : "Blue"; case .orange: language == .turkish ? "Turuncu" : "Orange" } }
    var color: Color { switch self { case .pink: .pink; case .purple: .purple; case .blue: .blue; case .orange: .orange } }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title, artist, album, recentlyAdded
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String { switch self { case .title: language == .turkish ? "Parça adı" : "Track name"; case .artist: language == .turkish ? "Sanatçı" : "Artist"; case .album: language == .turkish ? "Albüm" : "Album"; case .recentlyAdded: language == .turkish ? "Yeni eklenen" : "Recently added" } }
}

enum LibraryDisplay: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
}

enum RepeatMode: String, CaseIterable {
    case off, all, one
    var icon: String { switch self { case .off: "repeat"; case .all: "repeat"; case .one: "repeat.1" } }
}

enum EqualizerPreset: String, CaseIterable, Identifiable {
    case flat, bassBoost, trebleBoost, rock, pop, classical, electronic
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return language == .turkish ? "Bas Güçlendirme" : "Bass Boost"
        case .trebleBoost: return language == .turkish ? "Tiz Güçlendirme" : "Treble Boost"
        case .rock: return "Rock"
        case .pop: return "Pop"
        case .classical: return language == .turkish ? "Klasik" : "Classical"
        case .electronic: return language == .turkish ? "Elektronik" : "Electronic"
        }
    }
    var gains: [Float] { switch self {
    case .flat: Array(repeating: 0, count: 9)
    case .bassBoost: [7, 6, 4, 2, 0, 0, 0, 0, 0]
    case .trebleBoost: [0, 0, 0, 0, 0, 2, 4, 6, 7]
    case .rock: [5, 3, 1, -1, -2, 1, 3, 4, 5]
    case .pop: [-1, 2, 4, 5, 3, 0, -1, 0, 2]
    case .classical: [4, 3, 1, 0, -1, -1, 0, 2, 3]
    case .electronic: [5, 4, 1, 0, -2, 2, 1, 3, 5]
    } }
}

struct AmbientPalette: Equatable {
    let primary: NSColor
    let secondary: NSColor
    let id: String
    static let fallback = AmbientPalette(primary: .systemPink, secondary: .systemPurple, id: "fallback")
    var primaryColor: Color { Color(nsColor: primary) }
    var secondaryColor: Color { Color(nsColor: secondary) }
}

private final class AmbientPaletteBox: NSObject {
    let palette: AmbientPalette
    init(_ palette: AmbientPalette) { self.palette = palette }
}

final class AmbientArtworkAnalyzer {
    static let shared = AmbientArtworkAnalyzer()
    private let cache = NSCache<NSString, AmbientPaletteBox>()
    private let queue = DispatchQueue(label: "music.ambient-artwork", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])

    private init() { cache.countLimit = 64 }

    func palette(for artwork: Data, key: String, completion: @escaping (AmbientPalette) -> Void) {
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached.palette)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let palette = self.extractPalette(from: artwork, key: key) ?? .fallback
            self.cache.setObject(AmbientPaletteBox(palette), forKey: key as NSString)
            DispatchQueue.main.async { completion(palette) }
        }
    }

    private func extractPalette(from artwork: Data, key: String) -> AmbientPalette? {
        guard let image = CIImage(data: artwork) else { return nil }
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(32 / extent.width, 32 / extent.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = small.extent.integral
        guard let cgImage = context.createCGImage(small, from: bounds) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var buckets: [Int: (count: Int, red: CGFloat, green: CGFloat, blue: CGFloat)] = [:]
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                guard color.alphaComponent > 0.5, brightness > 0.06, brightness < 0.94 else { continue }
                let red = min(1, max(0, color.redComponent))
                let green = min(1, max(0, color.greenComponent))
                let blue = min(1, max(0, color.blueComponent))
                let bucket = (Int(red * 7) << 6) | (Int(green * 7) << 3) | Int(blue * 7)
                var value = buckets[bucket] ?? (0, 0, 0, 0)
                value.count += 1; value.red += red; value.green += green; value.blue += blue
                buckets[bucket] = value
            }
        }
        guard let first = buckets.values.max(by: { $0.count < $1.count }) else { return nil }
        let primary = NSColor(red: first.red / CGFloat(first.count), green: first.green / CGFloat(first.count), blue: first.blue / CGFloat(first.count), alpha: 1)
        let secondaryEntry = buckets.values.sorted { $0.count > $1.count }.first { entry in
            abs(entry.red / CGFloat(entry.count) - primary.redComponent) + abs(entry.green / CGFloat(entry.count) - primary.greenComponent) + abs(entry.blue / CGFloat(entry.count) - primary.blueComponent) > 0.35
        } ?? first
        let secondary = NSColor(red: secondaryEntry.red / CGFloat(secondaryEntry.count), green: secondaryEntry.green / CGFloat(secondaryEntry.count), blue: secondaryEntry.blue / CGFloat(secondaryEntry.count), alpha: 1)
        return AmbientPalette(primary: primary, secondary: secondary, id: key)
    }
}

enum ArtworkThumbnailer {
    static func thumbnailData(from data: Data, maximumDimension: Int = 240) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

struct Playlist: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var trackIDs: [String]
    init(name: String) { id = UUID().uuidString; self.name = name; trackIDs = [] }
}

struct Track: Identifiable, Equatable, Codable {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var year: String?
    var coverData: Data?
    var id: String { url.standardizedFileURL.path }
    var format: String { url.pathExtension.uppercased() }
    func subtitle(language: AppLanguage) -> String {
        let source = artist.isEmpty ? (language == .turkish ? "Yerel dosya" : "Local file") : artist
        return album.isEmpty ? "\(source) • \(format)" : "\(source) — \(album) • \(format)"
    }
    static func read(from url: URL) async -> Track {
        let asset = AVURLAsset(url: url)
        let metadata = (try? await asset.load(.commonMetadata)) ?? []
        func value(_ key: AVMetadataKey) async -> String? {
            guard let item = metadata.first(where: { $0.commonKey == key }) else { return nil }
            return (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let filename = url.deletingPathExtension().lastPathComponent
        let pieces = filename.components(separatedBy: " - ")
        let filenameArtist = pieces.count >= 2 ? pieces[0] : ""
        let filenameTitle = pieces.count >= 3 ? pieces.dropFirst().dropLast().joined(separator: " - ") : (pieces.count == 2 ? pieces[1] : filename)
        func cleaned(_ value: String) -> String {
            value.replacingOccurrences(of: #"\s*\((official[^)]*|lyrics?|audio|video|\d{2,4}k)\)"#, with: "", options: .regularExpression, range: nil).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = await value(.commonKeyTitle)
        let artist = await value(.commonKeyArtist)
        let album = await value(.commonKeyAlbumName)
        let year = await value(.commonKeyCreationDate)?.prefix(4).description
        let artwork: Data?
        if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }) { artwork = try? await item.load(.dataValue) } else { artwork = nil }
        return Track(url: url, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? cleaned(filenameTitle), artist: artist ?? cleaned(filenameArtist), album: album ?? "", year: year, coverData: artwork.flatMap { ArtworkThumbnailer.thumbnailData(from: $0) } ?? artwork)
    }
}

private struct RecordingResponse: Decodable { let recordings: [Recording] }
private struct Recording: Decodable {
    let title: String; let artistCredit: [Artist]?; let releases: [Release]?
    enum CodingKeys: String, CodingKey { case title, artistCredit = "artist-credit", releases }
}
private struct Artist: Decodable { let name: String? }
private struct Release: Decodable { let id: String; let title: String; let date: String? }
private struct ITunesResponse: Decodable { let results: [ITunesSong] }
private struct ITunesSong: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let releaseDate: String?
    let artworkUrl100: String?
}

/// Public MusicBrainz lookups are serialized (one request at a time).
@MainActor
final class MetadataEnricher {
    private var pending: [Track] = []
    private var isWorking = false
    func enqueue(_ tracks: [Track], completion: @escaping (Track) -> Void) { pending.append(contentsOf: tracks); processNext(completion: completion) }
    private func processNext(completion: @escaping (Track) -> Void) {
        guard !isWorking, !pending.isEmpty else { return }
        isWorking = true
        lookup(pending.removeFirst()) { enriched in
            if let enriched { completion(enriched) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.isWorking = false; self?.processNext(completion: completion) }
        }
    }
    private func lookup(_ track: Track, completion: @escaping (Track?) -> Void) {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: [track.artist, track.title].filter { !$0.isEmpty }.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: "TR")
        ]
        URLSession.shared.dataTask(with: components.url!) { data, _, _ in
            guard let data, let result = try? JSONDecoder().decode(ITunesResponse.self, from: data), let match = result.results.first else { DispatchQueue.main.async { completion(nil) }; return }
            var updated = track
            updated.title = match.trackName ?? updated.title
            updated.artist = match.artistName ?? updated.artist
            updated.album = match.collectionName ?? updated.album
            updated.year = match.releaseDate?.prefix(4).description ?? updated.year
            guard let artwork = match.artworkUrl100 else { DispatchQueue.main.async { completion(updated) }; return }
            let largeArtwork = artwork.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            Self.fetchImage(url: largeArtwork) { cover in
                updated.coverData = cover.flatMap { ArtworkThumbnailer.thumbnailData(from: $0) } ?? updated.coverData
                DispatchQueue.main.async { completion(updated) }
            }
        }.resume()
    }
    nonisolated private static func fetchImage(url: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: url) else { completion(nil); return }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            completion((response as? HTTPURLResponse)?.statusCode == 200 ? data : nil)
        }.resume()
    }
}

@MainActor
final class MusicPlayer: NSObject, ObservableObject {
    static let supportedExtensions: Set<String> = ["aac", "aif", "aiff", "alac", "caf", "flac", "m4a", "m4b", "mka", "mp2", "mp3", "mp4", "oga", "ogg", "opus", "wav", "wma"]
    @Published var tracks: [Track] = []
    @Published var currentTrackID: String?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Double = 0.8 { didSet { player.volume = Float(volume); applyEqualizer() } }
    @Published var message: String?
    @Published var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") } }
    @Published var accent: Accent { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
    @Published var favoriteIDs: Set<String> = [] { didSet { UserDefaults.standard.set(Array(favoriteIDs), forKey: "favoriteIDs") } }
    @Published var recentlyPlayedIDs: [String] = [] { didSet { UserDefaults.standard.set(recentlyPlayedIDs, forKey: "recentlyPlayedIDs") } }
    @Published var shuffleEnabled = false { didSet { UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled") } }
    @Published var repeatMode: RepeatMode = .off { didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") } }
    @Published var sortOrder: LibrarySort = .title { didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") } }
    @Published var playlists: [Playlist] = [] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(playlists), forKey: "playlists") } }
    @Published var language: AppLanguage = .turkish { didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") } }
    @Published var hasCompletedOnboarding = false { didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") } }
    @Published var libraryDisplay: LibraryDisplay = .list { didSet { UserDefaults.standard.set(libraryDisplay.rawValue, forKey: "libraryDisplay") } }
    @Published var eqEnabled = false { didSet { UserDefaults.standard.set(eqEnabled, forKey: "eqEnabled"); applyEqualizer(); if let track = currentTrack { play(track, preserveQueue: true) } } }
    @Published var eqPreset: EqualizerPreset = .flat { didSet { UserDefaults.standard.set(eqPreset.rawValue, forKey: "eqPreset") } }
    @Published var eqGains: [Float] = Array(repeating: 0, count: 9) { didSet { UserDefaults.standard.set(eqGains.map(Double.init), forKey: "eqGains"); applyEqualizer() } }
    @Published var ambientEnabled = true {
        didSet {
            UserDefaults.standard.set(ambientEnabled, forKey: "ambientEnabled")
            updateAmbientArtwork(for: currentTrack)
        }
    }
    @Published private(set) var ambientPalette = AmbientPalette.fallback
    private let player = AVPlayer(); private let enricher = MetadataEnricher()
    private var scanTimer: Timer?; private var scanTask: Task<Void, Never>?; private var isScanning = false; private var endObserver: NSObjectProtocol?; private var libraryFolder: URL?
    private var timeObserver: Any?; private var itemStatusObservation: NSKeyValueObservation?; private var timeControlObservation: NSKeyValueObservation?
    private var accessedURL: URL?
    private var lastNowPlayingUpdate: TimeInterval = 0
    private let audioEngine = AVAudioEngine(); private let audioNode = AVAudioPlayerNode(); private let equalizer = AVAudioUnitEQ(numberOfBands: 9)
    private var engineFile: AVAudioFile?; private var engineTimer: Timer?; private var engineBaseTime: TimeInterval = 0; private var engineStartedAt: Date?; private var usingEngine = false
    private var playbackQueueTrackIDs: [String] = []
    private var playbackPlaylistID: String?
    var currentTrack: Track? { tracks.first { $0.id == currentTrackID } }
    override init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "system") ?? .system
        accent = Accent(rawValue: UserDefaults.standard.string(forKey: "accent") ?? "pink") ?? .pink
        super.init(); player.volume = Float(volume)
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: "favoriteIDs") ?? [])
        recentlyPlayedIDs = UserDefaults.standard.stringArray(forKey: "recentlyPlayedIDs") ?? []
        shuffleEnabled = UserDefaults.standard.bool(forKey: "shuffleEnabled")
        repeatMode = RepeatMode(rawValue: UserDefaults.standard.string(forKey: "repeatMode") ?? "off") ?? .off
        sortOrder = LibrarySort(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "title") ?? .title
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "turkish") ?? .turkish
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        libraryDisplay = LibraryDisplay(rawValue: UserDefaults.standard.string(forKey: "libraryDisplay") ?? "list") ?? .list
        eqEnabled = UserDefaults.standard.bool(forKey: "eqEnabled")
        eqPreset = EqualizerPreset(rawValue: UserDefaults.standard.string(forKey: "eqPreset") ?? "flat") ?? .flat
        if let gains = UserDefaults.standard.array(forKey: "eqGains") as? [Double], gains.count == 9 { eqGains = gains.map(Float.init) }
        configureAudioEngine()
        ambientEnabled = UserDefaults.standard.object(forKey: "ambientEnabled") as? Bool ?? true
        if let data = UserDefaults.standard.data(forKey: "playlists") { playlists = (try? JSONDecoder().decode([Playlist].self, from: data)) ?? [] }
        libraryFolder = UserDefaults.standard.string(forKey: "libraryFolder").map(URL.init(fileURLWithPath:))
        refreshLibrary()
        scanTimer = Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refreshLibrary), userInfo: nil, repeats: true)
        let playbackPlayer = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, playbackPlayer] time in
            let current = time.seconds.isFinite ? time.seconds : 0
            let duration = playbackPlayer.currentItem?.duration.seconds ?? 0
            DispatchQueue.main.async {
                self?.currentTime = current
                self?.duration = duration.isFinite ? duration : 0
                self?.updateNowPlayingIfNeeded()
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async { self?.isPlaying = player.timeControlStatus == .playing; self?.updateNowPlaying(force: true) }
        }
        configureRemoteCommands()
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard note.object as? AVPlayerItem === self?.player.currentItem else { return }
            Task { @MainActor in self?.advanceAfterPlayback() }
        }
    }
    func pickFiles() {
        let panel = NSOpenPanel(); panel.title = text("Müzik dosyalarını seç", "Choose music files"); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.allowedContentTypes = Self.supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }; add(urls: panel.urls)
    }
    func pickLibraryFolder() {
        let panel = NSOpenPanel(); panel.title = text("Müzik klasörünü seç", "Choose music folder"); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }; libraryFolder = url; UserDefaults.standard.set(url.path, forKey: "libraryFolder"); refreshLibrary()
    }
    func resetOnboarding() { hasCompletedOnboarding = false }
    func text(_ turkish: String, _ english: String) -> String { language == .turkish ? turkish : english }
    @objc func refreshLibrary() {
        guard !isScanning else { return }
        isScanning = true
        let fileManager = FileManager.default
        let standardRoots = [fileManager.urls(for: .musicDirectory, in: .userDomainMask).first, fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first, fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first].compactMap { $0 }
        let roots = Array(Set(standardRoots + (libraryFolder.map { [$0] } ?? [])))
        let supportedExtensions = Self.supportedExtensions
        let known = Set(tracks.map(\.id))
        scanTask = Task { [weak self] in
            defer { self?.isScanning = false }
            let files = await Task.detached(priority: .utility) {
                var matches: [URL] = []
                for folder in roots {
                    guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                    while let url = enumerator.nextObject() as? URL {
                        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                              supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
                        matches.append(url)
                    }
                }
                return matches
            }.value
            let newURLs = files.filter { !known.contains($0.standardizedFileURL.path) }
            let scanned = await Task.detached(priority: .utility) {
                var result: [Track] = []
                for url in newURLs {
                    guard !Task.isCancelled else { break }
                    result.append(await Track.read(from: url))
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            self?.add(tracks: scanned)
        }
    }
    private func add(urls: [URL]) {
        Task { [weak self] in
            var parsed: [Track] = []
            for url in urls { parsed.append(await Track.read(from: url)) }
            self?.add(tracks: parsed)
        }
    }
    private func add(tracks newTracks: [Track]) {
        let known = Set(tracks.map(\.id)); let newTracks = newTracks.filter { !known.contains($0.id) }
        guard !newTracks.isEmpty else { return }; tracks.append(contentsOf: newTracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }); enricher.enqueue(newTracks) { [weak self] updated in self?.replace(updated) }
    }
    private func replace(_ track: Track) { guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }; tracks[index] = track; if track.id == currentTrackID { updateNowPlaying(force: true) } }
    private func configureAudioEngine() {
        audioEngine.attach(audioNode); audioEngine.attach(equalizer)
        audioEngine.connect(audioNode, to: equalizer, format: nil)
        audioEngine.connect(equalizer, to: audioEngine.mainMixerNode, format: nil)
        let frequencies: [Float] = [60, 120, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        for (index, band) in equalizer.bands.enumerated() { band.filterType = .parametric; band.frequency = frequencies[index]; band.bandwidth = 1; band.bypass = !eqEnabled }
        applyEqualizer()
    }
    private func applyEqualizer() {
        guard equalizer.bands.count == 9 else { return }
        let gains = eqEnabled ? eqGains : Array(repeating: 0, count: 9)
        for (index, band) in equalizer.bands.enumerated() { band.gain = gains[index]; band.bypass = !eqEnabled }
        let maximumBoost = gains.max() ?? 0
        audioNode.volume = Float(pow(10, -Double(max(0, maximumBoost - 3)) / 20)) * Float(volume)
    }
    private func updateAmbientArtwork(for track: Track?) {
        guard ambientEnabled, let track, let artwork = track.coverData else {
            ambientPalette = .fallback
            return
        }
        AmbientArtworkAnalyzer.shared.palette(for: artwork, key: track.id) { [weak self] palette in
            guard self?.currentTrackID == track.id, self?.ambientEnabled == true else { return }
            self?.ambientPalette = palette
        }
    }
    func selectEqualizerPreset(_ preset: EqualizerPreset) { eqPreset = preset; eqGains = preset.gains }
    private func startEnginePlayback(_ track: Track) -> Bool {
        guard let file = try? AVAudioFile(forReading: track.url) else { return false }
        guard file.processingFormat.channelCount <= 2 else {
            message = text("Bu çok kanallı parça EQ ile işlenmeden macOS oynatıcısında çalınıyor; kanal yapısı korunur.", "This multichannel track plays in the macOS player without EQ processing so its channel layout is preserved.")
            return false
        }
        player.pause(); player.replaceCurrentItem(with: nil); audioNode.stop(); engineTimer?.invalidate()
        do { if !audioEngine.isRunning { try audioEngine.start() } } catch { message = text("Ses işleme başlatılamadı: \(error.localizedDescription)", "Audio processing could not start: \(error.localizedDescription)"); return false }
        engineFile = file; usingEngine = true; engineBaseTime = 0; engineStartedAt = Date(); duration = Double(file.length) / file.processingFormat.sampleRate
        audioNode.scheduleFile(file, at: nil) { [weak self] in DispatchQueue.main.async { self?.advanceAfterPlayback() } }
        audioNode.play(); currentTrackID = track.id; isPlaying = true; updateAmbientArtwork(for: track); startEngineTimer(); updateNowPlaying(force: true)
        return true
    }
    private func startEngineTimer() { engineTimer?.invalidate(); engineTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(updateEngineProgress), userInfo: nil, repeats: true) }
    @objc private func updateEngineProgress() { guard usingEngine, let started = engineStartedAt else { return }; currentTime = engineBaseTime + Date().timeIntervalSince(started); if currentTime >= duration { currentTime = duration }; updateNowPlayingIfNeeded() }
    func play(_ track: Track?, preserveQueue: Bool = false) {
        guard let track else { return }
        message = nil
        if !preserveQueue {
            playbackQueueTrackIDs = tracks.map(\.id)
            playbackPlaylistID = nil
        }
        if eqEnabled && startEnginePlayback(track) { return }
        if eqEnabled, message == nil { message = text("Bu dosya Equalizer zincirinde açılamadı; macOS oynatıcısıyla EQ olmadan çalınıyor.", "This file could not open in the Equalizer chain; it is playing without EQ in the macOS player.") }
        usingEngine = false; engineTimer?.invalidate(); audioNode.stop()
        isPlaying = false; currentTime = 0; duration = 0
        if let accessedURL { accessedURL.stopAccessingSecurityScopedResource(); self.accessedURL = nil }
        if track.url.startAccessingSecurityScopedResource() { accessedURL = track.url }
        let asset = AVURLAsset(url: track.url)
        Task { @MainActor [weak self] in
            do {
                guard try await asset.load(.isPlayable) else { self?.playbackFailed(self?.text("Bu dosya macOS tarafından oynatılamıyor.", "This file is not playable by macOS.") ?? "This file is not playable by macOS."); return }
                guard let self else { return }
                let item = AVPlayerItem(asset: asset)
                self.itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
                    guard item.status == .failed else { return }
                    DispatchQueue.main.async { self?.playbackFailed(item.error?.localizedDescription ?? self?.text("Dosya açılamadı.", "The file could not be opened.") ?? "The file could not be opened.") }
                }
                self.player.replaceCurrentItem(with: item)
                self.player.play(); self.currentTrackID = track.id; self.updateAmbientArtwork(for: track)
                self.updateNowPlaying(force: true)
                self.recentlyPlayedIDs.removeAll { $0 == track.id }
                self.recentlyPlayedIDs.insert(track.id, at: 0)
                self.recentlyPlayedIDs = Array(self.recentlyPlayedIDs.prefix(50))
            } catch { self?.playbackFailed(error.localizedDescription) }
        }
    }
    func togglePlayback() { if usingEngine { if isPlaying { engineBaseTime = currentTime; engineStartedAt = nil; audioNode.pause() } else { engineStartedAt = Date(); audioNode.play() }; isPlaying.toggle(); updateNowPlaying(force: true); return }; guard player.currentItem != nil else { play(tracks.first); return }; isPlaying ? player.pause() : player.play(); isPlaying.toggle(); updateNowPlaying(force: true) }
    func seek(to time: TimeInterval) { if usingEngine, let file = engineFile { audioNode.stop(); engineBaseTime = min(max(0, time), duration); let frame = AVAudioFramePosition(engineBaseTime * file.processingFormat.sampleRate); let count = AVAudioFrameCount(max(0, file.length - frame)); audioNode.scheduleSegment(file, startingFrame: frame, frameCount: count, at: nil) { [weak self] in DispatchQueue.main.async { self?.advanceAfterPlayback() } }; if isPlaying { engineStartedAt = Date(); audioNode.play() }; currentTime = engineBaseTime; updateNowPlaying(force: true); return }; player.seek(to: CMTime(seconds: time, preferredTimescale: 600)); currentTime = time; updateNowPlaying(force: true) }
    private var activeQueue: [Track] {
        let ids = playbackQueueTrackIDs.isEmpty ? tracks.map(\.id) : playbackQueueTrackIDs
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
    func next() {
        let queue = activeQueue
        guard !queue.isEmpty else { return }
        guard let index = queue.firstIndex(where: { $0.id == currentTrackID }) else { play(queue.first, preserveQueue: true); return }
        if shuffleEnabled { play(queue.filter { $0.id != currentTrackID }.randomElement() ?? queue[index], preserveQueue: true); return }
        if index == queue.indices.last && repeatMode == .off { player.pause(); audioNode.pause(); isPlaying = false; updateNowPlaying(force: true); return }
        play(queue[(index + 1) % queue.count], preserveQueue: true)
    }
    func previous() {
        let queue = activeQueue
        guard let index = queue.firstIndex(where: { $0.id == currentTrackID }), !queue.isEmpty else { return }
        play(queue[(index - 1 + queue.count) % queue.count], preserveQueue: true)
    }
    func toggleFavorite(_ track: Track) { if favoriteIDs.contains(track.id) { favoriteIDs.remove(track.id) } else { favoriteIDs.insert(track.id) } }
    func createPlaylist(name: String) { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; playlists.append(Playlist(name: name)) }
    func renamePlaylist(_ playlistID: String, name: String) { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty, let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }; playlists[index].name = name }
    func deletePlaylist(_ playlistID: String) { playlists.removeAll { $0.id == playlistID }; if playbackPlaylistID == playlistID { playbackPlaylistID = nil; playbackQueueTrackIDs = tracks.map(\.id) } }
    func add(_ tracks: [Track], to playlistID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let existing = Set(playlists[index].trackIDs)
        playlists[index].trackIDs.append(contentsOf: tracks.map(\.id).filter { !existing.contains($0) })
    }
    func add(_ track: Track, to playlistID: String) { add([track], to: playlistID) }
    func remove(_ track: Track, from playlistID: String) { guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }; playlists[index].trackIDs.removeAll { $0 == track.id }; if playbackPlaylistID == playlistID { playbackQueueTrackIDs = playlists[index].trackIDs } }
    func playlistTracks(_ playlistID: String) -> [Track] {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { byID[$0] }
    }
    func playPlaylist(_ playlistID: String, startingWith track: Track? = nil) {
        let queue = playlistTracks(playlistID)
        guard let first = track ?? queue.first else { return }
        playbackQueueTrackIDs = queue.map(\.id); playbackPlaylistID = playlistID
        play(first, preserveQueue: true)
    }
    func cycleRepeatMode() { repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off) }
    private func advanceAfterPlayback() { if repeatMode == .one { play(currentTrack, preserveQueue: true) } else { next() } }
    func remove(_ track: Track) { if track.id == currentTrackID { stopPlayback() }; tracks.removeAll { $0.id == track.id } }
    private func playbackFailed(_ reason: String) { stopPlayback(); message = text("Bu dosya çalınamadı: \(reason)", "This file could not be played: \(reason)") }
    private func stopPlayback() { player.pause(); player.replaceCurrentItem(with: nil); audioNode.stop(); engineTimer?.invalidate(); usingEngine = false; engineFile = nil; currentTrackID = nil; ambientPalette = .fallback; isPlaying = false; currentTime = 0; duration = 0; itemStatusObservation = nil; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; MPNowPlayingInfoCenter.default().playbackState = .stopped; if let accessedURL { accessedURL.stopAccessingSecurityScopedResource(); self.accessedURL = nil } }
    private func updateNowPlayingIfNeeded() { if Date.timeIntervalSinceReferenceDate - lastNowPlayingUpdate > 1 { updateNowPlaying(force: false) } }
    private func updateNowPlaying(force: Bool) {
        guard let track = currentTrack else { return }
        lastNowPlayingUpdate = Date.timeIntervalSinceReferenceDate
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let data = track.coverData, let image = NSImage(data: data) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if self?.isPlaying == false { self?.togglePlayback() } }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { if self?.isPlaying == true { self?.togglePlayback() } }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.togglePlayback() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in DispatchQueue.main.async { self?.previous() }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }; DispatchQueue.main.async { self?.seek(to: event.positionTime) }; return .success }
    }
    deinit { scanTimer?.invalidate(); engineTimer?.invalidate(); audioNode.stop(); audioEngine.stop(); if let timeObserver { player.removeTimeObserver(timeObserver) }; if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; if let accessedURL { accessedURL.stopAccessingSecurityScopedResource() }; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
}

private enum LibraryView: Equatable { case all, favorites, recent, playlist(String) }

struct OnboardingView: View {
    @EnvironmentObject private var player: MusicPlayer
    @State private var step = 0
    var body: some View {
        VStack(spacing: 26) {
            Image(systemName: "music.note.house.fill").font(.system(size: 54)).foregroundStyle(player.accent.color)
            if step == 0 {
                Text(player.language == .turkish ? "Hoş geldin" : "Welcome").font(.largeTitle.bold())
                Text(player.language == .turkish ? "Dilini seç" : "Choose your language").foregroundStyle(.secondary)
                Picker("Language", selection: $player.language) { ForEach(AppLanguage.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).frame(width: 240)
            } else if step == 1 {
                Text(player.language == .turkish ? "Görünümünü seç" : "Choose your appearance").font(.title.bold())
                Picker("Theme", selection: $player.theme) { ForEach(AppTheme.allCases) { Text($0.title(player.language)).tag($0) } }.pickerStyle(.segmented).frame(width: 330)
            } else if step == 2 {
                Text(player.language == .turkish ? "Müziklerin nerede?" : "Where is your music?").font(.title.bold())
                Text(player.language == .turkish ? "Varsayılan Müzik, İndirilenler ve Masaüstü klasörleri taranır." : "Your Music, Downloads, and Desktop folders will be scanned.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button(player.language == .turkish ? "Özel müzik klasörü seç…" : "Choose a custom music folder…", action: player.pickLibraryFolder).buttonStyle(.bordered)
            } else {
                Text(player.language == .turkish ? "Müzik Odam'a hoş geldin! 🎵" : "Welcome to Music Room! 🎵").font(.title.bold())
                Text(player.language == .turkish ? "Müzik dosyaların cihazından dışarı yüklenmez." : "Your music files never leave your device.").foregroundStyle(.secondary)
            }
            HStack { if step > 0 { Button(player.language == .turkish ? "Geri" : "Back") { step -= 1 } }; Spacer(); Button(step == 3 ? (player.language == .turkish ? "Müzik Odam'ı Kullan" : "Start using Music Room") : (player.language == .turkish ? "Devam" : "Continue")) { if step == 3 { player.hasCompletedOnboarding = true; player.refreshLibrary() } else { step += 1 } }.buttonStyle(.borderedProminent).tint(player.accent.color) }
        }.padding(44).frame(maxWidth: 520, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @EnvironmentObject private var player: MusicPlayer
    @State private var libraryView: LibraryView = .all
    @State private var searchText = ""
    @State private var isCreatingPlaylist = false
    @State private var newPlaylistName = ""
    @State private var selectedAlbum = ""
    @State private var selectedArtist = ""
    @State private var showingEqualizer = false
    @State private var selectedTrackIDs: Set<String> = []
    @State private var playlistToRename: Playlist?
    @State private var renamedPlaylistName = ""
    @State private var playlistToDelete: Playlist?
    var body: some View { HStack(spacing: 0) { sidebar; Divider(); VStack(spacing: 0) { header; if let message = player.message { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.bottom, 8) }; trackList; Divider(); nowPlaying } }.background(Color(nsColor: .windowBackgroundColor)).sheet(isPresented: $showingEqualizer) { EqualizerView() }.sheet(isPresented: $isCreatingPlaylist) { VStack(spacing: 16) { Text(player.text("Yeni çalma listesi", "New playlist")).font(.title3.weight(.semibold)); TextField(player.text("Liste adı", "Playlist name"), text: $newPlaylistName).textFieldStyle(.roundedBorder); HStack { Button(player.text("Vazgeç", "Cancel")) { isCreatingPlaylist = false }; Spacer(); Button(player.text("Oluştur", "Create")) { player.createPlaylist(name: newPlaylistName); newPlaylistName = ""; isCreatingPlaylist = false }.buttonStyle(.borderedProminent) } }.padding(24).frame(width: 320) }.sheet(isPresented: Binding(get: { playlistToRename != nil }, set: { if !$0 { playlistToRename = nil } })) { VStack(spacing: 16) { Text(player.text("Playlist'i Yeniden Adlandır", "Rename Playlist")).font(.title3.weight(.semibold)); TextField(player.text("Playlist adı", "Playlist name"), text: $renamedPlaylistName).textFieldStyle(.roundedBorder); HStack { Button(player.text("Vazgeç", "Cancel")) { playlistToRename = nil }; Spacer(); Button(player.text("Kaydet", "Save")) { if let playlist = playlistToRename { player.renamePlaylist(playlist.id, name: renamedPlaylistName) }; playlistToRename = nil }.buttonStyle(.borderedProminent) } }.padding(24).frame(width: 320) }.alert(player.text("Playlist silinsin mi?", "Delete playlist?"), isPresented: Binding(get: { playlistToDelete != nil }, set: { if !$0 { playlistToDelete = nil } })) { Button(player.text("Vazgeç", "Cancel"), role: .cancel) { playlistToDelete = nil }; Button(player.text("Sil", "Delete"), role: .destructive) { if let playlist = playlistToDelete { player.deletePlaylist(playlist.id); if libraryView == .playlist(playlist.id) { libraryView = .all } }; playlistToDelete = nil } } message: { Text(player.text("Bu işlem yalnızca playlist'i siler. Müzik dosyalarınız Mac'inizde kalır.", "This removes only the playlist. Your music files stay on your Mac.")) }.sheet(isPresented: Binding(get: { !selectedAlbum.isEmpty }, set: { if !$0 { selectedAlbum = "" } })) { AlbumDetailView(album: selectedAlbum, tracks: player.tracks.filter { $0.album == selectedAlbum }) }.sheet(isPresented: Binding(get: { !selectedArtist.isEmpty }, set: { if !$0 { selectedArtist = "" } })) { ArtistDetailView(artist: selectedArtist, tracks: player.tracks.filter { $0.artist == selectedArtist }) } }
    private var sidebar: some View { VStack(alignment: .leading, spacing: 22) {
        Label("Müzik Odam", systemImage: "music.note.house.fill").font(.title3.weight(.bold)).foregroundStyle(player.accent.color)
        VStack(alignment: .leading, spacing: 10) {
            Button { libraryView = .all } label: { Label(player.text("Kütüphanem", "Library"), systemImage: "music.note.list") }.buttonStyle(.plain).fontWeight(libraryView == .all ? .semibold : .regular)
            Button { libraryView = .favorites } label: { Label(player.text("Favoriler", "Favorites"), systemImage: "heart.fill") }.buttonStyle(.plain).foregroundStyle(libraryView == .favorites ? player.accent.color : .primary)
            Button { libraryView = .recent } label: { Label(player.text("Son Çalınanlar", "Recently Played"), systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).foregroundStyle(libraryView == .recent ? player.accent.color : .primary)
            Text(player.text("\(player.tracks.count) parça", "\(player.tracks.count) tracks")).foregroundStyle(.secondary)
            Button(player.text("Klasörü Tara", "Scan Folders"), action: player.refreshLibrary).buttonStyle(.plain).foregroundStyle(player.accent.color)
            Button(player.text("Equalizer", "Equalizer")) { showingEqualizer = true }.buttonStyle(.plain).foregroundStyle(player.accent.color)
            Divider()
            HStack { Text(player.text("Playlistler", "Playlists")).font(.headline); Spacer(); Button { isCreatingPlaylist = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(player.accent.color).help(player.text("Yeni playlist", "New playlist")) }
            ForEach(player.playlists) { playlist in
                HStack(spacing: 6) {
                    Button { libraryView = .playlist(playlist.id); selectedTrackIDs.removeAll() } label: { Label(playlist.name, systemImage: "music.note.list") }.buttonStyle(.plain).foregroundStyle(libraryView == .playlist(playlist.id) ? player.accent.color : .primary).lineLimit(1)
                    Spacer()
                    Menu { Button(player.text("Çal", "Play")) { player.playPlaylist(playlist.id) }; Button(player.text("Yeniden Adlandır", "Rename")) { playlistToRename = playlist; renamedPlaylistName = playlist.name }; Divider(); Button(player.text("Sil…", "Delete…"), role: .destructive) { playlistToDelete = playlist } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
                }
            }
        }
        Spacer()
        Menu {
            Menu(player.text("Dil", "Language")) {
                ForEach(AppLanguage.allCases) { language in
                    Button { player.language = language } label: {
                        Label(language.title, systemImage: player.language == language ? "checkmark" : "")
                    }
                }
            }
            Menu(player.text("Görünüm", "Appearance")) {
                ForEach(AppTheme.allCases) { theme in
                    Button { player.theme = theme } label: {
                        Label(theme.title(player.language), systemImage: player.theme == theme ? "checkmark" : "")
                    }
                }
            }
            Menu(player.text("Vurgu rengi", "Accent color")) {
                ForEach(Accent.allCases) { accent in
                    Button { player.accent = accent } label: {
                        Label(accent.title(player.language), systemImage: player.accent == accent ? "checkmark" : "")
                    }
                }
            }
            Button { player.ambientEnabled.toggle() } label: {
                Label(player.text("Ambient Efekt", "Ambient Effect"), systemImage: player.ambientEnabled ? "checkmark" : "")
            }
            Divider()
            Button(player.text("Kurulum Ayarlarını Sıfırla", "Reset Setup"), action: player.resetOnboarding)
        } label: {
            Label(player.text("Görünüm", "Appearance"), systemImage: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        Text(player.text("Müzikler yalnızca Mac’inizde kalır.", "Your music stays on your Mac.")).font(.caption).foregroundStyle(.secondary)
    }.padding(24).frame(width: 210, alignment: .leading).background(.quaternary.opacity(0.45)) }
    private var activePlaylist: Playlist? {
        guard case let .playlist(id) = libraryView else { return nil }
        return player.playlists.first { $0.id == id }
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(activePlaylist?.name ?? player.text("Kütüphanem", "Library")).font(.title.bold())
                Text(activePlaylist == nil ? player.text("Yerel müziklerin otomatik taranır ve bilgileri yenilenir.", "Your local music is scanned and enriched automatically.") : player.text("Playlist içindeki şarkılar", "Songs in this playlist")).foregroundStyle(.secondary)
            }
            Spacer()
            if let playlist = activePlaylist {
                Button(player.text("Tümünü Çal", "Play All")) { player.playPlaylist(playlist.id) }.buttonStyle(.bordered)
                Menu { Button(player.text("Yeniden Adlandır", "Rename")) { playlistToRename = playlist; renamedPlaylistName = playlist.name }; Button(player.text("Sil…", "Delete…"), role: .destructive) { playlistToDelete = playlist } } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton)
            }
            if !selectedTrackIDs.isEmpty, !player.playlists.isEmpty {
                Menu { ForEach(player.playlists) { playlist in Button(playlist.name) { player.add(visibleTracks.filter { selectedTrackIDs.contains($0.id) }, to: playlist.id); selectedTrackIDs.removeAll() } } } label: { Label(player.text("Playlist'e Ekle", "Add to Playlist"), systemImage: "text.badge.plus") }.buttonStyle(.bordered)
            }
            TextField(player.text("Ara", "Search"), text: $searchText).textFieldStyle(.roundedBorder).frame(width: 180)
            Picker(player.text("Görünüm", "View"), selection: $player.libraryDisplay) { Image(systemName: "list.bullet").tag(LibraryDisplay.list); Image(systemName: "square.grid.2x2").tag(LibraryDisplay.grid) }.labelsHidden().pickerStyle(.segmented).frame(width: 90)
            Menu { Picker(player.text("Sırala", "Sort"), selection: $player.sortOrder) { ForEach(LibrarySort.allCases) { Text($0.title(player.language)).tag($0) } }; Divider(); Button(player.text("Müzik Dosyası Ekle…", "Add Music Files…"), action: player.pickFiles); Button(player.text("Müzik Klasörünü Seç…", "Choose Music Folder…",), action: player.pickLibraryFolder) } label: { Label(player.text("Müzik Ekle", "Add Music"), systemImage: "plus") }.buttonStyle(.borderedProminent).tint(player.accent.color)
        }.padding(28)
    }
    @ViewBuilder private var trackList: some View { if visibleTracks.isEmpty { VStack(spacing: 14) { Image(systemName: "music.note").font(.system(size: 44)).foregroundStyle(player.accent.color); Text(activePlaylist == nil ? player.text("Henüz müzik bulunamadı", "No music found") : player.text("Bu playlist boş", "This playlist is empty")).font(.title3.weight(.semibold)); Text(activePlaylist == nil ? player.text("Müzik klasörünüz otomatik taranır; isterseniz başka bir klasör de seçebilirsiniz.", "Your music folders are scanned automatically; you can also choose another folder.") : player.text("Kütüphaneden şarkı seçip playlist'e ekleyebilirsiniz.", "Select songs from the library to add them to this playlist.")).foregroundStyle(.secondary); if activePlaylist == nil { Button(player.text("Müzik Klasörü Seç…", "Choose Music Folder…"), action: player.pickLibraryFolder).buttonStyle(.bordered) } }.frame(maxWidth: .infinity, maxHeight: .infinity) } else if player.libraryDisplay == .list { List(visibleTracks, selection: $selectedTrackIDs) { track in trackRow(track) }.listStyle(.inset) } else { ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 220), spacing: 18)], spacing: 18) { ForEach(visibleTracks) { track in gridCard(track) } }.padding(.horizontal, 28).padding(.bottom, 20) } } }
    private func trackRow(_ track: Track) -> some View { HStack(spacing: 12) { CoverArt(data: track.coverData, size: 34, accent: player.accent.color); VStack(alignment: .leading, spacing: 3) { Text(track.title).lineLimit(1); HStack(spacing: 4) { Button(track.artist.isEmpty ? player.text("Bilinmeyen sanatçı", "Unknown artist") : track.artist) { if !track.artist.isEmpty { selectedArtist = track.artist } }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary); if !track.album.isEmpty { Text("•").foregroundStyle(.secondary); Button(track.album) { selectedAlbum = track.album }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary) } } }; Spacer(); if track.id == player.currentTrackID { Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.circle").foregroundStyle(player.accent.color) }; Button { player.toggleFavorite(track) } label: { Image(systemName: player.favoriteIDs.contains(track.id) ? "heart.fill" : "heart") }.buttonStyle(.plain).foregroundStyle(player.favoriteIDs.contains(track.id) ? player.accent.color : .secondary); Menu { ForEach(player.playlists) { playlist in Button(playlist.name) { player.add(track, to: playlist.id) } } } label: { Image(systemName: "text.badge.plus") }.menuStyle(.borderlessButton).help(player.text("Playlist'e ekle", "Add to playlist")); if let playlist = activePlaylist { Button { player.remove(track, from: playlist.id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).help(player.text("Playlist'ten çıkar", "Remove from playlist")) } else { Button { player.remove(track) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary) } }.contentShape(Rectangle()).onTapGesture { if let playlist = activePlaylist { player.playPlaylist(playlist.id, startingWith: track) } else { player.play(track) } }.padding(.vertical, 4) }
    private func gridCard(_ track: Track) -> some View { Button { if let playlist = activePlaylist { player.playPlaylist(playlist.id, startingWith: track) } else { player.play(track) } } label: { VStack(alignment: .leading, spacing: 8) { ZStack(alignment: .topTrailing) { CoverArt(data: track.coverData, size: 140, accent: player.accent.color).frame(maxWidth: .infinity); if track.id == player.currentTrackID { Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "play.fill").padding(8).background(.ultraThinMaterial, in: Circle()).foregroundStyle(player.accent.color) } }; Text(track.title).fontWeight(.semibold).lineLimit(1); Text(track.artist.isEmpty ? player.text("Bilinmeyen sanatçı", "Unknown artist") : track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1); Text(track.album).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(track.id == player.currentTrackID ? player.accent.color.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain).contextMenu { Menu(player.text("Playlist'e Ekle", "Add to Playlist")) { ForEach(player.playlists) { playlist in Button(playlist.name) { player.add(track, to: playlist.id) } } }; if let playlist = activePlaylist { Button(player.text("Playlist'ten Çıkar", "Remove from Playlist"), role: .destructive) { player.remove(track, from: playlist.id) } } } }
    private var nowPlaying: some View {
        VStack(spacing: 12) {
            HStack {
                CoverArt(data: player.currentTrack?.coverData, size: 46, accent: player.accent.color)
                VStack(alignment: .leading) {
                    Text(player.currentTrack?.title ?? player.text("Bir parça seç", "Choose a track")).fontWeight(.semibold).lineLimit(1)
                    Text(player.currentTrack?.subtitle(language: player.language) ?? player.text("Çalmaya hazır", "Ready to play")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let track = player.currentTrack {
                    Button { player.toggleFavorite(track) } label: { Image(systemName: player.favoriteIDs.contains(track.id) ? "heart.fill" : "heart") }.buttonStyle(.plain).foregroundStyle(player.favoriteIDs.contains(track.id) ? player.accent.color : .secondary)
                }
                Text(time(player.currentTime) + " / " + time(player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Text(time(player.currentTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Slider(value: Binding(get: { player.currentTime }, set: player.seek), in: 0...max(player.duration, 1)).tint(player.accent.color)
                Text(time(player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 25) {
                Button { player.shuffleEnabled.toggle() } label: { Image(systemName: "shuffle") }.buttonStyle(.plain).foregroundStyle(player.shuffleEnabled ? player.accent.color : .primary)
                Button(action: player.previous) { Image(systemName: "backward.fill") }.buttonStyle(.plain)
                Button(action: player.togglePlayback) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 42, height: 42) }.buttonStyle(.borderedProminent).tint(player.accent.color).clipShape(Circle())
                Button(action: player.next) { Image(systemName: "forward.fill") }.buttonStyle(.plain)
                Button(action: player.cycleRepeatMode) { Image(systemName: player.repeatMode.icon) }.buttonStyle(.plain).foregroundStyle(player.repeatMode == .off ? .primary : player.accent.color)
                Spacer()
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1).frame(width: 100).tint(player.accent.color)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(AmbientNowPlayingBackground().environmentObject(player))
    }
    private var visibleTracks: [Track] {
        var result = player.tracks
        switch libraryView {
        case .all: break
        case .favorites: result = result.filter { player.favoriteIDs.contains($0.id) }
        case .recent: result = player.recentlyPlayedIDs.compactMap { id in result.first { $0.id == id } }
        case .playlist(let playlistID):
            result = player.playlistTracks(playlistID)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { result = result.filter { "\($0.title) \($0.artist) \($0.album)".localizedCaseInsensitiveContains(query) } }
        switch player.sortOrder {
        case .title: return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .artist: return result.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album: return result.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .recentlyAdded: return result
        }
    }
    private func time(_ seconds: TimeInterval) -> String { guard seconds.isFinite else { return "0:00" }; return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

struct AlbumDetailView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss
    let album: String
    let tracks: [Track]
    var body: some View { VStack(alignment: .leading, spacing: 16) { HStack { CoverArt(data: tracks.first?.coverData, size: 110, accent: player.accent.color); VStack(alignment: .leading) { Text(album).font(.title.bold()); Text(tracks.first?.artist ?? "").foregroundStyle(.secondary); if let year = tracks.first?.year { Text(year).font(.caption).foregroundStyle(.secondary) } }; Spacer(); Button(player.text("Tümünü Oynat", "Play All")) { player.play(tracks.first) }.buttonStyle(.borderedProminent); Button(player.text("Bitti", "Done")) { dismiss() } }; List(tracks) { track in Button { player.play(track) } label: { HStack { Text(track.title); Spacer(); if track.id == player.currentTrackID { Image(systemName: "speaker.wave.2.fill").foregroundStyle(player.accent.color) } } }.buttonStyle(.plain) } }.padding(28).frame(minWidth: 500, minHeight: 420) }
}

struct EqualizerView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss
    private let labels = ["60 Hz", "120 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"]
    var body: some View { VStack(alignment: .leading, spacing: 18) { HStack { Text(player.text("Equalizer", "Equalizer")).font(.title.bold()); Spacer(); Toggle(player.text("Açık", "Enabled"), isOn: $player.eqEnabled); Button(player.text("Bitti", "Done")) { dismiss() }.keyboardShortcut(.defaultAction) }; Picker(player.text("Preset", "Preset"), selection: $player.eqPreset) { ForEach(EqualizerPreset.allCases) { Text($0.title(player.language)).tag($0) } }.onChange(of: player.eqPreset) { _, value in player.selectEqualizerPreset(value) }.pickerStyle(.menu); HStack(alignment: .bottom, spacing: 10) { ForEach(Array(labels.enumerated()), id: \.offset) { index, label in VStack { Text(String(format: "%+.0f", player.eqGains[index])).font(.caption.monospacedDigit()); Slider(value: Binding(get: { Double(player.eqGains[index]) }, set: { player.eqGains[index] = Float($0); player.eqPreset = .flat }), in: -12...12).rotationEffect(.degrees(-90)).frame(height: 130); Text(label).font(.caption2).frame(width: 45) } } }; HStack { Button(player.text("Sıfırla", "Reset")) { player.selectEqualizerPreset(.flat) }; Spacer(); Text(player.text("EQ açıkken AVAudioEngine ve AVAudioUnitEQ kullanılır.", "When enabled, EQ uses AVAudioEngine and AVAudioUnitEQ.")).font(.caption).foregroundStyle(.secondary) } }.padding(28).frame(width: 610) }
}

struct ArtistDetailView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.dismiss) private var dismiss
    let artist: String
    let tracks: [Track]
    var albums: [String] { Array(Set(tracks.map(\.album).filter { !$0.isEmpty })).sorted() }
    var body: some View { VStack(alignment: .leading, spacing: 16) { HStack { Text(artist).font(.largeTitle.bold()); Spacer(); Button(player.text("Bitti", "Done")) { dismiss() }.keyboardShortcut(.defaultAction) }; if !albums.isEmpty { Text(player.text("Albümler", "Albums")).font(.headline); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(albums, id: \.self) { album in VStack(alignment: .leading) { CoverArt(data: tracks.first(where: { $0.album == album })?.coverData, size: 82, accent: player.accent.color); Text(album).lineLimit(1).frame(width: 100, alignment: .leading) } } } } }; Text(player.text("Şarkılar", "Songs")).font(.headline); List(tracks) { track in Button(track.title) { player.play(track) }.buttonStyle(.plain) } }.padding(28).frame(minWidth: 500, minHeight: 420) }
}

struct AmbientNowPlayingBackground: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if player.ambientEnabled {
                ZStack {
                    LinearGradient(colors: [
                        player.ambientPalette.primaryColor.opacity(0.22),
                        player.ambientPalette.secondaryColor.opacity(0.13),
                        Color(nsColor: .windowBackgroundColor).opacity(0.72)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [player.ambientPalette.primaryColor.opacity(0.17), .clear], center: .topLeading, startRadius: 8, endRadius: 260)
                    RadialGradient(colors: [player.ambientPalette.secondaryColor.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 240)
                }
                .blur(radius: 0.4)
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.7), value: player.ambientPalette.id)
            } else {
                Color.clear
            }
        }
        .allowsHitTesting(false)
    }
}

struct CoverArt: View {
    let data: Data?; let size: CGFloat; let accent: Color
    var body: some View { Group { if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: "music.note").font(size > 40 ? .title2 : .body).foregroundStyle(accent) } }.frame(width: size, height: size).background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: size > 40 ? 10 : 7)).clipShape(RoundedRectangle(cornerRadius: size > 40 ? 10 : 7)) }
}

struct MenuBarNowPlayingView: View {
    @EnvironmentObject private var player: MusicPlayer
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CoverArt(data: player.currentTrack?.coverData, size: 42, accent: player.accent.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.title ?? player.text("Bir parça seç", "Choose a track")).lineLimit(1)
                    Text(player.currentTrack?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Slider(value: Binding(get: { player.currentTime }, set: player.seek), in: 0...max(player.duration, 1))
            HStack(spacing: 12) {
                Button(action: player.previous) { Image(systemName: "backward.fill").frame(width: 24, height: 24) }
                    .help(player.text("Önceki Parça", "Previous Track"))
                Button(action: player.togglePlayback) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 24, height: 24) }
                    .help(player.isPlaying ? player.text("Duraklat", "Pause") : player.text("Çal", "Play"))
                Button(action: player.next) { Image(systemName: "forward.fill").frame(width: 24, height: 24) }
                    .help(player.text("Sonraki Parça", "Next Track"))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(width: 260)
    }
}
