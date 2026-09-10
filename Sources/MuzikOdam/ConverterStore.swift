import Foundation
import AppKit

@MainActor
final class ConverterStore: ObservableObject {
    @Published private(set) var tasks: [ConversionTask] = [] { didSet { persistHistory() } }
    @Published var outputFolder: URL
    @Published private(set) var isConverting = false
    private var worker: Task<Void, Never>?

    init() {
        outputFolder = UserDefaults.standard.string(forKey: "converterOutputFolder").map(URL.init(fileURLWithPath:))
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        if let data = UserDefaults.standard.data(forKey: "conversionHistory") {
            tasks = Array((try? JSONDecoder().decode([ConversionTask].self, from: data)) ?? []).suffix(100)
        }
    }

    func add(urls: [URL], format: ConversionFormat) {
        tasks.append(contentsOf: urls.map { ConversionTask(sourceURL: $0, format: format) })
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose output folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolder = url
        UserDefaults.standard.set(url.path, forKey: "converterOutputFolder")
    }

    func start() {
        guard !isConverting, tasks.contains(where: { $0.state == .waiting }) else { return }
        isConverting = true
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, let index = self.tasks.firstIndex(where: { $0.state == .waiting }) {
                self.tasks[index].state = .converting
                self.tasks[index].errorMessage = nil
                let source = self.tasks[index].sourceURL
                let format = self.tasks[index].format
                let finalURL = self.uniqueOutputURL(for: source, format: format)
                let temporaryURL = finalURL.deletingLastPathComponent().appendingPathComponent("." + UUID().uuidString + ".partial." + format.fileExtension)
                do {
                    try await LocalConversionEngine.convert(source: source, destination: temporaryURL, format: format)
                    try Task.checkCancellation()
                    try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
                    self.tasks[index].outputURL = finalURL
                    self.tasks[index].state = .completed
                } catch is CancellationError {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    self.tasks[index].state = .cancelled
                } catch {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    self.tasks[index].state = .failed
                    self.tasks[index].errorMessage = error.localizedDescription
                }
            }
            self.isConverting = false
        }
    }

    func cancel(_ task: ConversionTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if tasks[index].state == .waiting { tasks[index].state = .cancelled } else if tasks[index].state == .converting { worker?.cancel() }
    }

    func retry(_ task: ConversionTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].state = .waiting
        tasks[index].errorMessage = nil
        tasks[index].outputURL = nil
    }

    func clearHistory() {
        guard !isConverting else { return }
        tasks.removeAll()
    }

    private func uniqueOutputURL(for source: URL, format: ConversionFormat) -> URL {
        let folder = outputFolder
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(base + " " + String(number)).appendingPathExtension(format.fileExtension)
            number += 1
        }
        return candidate
    }

    private func persistHistory() {
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(tasks.suffix(100))), forKey: "conversionHistory")
    }
}
