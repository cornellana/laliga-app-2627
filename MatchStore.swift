import Foundation
import SwiftUI

@Observable
@MainActor
final class MatchStore {
    var snapshot: MatchSnapshot?
    var isLoading = false
    var errorMessage: String?

    private static let remoteURL = URL(
        string: "https://raw.githubusercontent.com/cornellana/laliga-app-2627/refs/heads/main/data/laliga2627.json"
    )
    private static let cacheKey = "laliga2627_cache_v1"

    var matchDays: [MatchDay] { snapshot?.matchDays ?? [] }

    var standings: [LeagueStanding] {
        if let remote = snapshot?.standings, !remote.isEmpty { return remote }
        return computedStandings()
    }

    var topScorers: [TopScorer] { snapshot?.topScorers ?? [] }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // 1. Cache
        if snapshot == nil, let cached = loadFromCache() {
            snapshot = cached
        }

        // 2. Remote
        do {
            let fresh = try await fetchRemote()
            snapshot = fresh
            saveToCache(fresh)
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

        // 3. Fallback: seed del bundle (calendario completo 26/27)
        if snapshot == nil {
            snapshot = loadSeedFromBundle()
        }
    }

    // MARK: - Remote

    private func fetchRemote() async throws -> MatchSnapshot {
        guard let base = Self.remoteURL else { throw URLError(.badURL) }
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

    private func loadSeedFromBundle() -> MatchSnapshot? {
        guard let url = Bundle.main.url(forResource: "laliga2627-seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MatchSnapshot.self, from: data)
    }

    // MARK: - Cache

    private func loadFromCache() -> MatchSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(MatchSnapshot.self, from: data)
    }

    private func saveToCache(_ s: MatchSnapshot) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }

    // MARK: - Computed Standings

    private func computedStandings() -> [LeagueStanding] {
        var stats: [String: (w: Int, d: Int, l: Int, gf: Int, ga: Int)] = [:]
        for team in MatchesData.allTeams { stats[team] = (0, 0, 0, 0, 0) }

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
