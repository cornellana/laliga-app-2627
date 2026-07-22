import SwiftUI

// MARK: - MatchItem (sheet presenter)

struct MatchItem: Identifiable {
    var id: String { match.id }
    let match: Match
}

// MARK: - ContentView

struct ContentView: View {
    @State private var store = MatchStore()
    @State private var activeFilter: JornadaFilter = .all
    @State private var selectedMatchItem: MatchItem?
    @State private var showingStandings = false
    @State private var showingTopScorers = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if store.isLoading && store.matchDays.isEmpty {
                            loadingView
                        } else if filteredMatchDays.isEmpty {
                            emptyView
                        } else {
                            ForEach(filteredMatchDays) { day in
                                MatchDaySectionView(day: day) { match in
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
                .onChange(of: activeFilter) { _, newVal in
                    if case .all = newVal, let target = scrollTargetDate {
                        Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            withAnimation { proxy.scrollTo(target, anchor: .top) }
                        }
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
                JornadaFilterBar(activeFilter: $activeFilter, maxJornada: maxJornada)
            }
        }
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Computed

    private var filteredMatchDays: [MatchDay] {
        switch activeFilter {
        case .all:
            return store.matchDays
        case .jornada(let n):
            return store.matchDays.filter { $0.jornada == n }
        case .team(let t):
            return store.matchDays.compactMap { day in
                let games = day.games.filter { $0.home == t || $0.away == t }
                return games.isEmpty ? nil : MatchDay(date: day.date, jornada: day.jornada, games: games)
            }
        }
    }

    private var scrollTargetDate: String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let all = store.matchDays
        if all.contains(where: { $0.date == today }) { return today }
        return all.first(where: { $0.date > today })?.id
    }

    private var maxJornada: Int {
        store.matchDays.map(\.jornada).max() ?? 38
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Color(hex: 0x004D98)).scaleEffect(1.5)
            Text("Cargando...").foregroundStyle(.white.opacity(0.5)).font(.subheadline)
        }
        .frame(maxWidth: .infinity).padding(.top, 100)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            BarcelonaShieldView(size: 72)
                .opacity(0.6)
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
    @Binding var activeFilter: JornadaFilter
    let maxJornada: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "Todos", isActive: activeFilter == .all) { activeFilter = .all }

                Button {
                    activeFilter = .team("FC Barcelona")
                } label: {
                    HStack(spacing: 5) {
                        BarcelonaShieldView(size: 16)
                        Text("Barça")
                            .font(.caption.weight(activeFilter == .team("FC Barcelona") ? .bold : .regular))
                            .foregroundStyle(activeFilter == .team("FC Barcelona") ? .white : .white.opacity(0.65))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(
                        activeFilter == .team("FC Barcelona")
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(hex: 0x004D98), Color(hex: 0xA50044)],
                                startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.08))
                    )
                    .clipShape(Capsule())
                }

                if maxJornada > 0 {
                    ForEach(1...maxJornada, id: \.self) { n in
                        FilterChip(label: "J\(n)", isActive: activeFilter == .jornada(n)) {
                            activeFilter = .jornada(n)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.05))
        }
    }
}

struct FilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isActive ? .bold : .regular))
                .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isActive ? Color(hex: 0x004D98) : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }
}

// MARK: - Match Day Section

struct MatchDaySectionView: View {
    let day: MatchDay
    let onSelectMatch: (Match) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(formattedDate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("Jornada \(day.jornada)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(hex: 0xE8460B))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color(hex: 0x0F0F1E))
            .id(day.id)

            Divider().background(Color.white.opacity(0.06))

            ForEach(day.games) { match in
                MatchRowView(match: match)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectMatch(match) }
                if match.id != day.games.last?.id {
                    Divider().background(Color.white.opacity(0.04)).padding(.leading, 60)
                }
            }

            Divider().background(Color.white.opacity(0.08))
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: day.date) else { return day.date }
        fmt.dateFormat = "EEEE d MMM"
        fmt.locale = Locale(identifier: "es_ES")
        return fmt.string(from: d).capitalized
    }
}

// MARK: - Match Row

struct MatchRowView: View {
    let match: Match

    private let barcaBlue = Color(hex: 0x004D98)
    private let barcaRed  = Color(hex: 0xA50044)

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if match.involvesBarcelona {
                    BarcelonaShieldView(size: 30)
                }
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                TeamScoreRow(
                    name: match.home,
                    score: match.homeScore,
                    isWinner: match.done ? (match.homeScore ?? 0) > (match.awayScore ?? 0) : nil,
                    isBarcelona: match.home == "FC Barcelona"
                )
                TeamScoreRow(
                    name: match.away,
                    score: match.awayScore,
                    isWinner: match.done ? (match.awayScore ?? 0) > (match.homeScore ?? 0) : nil,
                    isBarcelona: match.away == "FC Barcelona"
                )
            }
            .padding(.vertical, 12)

            Spacer()

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
            .padding(.trailing, 16)
        }
        .background(
            match.involvesBarcelona
                ? LinearGradient(
                    stops: [
                        .init(color: barcaBlue.opacity(0.18), location: 0),
                        .init(color: barcaRed.opacity(0.08), location: 1)
                    ],
                    startPoint: .leading, endPoint: .trailing)
                : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        )
    }
}

struct TeamScoreRow: View {
    let name: String
    let score: Int?
    let isWinner: Bool?
    let isBarcelona: Bool

    private let barcaHighlight = Color(hex: 0x6EC0F0)

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.subheadline.weight(isBarcelona ? .bold : .regular))
                .foregroundStyle(
                    isBarcelona ? barcaHighlight
                    : (isWinner == true ? .white : .white.opacity(0.65))
                )
                .lineLimit(1)
            Spacer()
            if let s = score {
                Text("\(s)")
                    .font(.subheadline.weight(isWinner == true ? .bold : .regular))
                    .foregroundStyle(isWinner == true ? .white : .white.opacity(0.5))
                    .monospacedDigit()
                    .frame(width: 18, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct TVBadge: View {
    let channel: String

    private var bgColor: Color {
        switch channel.uppercased() {
        case "DAZN":              return Color(hex: 0xF5A623)
        case "MOVISTAR", "M+":   return Color(hex: 0x0077B6)
        case "GOL":               return Color(hex: 0x43AA8B)
        case "TVE", "LA 1":      return Color(hex: 0xE63946)
        default:                  return Color(hex: 0x444455)
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

#Preview {
    ContentView()
}
