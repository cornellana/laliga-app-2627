import Foundation

// MARK: - MomentumPoint

/// Un punto del gráfico de momentum de SofaScore.
/// `value` positivo = presión del equipo local (barra arriba).
/// `value` negativo = presión del visitante (barra abajo).
struct MomentumPoint: Identifiable {
    let minute: Int
    let value: Double
    var id: Int { minute }
}

// MARK: - SofaScoreService

/// Acceso a la API pública de SofaScore para La Liga (unique-tournament = 8).
enum SofaScoreService {

    /// Mapeo de espnYear → seasonID de SofaScore para La Liga.
    static let seasonIDs: [Int: Int] = [2026: 97268, 2025: 77559, 2024: 61643]

    // MARK: - Event resolution

    /// Resuelve el `eventID` de SofaScore a partir de temporada, jornada y nombres de equipo.
    /// Devuelve `nil` si no se encuentra o la red falla.
    static func resolveEventID(espnYear: Int, jornada: Int,
                               home: String, away: String) async -> Int? {
        guard let seasonID = seasonIDs[espnYear] else { return nil }

        var req = URLRequest(url: URL(string:
            "https://api.sofascore.com/api/v1/unique-tournament/8/season/\(seasonID)/events/round/\(jornada)"
        )!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else { return nil }

        guard let event = events.first(where: { e in
            let ht = (e["homeTeam"] as? [String: Any])?["name"] as? String
            let at = (e["awayTeam"] as? [String: Any])?["name"] as? String
            return teamMatches(ht, home) && teamMatches(at, away)
        }) else { return nil }

        return event["id"] as? Int
    }

    // MARK: - Momentum

    /// Descarga los puntos de momentum de un partido dado su `eventID`.
    /// Devuelve `nil` si el partido no tiene datos o la red falla.
    static func fetchMomentum(eventID: Int) async -> [MomentumPoint]? {
        var req = URLRequest(url: URL(string:
            "https://api.sofascore.com/api/v1/event/\(eventID)/graph"
        )!)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pts = json["graphPoints"] as? [[String: Any]] else { return nil }

        let points = pts.compactMap { p -> MomentumPoint? in
            guard let min = p["minute"] as? Int,
                  let val = p["value"] as? Double ?? (p["value"] as? Int).map(Double.init)
            else { return nil }
            return MomentumPoint(minute: min, value: val)
        }
        return points.isEmpty ? nil : points
    }

    // MARK: - Helpers

    /// Compara nombres de equipo ignorando tildes/mayúsculas, con fallback por palabras >3 chars.
    static func teamMatches(_ sfaName: String?, _ appName: String) -> Bool {
        guard let n = sfaName else { return false }
        let norm = n.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let app  = appName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if norm.contains(app) || app.contains(norm) { return true }
        return app.split(separator: " ").filter { $0.count > 3 }.contains { norm.contains($0) }
    }
}
