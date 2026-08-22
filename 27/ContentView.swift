import SwiftUI

// MARK: - MatchItem (sheet presenter)

struct MatchItem: Identifiable, Equatable {
    var id: String { match.id }
    let match: Match
    var allMatches: [Match] = []
    static func == (lhs: MatchItem, rhs: MatchItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - ContentView

struct ContentView: View {
    @State private var store = MatchStore()
    // Filtros independientes y combinables
    @State private var filterTeam: String? = nil
    @State private var filterJornada: Int? = nil
    @State private var selectedMatchItem: MatchItem?
    @State private var showingStandings = false
    @State private var showingTopScorers = false
    @State private var showingSettings = false
    @State private var showingCalendar = false
    @State private var highlightSettings = HighlightSettings()
    @Environment(\.scenePhase) private var scenePhase
    /// Sección en la que se sitúa la lista. Se fija al abrir para caer en la
    /// jornada en curso; después la mueve el usuario al desplazarse.
    @State private var anclaLista: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if store.isLoading && store.matchDays.isEmpty {
                            loadingView
                        } else if filteredJornadas.isEmpty {
                            emptyView
                        } else {
                            ForEach(filteredJornadas) { group in
                                JornadaSectionView(group: group) { match in
                                    selectedMatchItem = MatchItem(match: match, allMatches: allFilteredMatches)
                                }
                                // El identificador va aquí, en lo que produce el
                                // ForEach: dentro de la sección, .scrollPosition
                                // no lo ve y la lista nunca se movía de la
                                // jornada 1.
                                .id("jornada-\(group.jornada)")
                            }
                        }
                        Spacer(minLength: 80)
                    }
                    // Sin esto, .scrollPosition no sabe qué secciones hay y la
                    // lista se queda donde estaba.
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                // Posicionar por estado y no con scrollTo tras un temporizador:
                // al abrir, la lista se reconstruye cuando llegan los datos y
                // se llevaba por delante cualquier desplazamiento anterior, así
                // que la app aterrizaba siempre en la jornada 1.
                .scrollPosition(id: $anclaLista, anchor: .top)
                .refreshable { await store.refresh() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await store.refresh()
                    await situarEnJornadaActual(proxy: proxy)
                }
                .task(id: LiveRefresh(phase: scenePhase, interval: liveRefreshInterval)) {
                    // Hasta ahora la app solo se refrescaba al abrirla, al volver
                    // del segundo plano o tirando de la lista: con el partido en
                    // pantalla, los goles no entraban solos. Este bucle solo vive
                    // mientras hay fútbol y la app está delante, así que fuera de
                    // esas horas no gasta ni batería ni datos.
                    guard scenePhase == .active, let interval = liveRefreshInterval else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        if Task.isCancelled { break }
                        await store.refresh()
                    }
                }
                .onChange(of: store.matchDays.count) { anterior, actual in
                    // En una instalación limpia la lista está vacía cuando se
                    // abre la app, así que colocarla entonces no sirve de nada:
                    // aterrizaba en la jornada 1. Se vuelve a intentar en cuanto
                    // llegan los partidos.
                    guard anterior == 0, actual > 0 else { return }
                    Task { await situarEnJornadaActual(proxy: proxy) }
                }
                .onChange(of: filterTeam) { _, _ in scrollIfShowingAll(proxy: proxy) }
                .onChange(of: filterJornada) { _, newJornada in
                    if let j = newJornada {
                        // Scroll a la jornada seleccionada, las siguientes quedan visibles debajo
                        Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            withAnimation { proxy.scrollTo("jornada-\(j)", anchor: .top) }
                        }
                    } else {
                        scrollIfShowingAll(proxy: proxy)
                    }
                }
                .onChange(of: showingStandings) { _, isShowing in
                    guard !isShowing, let target = scrollTargetDate else { return }
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
                .onChange(of: showingTopScorers) { _, isShowing in
                    guard !isShowing, let target = scrollTargetDate else { return }
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
                .onChange(of: selectedMatchItem) { _, newItem in
                    guard newItem == nil, let target = scrollTargetDate else { return }
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
            .background(Color(hex: 0x0A0A14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 10) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gear")
                                .foregroundStyle(.white)
                        }
                        if store.isLoading {
                            ProgressView()
                                .tint(Color(hex: 0xE8460B))
                                .scaleEffect(0.8)
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    Menu {
                        ForEach(AppSeason.all) { season in
                            Button {
                                Task { await store.selectSeason(season) }
                            } label: {
                                if store.selectedSeason == season {
                                    Label("Temporada \(season.displayName)", systemImage: "checkmark")
                                } else {
                                    Text("Temporada \(season.displayName)")
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 1) {
                            Text("La Liga")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                            HStack(spacing: 3) {
                                Text("Temp. \(store.selectedSeason.displayName)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color(hex: 0xE8460B))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0xE8460B))
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button { showingCalendar = true } label: {
                            Image(systemName: "calendar")
                                .foregroundStyle(.white)
                        }
                        Button { showingTopScorers = true } label: {
                            Image(systemName: "soccerball")
                                .foregroundStyle(.white)
                        }
                        Button { showingStandings = true } label: {
                            Image(systemName: "list.number")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                JornadaFilterBar(
                    filterTeam: $filterTeam,
                    filterJornada: $filterJornada,
                    teams: allTeams,
                    jornadaDates: jornadaStartDates,
                    filterTeamHighlightColor: filterTeam.flatMap { highlightSettings.highlight(for: $0)?.color }
                )
            }
        }
        .environment(highlightSettings)
        .onChange(of: store.selectedSeason) { _, _ in
            filterTeam = nil
            filterJornada = nil
        }
        .sheet(item: $selectedMatchItem) { item in
            // El partido se vuelve a buscar en el store en cada repintado: si
            // se abriera con la copia guardada al pulsar, la ficha se quedaría
            // congelada en el marcador de ese instante mientras el refresco
            // automático actualiza la lista de detrás.
            let actual = store.matchDays
                .flatMap(\.games)
                .first { $0.id == item.match.id } ?? item.match
            MatchDetailSheet(match: actual, season: store.selectedSeason, allMatches: item.allMatches, matchDays: store.matchDays)
                .environment(highlightSettings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingStandings) {
            StandingsSheet(
                standings: store.standings,
                seasonName: store.selectedSeason.displayName,
                matchDays: store.matchDays,
                season: store.selectedSeason
            )
            .environment(highlightSettings)
        }
        .sheet(isPresented: $showingTopScorers) {
            TopScorersSheet(
                scorers: store.topScorers,
                seasonName: store.selectedSeason.displayName,
                season: store.selectedSeason
            )
            .environment(highlightSettings)
        }
        .sheet(isPresented: $showingCalendar) {
            TeamCalendarSheet(matchDays: store.matchDays, season: store.selectedSeason)
                .environment(highlightSettings)
        }
        .sheet(isPresented: $showingSettings) {
            HighlightSettingsSheet(settings: highlightSettings, allTeams: allTeams)
                .environment(highlightSettings)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Refresco automático

    /// Identidad del bucle de refresco: al cambiar, SwiftUI lo reinicia con la
    /// cadencia nueva; al quedarse en `nil` el intervalo, lo cancela.
    private struct LiveRefresh: Equatable {
        let phase: ScenePhase
        let interval: Duration?
    }

    /// Cada cuánto refrescar solo, o `nil` si no hay nada que seguir.
    ///
    /// Dos ritmos: rápido con el balón rodando, y uno tranquilo alrededor de la
    /// hora del saque. El segundo hace falta porque el estado "en juego" solo
    /// aparece si alguien ha refrescado antes: sin él, una app abierta desde
    /// media hora antes no se enteraría nunca de que el partido ha empezado.
    private var liveRefreshInterval: Duration? {
        if store.matchDays.contains(where: { $0.games.contains(where: \.isLive) }) {
            return .seconds(45)
        }
        // Cerca del saque hace falta ritmo rápido: el estado "en juego" solo
        // aparece si alguien refresca, y con cinco minutos el partido podía
        // llevar cuatro rodando sin que la app se enterara. Pasó en el
        // Espanyol-Real Madrid: llegó el aviso al móvil y la lista seguía
        // mostrando la hora del saque.
        if kickoffImminent { return .seconds(60) }
        return kickoffNearby ? .seconds(300) : nil
    }

    /// ¿Algún partido con el saque a menos de quince minutos, por delante o
    /// por detrás? Es la ventana en la que el estado está a punto de cambiar.
    private var kickoffImminent: Bool { kickoffWithin(before: 900, after: 900) }

    /// ¿Hay algún partido sin terminar cuyo saque caiga cerca de ahora?
    private var kickoffNearby: Bool { kickoffWithin(before: 3600, after: 3 * 3600) }

    /// ¿Algún partido sin terminar cuyo saque caiga dentro de la ventana dada?
    private func kickoffWithin(before: TimeInterval, after: TimeInterval) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.timeZone = TimeZone(identifier: "Europe/Madrid")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let ahora = Date()
        for day in store.matchDays {
            for game in day.games where !game.done {
                guard !game.time.isEmpty,
                      let saque = formatter.date(from: "\(day.date) \(game.time)") else { continue }
                let faltan = saque.timeIntervalSince(ahora)
                if faltan < before && faltan > -after { return true }
            }
        }
        return false
    }

    // MARK: - Situar la lista

    /// Coloca la lista en la jornada en curso al abrir la app.
    ///
    /// Se intenta varias veces a propósito: la lista es perezosa y, si el
    /// destino todavía no se ha construido, el primer `scrollTo` no agarra y la
    /// app se queda enseñando la jornada 1. Se para en cuanto la posición deja
    /// de cambiar.
    private func situarEnJornadaActual(proxy: ScrollViewProxy) async {
        guard let destino = scrollTargetDate else { return }
        // Dos pasadas: la primera fija la posición nada más llegar los datos y
        // la segunda la sostiene si la lista se ha vuelto a construir mientras.
        anclaLista = destino
        try? await Task.sleep(nanoseconds: 400_000_000)
        if Task.isCancelled { return }
        anclaLista = destino
    }

    // MARK: - Scroll helper

    private func scrollIfShowingAll(proxy: ScrollViewProxy) {
        guard filterTeam == nil, filterJornada == nil, let target = scrollTargetDate else { return }
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation { proxy.scrollTo(target, anchor: .top) }
        }
    }

    // MARK: - Filtrado combinado

    private var filteredMatchDays: [MatchDay] {
        var days = store.matchDays
        if let team = filterTeam {
            days = days.compactMap { day in
                let games = day.games.filter { $0.home == team || $0.away == team }
                return games.isEmpty ? nil : MatchDay(date: day.date, jornada: day.jornada, games: games)
            }
        }
        if let jornada = filterJornada {
            // Muestra la jornada seleccionada y todas las siguientes
            days = days.filter { $0.jornada >= jornada }
        }
        return days
    }

    private var filteredJornadas: [JornadaGroup] {
        let days = filteredMatchDays
        let grouped = Dictionary(grouping: days, by: \.jornada)
        return grouped.keys.sorted().map { j in
            JornadaGroup(jornada: j, days: grouped[j]!.sorted { $0.date < $1.date })
        }
    }

    private var allFilteredMatches: [Match] {
        filteredJornadas.flatMap { group in
            group.days.flatMap { $0.games }
        }
    }

    // MARK: - Scroll target

    private var scrollTargetDate: String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        // Las fechas del JSON son de La Liga, o sea hora de Madrid. Con la zona
        // del teléfono, de viaje se podría saltar de jornada por unas horas.
        fmt.timeZone = TimeZone(identifier: "Europe/Madrid")
        let today = fmt.string(from: Date())
        let all = store.matchDays
        guard !all.isEmpty else { return nil }
        if let dayToday = all.first(where: { $0.date == today }) { return "jornada-\(dayToday.jornada)" }
        if let nextDay  = all.first(where: { $0.date > today })  { return "jornada-\(nextDay.jornada)" }
        if let lastDay  = all.last                               { return "jornada-\(lastDay.jornada)" }
        return nil
    }

    // MARK: - Auxiliares

    private var jornadaStartDates: [(jornada: Int, date: String)] {
        var firstDate: [Int: String] = [:]
        for day in store.matchDays {
            if firstDate[day.jornada] == nil || day.date < firstDate[day.jornada]! {
                firstDate[day.jornada] = day.date
            }
        }
        return firstDate.keys.sorted().map { j in (jornada: j, date: firstDate[j]!) }
    }

    // Equipos resaltados primero, luego el resto en orden alfabético
    private var allTeams: [String] {
        var teams = Set(store.matchDays.flatMap { $0.games.flatMap { [$0.home, $0.away] } })
        if teams.isEmpty {
            teams = Set(["Real Madrid", "FC Barcelona", "Atlético", "Athletic", "R. Sociedad",
                     "Betis", "Villarreal", "Valencia", "Sevilla", "Osasuna", "Celta",
                     "Getafe", "Rayo", "Alavés", "Espanyol", "Levante", "Racing",
                     "Deportivo", "Elche", "Málaga"])
        }
        let sorted = teams.sorted()
        let highlighted = highlightSettings.highlights.map(\.team).filter { sorted.contains($0) }
        let rest = sorted.filter { !highlighted.contains($0) }
        return highlighted + rest
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color(hex: 0x004D98)).scaleEffect(1.5)
            Text("Cargando...").foregroundStyle(.white.opacity(0.5)).font(.subheadline)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            LaLigaLogoView(size: 72).opacity(0.85)
            Text("La Liga \(store.selectedSeason.displayName)")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
            Text("El calendario se cargará automáticamente\ncuando esté disponible")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            if let err = store.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                    Text(err)
                }
                .font(.caption)
                .foregroundStyle(Color(hex: 0xE8460B).opacity(0.8))
                .padding(.top, 4)
            } else {
                Text("Desliza hacia abajo para actualizar")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 80).padding(.horizontal, 32)
    }
}

// MARK: - Jornada Filter Bar

struct JornadaFilterBar: View {
    @Binding var filterTeam: String?
    @Binding var filterJornada: Int?
    let teams: [String]
    let jornadaDates: [(jornada: Int, date: String)]
    let filterTeamHighlightColor: Color?

    var body: some View {
        HStack(spacing: 8) {

            // ── Selector de equipo ───────────────────────────────
            Menu {
                Button {
                    filterTeam = nil
                } label: {
                    if filterTeam == nil {
                        Label("Todos los equipos", systemImage: "checkmark")
                    } else {
                        Text("Todos los equipos")
                    }
                }
                Divider()
                ForEach(teams, id: \.self) { team in
                    Button { filterTeam = team } label: {
                        filterTeam == team
                            ? Label(team, systemImage: "checkmark")
                            : Label(team, systemImage: "")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if let team = filterTeam {
                        TeamLogoView(teamName: team, size: 16)
                        Text(shortTeamName(team))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    } else {
                        Text("Equipo")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(filterTeam != nil ? .white : .white.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(teamSelectorBackground)
                .clipShape(Capsule())
            }

            // ── Selector de jornada ──────────────────────────────
            Menu {
                Button {
                    filterJornada = nil
                } label: {
                    if filterJornada == nil {
                        Label("Todas las jornadas", systemImage: "checkmark")
                    } else {
                        Text("Todas las jornadas")
                    }
                }
                Divider()
                ForEach(jornadaDates, id: \.jornada) { item in
                    Button { filterJornada = item.jornada } label: {
                        filterJornada == item.jornada
                            ? Label("J\(item.jornada)  ·  \(shortDate(item.date))", systemImage: "checkmark")
                            : Label("J\(item.jornada)  ·  \(shortDate(item.date))", systemImage: "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if let j = filterJornada {
                        Text("J\(j)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        if let d = jornadaDates.first(where: { $0.jornada == j })?.date {
                            Text("· \(shortDate(d))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    } else {
                        Text("Jornada")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(filterJornada != nil ? .white : .white.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(filterJornada != nil ? Color(hex: 0x004D98) : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.05))
        }
    }

    // Color del selector de equipo: usa el color del equipo resaltado si está seleccionado
    private var teamSelectorBackground: AnyShapeStyle {
        guard filterTeam != nil else { return AnyShapeStyle(Color.white.opacity(0.08)) }
        if let color = filterTeamHighlightColor {
            return AnyShapeStyle(color.opacity(0.75))
        }
        return AnyShapeStyle(Color(hex: 0x004D98))
    }

    private func shortTeamName(_ name: String) -> String {
        switch name {
        case "FC Barcelona": return "Barça"
        case "Real Madrid":  return "R. Madrid"
        case "R. Sociedad":  return "R. Soc."
        case "Deportivo":    return "Depor"
        default:             return name
        }
    }

    private func shortDate(_ dateStr: String) -> String {
        let parse = DateFormatter(); parse.dateFormat = "yyyy-MM-dd"
        guard let d = parse.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "d MMM"
        return fmt.string(from: d)
    }
}

// MARK: - Jornada Group

struct JornadaGroup: Identifiable {
    var id: Int { jornada }
    let jornada: Int
    let days: [MatchDay]
}

// MARK: - Jornada Section View

struct JornadaSectionView: View {
    let group: JornadaGroup
    let onSelectMatch: (Match) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("JORNADA \(group.jornada)")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color(hex: 0xE8460B))
                    .tracking(1.0)
                Spacer()
                Text(dateRange)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color(hex: 0x0F0F1E))

            ForEach(group.days) { day in
                HStack {
                    Text(formattedDate(day.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Color(hex: 0x080810))

                Divider().background(Color.white.opacity(0.04))

                ForEach(day.games) { match in
                    MatchRowView(match: match)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelectMatch(match) }
                    if match.id != day.games.last?.id {
                        Divider().background(Color.white.opacity(0.04)).padding(.leading, 48)
                    }
                }

                if day.id != group.days.last?.id {
                    Divider().background(Color.white.opacity(0.07))
                }
            }

            Divider().background(Color.white.opacity(0.11))
        }
    }

    private var dateRange: String {
        guard let first = group.days.first, let last = group.days.last else { return "" }
        let parse = DateFormatter(); parse.dateFormat = "yyyy-MM-dd"
        let display = DateFormatter()
        display.locale = Locale(identifier: "es_ES"); display.dateFormat = "d MMM"
        guard let d1 = parse.date(from: first.date), let d2 = parse.date(from: last.date) else { return "" }
        if first.date == last.date { return display.string(from: d1) }
        return "\(display.string(from: d1)) – \(display.string(from: d2))"
    }

    private func formattedDate(_ dateStr: String) -> String {
        let parse = DateFormatter(); parse.dateFormat = "yyyy-MM-dd"
        guard let d = parse.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "EEEE d MMM"
        display.locale = Locale(identifier: "es_ES")
        return display.string(from: d).capitalized
    }
}

// MARK: - Match Row

struct MatchRowView: View {
    let match: Match
    @Environment(HighlightSettings.self) private var highlights

    private var homeWins: Bool? { match.done ? (match.homeScore ?? 0) > (match.awayScore ?? 0) : nil }
    private var awayWins: Bool? { match.done ? (match.awayScore ?? 0) > (match.homeScore ?? 0) : nil }

    private var homeHL: TeamHighlight? { highlights.highlight(for: match.home) }
    private var awayHL: TeamHighlight? { highlights.highlight(for: match.away) }
    private var activeHL: TeamHighlight? { homeHL ?? awayHL }

    var body: some View {
        HStack(spacing: 0) {

            TeamLogoView(teamName: match.home, size: 28)
                .opacity(homeWins == false ? 0.45 : 1.0)
                .padding(.leading, 12)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 5) {
                Text(match.home)
                    .font(.subheadline.weight(nameWeight(for: match.home)))
                    .foregroundStyle(nameColor(for: match.home, wins: homeWins))
                    .lineLimit(1)
                Text(match.away)
                    .font(.subheadline.weight(nameWeight(for: match.away)))
                    .foregroundStyle(nameColor(for: match.away, wins: awayWins))
                    .lineLimit(1)
            }
            .padding(.vertical, 12)

            // Se muestra en cuanto hay marcador, no solo al terminar: durante el
            // partido `done` es falso pero `result` ya trae el tanteo en curso.
            if match.homeScore != nil {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(match.homeScore ?? 0)")
                        .font(.subheadline.weight(homeWins == true ? .bold : .regular))
                        .foregroundStyle(homeWins == true ? .white : .white.opacity(0.45))
                        .monospacedDigit()
                    Text("\(match.awayScore ?? 0)")
                        .font(.subheadline.weight(awayWins == true ? .bold : .regular))
                        .foregroundStyle(awayWins == true ? .white : .white.opacity(0.45))
                        .monospacedDigit()
                }
                .frame(width: 18, alignment: .trailing)
                .padding(.leading, 6)
                .padding(.vertical, 12)
            }

            TeamLogoView(teamName: match.away, size: 28)
                .opacity(awayWins == false ? 0.45 : 1.0)
                .padding(.leading, 6)
                .padding(.trailing, 4)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 5) {
                if match.done {
                    Text("Final")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                } else if let live = match.liveLabel {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: 0x30D158))
                            .frame(width: 6, height: 6)
                        Text(live)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x30D158))
                            .monospacedDigit()
                    }
                } else {
                    Text(match.time.isEmpty ? "TBD" : match.time)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
                if let tv = match.tv, !tv.isEmpty {
                    TVBadge(channel: tv)
                }
            }
            .padding(.trailing, 14)
        }
        .background(alignment: .leading) {
            if let h = activeHL {
                ZStack(alignment: .leading) {
                    h.color.opacity(0.12)
                    h.color.frame(width: 3)
                }
            }
        }
    }

    private func nameColor(for team: String, wins: Bool?) -> Color {
        if let h = highlights.highlight(for: team) {
            return h.color.opacity(0.9)
        }
        return wins == true ? .white : .white.opacity(0.7)
    }

    private func nameWeight(for team: String) -> Font.Weight {
        highlights.highlight(for: team) != nil ? .bold : .regular
    }
}

// MARK: - TV Badge

struct TVBadge: View {
    let channel: String

    private var bgColor: Color {
        switch channel.uppercased() {
        case "DAZN":             return Color(hex: 0xF5A623)
        case "MOVISTAR", "M+":  return Color(hex: 0x0077B6)
        case "GOL":              return Color(hex: 0x43AA8B)
        case "TVE", "LA 1":     return Color(hex: 0xE63946)
        default:                 return Color(hex: 0x444455)
        }
    }

    var body: some View {
        Text(channel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
