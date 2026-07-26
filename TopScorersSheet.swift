import SwiftUI

struct TopScorersSheet: View {
    let scorers: [TopScorer]
    let seasonName: String
    let season: AppSeason

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlayer: PlayerSelection? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if scorers.isEmpty {
                        emptyView
                    } else {
                        ForEach(Array(scorers.enumerated()), id: \.element.id) { idx, scorer in
                            TopScorerRow(rank: idx + 1, scorer: scorer, onTap: {
                                selectedPlayer = PlayerSelection(
                                    playerName: scorer.player,
                                    teamName: scorer.team,
                                    athleteID: nil
                                )
                            })
                            if idx < scorers.count - 1 {
                                Divider().background(Color.white.opacity(0.05)).padding(.leading, 60)
                            }
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
                        Text("Goleadores").font(.headline).foregroundStyle(.white)
                        Text("La Liga \(seasonName)").font(.caption2).foregroundStyle(Color(hex: 0xE8460B))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(Color(hex: 0x004D98))
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $selectedPlayer) { sel in
            PlayerStatsSheet(selection: sel, season: season)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "soccerball").font(.system(size: 44)).foregroundStyle(.white.opacity(0.2))
            Text("Sin datos de goleadores").foregroundStyle(.white.opacity(0.4)).font(.subheadline)
            Text("Disponible cuando haya partidos finalizados").foregroundStyle(.white.opacity(0.25)).font(.caption)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

struct TopScorerRow: View {
    let rank: Int
    let scorer: TopScorer
    var onTap: (() -> Void)? = nil
    @Environment(HighlightSettings.self) private var highlights

    var rankColor: Color {
        switch rank {
        case 1: return Color(hex: 0xDBB44B)   // gold
        case 2: return Color(hex: 0xADB5BD)   // silver
        case 3: return Color(hex: 0xCD7F32)   // bronze
        default: return Color.white.opacity(0.35)
        }
    }

    var body: some View {
        let hl = highlights.highlight(for: scorer.team)
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                // Rank badge
                ZStack {
                    Circle()
                        .fill(rankColor.opacity(rank <= 3 ? 0.15 : 0.06))
                        .frame(width: 36, height: 36)
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(rankColor)
                }
                .padding(.leading, 16)

                // Team logo
                TeamLogoView(teamName: scorer.team, size: 22)

                // Name + team
                VStack(alignment: .leading, spacing: 2) {
                    Text(scorer.player)
                        .font(.subheadline.weight(hl != nil ? .bold : .medium))
                        .foregroundStyle(hl?.color ?? .white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(scorer.team)
                            .font(.caption).foregroundStyle(.white.opacity(0.45))
                        if let pen = scorer.penalties, pen > 0 {
                            Text("(\(pen) pen)")
                                .font(.caption2).foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }

                Spacer()

                // Goals
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(scorer.goals)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(hl?.color ?? .white)
                    Text("goles")
                        .font(.caption2).foregroundStyle(.white.opacity(0.3))
                }
                .padding(.trailing, 16)
            }
            .padding(.vertical, 10)
            .background(
                hl != nil
                    ? AnyShapeStyle(hl!.color.opacity(0.10))
                    : AnyShapeStyle(Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
