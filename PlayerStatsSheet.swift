import SwiftUI

// MARK: - Modelo de tabla (Partido / Media / Total)

private struct StatConcept: Identifiable {
    let id: String
    let label: String
    let matchText: String?   // valor en este partido (nil → sin dato)
    let mediaText: String?   // media por partido (nil → —)
    let totalText: String?   // total de temporada (nil → —)
}

private struct StatGroup: Identifiable {
    let id: String
    let title: String
    var concepts: [StatConcept]
}

// MARK: - PlayerStatsSheet

struct PlayerStatsSheet: View {
    let selection: PlayerSelection
    let season: AppSeason

    @Environment(\.dismiss) private var dismiss

    @State private var groups: [StatGroup] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var hasMatchData = false
    @State private var playerAge: Int? = nil
    @State private var playerPosition: String? = nil
    @State private var sofascoreID: Int? = nil
    @State private var marketValue: Int? = nil

    // Anchos fijos de las columnas de valores (para alinear cabecera y filas)
    private let colChip:  CGFloat = 58
    private let colMedia: CGFloat = 58
    private let colTotal: CGFloat = 68

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    playerHeader

                    if isLoading {
                        loadingView
                    } else if failed || groups.isEmpty {
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

    // MARK: - Tabla de estadísticas

    private var statsContent: some View {
        VStack(spacing: 0) {
            if hasMatchData { matchBanner }
            columnHeader
            ForEach(groups) { group in
                VStack(spacing: 2) {
                    groupHeader(group.title)
                    ForEach(group.concepts) { concept in
                        conceptRow(concept)
                    }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var matchBanner: some View {
        let m = selection.matchContext
        let teamName = selection.teamName ?? ""
        let isHome = teamName == m?.home
        let opponent = isHome ? (m?.away ?? "") : (m?.home ?? "")
        let hs = m?.homeScore ?? 0
        let as_ = m?.awayScore ?? 0
        let score = isHome ? "\(hs)-\(as_)" : "\(as_)-\(hs)"

        return HStack(spacing: 8) {
            Text("PARTIDO · J\(m?.jornada ?? 0)")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color(hex: 0x4A9EDF))
                .tracking(0.8)
            Spacer()
            Text("vs \(opponent)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
            TeamLogoView(teamName: opponent, size: 16)
            Text(score)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(hex: 0x0D0D1A))
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if hasMatchData {
                Text("PARTIDO")
                    .foregroundStyle(Color(hex: 0x4A9EDF))
                    .frame(width: colChip)
            }
            Text("MEDIA")
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: colMedia, alignment: .trailing)
            Text("TOTAL")
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: colTotal, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .heavy))
        .tracking(0.6)
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
    }

    private func groupHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color(hex: 0xE8460B))
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(hex: 0x0D0D1A))
    }

    private func conceptRow(_ c: StatConcept) -> some View {
        HStack(spacing: 0) {
            Text(c.label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasMatchData {
                matchChip(c.matchText).frame(width: colChip)
            }

            Text(c.mediaText ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(c.mediaText == nil ? .white.opacity(0.25) : .white.opacity(0.85))
                .frame(width: colMedia, alignment: .trailing)

            Text(c.totalText ?? "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(c.totalText == nil ? .white.opacity(0.25) : .white)
                .frame(width: colTotal, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0F0F1E)))
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func matchChip(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: 0x1B3A5C)))
        } else {
            Text("—")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.25))
        }
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

    // MARK: - Carga de datos

    private func loadStats() async {
        isLoading = true
        failed = false
        defer { isLoading = false }

        // 1. Resolver athleteID + edad desde el roster de ESPN
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

        // 2. Estadísticas de temporada (ESPN), datos SofaScore y stats por partido en paralelo
        async let statsTask = fetchStats(athleteID: id)
        async let sofaTask = searchSofaScore()
        async let sofaMatchTask = fetchSofaScoreMatchStats()

        let rawStats = await statsTask
        let (sfID, sfValue) = await sofaTask
        let sofaMatchRaw = await sofaMatchTask

        sofascoreID = sfID
        marketValue = sfValue

        // 3. Valoración media de temporada (SofaScore) — requiere el playerID
        var seasonRating: Double? = nil
        if let sfID { seasonRating = await fetchSeasonRating(playerID: sfID) }

        hasMatchData = (selection.matchContext?.done ?? false) && !sofaMatchRaw.isEmpty

        let built = buildGroups(season: rawStats, match: sofaMatchRaw, seasonRating: seasonRating)
        groups = built
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

    /// Valoración media de temporada del jugador en La Liga (SofaScore).
    private func fetchSeasonRating(playerID: Int) async -> Double? {
        guard let seasonID = SofaScoreService.seasonIDs[season.espnYear],
              let url = URL(string: "https://api.sofascore.com/api/v1/player/\(playerID)/unique-tournament/8/season/\(seasonID)/statistics/overall") else {
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = json["statistics"] as? [String: Any] else { return nil }

        if let r = stats["rating"] as? Double { return r }
        if let r = stats["rating"] as? Int { return Double(r) }
        return nil
    }

    /// Fetches raw season stats [name: value] from ESPN APIs
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

    // MARK: - Construcción de grupos (fusión partido + temporada)

    private func buildGroups(season seasonStats: [String: Double],
                             match: [String: Any],
                             seasonRating: Double?) -> [StatGroup] {
        let hasMatch = hasMatchData
        let apps = seasonStats["appearances"] ?? 0

        func sVal(_ keys: [String]) -> Double? {
            for k in keys { if let v = seasonStats[k] { return v } }
            return nil
        }
        func mVal(_ key: String) -> Double? {
            if let v = match[key] as? Double { return v }
            if let v = match[key] as? Int    { return Double(v) }
            return nil
        }

        // Concepto contable: chip (partido) + media (total/partidos) + total
        func count(_ id: String, _ label: String,
                   match mKey: String?, season sKeys: [String], media: Bool = true) -> StatConcept? {
            let m = mKey.flatMap { mVal($0) }
            let s = sVal(sKeys)
            let mHas = (m ?? 0) > 0
            let sHas = (s ?? 0) > 0
            guard mHas || sHas else { return nil }
            let matchText = (hasMatch && mHas) ? formatInt(m!) : nil
            let totalText = sHas ? grouped(Int(s!.rounded())) : nil
            var mediaText: String? = nil
            if media, sHas, apps > 0 { mediaText = formatMedia(s! / apps) }
            return StatConcept(id: id, label: label, matchText: matchText, mediaText: mediaText, totalText: totalText)
        }

        // % Pases: porcentaje del partido + porcentaje medio de temporada (sin total)
        func passPercent() -> StatConcept? {
            var matchPct: Double? = nil
            if let t = mVal("totalPass"), let a = mVal("accuratePass"), t > 0 {
                matchPct = a / t * 100
            }
            let sPct = sVal(["passPct"])
            let mHas = matchPct != nil
            let sHas = (sPct ?? 0) > 0
            guard mHas || sHas else { return nil }
            let matchText = (hasMatch && mHas) ? formatPct0(matchPct!) : nil
            let mediaText = sHas ? formatPct0(sPct!) : nil
            return StatConcept(id: "pcpases", label: "% Pases", matchText: matchText, mediaText: mediaText, totalText: nil)
        }

        // Valoración: nota del partido + media de temporada (sin total)
        func ratingConcept() -> StatConcept? {
            let m = mVal("rating")
            let mHas = (m ?? 0) > 0
            let sHas = (seasonRating ?? 0) > 0
            guard mHas || sHas else { return nil }
            let matchText = (hasMatch && mHas) ? String(format: "%.1f", m!) : nil
            let mediaText = sHas ? String(format: "%.1f", seasonRating!) : nil
            return StatConcept(id: "valoracion", label: "Valoración", matchText: matchText, mediaText: mediaText, totalText: nil)
        }

        // Dato decimal solo de partido (Km, goles evitados…)
        func matchDecimal(_ id: String, _ label: String, _ key: String) -> StatConcept? {
            guard hasMatch, let v = mVal(key), v > 0 else { return nil }
            return StatConcept(id: id, label: label, matchText: String(format: "%.1f", v), mediaText: nil, totalText: nil)
        }

        func group(_ id: String, _ title: String, _ items: [StatConcept?]) -> StatGroup? {
            let concepts = items.compactMap { $0 }
            return concepts.isEmpty ? nil : StatGroup(id: id, title: title, concepts: concepts)
        }

        let all: [StatGroup?] = [
            group("general", "General", [
                count("min", "Minutos", match: "minutesPlayed", season: ["minutes"]),
                ratingConcept(),
                count("part", "Partidos", match: nil, season: ["appearances"], media: false),
                count("tit", "Titular", match: nil, season: ["starts"], media: false),
            ]),
            group("ataque", "Ataque", [
                count("goles", "Goles", match: "goals", season: ["totalGoals"]),
                count("asist", "Asistencias", match: "goalAssist", season: ["goalAssists"]),
                count("disp", "Disparos", match: "totalShots", season: ["totalShots"]),
                count("apuerta", "A puerta", match: "onTargetScoringAttempt", season: ["shotsOnTarget"]),
                count("kpass", "Pases clave", match: "keyPass", season: [], media: false),
                count("bcc", "Ocas. claras", match: "bigChanceCreated", season: [], media: false),
            ]),
            group("pases", "Pases", [
                count("pases", "Pases", match: "totalPass", season: ["totalPasses"]),
                count("pasesok", "Pases exactos", match: "accuratePass", season: ["accuratePasses"]),
                passPercent(),
            ]),
            group("defensa", "Defensa", [
                count("entradas", "Entradas", match: "totalTackle", season: ["totalTackles"]),
                count("entef", "Entradas ef.", match: "wonTackle", season: [], media: false),
                count("inter", "Intercepciones", match: "interceptionWon", season: ["interceptions"]),
                count("despejes", "Despejes", match: "totalClearance", season: [], media: false),
                count("recup", "Recuperaciones", match: "ballRecovery", season: [], media: false),
                count("aereos", "Aéreos gd.", match: "aerialWon", season: [], media: false),
            ]),
            group("disciplina", "Disciplina", [
                count("faltas", "Faltas", match: "fouls", season: ["foulsCommitted"]),
                count("perdidas", "Pérdidas", match: "possessionLostCtrl", season: [], media: false),
                count("amarillas", "Amarillas", match: nil, season: ["yellowCards"], media: false),
                count("rojas", "Rojas", match: nil, season: ["redCards"], media: false),
            ]),
            group("fisico", "Físico", [
                matchDecimal("km", "Km recorridos", "kilometersCovered"),
                count("toques", "Toques", match: "touches", season: [], media: false),
            ]),
            group("portero", "Portero", [
                count("paradas", "Paradas", match: "saves", season: ["saves"]),
                count("pararea", "Paradas (área)", match: "savedShotsFromInsideTheBox", season: [], media: false),
                matchDecimal("gevit", "G. evitados", "goalsPrevented"),
                count("pimbatido", "P. imbatido", match: nil, season: ["cleanSheet"], media: false),
            ]),
        ]
        return all.compactMap { $0 }
    }

    // MARK: - Formateadores

    private func formatInt(_ v: Double) -> String { String(Int(v.rounded())) }

    /// Media por partido: entero si ≥ 10, un decimal si < 10.
    private func formatMedia(_ v: Double) -> String {
        v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    private func formatPct0(_ v: Double) -> String {
        let pct = v > 1 ? v : v * 100
        return String(format: "%.0f%%", pct)
    }

    /// Entero con separador de miles "." (1024 → "1.024").
    private func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
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
}
