import Foundation

enum AdvancedLibrarySort: String, CaseIterable, Identifiable {
    case title, artist, album, genre, year, duration, dateAdded, lastPlayed, playCount, favorites

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        let tr: String
        let en: String
        switch self {
        case .title: (tr, en) = ("Parça adı", "Track name")
        case .artist: (tr, en) = ("Sanatçı", "Artist")
        case .album: (tr, en) = ("Albüm", "Album")
        case .genre: (tr, en) = ("Tür", "Genre")
        case .year: (tr, en) = ("Yıl", "Year")
        case .duration: (tr, en) = ("Süre", "Duration")
        case .dateAdded: (tr, en) = ("Eklenme tarihi", "Date added")
        case .lastPlayed: (tr, en) = ("Son çalınma", "Last played")
        case .playCount: (tr, en) = ("Çalma sayısı", "Play count")
        case .favorites: (tr, en) = ("Favoriler", "Favorites")
        }
        return language == .turkish ? tr : en
    }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending, descending
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        language == .turkish ? (self == .ascending ? "Artan" : "Azalan") : (self == .ascending ? "Ascending" : "Descending")
    }
}

enum SmartPlaylistKind: String, CaseIterable, Identifiable {
    case mostPlayed, recentlyPlayed, recentlyAdded, unplayed, favorites
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        let tr: String
        let en: String
        switch self {
        case .mostPlayed: (tr, en) = ("En Çok Çalınanlar", "Most Played")
        case .recentlyPlayed: (tr, en) = ("Son Çalınanlar", "Recently Played")
        case .recentlyAdded: (tr, en) = ("Son Eklenenler", "Recently Added")
        case .unplayed: (tr, en) = ("Hiç Çalınmayanlar", "Never Played")
        case .favorites: (tr, en) = ("Favoriler", "Favorites")
        }
        return language == .turkish ? tr : en
    }
    var icon: String {
        switch self {
        case .mostPlayed: "chart.bar.fill"
        case .recentlyPlayed: "clock.arrow.circlepath"
        case .recentlyAdded: "sparkles"
        case .unplayed: "play.slash"
        case .favorites: "heart.fill"
        }
    }
}

struct TrackStatistics: Codable, Equatable {
    var dateAdded: Date
    var lastPlayedDate: Date?
    var playCount: Int
    var skipCount: Int

    init(dateAdded: Date = .now, lastPlayedDate: Date? = nil, playCount: Int = 0, skipCount: Int = 0) {
        self.dateAdded = dateAdded
        self.lastPlayedDate = lastPlayedDate
        self.playCount = playCount
        self.skipCount = skipCount
    }
}

struct LibraryFilter: Equatable {
    var genre: String? = nil
    var year: String? = nil
    var favoritesOnly = false
}
