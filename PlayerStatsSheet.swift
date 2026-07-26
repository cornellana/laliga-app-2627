import SwiftUI

// MARK: - Stat Item

private struct StatItem: Identifiable {
    let id: String
    let label: String
    let value: String
}

// MARK: - Stats Section

private struct StatsSection: Identifiable {
    let id: String
    let title: String
    var items: [StatItem]
}

// MARK: - PlayerStatsSheet

struct PlayerStatsSheet: View {
    let selection: PlayerSelection
    let season: AppSeason

    @Environment(\.dismiss) private var dismiss

    @State private var sections: [StatsSection] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var playerAge: Int? = nil
    @State private var playerPosition: String? = nil
    @State private var sofascoreID: Int? = nil
    @State private var marketValue: Int? = nil
    @State private var matchStats: [StatItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    playerHeader

                    if let matchCtx = selection.matchContext, matchCtx.done, !matchStats.isEmpty {
                        matchSectionView(matchCtx)
                    }

                    if isLoading {
                        loadingView
                    } else if failed || sections.isEmpty {
                        noDataView
                    } else {
                        statsContent
                    }
                    Spacer(minLength: 40)
                }
            }
            .background(Color(hex: 0x0A0A14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Estadísticas").font(.headline).foregroundStyle(.white)
                        Text("La Liga \(season.displayName)").font(.caption2).foregroundStyle(Color(hex: 0xE8460B))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(Color(hex: 0x004D98))
                }
            }
            .preferredColorScheme(.dark)
        }
        .task { await loadStats() }
    }

    // MARK: - Player header

    private var playerHeader: some View {
        HStack(spacing: 12) {
            playerPhoto

            VStack(alignment: .leading, spacing: 3) {
                Text(selection.playerName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let teamName = selection.teamName, !teamName.isEmpty {
                    Text(teamName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }

                // Posición en español (from selection or from roster lookup)
                let pos = positionInSpanish(selection.position ?? playerPosition ?? "")
                if !pos.isEmpty {
                    Text(pos)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }

                if let age = playerAge {
                    Text("\(age) años")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            Spacer()

            if let mv = marketValue {
                VStack(spacing: 2) {
                    Text("Valor")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(formatMarketValue(mv))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x1B8A4C))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: 0x1B8A4C).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: 0x0F0F1E))
    }

    private var playerPhoto: some View {
        Group {
            if let sid = sofascoreID,
               let url = URL(string: "https://api.sofascore.app/api/v1/player/\(sid)/image") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    } else {
                        photoFallback
                    }
                }
            } else {
                photoFallback
            }
        }
    }

    @ViewBuilder
    private var photoFallback: some View {
        if let teamName = selection.teamName, !teamName.isEmpty {
            ZStack {
                Circle().fill(Color.white.opacity(0.05)).frame(width: 56, height: 56)
                TeamLogoView(teamName: teamName, size: 32)
            }
        } else {
            Circle().fill(Color.white.opacity(0.05))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.25))
                )
        }
    }

    // MARK: - Stats content

    private var statsContent: some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                sectionView(section)
            }
        }
    }

    private func sectionView(_ section: StatsSection) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(section.title.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: 0xE8460B))
                    .tracking(0.8)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(hex: 0x0D0D1A))

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 6
            ) {
                ForEach(section.items) { item in
                    statCell(item: item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func statCell(item: StatItem) -> some View {
        VStack(spacing: 2) {
            Text(item.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            Text(item.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(hex: 0x0F0F1E))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Color(hex: 0x004D98)).scaleEffect(1.3)
            Text("Cargando estadísticas…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.2))
            Text("Estadísticas no disponibles")
                .foregroundStyle(.white.opacity(0.4))
                .font(.subheadline)
            Text("No se encontraron datos para este jugador en esta temporada")
                .foregroundStyle(.white.opacity(0.25))
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 50)
    }

    // MARK: - ESPN fetch logic

    private func loadStats() async {
        isLoading = true
        failed = false
        defer { isLoading = false }

        // 1. Resolve athlete ID + age from roster
        var athleteID = selection.athleteID

        if athleteID == nil || athleteID!.isEmpty {
            let basics = await resolveAthleteBasics()
            athleteID = basics?.id
            playerAge = basics?.age
            if playerPosition == nil { playerPosition = basics?.position }
        }

        guard let id = athleteID, !id.isEmpty else {
            failed = true
            return
        }

        // 2. Fetch season stats, SofaScore player data, and per-match stats concurrently
        async let statsTask = fetchStats(athleteID: id)
        async let sofaTask = searchSofaScore()
        async let sofaMatchTask = fetchSofaScoreMatchStats()

        let rawStats = await statsTask
        let (sfID, sfValue) = await sofaTask
        let sofaMatchRaw = await sofaMatchTask

        sofascoreID = sfID
        marketValue = sfValue

        let perMatchItems = buildMatchStatItems(from: sofaMatchRaw)
        if !perMatchItems.isEmpty {
            matchStats = perMatchItems
        }

        let built = buildSections(from: rawStats)
        sections = built
        if built.isEmpty { failed = true }
    }

    private struct AthleteBasics {
        let id: String
        let age: Int?
        let position: String?
    }

    private func resolveAthleteBasics() async -> AthleteBasics? {
        guard let teamName = selection.teamName,
              let teamID = MatchesData.espnTeamIDs[teamName] else { return nil }

        let base = "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams/\(teamID)/roster"
        let year = season.espnYear

        for suffix in ["", "?season=\(year)", "?season=\(year - 1)"] {
            guard let url = URL(string: base + suffix),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            if let basics = findAthleteBasics(in: data, playerName: selection.playerName) {
                return basics
            }
        }
        return nil
    }

    private func findAthleteBasics(in data: Data, playerName: String) -> AthleteBasics? {
        struct Resp: Decodable {
            let athletes: [Athlete]
            struct Athlete: Decodable {
                let id: String
                let displayName: String?
                let fullName: String?
                let age: Int?
                let position: Pos?
                struct Pos: Decodable { let abbreviation: String? }
            }
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return nil }
        let needle = playerName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        for athlete in resp.athletes {
            let name = (athlete.displayName ?? athlete.fullName ?? "")
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
            if name.contains(needle) || needle.contains(name) {
                return AthleteBasics(id: athlete.id, age: athlete.age, position: athlete.position?.abbreviation)
            }
        }
        return nil
    }

    // Convierte abreviatura ESPN a posición en español
    private func positionInSpanish(_ abbr: String) -> String {
        switch abbr.uppercased() {
        case "G", "GK", "PO", "GR":           return "Portero"
        case "D", "DF", "CB", "LB", "RB",
             "LWB", "RWB", "SW":              return "Defensa"
        case "M", "MF", "CM", "DM", "AM",
             "CDM", "CAM", "LM", "RM":        return "Centrocampista"
        case "F", "FW", "LW", "RW", "CF",
             "ST", "SS", "ATT":               return "Delantero"
        default:                               return ""
        }
    }

    private func searchSofaScore() async -> (Int?, Int?) {
        let name = selection.playerName
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.sofascore.com/api/v1/search/\(encoded)") else {
            return (nil, nil)
        }

        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return (nil, nil)
        }

        let needle = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let playerResults = results.filter { ($0["type"] as? String) == "player" }

        func nameMatches(_ result: [String: Any]) -> Bool {
            guard let entity = result["entity"] as? [String: Any],
                  let entityName = entity["name"] as? String else { return false }
            let eName = entityName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return eName.contains(needle) || needle.contains(eName)
        }

        // Prefer a result where both name and team match
        let best = playerResults.first { result in
            guard nameMatches(result),
                  let teamName = selection.teamName,
                  let entity = result["entity"] as? [String: Any],
                  let team = entity["team"] as? [String: Any],
                  let eTeam = team["name"] as? String else { return false }
            let t = teamName.prefix(4).lowercased()
            return eTeam.lowercased().contains(t)
        } ?? playerResults.first { nameMatches($0) }

        guard let entity = best?["entity"] as? [String: Any],
              let playerID = entity["id"] as? Int else {
            return (nil, nil)
        }

        // Fetch player detail for market value
        guard let detailURL = URL(string: "https://api.sofascore.com/api/v1/player/\(playerID)") else {
            return (playerID, nil)
        }

        var detailReq = URLRequest(url: detailURL)
        detailReq.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (detailData, detailResp) = try? await URLSession.shared.data(for: detailReq),
              (detailResp as? HTTPURLResponse)?.statusCode == 200,
              let detailJSON = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
              let playerObj = detailJSON["player"] as? [String: Any] else {
            return (playerID, nil)
        }

        let value = playerObj["proposedMarketValue"] as? Int
        return (playerID, value)
    }

    /// Fetches raw stats [name: value] from ESPN APIs
    private func fetchStats(athleteID: String) async -> [String: Double] {
        let year = season.espnYear
        // Only fetch stats for the requested season — no fallback to prior year
        // (prevents 26/27 from showing 25/26 data when season hasn't started)
        let urlStr = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/esp.1/seasons/\(year)/types/2/athletes/\(athleteID)/statistics/0"
        if let url = URL(string: urlStr),
           let (data, resp) = try? await URLSession.shared.data(from: url),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            return parseStatsSplits(from: data)
        }
        return [:]
    }

    private func parseStatsSplits(from data: Data) -> [String: Double] {
        struct Resp: Decodable {
            let splits: Splits?
            struct Splits: Decodable {
                let categories: [Category]?
            }
            struct Category: Decodable {
                let name: String?
                let stats: [Stat]?
            }
            struct Stat: Decodable {
                let name: String
                let value: Double
            }
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return [:] }
        var result: [String: Double] = [:]
        for cat in resp.splits?.categories ?? [] {
            for stat in cat.stats ?? [] {
                result[stat.name] = stat.value
            }
        }
        return result
    }

    // MARK: - Build display sections

    private func buildSections(from stats: [String: Double]) -> [StatsSection] {
        func val(_ keys: [String]) -> Double? {
            for k in keys { if let v = stats[k] { return v } }
            return nil
        }

        var general: [StatItem] = []
        var ataque: [StatItem] = []
        var pases: [StatItem] = []
        var defensa: [StatItem] = []
        var disciplina: [StatItem] = []

        // General — ESPN uses "appearances" and "minutes" (not minutesPlayed)
        if let v = val(["appearances"]), v > 0 {
            general.append(StatItem(id: "partidos", label: "Partidos", value: formatInt(v)))
        }
        if let v = val(["starts"]), v > 0 {
            general.append(StatItem(id: "titulares", label: "Titular", value: formatInt(v)))
        }
        if let v = val(["minutes"]), v > 0 {
            general.append(StatItem(id: "minutos", label: "Minutos", value: formatInt(v)))
        }

        // Ataque — ESPN uses "totalGoals", "goalAssists", "totalShots", "shotsOnTarget"
        if let v = val(["totalGoals"]), v > 0 {
            ataque.append(StatItem(id: "goles", label: "Goles", value: formatInt(v)))
        }
        if let v = val(["goalAssists"]), v > 0 {
            ataque.append(StatItem(id: "asistencias", label: "Asistencias", value: formatInt(v)))
        }
        if let v = val(["totalShots"]), v > 0 {
            ataque.append(StatItem(id: "disparos", label: "Disparos", value: formatInt(v)))
        }
        if let v = val(["shotsOnTarget"]), v > 0 {
            ataque.append(StatItem(id: "apuerta", label: "A puerta", value: formatInt(v)))
        }
        // Goalkeeper stats
        if let v = val(["saves"]), v > 0 {
            ataque.append(StatItem(id: "paradas", label: "Paradas", value: formatInt(v)))
        }
        if let v = val(["cleanSheet"]), v > 0 {
            ataque.append(StatItem(id: "pimbatido", label: "P. imbatido", value: formatInt(v)))
        }

        // Pases — ESPN uses "totalPasses", "accuratePasses", "passPct" (0–1 fraction)
        if let v = val(["totalPasses"]), v > 0 {
            pases.append(StatItem(id: "pases", label: "Pases", value: formatInt(v)))
        }
        if let v = val(["accuratePasses"]), v > 0 {
            pases.append(StatItem(id: "pasesok", label: "Pases exactos", value: formatInt(v)))
        }
        if let v = val(["passPct"]), v > 0 {
            pases.append(StatItem(id: "pcpases", label: "% Pases", value: formatPct(v)))
        }

        // Defensa
        if let v = val(["totalTackles"]), v > 0 {
            defensa.append(StatItem(id: "entradas", label: "Entradas", value: formatInt(v)))
        }
        if let v = val(["interceptions"]), v > 0 {
            defensa.append(StatItem(id: "intercepciones", label: "Intercepciones", value: formatInt(v)))
        }
        if let v = val(["foulsCommitted"]), v > 0 {
            defensa.append(StatItem(id: "faltas", label: "Faltas", value: formatInt(v)))
        }

        // Disciplina
        if let v = val(["yellowCards"]), v > 0 {
            disciplina.append(StatItem(id: "amarillas", label: "Amarillas", value: formatInt(v)))
        }
        if let v = val(["redCards"]), v > 0 {
            disciplina.append(StatItem(id: "rojas", label: "Rojas", value: formatInt(v)))
        }

        var result: [StatsSection] = []
        if !general.isEmpty    { result.append(StatsSection(id: "general",    title: "General",    items: general)) }
        if !ataque.isEmpty     { result.append(StatsSection(id: "ataque",     title: "Ataque",     items: ataque)) }
        if !pases.isEmpty      { result.append(StatsSection(id: "pases",      title: "Pases",      items: pases)) }
        if !defensa.isEmpty    { result.append(StatsSection(id: "defensa",    title: "Defensa",    items: defensa)) }
        if !disciplina.isEmpty { result.append(StatsSection(id: "disciplina", title: "Disciplina", items: disciplina)) }
        return result
    }

    private func formatInt(_ v: Double) -> String {
        String(Int(v))
    }

    private func formatPct(_ v: Double) -> String {
        // value may already be a percentage (e.g. 85.3) or a fraction (0.853)
        let pct = v > 1 ? v : v * 100
        return String(format: "%.1f%%", pct)
    }

    private func formatMarketValue(_ value: Int) -> String {
        if value >= 1_000_000 {
            let m = Double(value) / 1_000_000
            return m == floor(m) ? "\(Int(m))M€" : String(format: "%.1fM€", m)
        } else if value >= 1_000 {
            return "\(value / 1_000)K€"
        }
        return "\(value)€"
    }

    // MARK: - Match section

    private func matchSectionView(_ match: Match) -> some View {
        let teamName = selection.teamName ?? ""
        let isHome = teamName == match.home
        let isAway = teamName == match.away
        let opponent = isHome ? match.away : (isAway ? match.home : match.away)
        let hs = match.homeScore ?? 0
        let as_ = match.awayScore ?? 0
        let score = isHome ? "\(hs)-\(as_)" : "\(as_)-\(hs)"

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("ESTE PARTIDO")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x4A9EDF))
                    .tracking(0.8)
                Spacer()
                HStack(spacing: 5) {
                    Text("J\(match.jornada)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                    TeamLogoView(teamName: opponent, size: 15)
                    Text(score)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(hex: 0x0D0D1A))

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 6
            ) {
                ForEach(matchStats) { item in
                    statCell(item: item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    // MARK: - SofaScore per-match stats

    private func fetchSofaScoreMatchStats() async -> [String: Any] {
        guard let matchCtx = selection.matchContext, matchCtx.done else { return [:] }

        // 1+2. Resolve SofaScore eventID via shared service
        guard let sofaEventID = await SofaScoreService.resolveEventID(
            espnYear: season.espnYear,
            jornada: matchCtx.jornada,
            home: matchCtx.home,
            away: matchCtx.away
        ) else { return [:] }

        // 3. Fetch lineups with per-player stats
        var req2 = URLRequest(url: URL(string: "https://api.sofascore.com/api/v1/event/\(sofaEventID)/lineups")!)
        req2.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (lineupsData, lineupsResp) = try? await URLSession.shared.data(for: req2),
              (lineupsResp as? HTTPURLResponse)?.statusCode == 200,
              let lineupsJSON = try? JSONSerialization.jsonObject(with: lineupsData) as? [String: Any] else { return [:] }

        // 4. Find player in home or away lineup (fuzzy name match)
        let needle = selection.playerName
            .folding(options: .diacriticInsensitive, locale: .current).lowercased()

        func findStats(in side: [String: Any]?) -> [String: Any]? {
            guard let players = side?["players"] as? [[String: Any]] else { return nil }
            return players.first { p in
                let name = (p["player"] as? [String: Any])?["name"] as? String ?? ""
                let norm = name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                return norm.contains(needle) || needle.contains(norm)
            }.flatMap { $0["statistics"] as? [String: Any] }
        }

        return findStats(in: lineupsJSON["home"] as? [String: Any])
            ?? findStats(in: lineupsJSON["away"] as? [String: Any])
            ?? [:]
    }

    private func buildMatchStatItems(from stats: [String: Any]) -> [StatItem] {
        guard !stats.isEmpty else { return [] }

        func num(_ key: String) -> Double? {
            if let v = stats[key] as? Double { return v }
            if let v = stats[key] as? Int    { return Double(v) }
            return nil
        }

        var items: [StatItem] = []

        // Tiempo y valoración
        if let v = num("minutesPlayed"),  v > 0 { items.append(StatItem(id: "m_min",      label: "Minutos",        value: formatInt(v))) }
        if let v = num("rating"),         v > 0 { items.append(StatItem(id: "m_rating",   label: "Valoración",     value: String(format: "%.1f", v))) }

        // Ataque
        if let v = num("goalAssist"),              v > 0 { items.append(StatItem(id: "m_asist",    label: "Asistencias",    value: formatInt(v))) }
        if let v = num("keyPass"),                 v > 0 { items.append(StatItem(id: "m_kpass",    label: "Pases clave",    value: formatInt(v))) }
        if let v = num("bigChanceCreated"),        v > 0 { items.append(StatItem(id: "m_bcc",      label: "Ocast. clave",   value: formatInt(v))) }
        if let v = num("totalShots"),              v > 0 { items.append(StatItem(id: "m_disparos", label: "Chutes",         value: formatInt(v))) }
        if let v = num("onTargetScoringAttempt"),  v > 0 { items.append(StatItem(id: "m_apuerta",  label: "A puerta",       value: formatInt(v))) }

        // Pases
        if let v = num("totalPass"),  v > 0 { items.append(StatItem(id: "m_pases",   label: "Pases",          value: formatInt(v))) }
        if let v = num("accuratePass"), v > 0 { items.append(StatItem(id: "m_pasesok", label: "Pases exactos",  value: formatInt(v))) }
        if let total = num("totalPass"), let acc = num("accuratePass"), total > 0 {
            items.append(StatItem(id: "m_pcpases", label: "% Pases", value: String(format: "%.0f%%", acc / total * 100)))
        }

        // Defensa
        if let v = num("totalTackle"),    v > 0 { items.append(StatItem(id: "m_entradas",  label: "Entradas",       value: formatInt(v))) }
        if let v = num("wonTackle"),      v > 0 { items.append(StatItem(id: "m_entef",     label: "Entradas ef.",   value: formatInt(v))) }
        if let v = num("interceptionWon"),v > 0 { items.append(StatItem(id: "m_inter",     label: "Intercepciones", value: formatInt(v))) }
        if let v = num("totalClearance"), v > 0 { items.append(StatItem(id: "m_despejes",  label: "Despejes",       value: formatInt(v))) }
        if let v = num("ballRecovery"),   v > 0 { items.append(StatItem(id: "m_recup",     label: "Recuperaciones", value: formatInt(v))) }

        // Duelos
        let duelW = num("duelWon") ?? 0
        let duelL = num("duelLost") ?? 0
        if duelW + duelL > 0 {
            items.append(StatItem(id: "m_duelos", label: "Duelos", value: "\(Int(duelW))/\(Int(duelW + duelL))"))
        }
        if let v = num("aerialWon"),  v > 0 { items.append(StatItem(id: "m_aereos",  label: "Aéreos gd.",     value: formatInt(v))) }

        // Faltas y pérdidas
        if let v = num("fouls"),              v > 0 { items.append(StatItem(id: "m_faltas",  label: "Faltas",         value: formatInt(v))) }
        if let v = num("possessionLostCtrl"), v > 0 { items.append(StatItem(id: "m_perdidas",label: "Pérdidas",       value: formatInt(v))) }
        if let v = num("touches"),            v > 0 { items.append(StatItem(id: "m_toques",  label: "Toques",         value: formatInt(v))) }

        // Físico
        if let v = num("kilometersCovered"), v > 0 {
            items.append(StatItem(id: "m_km", label: "Km recorridos", value: String(format: "%.1f", v)))
        }

        // Portero
        if let v = num("saves"),                      v > 0 { items.append(StatItem(id: "m_paradas",  label: "Paradas",        value: formatInt(v))) }
        if let v = num("savedShotsFromInsideTheBox"), v > 0 { items.append(StatItem(id: "m_paradarea",label: "Paradas (área)",  value: formatInt(v))) }
        if let v = num("goalsPrevented"),             v > 0 { items.append(StatItem(id: "m_gevit",    label: "G. evitados",    value: String(format: "%.1f", v))) }

        return items
    }
}
