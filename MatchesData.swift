import Foundation

enum MatchesData {
    static let allTeams: [String] = [
        "Real Madrid", "FC Barcelona", "Atlético", "Athletic",
        "R. Sociedad", "Betis", "Villarreal", "Valencia",
        "Sevilla", "Osasuna", "Celta", "Getafe",
        "Rayo", "Alavés", "Espanyol", "Levante",
        "Racing", "Deportivo", "Elche", "Málaga"
    ]

    // IDs de equipo en la ESPN API (usados para logos y endpoint de plantilla)
    // Incluye equipos de temporadas 24/25, 25/26 y 26/27
    static let espnTeamIDs: [String: Int] = [
        // Temporada 26/27 (equipos base)
        "FC Barcelona": 83,
        "Real Madrid":  86,
        "Atlético":     1068,
        "Athletic":     93,
        "R. Sociedad":  89,
        "Betis":        244,
        "Villarreal":   102,
        "Valencia":     94,
        "Sevilla":      243,
        "Osasuna":      97,
        "Celta":        85,
        "Getafe":       2922,
        "Rayo":         101,
        "Alavés":       96,
        "Espanyol":     88,
        "Levante":      1538,
        "Racing":       87,
        "Deportivo":    90,
        "Elche":        3751,
        "Málaga":       99,
        // Equipos históricos (temporadas 24/25 y 25/26)
        "Mallorca":     84,
        "Las Palmas":   98,
        "Girona":       9812,
        "Valladolid":   95,
        "Leganés":      17534,
        "Cádiz":        2948,
        "Granada":      2858,
        "Almería":      1216,
        "Real Oviedo":  92,
    ]
}
