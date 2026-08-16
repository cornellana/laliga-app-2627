import Foundation
import SwiftUI

// MARK: - App Season

struct AppSeason: Identifiable, Equatable, Hashable {
    var id: String { code }
    let code: String           // "2627", "2526", "2425"
    let displayName: String    // "26/27"
    let espnYear: Int
    let remoteURL: URL?
    let seedName: String       // bundle resource name (without .json)

    static let all: [AppSeason] = [
        AppSeason(
            code: "2627", displayName: "26/27", espnYear: 2026,
            remoteURL: URL(string: "https://raw.githubusercontent.com/cornellana/laliga-app-2627/refs/heads/main/data/laliga2627.json"),
            seedName: "laliga2627-seed"
        ),
        AppSeason(
            code: "2526", displayName: "25/26", espnYear: 2025,
            remoteURL: URL(string: "https://raw.githubusercontent.com/cornellana/laliga-app-2627/refs/heads/main/data/laliga2526.json"),
            seedName: "laliga2526-seed"
        ),
        AppSeason(
            code: "2425", displayName: "24/25", espnYear: 2024,
            remoteURL: URL(string: "https://raw.githubusercontent.com/cornellana/laliga-app-2627/refs/heads/main/data/laliga2425.json"),
            seedName: "laliga2425-seed"
        ),
    ]

    static var current: AppSeason { all[0] }
}

// MARK: - Match

struct Match: Identifiable, Codable {
    let id: String
    let time: String
    let home: String
    let away: String
    let jornada: Int
    let tv: String?
    let done: Bool
    let result: String?
    let details: MatchDetails?
    let stadium: String?
    let venueCity: String?
    let espnEventID: String?

    // Estado en vivo. Son `var` con valor por defecto para que los datos
    // antiguos (y los tests) sigan decodificándose y construyéndose igual.
    /// "pre" sin empezar · "in" en juego · "post" terminado. Nil si se desconoce.
    var state: String? = nil
    /// Minuto en curso tal cual lo da ESPN: "45'+2'". Solo mientras se juega.
    var clock: String? = nil
    /// Descripción del estado en inglés ("Halftime", "First Half"…).
    var statusText: String? = nil

    var involvesBarcelona: Bool {
        home == "FC Barcelona" || away == "FC Barcelona"
    }

    /// El partido se está jugando ahora mismo.
    var isLive: Bool { state == "in" && !done }

    /// Texto para la columna de estado mientras el partido está en juego.
    var liveLabel: String? {
        guard isLive else { return nil }
        if let t = statusText?.lowercased() {
            if t.contains("halftime") { return "Descanso" }
            if t.contains("delayed")  { return "Aplazado" }
        }
        if let c = clock, !c.isEmpty { return c }
        return "EN JUEGO"
    }

    var homeScore: Int? {
        guard let result, let dash = result.firstIndex(of: "-") else { return nil }
        return Int(result[result.startIndex..<dash])
    }

    var awayScore: Int? {
        guard let result, let dash = result.firstIndex(of: "-") else { return nil }
        let after = result.index(after: dash)
        return Int(result[after...])
    }
}

// MARK: - MatchDay

struct MatchDay: Identifiable, Codable {
    var id: String { date }
    let date: String      // "yyyy-MM-dd"
    let jornada: Int
    let games: [Match]
}

// MARK: - Snapshot (root JSON)

struct MatchSnapshot: Codable {
    let lastUpdated: String
    let season: String
    let matchDays: [MatchDay]
    let standings: [LeagueStanding]?
    let topScorers: [TopScorer]?
}

// MARK: - Match Details

struct MatchDetails: Codable {
    let homeLineup: TeamLineup?
    let awayLineup: TeamLineup?
    let events: [MatchEvent]?
}

struct TeamLineup: Codable {
    let formation: String?
    let players: [LineupPlayer]
}

struct LineupPlayer: Codable, Identifiable {
    let id: String
    let jersey: Int?
    let name: String
    let position: String?
    let isStarter: Bool
    let events: [MatchEvent]?
}

struct MatchEvent: Codable, Identifiable {
    let id: String
    let type: MatchEventType
    let minute: Int
    let extraTime: Int?
    let playerName: String?
    let teamName: String?
    let text: String?
}

enum MatchEventType: String, Codable {
    case goal = "GOAL"
    case yellowCard = "YELLOW_CARD"
    case redCard = "RED_CARD"
    case substitution = "SUBSTITUTION"
    case ownGoal = "OWN_GOAL"
    case penalty = "PENALTY"
    case missedPenalty = "MISSED_PENALTY"

    var symbol: String {
        switch self {
        case .goal:          return "⚽"
        case .yellowCard:    return "🟨"
        case .redCard:       return "🟥"
        case .substitution:  return "🔄"
        case .ownGoal:       return "⚽ (pp)"
        case .penalty:       return "⚽ (p)"
        case .missedPenalty: return "❌"
        }
    }
}

// MARK: - Standings

struct LeagueStanding: Identifiable, Codable, Hashable {
    var id: String { team }
    let position: Int
    let team: String
    var played: Int
    var won: Int
    var drawn: Int
    var lost: Int
    var goalsFor: Int
    var goalsAgainst: Int

    var goalDifference: Int { goalsFor - goalsAgainst }
    var points: Int { won * 3 + drawn }

    var zone: StandingZone {
        switch position {
        case 1...4:   return .championsLeague
        case 5...6:   return .europaLeague
        case 7:       return .conferenceLeague
        case 18...20: return .relegation
        default:      return .mid
        }
    }
}

enum StandingZone {
    case championsLeague, europaLeague, conferenceLeague, mid, relegation

    var color: Color {
        switch self {
        case .championsLeague:  return Color(hex: 0x1B8A4C)
        case .europaLeague:     return Color(hex: 0x2471A3)
        case .conferenceLeague: return Color(hex: 0x5DADE2)
        case .mid:              return Color.clear
        case .relegation:       return Color(hex: 0xC0392B)
        }
    }
}

// MARK: - Top Scorers

struct TopScorer: Identifiable, Codable {
    var id: String { "\(player)_\(team)" }
    let player: String
    let team: String
    let goals: Int
    let penalties: Int?
}

// MARK: - Player Selection

struct PlayerSelection: Identifiable, Equatable {
    var id: String { "\(playerName)_\(teamName ?? "")_\(athleteID ?? "")_\(matchContext?.id ?? "")" }
    let playerName: String
    let teamName: String?
    let athleteID: String?
    let matchContext: Match?
    let matchDetails: MatchDetails?  // effectiveDetails from MatchDetailSheet (may differ from match.details)
    let position: String?            // abbreviation like "G", "D", "M", "F" — nil if unknown

    init(playerName: String, teamName: String?, athleteID: String?, matchContext: Match? = nil, matchDetails: MatchDetails? = nil, position: String? = nil) {
        self.playerName = playerName
        self.teamName = teamName
        self.athleteID = athleteID
        self.matchContext = matchContext
        self.matchDetails = matchDetails
        self.position = position
    }

    static func == (lhs: PlayerSelection, rhs: PlayerSelection) -> Bool {
        lhs.playerName == rhs.playerName &&
        lhs.teamName == rhs.teamName &&
        lhs.athleteID == rhs.athleteID &&
        lhs.matchContext?.id == rhs.matchContext?.id
    }
}

// MARK: - Color Helpers

extension Color {
    init(hex: UInt) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double(hex         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Convierte un Color a entero hex RGB (para persistir en UserDefaults).
    func toHex() -> UInt {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt(max(0, min(255, r * 255)))
        let gi = UInt(max(0, min(255, g * 255)))
        let bi = UInt(max(0, min(255, b * 255)))
        return (ri << 16) | (gi << 8) | bi
    }
}
