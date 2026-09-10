import Foundation
import AVFoundation

enum ConversionFormat: String, CaseIterable, Codable, Identifiable {
    case m4a
    var id: String { rawValue }
    var fileExtension: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .m4a: "AAC / M4A"
        }
    }
}

enum ConversionState: String, Codable {
    case waiting, converting, completed, failed, cancelled
    func title(_ language: AppLanguage) -> String {
        let tr: String
        let en: String
        switch self {
        case .waiting: (tr, en) = ("Bekliyor", "Waiting")
        case .converting: (tr, en) = ("Dönüştürülüyor", "Converting")
        case .completed: (tr, en) = ("Tamamlandı", "Completed")
        case .failed: (tr, en) = ("Başarısız", "Failed")
        case .cancelled: (tr, en) = ("İptal edildi", "Cancelled")
        }
        return language == .turkish ? tr : en
    }
}

struct ConversionTask: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceURL: URL
    var outputURL: URL?
    var format: ConversionFormat
    var state: ConversionState
    var errorMessage: String?
    var createdAt: Date

    init(sourceURL: URL, format: ConversionFormat) {
        id = UUID()
        self.sourceURL = sourceURL
        outputURL = nil
        self.format = format
        state = .waiting
        errorMessage = nil
        createdAt = .now
    }
}

enum LocalConverterError: LocalizedError {
    case unsupportedInput
    case cancelled
    case outputUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedInput: "The selected file has no readable audio track."
        case .cancelled: "Conversion was cancelled."
        case .outputUnavailable: "The output could not be created."
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}

enum LocalConversionEngine {
    static func convert(source: URL, destination: URL, format: ConversionFormat) async throws {
        switch format {
        case .m4a: try await exportM4A(source: source, destination: destination)
        }
    }

    private static func exportM4A(source: URL, destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let hasAudio = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        guard try await asset.load(.isPlayable), hasAudio else { throw LocalConverterError.unsupportedInput }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw LocalConverterError.outputUnavailable }
        guard await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetAppleM4A, with: asset, outputFileType: .m4a) else { throw LocalConverterError.unsupportedInput }
        session.outputURL = destination
        session.outputFileType = .m4a
        session.metadata = (try? await asset.load(.commonMetadata)) ?? []
        let sessionBox = ExportSessionBox(session)
        try await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            try Task.checkCancellation()
            guard session.status == .completed else { throw session.error ?? LocalConverterError.outputUnavailable }
        }, onCancel: {
            sessionBox.session.cancelExport()
        })
    }
}
