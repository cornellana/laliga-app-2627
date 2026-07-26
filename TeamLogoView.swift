import SwiftUI

/// Escudo de equipo: usa el asset local para el Barça, AsyncImage de ESPN para el resto.
struct TeamLogoView: View {
    let teamName: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if teamName == "FC Barcelona" {
                Image("BarcelonaShield")
                    .resizable()
                    .scaledToFit()
            } else if let url = Self.logoURL(for: teamName) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    case .failure, .empty:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(Self.teamColor(for: teamName).opacity(0.25))
            Text(initials)
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(Self.teamColor(for: teamName))
        }
    }

    private var initials: String {
        teamName
            .components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
    }

    // MARK: - ESPN logo URLs (ID → png en CDN)

    static func logoURL(for team: String) -> URL? {
        guard let id = logoIDs[team] else { return nil }
        return URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\(id).png")
    }

    private static let logoIDs: [String: Int] = [
        "Real Madrid":  86,
        "Atlético":     1068,
        "Athletic":     93,
        "R. Sociedad":  89,
        "Betis":        244,
        "Villarreal":   102,
        "Valencia":     94,
        "Sevilla":      243,
        "Osasuna":      97,
        "Getafe":       2922,
        "Celta":        85,
        "Rayo":         101,
        "Alavés":       96,
        "Espanyol":     88,
        "Levante":      1538,
        "Racing":       87,
        "Deportivo":    90,
        "Elche":        3751,
        "Málaga":       99,
        // Equipos de temporadas anteriores (por si aparecen en cache)
        "Girona":       9812,
        "Mallorca":     95,
        "Las Palmas":   3842,
        "Leganés":      6900,
        "Valladolid":   100,
        "Real Oviedo":  92,
    ]

    // Color representativo de cada equipo para el fallback
    static func teamColor(for team: String) -> Color {
        switch team {
        case "Real Madrid":  return Color(hex: 0xF5C518)
        case "FC Barcelona": return Color(hex: 0x004D98)
        case "Atlético":     return Color(hex: 0xCB3524)
        case "Athletic":     return Color(hex: 0xCC0000)
        case "R. Sociedad":  return Color(hex: 0x0066B2)
        case "Betis":        return Color(hex: 0x00954C)
        case "Villarreal":   return Color(hex: 0xF7D026)
        case "Valencia":     return Color(hex: 0xF7A800)
        case "Sevilla":      return Color(hex: 0xCC0000)
        case "Osasuna":      return Color(hex: 0xD40000)
        case "Getafe":       return Color(hex: 0x0057A8)
        case "Celta":        return Color(hex: 0x87CEEB)
        case "Rayo":         return Color(hex: 0xCC0000)
        case "Alavés":       return Color(hex: 0x0039A6)
        case "Espanyol":     return Color(hex: 0x005CA9)
        case "Levante":      return Color(hex: 0x005CA9)
        case "Racing":       return Color(hex: 0x007A33)
        case "Deportivo":    return Color(hex: 0x003087)
        case "Elche":        return Color(hex: 0x007A33)
        case "Málaga":       return Color(hex: 0x0055A5)
        case "Real Oviedo":  return Color(hex: 0x003087)
        default:             return Color(hex: 0x555566)
        }
    }
}

#Preview {
    let teams = ["Real Madrid", "FC Barcelona", "Atlético", "Athletic",
                 "Sevilla", "Betis", "Valencia", "Villarreal"]
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
            ForEach(teams, id: \.self) { team in
                VStack(spacing: 6) {
                    TeamLogoView(teamName: team, size: 60)
                    Text(team).font(.caption2).foregroundStyle(.white).lineLimit(1)
                }
            }
        }
        .padding()
    }
    .background(Color(hex: 0x0A0A14))
}
