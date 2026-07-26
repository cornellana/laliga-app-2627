//
//  NotificationService.swift
//  27
//

import Foundation

private let backendBase = "https://laliga-api.cornellanas.net"
private let apnsEnv: String = {
    #if DEBUG
    return "sandbox"
    #else
    return "production"
    #endif
}()

// MARK: - NotificationService

@Observable
final class NotificationService {
    static let shared = NotificationService()

    private(set) var deviceToken: String?

    // Últimos valores conocidos; permite re-sincronizar cuando llega el token
    private var lastTeams: [String] = []
    private var lastPrefs = NotificationPrefs()

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: "apns_device_token")
    }

    // Llamado desde HighlightSettings.init() para cachear sin tocar la red
    func updateCache(teams: [String], prefs: NotificationPrefs) {
        lastTeams = teams
        lastPrefs = prefs
    }

    // Llamado por AppDelegate cuando APNs entrega el token
    func setToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        print("[APNs] device token: \(hex)")
        UserDefaults.standard.set(hex, forKey: "apns_device_token")
        deviceToken = hex
        if lastPrefs.enabled && !lastTeams.isEmpty {
            performPost("/register", body: registerBody(token: hex, teams: lastTeams, prefs: lastPrefs))
        }
    }

    // Llamado cuando cambian highlights o prefs (acción del usuario)
    func sync(teams: [String], prefs: NotificationPrefs) {
        lastTeams = teams
        lastPrefs = prefs
        guard let token = deviceToken, !token.isEmpty else { return }
        if prefs.enabled && !teams.isEmpty {
            performPost("/register", body: registerBody(token: token, teams: teams, prefs: prefs))
        } else {
            performPost("/unregister", body: ["deviceToken": token])
        }
    }

    // MARK: Private helpers

    private func registerBody(token: String, teams: [String], prefs: NotificationPrefs) -> [String: Any] {
        ["deviceToken": token,
         "environment": apnsEnv,
         "teams": teams,
         "prefs": [
            "enabled":    prefs.enabled,
            "goals":      prefs.goals,
            "penalties":  prefs.penalties,
            "redCards":   prefs.redCards,
            "startEnd":   prefs.startEnd
         ] as [String: Any]]
    }

    private func performPost(_ path: String, body: [String: Any]) {
        guard let url = URL(string: backendBase + path),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        req.timeoutInterval = 10
        Task {
            try? await URLSession.shared.data(for: req)
        }
    }
}
