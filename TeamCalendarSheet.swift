import SwiftUI

// MARK: - Private model types

private struct MonthData: Identifiable {
    let year: Int
    let month: Int
    let title: String
    let weeks: [[DayData?]]  // exactly 7 cols per row, nil = out-of-month padding

    var id: String { "\(year)-\(month)" }
}

private struct DayData {
    let day: Int
    let match: Match?
    let opponent: String?  // nil if no match
    let isHome: Bool
}

// MARK: - TeamCalendarSheet

struct TeamCalendarSheet: View {
    let matchDays: [MatchDay]
    let season: AppSeason
    @Environment(\.dismiss) private var dismiss
    @Environment(HighlightSettings.self) private var highlights
    @State private var selectedMatch: MatchItem? = nil

    var body: some View {
        NavigationStack {
            teamListView
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text("Calendario").font(.headline).foregroundStyle(.white)
                            Text("La Liga \(season.displayName)").font(.caption2).foregroundStyle(Color(hex: 0xE8460B))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cerrar") { dismiss() }.foregroundStyle(Color(hex: 0x004D98))
                    }
                }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $selectedMatch) { item in
            MatchDetailSheet(match: item.match, season: season, allMatches: item.allMatches, matchDays: matchDays)
                .environment(highlights)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // Equipos resaltados primero, luego resto en orden de aparición (respeta orden del calendario)
    private var allTeams: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for md in matchDays {
            for g in md.games {
                if seen.insert(g.home).inserted { result.append(g.home) }
                if seen.insert(g.away).inserted { result.append(g.away) }
            }
        }
        let sorted = result.sorted()
        let highlighted = highlights.highlights.map(\.team).filter { sorted.contains($0) }
        let rest = sorted.filter { !highlighted.contains($0) }
        return highlighted + rest
    }

    private var teamListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(allTeams, id: \.self) { team in
                    NavigationLink {
                        TeamCalendarDetailView(
                            allTeams: allTeams,
                            initialTeam: team,
                            matchDays: matchDays,
                            onSelectMatch: { match, teamMatches in
                                selectedMatch = MatchItem(match: match, allMatches: teamMatches)
                            }
                        )
                    } label: {
                        let hl = highlights.highlight(for: team)
                        HStack(spacing: 14) {
                            TeamLogoView(teamName: team, size: 30)
                            Text(team)
                                .font(.subheadline.weight(hl != nil ? .bold : .regular))
                                .foregroundStyle(hl?.color ?? .white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.22))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(
                            hl != nil
                                ? AnyShapeStyle(hl!.color.opacity(0.10))
                                : AnyShapeStyle(Color(hex: 0x0A0A14))
                        )
                    }
                    Divider().background(Color.white.opacity(0.06)).padding(.leading, 64)
                }
            }
        }
        .background(Color(hex: 0x0A0A14))
    }
}

// MARK: - TeamCalendarDetailView (swipe entre equipos con TabView)

private struct TeamCalendarDetailView: View {
    let allTeams: [String]
    let matchDays: [MatchDay]
    let onSelectMatch: (Match, [Match]) -> Void

    @State private var selectedIndex: Int
    @Environment(HighlightSettings.self) private var highlights

    init(allTeams: [String], initialTeam: String, matchDays: [MatchDay], onSelectMatch: @escaping (Match, [Match]) -> Void) {
        self.allTeams = allTeams
        self.matchDays = matchDays
        self.onSelectMatch = onSelectMatch
        _selectedIndex = State(initialValue: allTeams.firstIndex(of: initialTeam) ?? 0)
    }

    private var currentTeam: String {
        guard !allTeams.isEmpty, selectedIndex < allTeams.count else { return "" }
        return allTeams[selectedIndex]
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(allTeams.enumerated()), id: \.offset) { idx, team in
                TeamCalendarPageContent(team: team, matchDays: matchDays, onSelectMatch: { match, teamMatches in
                    onSelectMatch(match, teamMatches)
                })
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color(hex: 0x0A0A14))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    TeamLogoView(teamName: currentTeam, size: 22)
                    Text(currentTeam)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(highlights.highlight(for: currentTeam)?.color ?? .white)
                        .lineLimit(1)
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }
}

// MARK: - TeamCalendarPageContent (contenido de una página del TabView)

private struct TeamCalendarPageContent: View {
    let team: String
    let matchDays: [MatchDay]
    let onSelectMatch: (Match, [Match]) -> Void

    private var months: [MonthData] { buildMonths() }

    private var teamMatches: [Match] {
        matchDays.sorted { $0.date < $1.date }.flatMap { $0.games }.filter { $0.home == team || $0.away == team }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(months) { month in
                    MonthCalendarCard(month: month, team: team, onSelectMatch: { match in
                        onSelectMatch(match, teamMatches)
                    })
                }
                Spacer(minLength: 40)
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
        .background(Color(hex: 0x0A0A14))
    }

    private func buildMonths() -> [MonthData] {
        let pairs: [(date: String, match: Match)] = matchDays.flatMap { md in
            md.games.filter { $0.home == team || $0.away == team }.map { (md.date, $0) }
        }

        var seen = Set<String>()
        var yearMonths: [(Int, Int)] = []
        for (date, _) in pairs {
            let parts = date.split(separator: "-")
            guard parts.count >= 2, let y = Int(parts[0]), let m = Int(parts[1]) else { continue }
            let key = "\(y)-\(m)"
            if seen.insert(key).inserted { yearMonths.append((y, m)) }
        }
        yearMonths.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        return yearMonths.map { buildMonthData(year: $0.0, month: $0.1, pairs: pairs) }
    }

    private func buildMonthData(year: Int, month: Int, pairs: [(date: String, match: Match)]) -> MonthData {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2

        let firstDay = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let daysInMonth = cal.range(of: .day, in: .month, for: firstDay)!.count
        let startOffset = (cal.component(.weekday, from: firstDay) - 2 + 7) % 7

        var matchByDay: [Int: Match] = [:]
        for (date, match) in pairs {
            let parts = date.split(separator: "-")
            guard parts.count == 3,
                  let py = Int(parts[0]), let pm = Int(parts[1]), let pd = Int(parts[2]),
                  py == year, pm == month else { continue }
            matchByDay[pd] = match
        }

        var cells: [DayData?] = Array(repeating: nil, count: startOffset)
        for d in 1...daysInMonth {
            if let m = matchByDay[d] {
                cells.append(DayData(day: d, match: m, opponent: m.home == team ? m.away : m.home, isHome: m.home == team))
            } else {
                cells.append(DayData(day: d, match: nil, opponent: nil, isHome: false))
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "LLLL yyyy"

        return MonthData(year: year, month: month, title: fmt.string(from: firstDay), weeks: weeks)
    }
}

// MARK: - MonthCalendarCard

private struct MonthCalendarCard: View {
    let month: MonthData
    let team: String
    let onSelectMatch: (Match) -> Void

    private let dayHeaders = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(month.title.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 6)

            HStack(spacing: 4) {
                ForEach(dayHeaders, id: \.self) { d in
                    Text(d)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { col in
                        CalendarDayCell(
                            data: week[col],
                            team: team,
                            onTap: { if let m = week[col]?.match { onSelectMatch(m) } }
                        )
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Color(hex: 0x0F0F1E))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CalendarDayCell

private struct CalendarDayCell: View {
    let data: DayData?
    let team: String
    let onTap: () -> Void

    var body: some View {
        Group {
            if let d = data {
                if d.match != nil {
                    Button(action: onTap) { matchContent(d) }.buttonStyle(.plain)
                } else {
                    emptyDay(d.day)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
    }

    private func matchContent(_ d: DayData) -> some View {
        let played = d.match?.done ?? false
        return VStack(spacing: 1) {
            Text("\(d.day)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(played ? 0.65 : 0.4))
            if let opp = d.opponent {
                TeamLogoView(teamName: opp, size: 27)
                    .opacity(played ? 1.0 : 0.35)
            }
            HStack(spacing: 3) {
                Text(d.isHome ? "L" : "V")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(d.isHome ? Color(hex: 0x4A9EDF) : Color(hex: 0xE8460B))
                if played, let score = scoreText(d) {
                    Text(score)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(RoundedRectangle(cornerRadius: 7).fill(cellBackground(d)))
    }

    // Siempre muestra local-visitante (goles del local primero)
    private func scoreText(_ d: DayData) -> String? {
        guard let hs = d.match?.homeScore, let as_ = d.match?.awayScore else { return nil }
        return "\(hs)-\(as_)"
    }

    private func cellBackground(_ d: DayData) -> Color {
        guard d.match?.done == true,
              let hs = d.match?.homeScore, let as_ = d.match?.awayScore else {
            return Color.white.opacity(0.03)
        }
        let tf = d.isHome ? hs : as_
        let of = d.isHome ? as_ : hs
        if tf > of { return Color(hex: 0x1B8A4C).opacity(0.18) }
        if tf < of { return Color(hex: 0xC0392B).opacity(0.14) }
        return Color.white.opacity(0.07)
    }

    private func emptyDay(_ day: Int) -> some View {
        VStack(alignment: .center) {
            Text("\(day)")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
    }
}
