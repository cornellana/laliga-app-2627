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
    static let espnTeamIDs: [String: Int] = [
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
    ]
}
