import Foundation

// MARK: - Modelos de salida

/// Una fila del desglose ampliable del pronóstico (etiqueta + valor de cada equipo).
struct PredictionFactor: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let homeValue: String
    let awayValue: String
}

/// Probabilidades de resultado (suman 1) más los factores que las explican.
struct MatchPrediction: Sendable {
    let homeWin: Double
    let draw: Double
    let awayWin: Double
    let factors: [PredictionFactor]

    var homePercent: Int { Int((homeWin * 100).rounded()) }
    var drawPercent: Int { Int((draw * 100).rounded()) }
    var awayPercent: Int { Int((awayWin * 100).rounded()) }
}

// MARK: - Motor de predicción

/// Modelo Poisson bivariante (tipo Dixon–Coles simplificado). Puro, sincrónico y sin red:
/// deriva fuerza ofensiva/defensiva de los resultados de la temporada, aplica la ventaja de
/// local a través de las medias de goles de la liga y, al arranque de temporada (muestra
/// pequeña), regresa a un *prior* calculado con las temporadas anteriores incluidas en el bundle.
enum PredictionEngine {

    /// Goles máximos por equipo considerados en la matriz de probabilidad.
    private static let maxGoals = 8
    /// Constante de regresión al *prior* (número de partidos "virtuales").
    private static let shrinkageK = 5.0
    /// Medias por defecto cuando no hay ninguna muestra (goles de local / visitante por partido).
    private static let fallbackHomeAvg = 1.5
    private static let fallbackAwayAvg = 1.1

    /// Devuelve el pronóstico del partido, o `nil` si no hay ninguna señal utilizable.
    static func predict(match: Match, matchDays: [MatchDay], season: AppSeason) -> MatchPrediction? {
        let priorDays = priorMatchDays(excluding: season)
        let current = aggregate(matchDays)
        let prior = aggregate(priorDays)

        // Sin datos de temporada ni histórico: no hay nada que estimar.
        guard current.matches > 0 || prior.matches > 0 else { return nil }

        // Medias de liga (encierran la ventaja de local). Se prefiere la temporada en curso.
        let leagueHomeAvg = current.matches > 0 ? current.leagueHomeAvg
            : (prior.matches > 0 ? prior.leagueHomeAvg : fallbackHomeAvg)
        let leagueAwayAvg = current.matches > 0 ? current.leagueAwayAvg
            : (prior.matches > 0 ? prior.leagueAwayAvg : fallbackAwayAvg)

        let homeAtt = attackStrength(match.home, current: current, prior: prior)
        let homeDef = defenseStrength(match.home, current: current, prior: prior)
        let awayAtt = attackStrength(match.away, current: current, prior: prior)
        let awayDef = defenseStrength(match.away, current: current, prior: prior)

        // Goles esperados de cada equipo.
        let lambdaHome = max(0.15, homeAtt * awayDef * leagueHomeAvg)
        let lambdaAway = max(0.15, awayAtt * homeDef * leagueAwayAvg)

        var pHome = 0.0, pDraw = 0.0, pAway = 0.0
        for i in 0...maxGoals {
            for j in 0...maxGoals {
                let p = poisson(i, lambdaHome) * poisson(j, lambdaAway)
                if i > j { pHome += p } else if i < j { pAway += p } else { pDraw += p }
            }
        }
        let total = pHome + pDraw + pAway
        guard total > 0 else { return nil }
        pHome /= total; pDraw /= total; pAway /= total

        let factors = buildFactors(
            match: match, season: season, currentDays: matchDays, priorDays: priorDays,
            current: current, prior: prior, lambdaHome: lambdaHome, lambdaAway: lambdaAway
        )

        return MatchPrediction(homeWin: pHome, draw: pDraw, awayWin: pAway, factors: factors)
    }

    // MARK: - Fuerzas con regresión al prior

    private static func attackStrength(_ team: String, current: RateAggregate, prior: RateAggregate) -> Double {
        blendedStrength(current.attack(team), prior.attack(team), games: current.games[team] ?? 0)
    }

    private static func defenseStrength(_ team: String, current: RateAggregate, prior: RateAggregate) -> Double {
        blendedStrength(current.defense(team), prior.defense(team), games: current.games[team] ?? 0)
    }

    /// Mezcla la fuerza de la temporada en curso con el *prior* según cuántos partidos hay.
    private static func blendedStrength(_ raw: Double?, _ prior: Double?, games: Int) -> Double {
        let priorStrength = prior ?? 1.0            // sin histórico → fuerza media de liga
        guard let raw else { return priorStrength }
        let w = Double(games) / (Double(games) + shrinkageK)
        return w * raw + (1 - w) * priorStrength
    }

    // MARK: - Agregación de tasas

    /// Tasas de goles por equipo y de liga a partir de partidos completados.
    private struct RateAggregate {
        var gf: [String: Int] = [:]
        var ga: [String: Int] = [:]
        var games: [String: Int] = [:]
        var homeGoals = 0
        var awayGoals = 0
        var matches = 0

        var leagueHomeAvg: Double { matches > 0 ? Double(homeGoals) / Double(matches) : 0 }
        var leagueAwayAvg: Double { matches > 0 ? Double(awayGoals) / Double(matches) : 0 }
        /// Goles medios que marca un equipo por partido en esta muestra.
        var perTeamAvg: Double { matches > 0 ? Double(homeGoals + awayGoals) / Double(matches * 2) : 0 }

        /// Fuerza ofensiva (1.0 = media de liga); `nil` si el equipo no tiene partidos.
        func attack(_ team: String) -> Double? {
            guard let g = games[team], g > 0, perTeamAvg > 0 else { return nil }
            return (Double(gf[team] ?? 0) / Double(g)) / perTeamAvg
        }

        /// Fuerza defensiva (1.0 = media; >1 encaja más de lo normal); `nil` si no hay partidos.
        func defense(_ team: String) -> Double? {
            guard let g = games[team], g > 0, perTeamAvg > 0 else { return nil }
            return (Double(ga[team] ?? 0) / Double(g)) / perTeamAvg
        }
    }

    private static func aggregate(_ matchDays: [MatchDay]) -> RateAggregate {
        var agg = RateAggregate()
        for day in matchDays {
            for m in day.games where m.done {
                guard let hs = m.homeScore, let as_ = m.awayScore else { continue }
                agg.gf[m.home, default: 0] += hs
                agg.ga[m.home, default: 0] += as_
                agg.gf[m.away, default: 0] += as_
                agg.ga[m.away, default: 0] += hs
                agg.games[m.home, default: 0] += 1
                agg.games[m.away, default: 0] += 1
                agg.homeGoals += hs
                agg.awayGoals += as_
                agg.matches += 1
            }
        }
        return agg
    }

    /// Partidos de las temporadas anteriores (desde los *seeds* del bundle), usados como *prior*.
    private static func priorMatchDays(excluding current: AppSeason) -> [MatchDay] {
        var days: [MatchDay] = []
        for season in AppSeason.all where season.code != current.code {
            if let snapshot = loadSeed(season.seedName) {
                days.append(contentsOf: snapshot.matchDays)
            }
        }
        return days
    }

    /// La temporada inmediatamente anterior a `current` (nil si no hay histórico).
    private static func previousSeason(of current: AppSeason) -> AppSeason? {
        guard let idx = AppSeason.all.firstIndex(where: { $0.code == current.code }) else { return nil }
        let next = idx + 1
        return next < AppSeason.all.count ? AppSeason.all[next] : nil
    }

    private static func loadSeed(_ name: String) -> MatchSnapshot? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MatchSnapshot.self, from: data)
    }

    // MARK: - Factores del desglose

    private static func buildFactors(
        match: Match, season: AppSeason, currentDays: [MatchDay], priorDays: [MatchDay],
        current: RateAggregate, prior: RateAggregate,
        lambdaHome: Double, lambdaAway: Double
    ) -> [PredictionFactor] {
        // Para cada equipo, usa la temporada en curso si ya ha jugado; si no, el histórico.
        func rates(_ team: String) -> RateAggregate { (current.games[team] ?? 0) > 0 ? current : prior }
        let homeRates = rates(match.home)
        let awayRates = rates(match.away)

        var factors: [PredictionFactor] = []

        // Forma reciente: partidos de la temporada en curso + histórico, por fecha (los 5 más nuevos).
        let formDays = currentDays + priorDays
        factors.append(PredictionFactor(
            label: "Forma reciente",
            homeValue: recentForm(team: match.home, matchDays: formDays),
            awayValue: recentForm(team: match.away, matchDays: formDays)
        ))
        factors.append(PredictionFactor(
            label: "Goles a favor /p",
            homeValue: perGame(homeRates.gf[match.home], games: homeRates.games[match.home]),
            awayValue: perGame(awayRates.gf[match.away], games: awayRates.games[match.away])
        ))
        factors.append(PredictionFactor(
            label: "Goles en contra /p",
            homeValue: perGame(homeRates.ga[match.home], games: homeRates.games[match.home]),
            awayValue: perGame(awayRates.ga[match.away], games: awayRates.games[match.away])
        ))

        // Posición: clasificación en curso si la hay; si no, la final de la temporada anterior.
        let positionLabel: String
        let ranking: [String: Int]
        if current.matches > 0 {
            positionLabel = "Posición"
            ranking = positionRanking(currentDays)
        } else if let prev = previousSeason(of: season), let snap = loadSeed(prev.seedName) {
            positionLabel = "Posición \(prev.displayName)"
            ranking = positionRanking(snap.matchDays)
        } else {
            positionLabel = "Posición"
            ranking = [:]
        }
        factors.append(PredictionFactor(
            label: positionLabel,
            homeValue: ranking[match.home].map { "\($0)º" } ?? "—",
            awayValue: ranking[match.away].map { "\($0)º" } ?? "—"
        ))
        factors.append(PredictionFactor(
            label: "Goles esperados",
            homeValue: String(format: "%.1f", lambdaHome),
            awayValue: String(format: "%.1f", lambdaAway)
        ))

        return factors
    }

    /// Últimos 5 resultados del equipo, del más antiguo al más reciente ("V E D …").
    private static func recentForm(team: String, matchDays: [MatchDay]) -> String {
        let completed = matchDays
            .flatMap { day in day.games.filter { ($0.home == team || $0.away == team) && $0.done }
                .map { (date: day.date, match: $0) } }
            .sorted { $0.date < $1.date }
            .suffix(5)
        guard !completed.isEmpty else { return "—" }
        return completed.map { item -> String in
            let m = item.match
            guard let hs = m.homeScore, let as_ = m.awayScore else { return "·" }
            let mine = m.home == team ? hs : as_
            let theirs = m.home == team ? as_ : hs
            if mine > theirs { return "V" }
            if mine < theirs { return "D" }
            return "E"
        }.joined(separator: " ")
    }

    private static func perGame(_ goals: Int?, games: Int?) -> String {
        guard let games, games > 0 else { return "—" }
        return String(format: "%.1f", Double(goals ?? 0) / Double(games))
    }

    /// Ranking (posición) por puntos, luego diferencia de goles, luego goles a favor.
    private static func positionRanking(_ matchDays: [MatchDay]) -> [String: Int] {
        struct Row { var pts = 0, gd = 0, gf = 0 }
        var rows: [String: Row] = [:]
        for day in matchDays {
            for m in day.games where m.done {
                guard let hs = m.homeScore, let as_ = m.awayScore else { continue }
                var home = rows[m.home] ?? Row(); var away = rows[m.away] ?? Row()
                home.gf += hs; home.gd += hs - as_
                away.gf += as_; away.gd += as_ - hs
                if hs > as_ { home.pts += 3 } else if hs < as_ { away.pts += 3 }
                else { home.pts += 1; away.pts += 1 }
                rows[m.home] = home; rows[m.away] = away
            }
        }
        let sorted = rows.sorted {
            if $0.value.pts != $1.value.pts { return $0.value.pts > $1.value.pts }
            if $0.value.gd != $1.value.gd { return $0.value.gd > $1.value.gd }
            return $0.value.gf > $1.value.gf
        }
        var ranking: [String: Int] = [:]
        for (idx, entry) in sorted.enumerated() { ranking[entry.key] = idx + 1 }
        return ranking
    }

    // MARK: - Poisson

    private static func poisson(_ k: Int, _ lambda: Double) -> Double {
        guard k > 0 else { return exp(-lambda) }
        var result = exp(-lambda)
        for i in 1...k {
            result *= lambda / Double(i)
        }
        return result
    }
}
