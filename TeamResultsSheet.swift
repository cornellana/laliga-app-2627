import SwiftUI

struct TeamResultsSheet: View {
    let team: String
    let matchDays: [MatchDay]
    let seasonName: String

    @Environment(\.dismiss) private var dismiss

    private var teamMatches: [(date: String, jornada: Int, match: Match)] {
        matchDays.flatMap { day in
            day.games
                .filter { $0.home == team || $0.away == team }
                .map { (date: day.date, jornada: day.jornada, match: $0) }
        }
        .sorted { $0.date < $1.date }
    }

    private var completedMatches: [(date: String, jornada: Int, match: Match)] {
        teamMatches.filter { $0.match.done }
    }

    // MARK: - Stats computed from completed matches
    private var played: Int   { completedMatches.count }
    private var won: Int      { completedMatches.filter { outcome(for: $0.match) == .win }.count }
    private var drawn: Int    { completedMatches.filter { outcome(for: $0.match) == .draw }.count }
    private var lost: Int     { completedMatches.filter { outcome(for: $0.match) == .loss }.count }
    private var goalsFor: Int {
        completedMatches.reduce(0) { acc, item in
            acc + (item.match.home == team ? item.match.homeScore ?? 0 : item.match.awayScore ?? 0)
        }
    }
    private var goalsAgainst: Int {
        completedMatches.reduce(0) { acc, item in
            acc + (item.match.home == team ? item.match.awayScore ?? 0 : item.match.homeScore ?? 0)
        }
    }
    private var points: Int { won * 3 + drawn }
    private var goalDiff: Int { goalsFor - goalsAgainst }

    private enum Outcome { case win, draw, loss }
    private func outcome(for match: Match) -> Outcome {
        guard match.done, let hs = match.homeScore, let as_ = match.awayScore else { return .draw }
        let teamScore  = match.home == team ? hs : as_
        let enemyScore = match.home == team ? as_ : hs
        if teamScore > enemyScore { return .win }
        if teamScore < enemyScore { return .loss }
        return .draw
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    summaryBar
                    Divider().background(Color.white.opacity(0.08))

                    if teamMatches.isEmpty {
                        emptyView
                    } else {
                        ForEach(teamMatches, id: \.match.id) { item in
                            TeamResultRow(team: team, item: item)
                            Divider()
                                .background(Color.white.opacity(0.05))
                                .padding(.leading, 56)
                        }
                    }
                    Spacer(minLength: 40)
                }
            }
            .background(Color(hex: 0x0A0A14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(team)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("La Liga \(seasonName)")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: 0xE8460B))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Color(hex: 0x004D98))
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 0) {
            TeamLogoView(teamName: team, size: 36)
                .padding(.leading, 16)
                .padding(.trailing, 12)

            HStack(spacing: 0) {
                statCell(label: "PJ", value: "\(played)")
                statCell(label: "PG", value: "\(won)",   color: Color(hex: 0x1B8A4C))
                statCell(label: "PE", value: "\(drawn)",  color: .white.opacity(0.55))
                statCell(label: "PP", value: "\(lost)",   color: Color(hex: 0xC0392B))
                statCell(label: "GF", value: "\(goalsFor)")
                statCell(label: "GC", value: "\(goalsAgainst)")
                statCell(label: "DG", value: goalDiff >= 0 ? "+\(goalDiff)" : "\(goalDiff)",
                         color: goalDiff > 0 ? Color(hex: 0x1B8A4C) : goalDiff < 0 ? Color(hex: 0xC0392B) : .white.opacity(0.55))
                statCell(label: "Pts", value: "\(points)", color: .white, bold: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .background(Color(hex: 0x0F0F1E))
    }

    private func statCell(label: String, value: String, color: Color = .white.opacity(0.75), bold: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: bold ? .bold : .semibold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.2))
            Text("Sin partidos disponibles")
                .foregroundStyle(.white.opacity(0.4))
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Team Result Row

private struct TeamResultRow: View {
    let team: String
    let item: (date: String, jornada: Int, match: Match)

    private var match: Match { item.match }
    private var isHome: Bool { match.home == team }
    private var opponent: String { isHome ? match.away : match.home }

    private enum Outcome { case win, draw, loss, pending }
    private var outcome: Outcome {
        guard match.done, let hs = match.homeScore, let as_ = match.awayScore else { return .pending }
        let teamScore  = isHome ? hs : as_
        let enemyScore = isHome ? as_ : hs
        if teamScore > enemyScore { return .win }
        if teamScore < enemyScore { return .loss }
        return .draw
    }

    private var teamScore: Int? {
        guard match.done else { return nil }
        return isHome ? match.homeScore : match.awayScore
    }
    private var oppScore: Int? {
        guard match.done else { return nil }
        return isHome ? match.awayScore : match.homeScore
    }

    var body: some View {
        HStack(spacing: 10) {
            // Outcome badge
            outcomeBadge
                .frame(width: 28)
                .padding(.leading, 14)

            // Jornada + L/V
            VStack(spacing: 1) {
                Text("J\(item.jornada)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                Text(isHome ? "L" : "V")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isHome ? Color(hex: 0x004D98) : Color(hex: 0xE8460B))
            }
            .frame(width: 22)

            // Opponent logo + name
            TeamLogoView(teamName: opponent, size: 24)
            Text(opponent)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Score or date
            if match.done, let ts = teamScore, let os = oppScore {
                Text("\(ts) – \(os)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.trailing, 14)
            } else {
                Text(shortDate(item.date))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.trailing, 14)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var outcomeBadge: some View {
        switch outcome {
        case .win:
            outcomeCircle("V", color: Color(hex: 0x1B8A4C))
        case .draw:
            outcomeCircle("E", color: Color.gray)
        case .loss:
            outcomeCircle("D", color: Color(hex: 0xC0392B))
        case .pending:
            outcomeCircle("–", color: Color.white.opacity(0.15))
        }
    }

    private func outcomeCircle(_ letter: String, color: Color) -> some View {
        ZStack {
            Circle().fill(color.opacity(0.2)).frame(width: 26, height: 26)
            Text(letter)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
        }
    }

    private func shortDate(_ dateStr: String) -> String {
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd"
        guard let d = parse.date(from: dateStr) else { return dateStr }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "es_ES")
        fmt.dateFormat = "d MMM"
        return fmt.string(from: d)
    }
}
