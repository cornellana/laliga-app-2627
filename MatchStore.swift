import Foundation
import SwiftUI

@Observable
@MainActor
final class MatchStore {
    private(set) var selectedSeason: AppSeason = .current
    var isLoading = true   // spinner desde el primer render, sin esperar al .task
    var errorMessage: String?

    /// Marca de tiempo del dato que hay ahora en pantalla, sacada del propio
    /// JSON. No es cuándo se pidió, es de cuándo son los datos.
    private(set) var dataTimestamp: Date?

    /// `true` si el último intento de refresco no llegó a buen puerto.
    ///
    /// Hace falta porque hasta ahora solo se avisaba de los errores de red
    /// conocidos: si fallaba cualquier otra cosa —una respuesta rara del
    /// servidor, un JSON que no decodifica— la app se quedaba callada con los
    /// datos viejos y desde fuera parecía que simplemente no pasaba nada.
    private(set) var lastRefreshFailed = false

    // Caché en memoria por temporada (evita refetches innecesarios al volver a la temporada)
    private var cache: [String: MatchSnapshot] = [:]

    var snapshot: MatchSnapshot? { cache[selectedSeason.code] }

    var matchDays: [MatchDay]       { snapshot?.matchDays ?? [] }
    var topScorers: [TopScorer]     { snapshot?.topScorers ?? [] }

    var standings: [LeagueStanding] {
        if let remote = snapshot?.standings, !remote.isEmpty { return remote }
        return computedStandings()
    }

    // MARK: - Season selection

    func selectSeason(_ season: AppSeason) async {
        guard season != selectedSeason else { return }
        selectedSeason = season
        errorMessage = nil
        if cache[season.code] == nil {
            await refresh()
        }
    }

    // MARK: - Refresh

    func refresh() async {
        let season = selectedSeason
        errorMessage = nil

        // 1. Memoria — si ya hay datos, no bloquear la UI en absoluto
        if cache[season.code] != nil {
            await silentRemoteRefresh(season: season)
            return
        }

        // 2. UserDefaults — mostrar datos en caché antes de ir a la red
        isLoading = true
        if let cached = decodeOffMain({ self.loadFromUserDefaults(season) }) {
            cache[season.code] = cached
            dataTimestamp = Self.parseTimestamp(cached.lastUpdated)
            isLoading = false          // datos disponibles: UI visible mientras se refresca la red
        }

        // 3. Sin caché: ir a red con spinner visible
        await silentRemoteRefresh(season: season)

        // 4. Seed del bundle si la red falló y seguimos sin datos
        if cache[season.code] == nil {
            isLoading = true
            if let seed = decodeOffMain({ self.loadSeedFromBundle(season) }) {
                cache[season.code] = seed
                dataTimestamp = Self.parseTimestamp(seed.lastUpdated)
            }
            isLoading = false
        }
    }

    /// Refresca desde la red sin tocar isLoading (silent background update).
    private func silentRemoteRefresh(season: AppSeason) async {
        do {
            let fresh = try await fetchRemote(season)
            cache[season.code] = fresh
            dataTimestamp = Self.parseTimestamp(fresh.lastUpdated)
            lastRefreshFailed = false
            errorMessage = nil
            saveToUserDefaults(fresh, season: season)
        } catch {
            lastRefreshFailed = true
            if let urlError = error as? URLError,
               [.notConnectedToInternet, .networkConnectionLost,
                .timedOut, .cannotConnectToHost].contains(urlError.code) {
                errorMessage = "Sin conexión a Internet"
            }
        }
        isLoading = false
    }

    /// Antigüedad del dato en pantalla, o `nil` si no se sabe.
    var dataAge: TimeInterval? {
        dataTimestamp.map { Date().timeIntervalSince($0) }
    }

    /// Convierte la marca del JSON a fecha. Es `"2026-08-31T20:06:58Z"`.
    private static func parseTimestamp(_ raw: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }

    /// Ejecuta un decode JSON en el main actor (conformances Codable son @MainActor con InferIsolatedConformances).
    private func decodeOffMain<T>(_ work: () -> T?) -> T? {
        work()
    }

    // MARK: - Remote

    /// Primero el NAS, que publica en segundos; si no contesta rápido, GitHub.
    ///
    /// La app no puede quedar atada a que el NAS o la fibra de casa estén en
    /// pie: por eso el intento rápido lleva un tiempo límite corto y cualquier
    /// fallo —red, servidor caído, JSON a medias— cae en silencio a la fuente
    /// de siempre, que es la que ha funcionado hasta ahora.
    nonisolated private func fetchRemote(_ season: AppSeason) async throws -> MatchSnapshot {
        if let fast = season.fastURL,
           let data = try? await download(fast, timeout: 4),
           let snapshot = try? await decodeSnapshot(data) {
            return snapshot
        }
        guard let base = season.remoteURL else { throw URLError(.badURL) }
        return try await decodeSnapshot(try await download(base, timeout: 20))
    }

    nonisolated private func download(_ base: URL, timeout: TimeInterval) async throws -> Data {
        // El sufijo temporal esquiva cachés intermedias; el de GitHub las tiene.
        let urlStr = "\(base.absoluteString)?t=\(Int(Date().timeIntervalSince1970))"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }

    nonisolated private func decodeSnapshot(_ data: Data) async throws -> MatchSnapshot {
        try await MainActor.run {
            try JSONDecoder().decode(MatchSnapshot.self, from: data)
        }
    }

    // MARK: - Bundle seed

    private func loadSeedFromBundle(_ season: AppSeason) -> MatchSnapshot? {
        guard let url = Bundle.main.url(forResource: season.seedName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MatchSnapshot.self, from: data)
    }

    // MARK: - UserDefaults cache

    private func cacheKey(_ season: AppSeason) -> String { "laliga_cache_v2_\(season.code)" }

    private func loadFromUserDefaults(_ season: AppSeason) -> MatchSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(season)) else { return nil }
        return try? JSONDecoder().decode(MatchSnapshot.self, from: data)
    }

    private func saveToUserDefaults(_ snapshot: MatchSnapshot, season: AppSeason) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(season))
    }

    // MARK: - Computed Standings

    private func computedStandings() -> [LeagueStanding] {
        var stats: [String: (w: Int, d: Int, l: Int, gf: Int, ga: Int)] = [:]
        for day in matchDays {
            for match in day.games {
                if stats[match.home] == nil { stats[match.home] = (0, 0, 0, 0, 0) }
                if stats[match.away] == nil { stats[match.away] = (0, 0, 0, 0, 0) }
            }
        }

        for day in matchDays {
            for match in day.games where match.done {
                guard var home = stats[match.home], var away = stats[match.away],
                      let hs = match.homeScore, let as_ = match.awayScore else { continue }
                if hs > as_ { home.w += 1; away.l += 1 }
                else if hs < as_ { home.l += 1; away.w += 1 }
                else { home.d += 1; away.d += 1 }
                home.gf += hs; home.ga += as_
                away.gf += as_; away.ga += hs
                stats[match.home] = home; stats[match.away] = away
            }
        }

        let sorted = stats
            .map { team, s in
                LeagueStanding(position: 0, team: team,
                               played: s.w + s.d + s.l,
                               won: s.w, drawn: s.d, lost: s.l,
                               goalsFor: s.gf, goalsAgainst: s.ga)
            }
            .sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                if $0.goalDifference != $1.goalDifference { return $0.goalDifference > $1.goalDifference }
                return $0.goalsFor > $1.goalsFor
            }

        return sorted.enumerated().map { idx, s in
            LeagueStanding(position: idx + 1, team: s.team,
                           played: s.played, won: s.won, drawn: s.drawn, lost: s.lost,
                           goalsFor: s.goalsFor, goalsAgainst: s.goalsAgainst)
        }
    }
}
