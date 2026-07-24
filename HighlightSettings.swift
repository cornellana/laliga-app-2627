import SwiftUI
import Foundation

// MARK: - TeamHighlight

struct TeamHighlight: Codable, Identifiable, Equatable {
    var id: String { team }
    var team: String
    var colorHex: UInt

    var color: Color { Color(hex: colorHex) }
}

// MARK: - HighlightSettings

@Observable
final class HighlightSettings {
    private static let key = "highlight_settings_v1"

    var highlights: [TeamHighlight] {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([TeamHighlight].self, from: data) {
            self.highlights = decoded
        } else {
            // Default: FC Barcelona blaugrana
            self.highlights = [TeamHighlight(team: "FC Barcelona", colorHex: 0x004D98)]
        }
    }

    func highlight(for team: String) -> TeamHighlight? {
        highlights.first { $0.team == team }
    }

    func add(team: String, color: Color) {
        guard !highlights.contains(where: { $0.team == team }) else { return }
        highlights.append(TeamHighlight(team: team, colorHex: color.toHex()))
    }

    func remove(at offsets: IndexSet) {
        highlights.remove(atOffsets: offsets)
    }

    func update(id: String, color: Color) {
        guard let idx = highlights.firstIndex(where: { $0.id == id }) else { return }
        highlights[idx].colorHex = color.toHex()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(highlights) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
