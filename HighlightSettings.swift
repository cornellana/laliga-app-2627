import SwiftUI
import Foundation

// MARK: - TeamHighlight

struct TeamHighlight: Codable, Identifiable, Equatable {
    var id: String { team }
    var team: String
    var colorHex: UInt

    var color: Color { Color(hex: colorHex) }
}

// MARK: - NotificationPrefs

struct NotificationPrefs: Codable, Equatable {
    var enabled:    Bool = false
    var goals:      Bool = true
    var penalties:  Bool = true
    var redCards:   Bool = true
    var startEnd:   Bool = true
}

// MARK: - HighlightSettings

@Observable
final class HighlightSettings {
    private static let highlightKey = "highlight_settings_v1"
    private static let notifKey     = "notification_prefs_v1"

    var highlights: [TeamHighlight] {
        didSet {
            persist()
            NotificationService.shared.sync(teams: highlights.map(\.team), prefs: notifications)
        }
    }

    var notifications: NotificationPrefs {
        didSet {
            persistNotifications()
            NotificationService.shared.sync(teams: highlights.map(\.team), prefs: notifications)
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.highlightKey),
           let decoded = try? JSONDecoder().decode([TeamHighlight].self, from: data) {
            self.highlights = decoded
        } else {
            self.highlights = []
        }

        if let data = UserDefaults.standard.data(forKey: Self.notifKey),
           let decoded = try? JSONDecoder().decode(NotificationPrefs.self, from: data) {
            self.notifications = decoded
        } else {
            self.notifications = NotificationPrefs()
        }

        // Cachea teams y prefs para que NotificationService pueda registrar
        // en cuanto APNs entregue el token
        NotificationService.shared.updateCache(
            teams: self.highlights.map(\.team),
            prefs: self.notifications
        )
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
            UserDefaults.standard.set(data, forKey: Self.highlightKey)
        }
    }

    private func persistNotifications() {
        if let data = try? JSONEncoder().encode(notifications) {
            UserDefaults.standard.set(data, forKey: Self.notifKey)
        }
    }
}
