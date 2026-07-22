import SwiftUI

struct MatchDetailSheet: View {
    let match: Match
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    scoreHeader
                    Divider().background(Color.white.opacity(0.08))

                    if let details = match.details {
                        if let events = details.events, !events.isEmpty {
                            eventsList(events)
                            Divider().background(Color.white.opacity(0.08))
                        }
                        if let home = details.homeLineup, let away = details.awayLineup {
                            lineupSection(home: home, away: away)
                        }
                    } else {
                        pendingView
                    }
                    Spacer(minLength: 40)
                }
            }
            .background(Color(hex: 0x0A0A14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Color(hex: 0x004D98))
                }
                ToolbarItem(placement: .principal) {
                    Text("Jornada \(match.jornada)")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        VStack(spacing: 0) {
            // Teams row
            HStack(alignment: .center, spacing: 0) {
                // Local
                teamColumn(name: match.home, isHome: true)

                // Score / Time
                VStack(spacing: 6) {
                    if match.done, let result = match.result {
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
                    }
                }
                .frame(width: 130)

                // Visitante
                teamColumn(name: match.away, isHome: false)
            }
            .padding(.top, 20)
            .padding(.horizontal, 12)

            // Venue + TV
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
        .background(
            match.involvesBarcelona
                ? LinearGradient(
                    stops: [.init(color: Color(hex: 0x004D98).opacity(0.22), location: 0),
                            .init(color: Color(hex: 0xA50044).opacity(0.10), location: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [Color(hex: 0x0F0F1E)], startPoint: .top, endPoint: .bottom)
        )
    }

    private func teamColumn(name: String, isHome: Bool) -> some View {
        let isBarça = name == "FC Barcelona"
        let isWinner: Bool? = match.done
            ? (isHome ? (match.homeScore ?? 0) > (match.awayScore ?? 0)
                      : (match.awayScore ?? 0) > (match.homeScore ?? 0))
            : nil

        return VStack(spacing: 10) {
            TeamLogoView(teamName: name, size: 72)
                .shadow(color: isBarça ? Color(hex: 0x004D98).opacity(0.5) : .clear, radius: 12)
                .opacity(isWinner == false ? 0.55 : 1.0)

            Text(name)
                .font(.system(size: 13, weight: isBarça ? .bold : .medium))
                .foregroundStyle(isBarça ? Color(hex: 0x6EC0F0) : .white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Events

    private func eventsList(_ events: [MatchEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Eventos del partido")
            ForEach(events) { event in
                EventRow(event: event, homeTeam: match.home)
                Divider().background(Color.white.opacity(0.04)).padding(.leading, 16)
            }
        }
    }

    // MARK: - Lineups

    private func lineupSection(home: TeamLineup, away: TeamLineup) -> some View {
        VStack(spacing: 0) {
            sectionHeader("Alineaciones")
            HStack(alignment: .top, spacing: 0) {
                LineupColumn(lineup: home, team: match.home)
                Divider().background(Color.white.opacity(0.06))
                LineupColumn(lineup: away, team: match.away)
            }
        }
    }

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

    // MARK: - Pending

    private var pendingView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                TeamLogoView(teamName: match.home, size: 56).opacity(0.5)
                Image(systemName: "clock.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.2))
                TeamLogoView(teamName: match.away, size: 56).opacity(0.5)
            }
            .padding(.top, 8)
            Text("Partido pendiente")
                .foregroundStyle(.white.opacity(0.45))
                .font(.subheadline)
            Text("Los detalles aparecerán cuando finalice")
                .foregroundStyle(.white.opacity(0.25))
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding(36)
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: MatchEvent
    let homeTeam: String

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

    private func eventInfo(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(event.playerName ?? "").font(.subheadline).foregroundStyle(.white)
            if let txt = event.text {
                Text(txt).font(.caption).foregroundStyle(.white.opacity(0.4))
            }
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

    private var starters: [LineupPlayer] { lineup.players.filter(\.isStarter) }
    private var subs: [LineupPlayer] { lineup.players.filter { !$0.isStarter } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Team logo + name header
            HStack(spacing: 8) {
                TeamLogoView(teamName: team, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(team)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(team == "FC Barcelona" ? Color(hex: 0x6EC0F0) : .white.opacity(0.8))
                        .lineLimit(1)
                    if let f = lineup.formation {
                        Text(f).font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
                    }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color(hex: 0x0D0D1A))

            ForEach(starters) { p in PlayerRow(player: p) }

            if !subs.isEmpty {
                Text("Suplentes")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
                ForEach(subs) { p in PlayerRow(player: p) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlayerRow: View {
    let player: LineupPlayer

    var body: some View {
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
}
