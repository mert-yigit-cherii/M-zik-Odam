import SwiftUI
import UniformTypeIdentifiers

struct LibraryDropModifier: ViewModifier {
    let player: MusicPlayer
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isTargeted ? player.accent.color : .clear, lineWidth: 2).padding(8))
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                for provider in providers {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                        DispatchQueue.main.async { player.importDroppedURL(url) }
                    }
                }
                return true
            }
    }
}
