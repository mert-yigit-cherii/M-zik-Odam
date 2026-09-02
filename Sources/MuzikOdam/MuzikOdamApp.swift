import SwiftUI
import AppKit
@preconcurrency import AVFoundation

@main
struct MuzikOdamApp: App {
    @StateObject private var player = MusicPlayer()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(player).preferredColorScheme(player.theme.colorScheme).tint(player.accent.color).frame(minWidth: 780, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Müzik Ekle…") { player.pickFiles() }.keyboardShortcut("o", modifiers: .command)
                Button("Müzik Klasörünü Seç…") { player.pickLibraryFolder() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button(player.isPlaying ? "Duraklat" : "Çal") { player.togglePlayback() }.keyboardShortcut(.space, modifiers: [])
                Button("Sonraki Parça") { player.next() }.keyboardShortcut(.rightArrow, modifiers: [.command])
                Button("Önceki Parça") { player.previous() }.keyboardShortcut(.leftArrow, modifiers: [.command])
            }
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "Sistem"; case .light: "Açık"; case .dark: "Koyu" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
enum Accent: String, CaseIterable, Identifiable {
    case pink, purple, blue, orange
    var id: String { rawValue }
    var title: String { switch self { case .pink: "Pembe"; case .purple: "Mor"; case .blue: "Mavi"; case .orange: "Turuncu" } }
    var color: Color { switch self { case .pink: .pink; case .purple: .purple; case .blue: .blue; case .orange: .orange } }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title, artist, album, recentlyAdded
    var id: String { rawValue }
    var title: String { switch self { case .title: "Parça adı"; case .artist: "Sanatçı"; case .album: "Albüm"; case .recentlyAdded: "Yeni eklenen" } }
}

enum RepeatMode: String, CaseIterable {
    case off, all, one
    var icon: String { switch self { case .off: "repeat"; case .all: "repeat"; case .one: "repeat.1" } }
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
    var subtitle: String {
        let source = artist.isEmpty ? "Yerel dosya" : artist
        return album.isEmpty ? "\(source) • \(format)" : "\(source) — \(album) • \(format)"
    }
    static func read(from url: URL) -> Track {
        let metadata = AVURLAsset(url: url).commonMetadata
        func text(_ key: AVMetadataKey) -> String? { metadata.first(where: { $0.commonKey == key })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
        let filename = url.deletingPathExtension().lastPathComponent
        let pieces = filename.components(separatedBy: " - ")
        let filenameArtist = pieces.count >= 2 ? pieces[0] : ""
        let filenameTitle = pieces.count >= 3 ? pieces.dropFirst().dropLast().joined(separator: " - ") : (pieces.count == 2 ? pieces[1] : filename)
        func cleaned(_ value: String) -> String {
            value.replacingOccurrences(of: #"\s*\((official[^)]*|lyrics?|audio|video|\d{2,4}k)\)"#, with: "", options: .regularExpression, range: nil).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Track(url: url, title: text(.commonKeyTitle).flatMap { $0.isEmpty ? nil : $0 } ?? cleaned(filenameTitle), artist: text(.commonKeyArtist) ?? cleaned(filenameArtist), album: text(.commonKeyAlbumName) ?? "", year: text(.commonKeyCreationDate)?.prefix(4).description, coverData: metadata.first(where: { $0.commonKey == .commonKeyArtwork })?.dataValue)
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
                updated.coverData = cover ?? updated.coverData
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
    @Published var volume: Double = 0.8 { didSet { player.volume = Float(volume) } }
    @Published var message: String?
    @Published var theme: AppTheme { didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") } }
    @Published var accent: Accent { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
    @Published var favoriteIDs: Set<String> = [] { didSet { UserDefaults.standard.set(Array(favoriteIDs), forKey: "favoriteIDs") } }
    @Published var recentlyPlayedIDs: [String] = [] { didSet { UserDefaults.standard.set(recentlyPlayedIDs, forKey: "recentlyPlayedIDs") } }
    @Published var shuffleEnabled = false { didSet { UserDefaults.standard.set(shuffleEnabled, forKey: "shuffleEnabled") } }
    @Published var repeatMode: RepeatMode = .off { didSet { UserDefaults.standard.set(repeatMode.rawValue, forKey: "repeatMode") } }
    @Published var sortOrder: LibrarySort = .title { didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "sortOrder") } }
    @Published var playlists: [Playlist] = [] { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(playlists), forKey: "playlists") } }
    private let player = AVPlayer(); private let enricher = MetadataEnricher()
    private var progressTimer: Timer?; private var scanTimer: Timer?; private var endObserver: NSObjectProtocol?; private var libraryFolder: URL?
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
        if let data = UserDefaults.standard.data(forKey: "playlists") { playlists = (try? JSONDecoder().decode([Playlist].self, from: data)) ?? [] }
        libraryFolder = UserDefaults.standard.string(forKey: "libraryFolder").map(URL.init(fileURLWithPath:))
        refreshLibrary()
        scanTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(refreshLibrary), userInfo: nil, repeats: true)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            guard note.object as? AVPlayerItem === self?.player.currentItem else { return }
            Task { @MainActor in self?.advanceAfterPlayback() }
        }
    }
    func pickFiles() {
        let panel = NSOpenPanel(); panel.title = "Müzik dosyalarını seç"; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.allowedFileTypes = Array(Self.supportedExtensions).sorted()
        guard panel.runModal() == .OK else { return }; add(urls: panel.urls)
    }
    func pickLibraryFolder() {
        let panel = NSOpenPanel(); panel.title = "Müzik klasörünü seç"; panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }; libraryFolder = url; UserDefaults.standard.set(url.path, forKey: "libraryFolder"); refreshLibrary()
    }
    @objc func refreshLibrary() {
        let fileManager = FileManager.default
        let standardRoots = [fileManager.urls(for: .musicDirectory, in: .userDomainMask).first, fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first, fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first].compactMap { $0 }
        let roots = Array(Set(standardRoots + (libraryFolder.map { [$0] } ?? [])))
        let files = roots.flatMap { folder in
            (fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])?.allObjects as? [URL] ?? [])
        }.filter { url in
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && Self.supportedExtensions.contains(url.pathExtension.lowercased())
        }
        add(urls: files)
    }
    private func add(urls: [URL]) {
        let known = Set(tracks.map(\.id)); let newTracks = urls.map(Track.read).filter { !known.contains($0.id) }
        guard !newTracks.isEmpty else { return }; tracks.append(contentsOf: newTracks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }); enricher.enqueue(newTracks) { [weak self] updated in self?.replace(updated) }
    }
    private func replace(_ track: Track) { guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }; tracks[index] = track }
    func play(_ track: Track?) {
        guard let track else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: track.url)); player.play()
        currentTrackID = track.id; isPlaying = true; currentTime = 0; duration = 0; startTimer()
        recentlyPlayedIDs.removeAll { $0 == track.id }
        recentlyPlayedIDs.insert(track.id, at: 0)
        recentlyPlayedIDs = Array(recentlyPlayedIDs.prefix(50))
    }
    func togglePlayback() { guard player.currentItem != nil else { play(tracks.first); return }; isPlaying ? player.pause() : player.play(); isPlaying.toggle() }
    func seek(to time: TimeInterval) { player.seek(to: CMTime(seconds: time, preferredTimescale: 600)); currentTime = time }
    func next() {
        guard !tracks.isEmpty else { return }
        guard let index = tracks.firstIndex(where: { $0.id == currentTrackID }) else { play(tracks.first); return }
        if shuffleEnabled { play(tracks.filter { $0.id != currentTrackID }.randomElement() ?? tracks[index]); return }
        if index == tracks.indices.last && repeatMode == .off { player.pause(); isPlaying = false; return }
        play(tracks[(index + 1) % tracks.count])
    }
    func previous() { guard let index = tracks.firstIndex(where: { $0.id == currentTrackID }), !tracks.isEmpty else { return }; play(tracks[(index - 1 + tracks.count) % tracks.count]) }
    func toggleFavorite(_ track: Track) { if favoriteIDs.contains(track.id) { favoriteIDs.remove(track.id) } else { favoriteIDs.insert(track.id) } }
    func createPlaylist(name: String) { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; playlists.append(Playlist(name: name)) }
    func add(_ track: Track, to playlistID: String) { guard let index = playlists.firstIndex(where: { $0.id == playlistID }), !playlists[index].trackIDs.contains(track.id) else { return }; playlists[index].trackIDs.append(track.id) }
    func cycleRepeatMode() { repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off) }
    private func advanceAfterPlayback() { if repeatMode == .one { play(currentTrack) } else { next() } }
    func remove(_ track: Track) { if track.id == currentTrackID { player.pause(); player.replaceCurrentItem(with: nil); currentTrackID = nil; isPlaying = false; currentTime = 0; duration = 0 }; tracks.removeAll { $0.id == track.id } }
    private func startTimer() { progressTimer?.invalidate(); progressTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(updateProgress), userInfo: nil, repeats: true) }
    @objc private func updateProgress() { let current = player.currentTime().seconds; currentTime = current.isFinite ? current : 0; let total = player.currentItem?.duration.seconds ?? 0; duration = total.isFinite ? total : 0; if let error = player.currentItem?.error { message = "Bu dosya macOS’un yerleşik çözücüsüyle çalınamadı: \(error.localizedDescription)"; isPlaying = false } }
    deinit { progressTimer?.invalidate(); scanTimer?.invalidate(); if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }
}

private enum LibraryView { case all, favorites, recent, playlist(String) }

struct ContentView: View {
    @EnvironmentObject private var player: MusicPlayer
    @State private var libraryView: LibraryView = .all
    @State private var searchText = ""
    @State private var isCreatingPlaylist = false
    @State private var newPlaylistName = ""
    var body: some View { HStack(spacing: 0) { sidebar; Divider(); VStack(spacing: 0) { header; if let message = player.message { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 28).padding(.bottom, 8) }; trackList; Divider(); nowPlaying } }.background(Color(nsColor: .windowBackgroundColor)).sheet(isPresented: $isCreatingPlaylist) { VStack(spacing: 16) { Text("Yeni çalma listesi").font(.title3.weight(.semibold)); TextField("Liste adı", text: $newPlaylistName).textFieldStyle(.roundedBorder); HStack { Button("Vazgeç") { isCreatingPlaylist = false }; Spacer(); Button("Oluştur") { player.createPlaylist(name: newPlaylistName); newPlaylistName = ""; isCreatingPlaylist = false }.buttonStyle(.borderedProminent) } }.padding(24).frame(width: 320) } }
    private var sidebar: some View { VStack(alignment: .leading, spacing: 22) {
        Label("Müzik Odam", systemImage: "music.note.house.fill").font(.title3.weight(.bold)).foregroundStyle(player.accent.color)
        VStack(alignment: .leading, spacing: 10) {
            Button { libraryView = .all } label: { Label("Kütüphanem", systemImage: "music.note.list") }.buttonStyle(.plain).fontWeight(libraryView == .all ? .semibold : .regular)
            Button { libraryView = .favorites } label: { Label("Favoriler", systemImage: "heart.fill") }.buttonStyle(.plain).foregroundStyle(libraryView == .favorites ? player.accent.color : .primary)
            Button { libraryView = .recent } label: { Label("Son Çalınanlar", systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).foregroundStyle(libraryView == .recent ? player.accent.color : .primary)
            Text("\(player.tracks.count) parça").foregroundStyle(.secondary)
            Button("Klasörü Tara", action: player.refreshLibrary).buttonStyle(.plain).foregroundStyle(player.accent.color)
        }
        Spacer()
        Menu { Picker("Görünüm", selection: $player.theme) { ForEach(AppTheme.allCases) { Text($0.title).tag($0) } }; Picker("Vurgu rengi", selection: $player.accent) { ForEach(Accent.allCases) { Text($0.title).tag($0) } } } label: { Label("Görünüm", systemImage: "paintpalette") }.menuStyle(.borderlessButton)
        Text("Müzikler yalnızca Mac’inizde kalır.").font(.caption).foregroundStyle(.secondary)
    }.padding(24).frame(width: 210, alignment: .leading).background(.quaternary.opacity(0.45)) }
    private var header: some View { HStack { VStack(alignment: .leading, spacing: 4) { Text("Kütüphanem").font(.title.bold()); Text("Yerel müziklerin otomatik taranır ve bilgileri yenilenir.").foregroundStyle(.secondary) }; Spacer(); TextField("Ara", text: $searchText).textFieldStyle(.roundedBorder).frame(width: 180); Menu { Picker("Sırala", selection: $player.sortOrder) { ForEach(LibrarySort.allCases) { Text($0.title).tag($0) } }; Divider(); Button("Müzik Dosyası Ekle…", action: player.pickFiles); Button("Müzik Klasörünü Seç…", action: player.pickLibraryFolder) } label: { Label("Müzik Ekle", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(player.accent.color) }.padding(28) }
    @ViewBuilder private var trackList: some View { if player.tracks.isEmpty { VStack(spacing: 14) { Image(systemName: "music.note").font(.system(size: 44)).foregroundStyle(player.accent.color); Text("Henüz müzik bulunamadı").font(.title3.weight(.semibold)); Text("Müzik klasörünüz otomatik taranır; isterseniz başka bir klasör de seçebilirsiniz.").foregroundStyle(.secondary); Button("Müzik Klasörü Seç…", action: player.pickLibraryFolder).buttonStyle(.bordered) }.frame(maxWidth: .infinity, maxHeight: .infinity) } else { List(visibleTracks) { track in HStack(spacing: 12) { CoverArt(data: track.coverData, size: 34, accent: player.accent.color); VStack(alignment: .leading, spacing: 3) { Text(track.title).lineLimit(1); Text(track.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Button { player.toggleFavorite(track) } label: { Image(systemName: player.favoriteIDs.contains(track.id) ? "heart.fill" : "heart") }.buttonStyle(.plain).foregroundStyle(player.favoriteIDs.contains(track.id) ? player.accent.color : .secondary); Button { player.remove(track) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary) }.contentShape(Rectangle()).onTapGesture { player.play(track) }.padding(.vertical, 4) }.listStyle(.inset) } }
    private var nowPlaying: some View { VStack(spacing: 12) { HStack { CoverArt(data: player.currentTrack?.coverData, size: 46, accent: player.accent.color); VStack(alignment: .leading) { Text(player.currentTrack?.title ?? "Bir parça seç").fontWeight(.semibold).lineLimit(1); Text(player.currentTrack?.subtitle ?? "Çalmaya hazır").font(.caption).foregroundStyle(.secondary) }; Spacer(); if let track = player.currentTrack { Button { player.toggleFavorite(track) } label: { Image(systemName: player.favoriteIDs.contains(track.id) ? "heart.fill" : "heart") }.buttonStyle(.plain).foregroundStyle(player.favoriteIDs.contains(track.id) ? player.accent.color : .secondary) }; Text(time(player.currentTime) + " / " + time(player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }; HStack(spacing: 10) { Text(time(player.currentTime)).font(.caption.monospacedDigit()).foregroundStyle(.secondary); Slider(value: Binding(get: { player.currentTime }, set: player.seek), in: 0...max(player.duration, 1)).tint(player.accent.color); Text(time(player.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }; HStack(spacing: 25) { Button { player.shuffleEnabled.toggle() } label: { Image(systemName: "shuffle") }.buttonStyle(.plain).foregroundStyle(player.shuffleEnabled ? player.accent.color : .primary); Button(action: player.previous) { Image(systemName: "backward.fill") }.buttonStyle(.plain); Button(action: player.togglePlayback) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 42, height: 42) }.buttonStyle(.borderedProminent).tint(player.accent.color).clipShape(Circle()); Button(action: player.next) { Image(systemName: "forward.fill") }.buttonStyle(.plain); Button(action: player.cycleRepeatMode) { Image(systemName: player.repeatMode.icon) }.buttonStyle(.plain).foregroundStyle(player.repeatMode == .off ? .primary : player.accent.color); Spacer(); Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary); Slider(value: $player.volume, in: 0...1).frame(width: 100).tint(player.accent.color) } }.padding(.horizontal, 28).padding(.vertical, 18) }
    private var visibleTracks: [Track] {
        var result = player.tracks
        switch libraryView {
        case .all: break
        case .favorites: result = result.filter { player.favoriteIDs.contains($0.id) }
        case .recent: result = player.recentlyPlayedIDs.compactMap { id in result.first { $0.id == id } }
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

struct CoverArt: View {
    let data: Data?; let size: CGFloat; let accent: Color
    var body: some View { Group { if let data, let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFill() } else { Image(systemName: "music.note").font(size > 40 ? .title2 : .body).foregroundStyle(accent) } }.frame(width: size, height: size).background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: size > 40 ? 10 : 7)).clipShape(RoundedRectangle(cornerRadius: size > 40 ? 10 : 7)) }
}
