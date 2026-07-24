import SwiftUI

// MARK: - MatchItem (sheet presenter)

struct MatchItem: Identifiable, Equatable {
    var id: String { match.id }
    let match: Match
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
    @State private var highlightSettings = HighlightSettings()
    @Environment(\.scenePhase) private var scenePhase

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
                                    selectedMatchItem = MatchItem(match: match)
                                }
                            }
                        }
                        Spacer(minLength: 80)
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refresh() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await store.refresh()
                    guard let target = scrollTargetDate else { return }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(target, anchor: .top) }
                }
                // Scroll a jornada actual solo cuando ambos filtros quedan en nil (botón Todos)
                .onChange(of: filterTeam) { _, _ in scrollIfShowingAll(proxy: proxy) }
                .onChange(of: filterJornada) { _, _ in scrollIfShowingAll(proxy: proxy) }
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
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("La Liga")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Temporada 26/27")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color(hex: 0xE8460B))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button { showingTopScorers = true } label: {
                            Image(systemName: "soccerball")
                                .foregroundStyle(Color(hex: 0xE8460B))
                        }
                        Button { showingStandings = true } label: {
                            Image(systemName: "list.number")
                                .foregroundStyle(Color(hex: 0x004D98))
                        }
                        Button { showingSettings = true } label: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(
                                    highlightSettings.highlights.count > 1
                                        ? Color(hex: 0xE8460B)
                                        : .white.opacity(0.6)
                                )
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if store.isLoading {
                        ProgressView()
                            .tint(Color(hex: 0xE8460B))
                            .scaleEffect(0.8)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                JornadaFilterBar(
                    filterTeam: $filterTeam,
                    filterJornada: $filterJornada,
                    teams: allTeams,
                    jornadaDates: jornadaStartDates
                )
            }
        }
        .environment(highlightSettings)
        .sheet(item: $selectedMatchItem) { item in
            MatchDetailSheet(match: item.match)
                .presentationDetents(item.match.details != nil ? [.large] : [.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingStandings) {
            StandingsSheet(standings: store.standings)
        }
        .sheet(isPresented: $showingTopScorers) {
            TopScorersSheet(scorers: store.topScorers)
        }
        .sheet(isPresented: $showingSettings) {
            HighlightSettingsSheet(settings: highlightSettings, allTeams: allTeams)
        }
        .preferredColorScheme(.dark)
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
            days = days.filter { $0.jornada == jornada }
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

    // MARK: - Scroll target

    private var scrollTargetDate: String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
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

    private var allTeams: [String] {
        var teams = Set(store.matchDays.flatMap { $0.games.flatMap { [$0.home, $0.away] } })
        if teams.isEmpty {
            teams = ["FC Barcelona", "Real Madrid", "Atlético", "Athletic", "R. Sociedad",
                     "Betis", "Villarreal", "Valencia", "Sevilla", "Osasuna", "Celta",
                     "Getafe", "Rayo", "Alavés", "Espanyol", "Levante", "Racing",
                     "Deportivo", "Elche", "Málaga"]
        }
        var sorted = teams.sorted()
        if let idx = sorted.firstIndex(of: "FC Barcelona") {
            sorted.remove(at: idx)
            sorted.insert("FC Barcelona", at: 0)
        }
        return sorted
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
            BarcelonaShieldView(size: 72).opacity(0.6)
            Text("La Liga 26/27")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
            Text("El calendario se cargará automáticamente\ncuando comience la temporada")
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
                .background(
                    filterTeam != nil
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(hex: 0x004D98), Color(hex: 0xA50044)],
                            startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.white.opacity(0.08))
                )
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
            .id("jornada-\(group.jornada)")

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

            if match.done {
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
