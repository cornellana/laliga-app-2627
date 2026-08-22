import SwiftUI
import Charts

// MARK: - Roster model

struct RosterPlayer: Identifiable {
    let id: String
    let name: String
    let jersey: Int?
    let position: String?
    let positionGroup: String
}

// MARK: - MatchDetailSheet (wrapper con swipe entre partidos)

struct MatchDetailSheet: View {
    let allMatches: [Match]
    let season: AppSeason
    let matchDays: [MatchDay]
    @State private var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss

    init(match: Match, season: AppSeason, allMatches: [Match] = [], matchDays: [MatchDay] = []) {
        let matches = allMatches.isEmpty ? [match] : allMatches
        self.allMatches = matches
        self.season = season
        self.matchDays = matchDays
        _selectedIndex = State(initialValue: matches.firstIndex(where: { $0.id == match.id }) ?? 0)
    }

    private var currentMatch: Match {
        guard selectedIndex >= 0, selectedIndex < allMatches.count else { return allMatches[0] }
        return allMatches[selectedIndex]
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(allMatches.enumerated()), id: \.offset) { idx, match in
                    MatchDetailPage(match: match, season: season, matchDays: matchDays)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color(hex: 0x0A0A14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Color(hex: 0x004D98))
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text("Jornada \(currentMatch.jornada)")
                            .font(.headline)
                            .foregroundStyle(.white)
                        if allMatches.count > 1 {
                            Image(systemName: "chevron.left.chevron.right")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - MatchDetailPage (una página por partido)

private struct MatchDetailPage: View {
    let match: Match
    let season: AppSeason
    let matchDays: [MatchDay]
    @Environment(HighlightSettings.self) private var highlights

    @State private var fetchedDetails: MatchDetails? = nil
    @State private var isFetchingDetails = false
    @State private var homeRoster: [RosterPlayer] = []
    @State private var awayRoster:  [RosterPlayer] = []
    @State private var isLoadingRoster = false
    @State private var momentum: [MomentumPoint]? = nil
    @State private var isFetchingMomentum = false
    @State private var selectedPlayer: PlayerSelection? = nil
    @State private var showPredictionDetail = false
    /// Pronóstico para partidos aún no jugados; se calcula una vez en `.task`.
    @State private var prediction: MatchPrediction? = nil

    private var effectiveDetails: MatchDetails? { match.details ?? fetchedDetails }

    /// Tramo de tres minutos del reloj, o -1 si el partido no está en juego.
    /// Sirve de identidad al refresco del momentum.
    private var momentumTick: Int {
        guard match.isLive, let reloj = match.clock else { return -1 }
        let digitos = reloj.prefix { $0.isNumber }
        guard let minuto = Int(digitos) else { return -1 }
        return minuto / 3
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                scoreHeader

                if let prediction, showPredictionDetail {
                    predictionDetail(prediction)
                }

                Divider().background(Color.white.opacity(0.08))

                if let pts = momentum, !pts.isEmpty {
                    momentumSection(pts)
                    Divider().background(Color.white.opacity(0.08))
                }

                if let details = effectiveDetails {
                    if let events = details.events, !events.isEmpty {
                        eventsList(events, matchCtx: match)
                        Divider().background(Color.white.opacity(0.08))
                    }
                    if let home = details.homeLineup, let away = details.awayLineup {
                        lineupSection(home: home, away: away, matchCtx: match)
                    }
                } else if match.done {
                    completedNoDetailsSection
                } else {
                    rosterSection
                }

                Spacer(minLength: 40)
            }
        }
        .background(Color(hex: 0x0A0A14))
        .task {
            if !match.done, !match.isLive, prediction == nil {
                let m = match, days = matchDays, s = season
                prediction = PredictionEngine.predict(match: m, matchDays: days, season: s)
            }
            if match.done, match.details == nil {
                await fetchMatchDetails()
            } else if !match.done, match.details == nil {
                await loadRosters()
            }
            if match.done || match.isLive {
                await loadMomentum()
            }
        }
        .task(id: momentumTick) {
            // Solo con el partido en juego: la clave cambia cada tres minutos
            // de reloj, así que SofaScore recibe una petición cada tres
            // minutos y no una por cada refresco de la lista.
            guard match.isLive, momentumTick >= 0 else { return }
            await loadMomentum()
        }
        .sheet(item: $selectedPlayer) { sel in
            PlayerStatsSheet(selection: sel, season: season)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                teamColumn(name: match.home, isHome: true)

                VStack(spacing: 6) {
                    // El marcador manda en cuanto hay partido: terminado o en
                    // juego. La hora del saque solo tiene sentido antes.
                    if let result = match.result, match.done || match.isLive {
                        Text(result)
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                    } else {
                        VStack(spacing: 2) {
                            Text(match.time.isEmpty ? "TBD" : match.time)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Text("hora Madrid")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    if match.done {
                        Text("Finalizado")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    } else if let live = match.liveLabel {
                        // Mismo verde y mismo punto que la fila de la lista.
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: 0x30D158))
                                .frame(width: 6, height: 6)
                            Text(live)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x30D158))
                                .monospacedDigit()
                        }
                    }
                }
                .frame(width: 130)

                teamColumn(name: match.away, isHome: false)
            }
            .padding(.top, 20)
            .padding(.horizontal, 12)

            if let prediction {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showPredictionDetail.toggle() }
                } label: {
                    PredictionBar(
                        prediction: prediction,
                        homeColor: highlights.highlight(for: match.home)?.color ?? Color(hex: 0x004D98),
                        awayColor: highlights.highlight(for: match.away)?.color ?? Color(hex: 0xE8460B),
                        isExpanded: showPredictionDetail
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }

            HStack(spacing: 16) {
                if let stadium = match.stadium {
                    Label(
                        "\(stadium)\(match.venueCity.map { ", \($0)" } ?? "")",
                        systemImage: "mappin.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                }
                if let tv = match.tv {
                    TVBadge(channel: tv)
                }
            }
            .padding(.vertical, 14)
        }
        .background(scoreHeaderBackground)
    }

    private var scoreHeaderBackground: LinearGradient {
        let homeHL = highlights.highlight(for: match.home)
        let awayHL = highlights.highlight(for: match.away)
        if let h = homeHL ?? awayHL {
            return LinearGradient(
                stops: [.init(color: h.color.opacity(0.22), location: 0),
                        .init(color: h.color.opacity(0.08), location: 1)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [Color(hex: 0x0F0F1E)], startPoint: .top, endPoint: .bottom)
    }

    private func teamColumn(name: String, isHome: Bool) -> some View {
        let hl = highlights.highlight(for: name)
        let isWinner: Bool? = match.done
            ? (isHome ? (match.homeScore ?? 0) > (match.awayScore ?? 0)
                      : (match.awayScore ?? 0) > (match.homeScore ?? 0))
            : nil

        return VStack(spacing: 10) {
            TeamLogoView(teamName: name, size: 72)
                .shadow(color: hl.map { $0.color.opacity(0.5) } ?? .clear, radius: 12)
                .opacity(isWinner == false ? 0.55 : 1.0)

            Text(name)
                .font(.system(size: 13, weight: hl != nil ? .bold : .medium))
                .foregroundStyle(hl?.color ?? .white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Prediction detail

    private func predictionDetail(_ prediction: MatchPrediction) -> some View {
        let homeColor = highlights.highlight(for: match.home)?.color ?? Color(hex: 0x004D98)
        let awayColor = highlights.highlight(for: match.away)?.color ?? Color(hex: 0xE8460B)
        return VStack(spacing: 0) {
            sectionHeader("Pronóstico")
            VStack(spacing: 0) {
                HStack {
                    Text(match.home)
                        .foregroundStyle(homeColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("vs")
                        .foregroundStyle(.white.opacity(0.3))
                    Text(match.away)
                        .foregroundStyle(awayColor)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .padding(.bottom, 8)

                ForEach(prediction.factors) { factor in
                    HStack(spacing: 8) {
                        Text(factor.homeValue)
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(factor.label)
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 130)
                        Text(factor.awayValue)
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .padding(.vertical, 5)
                    if factor.id != prediction.factors.last?.id {
                        Divider().background(Color.white.opacity(0.04))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Text("Estimación estadística basada en resultados de la temporada y anteriores.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .background(Color(hex: 0x0A0A14))
    }

    // MARK: - Events

    private func eventsList(_ events: [MatchEvent], matchCtx: Match) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Eventos del partido")
            ForEach(events) { event in
                EventRow(event: event, homeTeam: match.home, matchContext: matchCtx, onSelectPlayer: { sel in
                    selectedPlayer = PlayerSelection(
                        playerName: sel.playerName,
                        teamName: sel.teamName,
                        athleteID: sel.athleteID,
                        matchContext: sel.matchContext,
                        matchDetails: effectiveDetails
                    )
                })
                Divider().background(Color.white.opacity(0.04)).padding(.leading, 16)
            }
        }
    }

    // MARK: - Lineups

    private func lineupSection(home: TeamLineup, away: TeamLineup, matchCtx: Match) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Alineaciones")
            HStack(alignment: .top, spacing: 0) {
                LineupColumn(lineup: home, team: match.home, matchContext: matchCtx, onSelectPlayer: { sel in
                    selectedPlayer = PlayerSelection(
                        playerName: sel.playerName,
                        teamName: sel.teamName,
                        athleteID: sel.athleteID,
                        matchContext: sel.matchContext,
                        matchDetails: effectiveDetails,
                        position: sel.position
                    )
                })
                Divider().background(Color.white.opacity(0.06))
                LineupColumn(lineup: away, team: match.away, matchContext: matchCtx, onSelectPlayer: { sel in
                    selectedPlayer = PlayerSelection(
                        playerName: sel.playerName,
                        teamName: sel.teamName,
                        athleteID: sel.athleteID,
                        matchContext: sel.matchContext,
                        matchDetails: effectiveDetails,
                        position: sel.position
                    )
                })
            }
        }
    }

    // MARK: - Completed without details

    @ViewBuilder
    private var completedNoDetailsSection: some View {
        if isFetchingDetails {
            VStack(spacing: 14) {
                ProgressView().tint(Color(hex: 0x004D98)).scaleEffect(1.3)
                Text("Cargando detalles…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.15))
                    .padding(.top, 24)
                Text("Detalles no disponibles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                Text("No se pudieron cargar los detalles de este partido")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Roster (partidos pendientes)

    @ViewBuilder
    private var rosterSection: some View {
        if isLoadingRoster {
            VStack(spacing: 14) {
                ProgressView().tint(Color(hex: 0x004D98)).scaleEffect(1.3)
                Text("Cargando plantillas…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else if homeRoster.isEmpty && awayRoster.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white.opacity(0.15))
                    .padding(.top, 24)
                Text("Plantillas no disponibles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Los detalles aparecerán cuando comience el partido")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        } else {
            VStack(spacing: 0) {
                sectionHeader("Plantillas")
                HStack(alignment: .top, spacing: 0) {
                    RosterColumn(players: homeRoster, team: match.home, onSelectPlayer: { sel in
                        selectedPlayer = sel
                    })
                    Divider().background(Color.white.opacity(0.06))
                    RosterColumn(players: awayRoster, team: match.away, onSelectPlayer: { sel in
                        selectedPlayer = sel
                    })
                }
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: 0xE8460B))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0x0D0D1A))
    }

    // MARK: - Momentum

    private func loadMomentum() async {
        isFetchingMomentum = true
        defer { isFetchingMomentum = false }
        if let eventID = await SofaScoreService.resolveEventID(
            espnYear: season.espnYear,
            jornada: match.jornada,
            home: match.home,
            away: match.away
        ) {
            momentum = await SofaScoreService.fetchMomentum(eventID: eventID)
        }
    }

    /// Colores de las dos mitades del gráfico.
    ///
    /// Antes salía todo del mismo color cuando el color destacado que tenías
    /// puesto para un equipo coincidía con el naranja por defecto del otro:
    /// en el Espanyol-Real Madrid las dos mitades eran naranjas y no se
    /// distinguía quién apretaba. Ahora manda el color de cada club y, si aun
    /// así quedaran parecidos, el visitante cae a un gris azulado.
    private var momentumColors: (Color, Color) {
        let local = highlights.highlight(for: match.home)?.color
            ?? TeamLogoView.teamColor(for: match.home)
        var visitante = highlights.highlight(for: match.away)?.color
            ?? TeamLogoView.teamColor(for: match.away)
        if seParecen(local, visitante) {
            visitante = Color(hex: 0x4A5568)
        }
        return (local, visitante)
    }

    /// ¿Dos colores quedan tan cerca que el gráfico parecería de un solo tono?
    private func seParecen(_ a: Color, _ b: Color) -> Bool {
        let ca = UIColor(a).cgColor.components ?? []
        let cb = UIColor(b).cgColor.components ?? []
        guard ca.count >= 3, cb.count >= 3 else { return false }
        let distancia = (0..<3).reduce(0.0) { $0 + abs(Double(ca[$1] - cb[$1])) }
        return distancia < 0.45
    }

    /// Un gol situado en el gráfico: minuto y lado.
    private struct GoalMark: Identifiable {
        let id: String
        /// Posición en el eje: minuto + descuento, con un pequeño desplazamiento
        /// si varios goles caen en el mismo punto.
        let x: Double
        let isHome: Bool
        let isOwnGoal: Bool
    }

    /// Goles del partido, sacados de los eventos que ya tiene la ficha. Los
    /// goles en propia meta se pintan del lado del equipo que se apunta el
    /// tanto, no del que lo mete, que es como se leen en un marcador.
    private var goalMarks: [GoalMark] {
        guard let eventos = effectiveDetails?.events else { return [] }
        let goles = eventos.filter {
            $0.type == .goal || $0.type == .penalty || $0.type == .ownGoal
        }
        // El balón es una indicación, no una medida: el minuto exacto está en la
        // lista de eventos justo debajo. Así que se le permite desplazarse lo
        // necesario para que dos goles seguidos no se tapen. Con el ancho del
        // gráfico, un minuto son unos nueve píxeles y el balón mide veintidós:
        // el Racing-Villarreal, con goles en el 45 y el 45+1, enseñaba uno solo.
        let separacionMinima = 3.5

        // Último punto ocupado en cada lado: los de arriba y los de abajo no se
        // estorban entre sí.
        var ultimoArriba = -Double.infinity
        var ultimoAbajo  = -Double.infinity

        return goles
            .map { ev -> (MatchEvent, Double, Bool) in
                // El descuento cuenta: un gol en el 90+4 va en el 94, no en el
                // 90. Sin esto, los dos del Alavés-Getafe caían encima del 90 y
                // además fuera del eje, que acaba en el 90,5.
                let punto = Double(ev.minute + (ev.extraTime ?? 0))
                let deLocal = (ev.teamName == match.home)
                let aFavorDelLocal = (ev.type == .ownGoal) ? !deLocal : deLocal
                return (ev, punto, aFavorDelLocal)
            }
            .sorted { $0.1 < $1.1 }
            .map { ev, punto, arriba in
                var x = punto
                if arriba {
                    x = max(x, ultimoArriba + separacionMinima)
                    ultimoArriba = x
                } else {
                    x = max(x, ultimoAbajo + separacionMinima)
                    ultimoAbajo = x
                }
                return GoalMark(id: ev.id, x: x,
                                isHome: arriba, isOwnGoal: ev.type == .ownGoal)
            }
    }

    @ViewBuilder
    private func momentumSection(_ points: [MomentumPoint]) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Momentum del partido")

            VStack(spacing: 4) {
                Text(match.home)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(highlights.highlight(for: match.home)?.color ?? Color.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let (homeColor, awayColor) = momentumColors
                let maxVal = points.map { abs($0.value) }.max() ?? 1.0
                // El eje es siempre el partido entero y se va rellenando, en vez
                // de encogerse al minuto actual: con el dominio ajustado a los
                // datos, en el minuto 13 las barras ocupaban toda la pantalla y
                // se iban compactando según avanzaba el partido.
                // Solo se estira más allá del 90 si hay algo que pintar ahí,
                // como un gol en el descuento.
                let maxMin = max(90,
                                 max(Double(points.map(\.minute).max() ?? 90),
                                     goalMarks.map(\.x).max() ?? 90))

                Chart {
                    ForEach(points) { p in
                        BarMark(
                            x: .value("min", p.minute),
                            y: .value("presión", p.value)
                        )
                        .foregroundStyle(p.value >= 0 ? homeColor : awayColor)
                    }

                    RuleMark(y: .value("", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.white.opacity(0.18))

                    // Los goles, arriba los del local y abajo los del visitante,
                    // como en las gráficas de momentum al uso: el gráfico mide
                    // presión, y el gol es el hito que la explica.
                    ForEach(goalMarks) { gol in
                        PointMark(
                            x: .value("min", gol.x),
                            y: .value("presión", gol.isHome ? maxVal : -maxVal)
                        )
                        .symbolSize(0)
                        .annotation(position: gol.isHome ? .top : .bottom, spacing: 1) {
                            Text("⚽")
                                .font(.system(size: 11))
                                // En propia meta: balón apagado con aro rojo.
                                // Está del lado de quien se apunta el tanto,
                                // así que sin distintivo parecería suyo.
                                .saturation(gol.isOwnGoal ? 0 : 1)
                                .overlay {
                                    if gol.isOwnGoal {
                                        Circle()
                                            .stroke(Color(hex: 0xE8460B), lineWidth: 1.5)
                                            .frame(width: 15, height: 15)
                                    }
                                }
                        }
                    }
                }
                .chartYScale(domain: -maxVal ... maxVal)
                .chartXScale(domain: 0 ... (maxMin + 1.5))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: [15, 30, 45, 60, 75, 90]) { val in
                        AxisValueLabel {
                            if let m = val.as(Int.self) {
                                Text("\(m)'")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.white.opacity(0.08))
                    }
                }
                .frame(height: 130)
                .padding(.vertical, 9)   // sitio para los iconos de gol

                Text(match.away)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(highlights.highlight(for: match.away)?.color ?? Color.white.opacity(0.55))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - On-demand detail fetch

    private func fetchMatchDetails() async {
        guard let espnID = match.espnEventID else { return }
        isFetchingDetails = true
        defer { isFetchingDetails = false }

        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/summary?event=\(espnID)"),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return }

        fetchedDetails = parseSummary(from: data)
    }

    private func parseSummary(from data: Data) -> MatchDetails? {
        struct Resp: Decodable {
            let rosters: [ESPNRoster]?
            let keyEvents: [ESPNKeyEvent]?

            struct ESPNRoster: Decodable {
                let homeAway: String
                let team: Team
                let roster: [Player]
                let formation: String?
                struct Team: Decodable { let displayName: String }
                struct Player: Decodable {
                    let athlete: Athlete
                    let jersey: String?
                    let position: Pos?
                    let starter: Bool
                    struct Athlete: Decodable {
                        let id: String
                        let displayName: String?
                        let fullName: String?
                    }
                    struct Pos: Decodable { let abbreviation: String? }
                }
            }

            struct ESPNKeyEvent: Decodable {
                let id: String
                let type: EventType
                let clock: Clock?
                let text: String?
                let team: TeamRef?
                let scoringPlay: Bool?
                struct EventType: Decodable { let id: String; let text: String? }
                struct Clock: Decodable { let displayValue: String? }
                struct TeamRef: Decodable { let displayName: String? }
            }
        }

        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return nil }

        var homeLineup: TeamLineup? = nil
        var awayLineup: TeamLineup? = nil

        for roster in resp.rosters ?? [] {
            let players: [LineupPlayer] = roster.roster.compactMap { p in
                let name = p.athlete.displayName ?? p.athlete.fullName ?? ""
                guard !name.isEmpty else { return nil }
                return LineupPlayer(
                    id: p.athlete.id,
                    jersey: p.jersey.flatMap(Int.init),
                    name: name,
                    position: p.position?.abbreviation,
                    isStarter: p.starter,
                    events: nil
                )
            }
            let lineup = TeamLineup(formation: roster.formation, players: players)
            if roster.homeAway == "home" { homeLineup = lineup }
            else { awayLineup = lineup }
        }

        let nonGoalTypeIDs: Set<String> = ["76", "94", "95", "96"]
        var events: [MatchEvent] = []

        for (idx, event) in (resp.keyEvents ?? []).enumerated() {
            let typeID = event.type.id
            let isGoal = event.scoringPlay == true
            guard isGoal || nonGoalTypeIDs.contains(typeID) else { continue }

            let clockStr = event.clock?.displayValue ?? ""
            let clean = clockStr.replacingOccurrences(of: "'", with: "")
            let minute: Int
            let extraTime: Int?
            if let plusIdx = clean.firstIndex(of: "+") {
                minute = Int(String(clean[clean.startIndex..<plusIdx])) ?? 0
                extraTime = Int(String(clean[clean.index(after: plusIdx)...])) ?? nil
            } else {
                minute = Int(clean) ?? 0
                extraTime = nil
            }

            let eventType: MatchEventType
            if isGoal {
                let text = event.text?.lowercased() ?? ""
                if typeID == "97" || text.hasPrefix("own goal") {
                    eventType = .ownGoal
                } else if typeID == "98" {
                    eventType = .penalty
                } else {
                    eventType = .goal
                }
            } else {
                switch typeID {
                case "76": eventType = .substitution
                case "94": eventType = .yellowCard
                case "95", "96": eventType = .redCard
                default: continue
                }
            }

            let playerName = extractPlayer(from: event.text, type: typeID)
            let rawTeamFromText: String? = teamFromText(event.text, typeID: typeID)
            let resolvedTeam = resolveTeam(rawTeamFromText ?? event.team?.displayName)

            let shortText: String?
            if typeID == "76", let raw = event.text {
                let parts = raw.components(separatedBy: ". ")
                if parts.count > 1 {
                    let sub = parts[1].components(separatedBy: " replaces ")
                    shortText = sub.count > 1
                        ? sub[1].trimmingCharacters(in: .punctuationCharacters).trimmingCharacters(in: .whitespaces)
                        : nil
                } else { shortText = nil }
            } else {
                shortText = nil
            }

            events.append(MatchEvent(
                id: "\(event.id)_\(idx)",
                type: eventType,
                minute: minute,
                extraTime: extraTime,
                playerName: playerName,
                teamName: resolvedTeam,
                text: shortText
            ))
        }

        return MatchDetails(
            homeLineup: homeLineup,
            awayLineup: awayLineup,
            events: events.isEmpty ? nil : events
        )
    }

    private func teamFromText(_ text: String?, typeID: String) -> String? {
        guard let text else { return nil }
        switch typeID {
        case "76":
            if text.hasPrefix("Substitution, ") {
                let after = text.dropFirst("Substitution, ".count)
                if let first = after.components(separatedBy: ". ").first { return first }
            }
        case "94", "95", "96":
            if let open = text.firstIndex(of: "("), let close = text.firstIndex(of: ")") {
                return String(text[text.index(after: open)..<close])
            }
        default: break
        }
        return nil
    }

    private func resolveTeam(_ espnName: String?) -> String? {
        guard let name = espnName, !name.isEmpty else { return nil }
        func fold(_ s: String) -> String {
            s.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        }
        let n = fold(name), h = fold(match.home), a = fold(match.away)
        if h == n || h.contains(n) || n.contains(h) { return match.home }
        if a == n || a.contains(n) || n.contains(a) { return match.away }
        return name
    }

    private func extractPlayer(from text: String?, type typeID: String) -> String? {
        guard let text else { return nil }
        switch typeID {
        case "97":
            let lower = text.lowercased()
            if lower.hasPrefix("own goal by ") {
                let after = text.dropFirst("Own Goal by ".count)
                if let comma = after.firstIndex(of: ",") {
                    return String(after[after.startIndex..<comma]).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        case "76":
            let parts = text.components(separatedBy: ". ")
            if parts.count > 1 {
                let subParts = parts[1].components(separatedBy: " replaces ")
                return subParts.first?.trimmingCharacters(in: .whitespaces)
            }
            return nil
        case "94", "95", "96":
            if let idx = text.firstIndex(of: "(") {
                let name = String(text[text.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { return name }
            }
            return nil
        default:
            let parts = text.components(separatedBy: ". ")
            if parts.count > 1 {
                let afterScore = parts[1...].joined(separator: ". ")
                if let idx = afterScore.firstIndex(of: "(") {
                    return String(afterScore[afterScore.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }
    }

    // MARK: - Roster fetch

    private func loadRosters() async {
        isLoadingRoster = true
        defer { isLoadingRoster = false }
        async let home = fetchRoster(for: match.home)
        async let away = fetchRoster(for: match.away)
        (homeRoster, awayRoster) = await (home, away)
    }

    private func fetchRoster(for team: String) async -> [RosterPlayer] {
        guard let id = MatchesData.espnTeamIDs[team] else { return [] }
        let base = "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/teams/\(id)/roster"
        let year = Calendar.current.component(.year, from: Date())

        for suffix in ["", "?season=\(year)", "?season=\(year - 1)"] {
            guard let url = URL(string: base + suffix),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { continue }
            let players = parseRoster(from: data)
            if players.count >= 10 { return players }
        }
        return []
    }

    private func parseRoster(from data: Data) -> [RosterPlayer] {
        struct Resp: Decodable {
            let athletes: [Athlete]
            struct Athlete: Decodable {
                let id: String
                let displayName: String?
                let fullName: String?
                let jersey: String?
                let position: Pos?
                struct Pos: Decodable { let abbreviation: String? }
            }
        }
        guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else { return [] }

        let groupMap: [String: String] = [
            "G": "Porteros", "GK": "Porteros",
            "D": "Defensas", "DF": "Defensas",
            "M": "Centrocampistas", "MF": "Centrocampistas",
            "F": "Delanteros", "FW": "Delanteros",
        ]

        return resp.athletes.compactMap { a in
            let name = a.displayName ?? a.fullName ?? ""
            guard !name.isEmpty else { return nil }
            let abbr = a.position?.abbreviation ?? ""
            return RosterPlayer(
                id: a.id,
                name: name,
                jersey: a.jersey.flatMap(Int.init),
                position: abbr.isEmpty ? nil : abbr,
                positionGroup: groupMap[abbr] ?? "Otros"
            )
        }
    }
}

// MARK: - Roster Column

struct RosterColumn: View {
    let players: [RosterPlayer]
    let team: String
    var onSelectPlayer: ((PlayerSelection) -> Void)? = nil
    @Environment(HighlightSettings.self) private var highlights

    private var groups: [(String, [RosterPlayer])] {
        let order = ["Porteros", "Defensas", "Centrocampistas", "Delanteros"]
        let dict = Dictionary(grouping: players, by: \.positionGroup)
        let knownOrder = order.compactMap { key -> (String, [RosterPlayer])? in
            guard let v = dict[key] else { return nil }
            return (key, v.sorted { ($0.jersey ?? 99) < ($1.jersey ?? 99) })
        }
        let knownKeys = Set(order)
        let unknown = dict.filter { !knownKeys.contains($0.key) }
            .map { ($0.key, $0.value.sorted { ($0.jersey ?? 99) < ($1.jersey ?? 99) }) }
        return knownOrder + unknown
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TeamLogoView(teamName: team, size: 26)
                Text(team)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(highlights.highlight(for: team)?.color ?? .white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(hex: 0x0D0D1A))

            ForEach(groups, id: \.0) { groupName, groupPlayers in
                Text(groupName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)

                ForEach(groupPlayers) { player in
                    Button(action: {
                        let sel = PlayerSelection(
                            playerName: player.name,
                            teamName: team,
                            athleteID: player.id,
                            position: player.position
                        )
                        onSelectPlayer?(sel)
                    }) {
                        HStack(spacing: 6) {
                            Text(player.jersey.map { "\($0)" } ?? "–")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.3))
                                .frame(width: 22, alignment: .trailing)
                            Text(player.name)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: MatchEvent
    let homeTeam: String
    var matchContext: Match? = nil
    var onSelectPlayer: ((PlayerSelection) -> Void)? = nil

    private var isHome: Bool { event.teamName == homeTeam }

    var body: some View {
        HStack(spacing: 8) {
            if isHome {
                Text(event.type.symbol).frame(width: 24)
                eventInfo(alignment: .leading)
                Spacer()
                minuteLabel
            } else {
                minuteLabel
                Spacer()
                eventInfo(alignment: .trailing)
                Text(event.type.symbol).frame(width: 24)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    @ViewBuilder
    private func eventInfo(alignment: HorizontalAlignment) -> some View {
        if event.type == .substitution, let outgoing = event.text, !outgoing.isEmpty {
            VStack(alignment: alignment, spacing: 2) {
                playerNameView(event.playerName ?? "", alignment: alignment)
                Text(outgoing)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.45))
            }
        } else {
            playerNameView(event.playerName ?? "", alignment: alignment)
        }
    }

    @ViewBuilder
    private func playerNameView(_ name: String, alignment: HorizontalAlignment) -> some View {
        if !name.isEmpty {
            Button(action: {
                let sel = PlayerSelection(playerName: name, teamName: event.teamName, athleteID: nil, matchContext: matchContext)
                onSelectPlayer?(sel)
            }) {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        } else {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.white)
        }
    }

    private var minuteLabel: some View {
        Text("\(event.minute)'\(event.extraTime.map { "+\($0)" } ?? "")")
            .font(.caption.weight(.bold))
            .foregroundStyle(Color(hex: 0xE8460B))
            .frame(width: 36)
    }
}

// MARK: - Lineup Column

struct LineupColumn: View {
    let lineup: TeamLineup
    let team: String
    var matchContext: Match? = nil
    var onSelectPlayer: ((PlayerSelection) -> Void)? = nil
    @Environment(HighlightSettings.self) private var highlights

    private var starters: [LineupPlayer] { lineup.players.filter(\.isStarter) }
    private var subs:     [LineupPlayer] { lineup.players.filter { !$0.isStarter } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TeamLogoView(teamName: team, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(team)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(highlights.highlight(for: team)?.color ?? .white.opacity(0.8))
                        .lineLimit(1)
                    if let f = lineup.formation {
                        Text(f).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(hex: 0x0D0D1A))

            ForEach(starters) { p in
                PlayerRow(player: p, team: team, matchContext: matchContext, onSelectPlayer: onSelectPlayer)
            }

            if !subs.isEmpty {
                Text("Suplentes")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
                ForEach(subs) { p in
                    PlayerRow(player: p, team: team, matchContext: matchContext, onSelectPlayer: onSelectPlayer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlayerRow: View {
    let player: LineupPlayer
    var team: String? = nil
    var matchContext: Match? = nil
    var onSelectPlayer: ((PlayerSelection) -> Void)? = nil

    var body: some View {
        Button(action: {
            let sel = PlayerSelection(
                playerName: player.name,
                teamName: team,
                athleteID: player.id,
                matchContext: matchContext,
                position: player.position
            )
            onSelectPlayer?(sel)
        }) {
            HStack(spacing: 6) {
                Text(player.jersey.map { "\($0)" } ?? "-")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .frame(width: 22, alignment: .trailing)
                Text(player.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PredictionBar

/// Barra tricolor (gana local / empate / gana visitante) con los tres porcentajes debajo.
struct PredictionBar: View {
    let prediction: MatchPrediction
    let homeColor: Color
    let awayColor: Color
    let isExpanded: Bool

    private let drawColor = Color.white.opacity(0.35)

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 0) {
                    Rectangle().fill(homeColor)
                        .frame(width: max(0, w * prediction.homeWin))
                    Rectangle().fill(drawColor)
                        .frame(width: max(0, w * prediction.draw))
                    Rectangle().fill(awayColor)
                        .frame(width: max(0, w * prediction.awayWin))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            HStack {
                percentLabel("\(prediction.homePercent)%", color: homeColor, alignment: .leading)
                Text("\(prediction.drawPercent)%")
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                percentLabel("\(prediction.awayPercent)%", color: awayColor, alignment: .trailing)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()

            HStack(spacing: 4) {
                Text("Pronóstico")
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func percentLabel(_ text: String, color: Color, alignment: Alignment) -> some View {
        Text(text)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
