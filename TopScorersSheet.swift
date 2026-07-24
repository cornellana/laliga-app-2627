import SwiftUI

struct TopScorersSheet: View {
    let scorers: [TopScorer]
    let seasonName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if scorers.isEmpty {
                        emptyView
                    } else {
                        ForEach(Array(scorers.enumerated()), id: \.element.id) { idx, scorer in
                            TopScorerRow(rank: idx + 1, scorer: scorer)
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

    private var isBarcelona: Bool { scorer.team == "FC Barcelona" }

    var rankColor: Color {
        switch rank {
        case 1: return Color(hex: 0xDBB44B)   // gold
        case 2: return Color(hex: 0xADB5BD)   // silver
        case 3: return Color(hex: 0xCD7F32)   // bronze
        default: return Color.white.opacity(0.35)
        }
    }

    var body: some View {
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

            // Barcelona shield if applicable
            if isBarcelona {
                BarcelonaShieldView(size: 22)
            }

            // Name + team
            VStack(alignment: .leading, spacing: 2) {
                Text(scorer.player)
                    .font(.subheadline.weight(isBarcelona ? .bold : .medium))
                    .foregroundStyle(isBarcelona ? Color(hex: 0x6EC0F0) : .white)
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
                    .foregroundStyle(isBarcelona ? Color(hex: 0x6EC0F0) : .white)
                Text("goles")
                    .font(.caption2).foregroundStyle(.white.opacity(0.3))
            }
            .padding(.trailing, 16)
        }
        .padding(.vertical, 10)
        .background(
            isBarcelona
                ? LinearGradient(
                    stops: [.init(color: Color(hex: 0x004D98).opacity(0.15), location: 0),
                            .init(color: Color(hex: 0xA50044).opacity(0.07), location: 1)],
                    startPoint: .leading, endPoint: .trailing)
                : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        )
    }
}
