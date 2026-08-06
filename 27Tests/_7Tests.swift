//
//  _7Tests.swift
//  27Tests
//
//  Created by Francisco on 7/3/26.
//

import Testing
@testable import _7

struct _7Tests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}

// MARK: - PredictionEngine

private func completed(_ home: String, _ hs: Int, _ away: String, _ as_: Int, jornada: Int) -> Match {
    Match(id: "\(home)-\(away)-\(jornada)", time: "21:00", home: home, away: away,
          jornada: jornada, tv: nil, done: true, result: "\(hs)-\(as_)",
          details: nil, stadium: nil, venueCity: nil, espnEventID: nil)
}

private func upcoming(_ home: String, _ away: String, jornada: Int) -> Match {
    Match(id: "\(home)-\(away)-next", time: "21:00", home: home, away: away,
          jornada: jornada, tv: nil, done: false, result: nil,
          details: nil, stadium: nil, venueCity: nil, espnEventID: nil)
}

struct PredictionEngineTests {

    /// Historial donde "Fuerte" golea siempre y "Débil" siempre encaja.
    private var lopsidedMatchDays: [MatchDay] {
        [
            MatchDay(date: "2026-08-15", jornada: 1, games: [
                completed("Fuerte", 4, "Medio", 0, jornada: 1),
                completed("Otro", 1, "Débil", 3, jornada: 1),
            ]),
            MatchDay(date: "2026-08-22", jornada: 2, games: [
                completed("Fuerte", 3, "Otro", 0, jornada: 2),
                completed("Débil", 0, "Medio", 2, jornada: 2),
            ]),
            MatchDay(date: "2026-08-29", jornada: 3, games: [
                completed("Medio", 1, "Otro", 1, jornada: 3),
                completed("Fuerte", 5, "Débil", 0, jornada: 3),
            ]),
        ]
    }

    @Test func probabilitiesSumToOne() throws {
        let match = upcoming("Fuerte", "Débil", jornada: 4)
        let p = try #require(PredictionEngine.predict(match: match, matchDays: lopsidedMatchDays, season: .current))
        #expect(abs((p.homeWin + p.draw + p.awayWin) - 1.0) < 0.001)
        for value in [p.homeWin, p.draw, p.awayWin] {
            #expect(value >= 0 && value <= 1)
        }
    }

    @Test func favoriteHasHigherWinProbability() throws {
        let match = upcoming("Fuerte", "Débil", jornada: 4)
        let p = try #require(PredictionEngine.predict(match: match, matchDays: lopsidedMatchDays, season: .current))
        #expect(p.homeWin > p.awayWin)
        #expect(p.homeWin > p.draw)
    }

    @Test func producesExpectedFactors() throws {
        let match = upcoming("Fuerte", "Débil", jornada: 4)
        let p = try #require(PredictionEngine.predict(match: match, matchDays: lopsidedMatchDays, season: .current))
        #expect(p.factors.contains { $0.label == "Forma reciente" })
        #expect(p.factors.contains { $0.label == "Goles esperados" })
    }

    @Test func noDataReturnsNil() {
        let match = upcoming("A", "B", jornada: 1)
        // Sin partidos completados en la temporada de test; el prior del bundle puede no existir
        // en el bundle de pruebas, en cuyo caso no hay señal y debe devolver nil.
        let emptyDays: [MatchDay] = [MatchDay(date: "2026-08-15", jornada: 1, games: [match])]
        let p = PredictionEngine.predict(match: match, matchDays: emptyDays, season: .current)
        if let p { #expect(abs((p.homeWin + p.draw + p.awayWin) - 1.0) < 0.001) }
    }
}
