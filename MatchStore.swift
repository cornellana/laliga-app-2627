import Foundation
import SwiftUI

@Observable
@MainActor
final class MatchStore {
    private(set) var selectedSeason: AppSeason = .current
    var isLoading = false
    var errorMessage: String?

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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 1. UserDefaults cache (solo si no hay caché en memoria)
        if cache[season.code] == nil, let cached = loadFromUserDefaults(season) {
            cache[season.code] = cached
        }

        // 2. Remote
        do {
            let fresh = try await fetchRemote(season)
            cache[season.code] = fresh
            saveToUserDefaults(fresh, season: season)
            return
        } catch {
            let isOffline: Bool
            if let urlError = error as? URLError {
                isOffline = [.notConnectedToInternet, .networkConnectionLost,
                             .timedOut, .cannotConnectToHost].contains(urlError.code)
            } else {
                isOffline = false
            }
            if isOffline { errorMessage = "Sin conexión a Internet" }
        }

        // 3. Seed del bundle
        if cache[season.code] == nil {
            cache[season.code] = loadSeedFromBundle(season)
        }
    }

    // MARK: - Remote

    private func fetchRemote(_ season: AppSeason) async throws -> MatchSnapshot {
        guard let base = season.remoteURL else { throw URLError(.badURL) }
        let urlStr = "\(base.absoluteString)?t=\(Int(Date().timeIntervalSince1970))"
        let url = URL(string: urlStr)!
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MatchSnapshot.self, from: data)
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
