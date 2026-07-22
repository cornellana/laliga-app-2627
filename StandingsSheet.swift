import SwiftUI

struct StandingsSheet: View {
    let standings: [LeagueStanding]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    Divider().background(Color.white.opacity(0.1))

                    if standings.isEmpty {
                        emptyView
                    } else {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { idx, standing in
                            StandingRow(standing: standing, isBarcelona: standing.team == "FC Barcelona")
                            if idx < standings.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(standing.position == 4 || standing.position == 6 || standing.position == 7 || standing.position == 17 ? 0.25 : 0.05))
                            }
                        }
                    }
                }
            }
            .background(Color(hex: 0x0A0A14))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Clasificación").font(.headline).foregroundStyle(.white)
                        Text("La Liga 26/27").font(.caption2).foregroundStyle(Color(hex: 0xE8460B))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(Color(hex: 0x004D98))
                }
            }
            .safeAreaInset(edge: .bottom) { zoneLegend }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Column header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("#").frame(width: 28, alignment: .center)
            Text("Equipo").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
            Group {
                Text("PJ").frame(width: 28, alignment: .center)
                Text("PG").frame(width: 28, alignment: .center)
                Text("PE").frame(width: 28, alignment: .center)
                Text("PP").frame(width: 28, alignment: .center)
                Text("DG").frame(width: 32, alignment: .center)
                Text("Pts").frame(width: 32, alignment: .center)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(Color(hex: 0x0F0F1E))
    }

    // MARK: - Zone Legend

    private var zoneLegend: some View {
        HStack(spacing: 16) {
            LegendItem(color: Color(hex: 0x1B8A4C), label: "Champions")
            LegendItem(color: Color(hex: 0x2471A3), label: "Europa")
            LegendItem(color: Color(hex: 0x5DADE2), label: "Conference")
            LegendItem(color: Color(hex: 0xC0392B), label: "Descenso")
        }
        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(.ultraThinMaterial)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.number").font(.system(size: 44)).foregroundStyle(.white.opacity(0.2))
            Text("Sin datos de clasificación").foregroundStyle(.white.opacity(0.4)).font(.subheadline)
            Text("Disponible cuando haya partidos finalizados").foregroundStyle(.white.opacity(0.25)).font(.caption)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

struct StandingRow: View {
    let standing: LeagueStanding
    let isBarcelona: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Zone indicator
            Rectangle()
                .fill(standing.zone.color)
                .frame(width: 3)

            // Position
            Text("\(standing.position)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 28, alignment: .center)

            // Team name
            Text(standing.team)
                .font(.system(size: 13, weight: isBarcelona ? .bold : .regular))
                .foregroundStyle(isBarcelona ? Color(hex: 0x6EC0F0) : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)

            Group {
                Text("\(standing.played)").frame(width: 28, alignment: .center)
                Text("\(standing.won)").frame(width: 28, alignment: .center)
                Text("\(standing.drawn)").frame(width: 28, alignment: .center)
                Text("\(standing.lost)").frame(width: 28, alignment: .center)
                Text(standing.goalDifference >= 0 ? "+\(standing.goalDifference)" : "\(standing.goalDifference)")
                    .frame(width: 32, alignment: .center)
                    .foregroundStyle(standing.goalDifference > 0 ? Color(hex: 0x1B8A4C) : standing.goalDifference < 0 ? Color(hex: 0xC0392B) : .white.opacity(0.55))
                Text("\(standing.points)")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, alignment: .center)
                    .foregroundStyle(.white)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(.vertical, 9)
        .background(
            isBarcelona
                ? LinearGradient(
                    stops: [.init(color: Color(hex: 0x004D98).opacity(0.2), location: 0),
                            .init(color: Color(hex: 0xA50044).opacity(0.08), location: 1)],
                    startPoint: .leading, endPoint: .trailing)
                : LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
        )
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }
}
