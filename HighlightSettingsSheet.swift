import SwiftUI
import UserNotifications

// MARK: - Highlight Settings Sheet

struct HighlightSettingsSheet: View {
    @Bindable var settings: HighlightSettings
    let allTeams: [String]

    @State private var showingAddTeam = false
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    private var availableTeams: [String] {
        let highlighted = Set(settings.highlights.map(\.team))
        return allTeams.filter { !highlighted.contains($0) }
    }

    /// Versión y número de build, como los deja Xcode en el Info.plist.
    ///
    /// Van juntos porque la versión sola no distingue nada: se queda en 1.1
    /// durante muchas compilaciones. Repartiendo la app por Ad Hoc no hay ficha
    /// de la tienda ni TestFlight que diga qué build tiene instalada el
    /// probador, así que o lo dice la app o no lo dice nadie.
    private var versionInstalada: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Equipos resaltados
                Section {
                    if settings.highlights.isEmpty {
                        Text("Ningún equipo resaltado")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach($settings.highlights) { $highlight in
                            HighlightRow(highlight: $highlight)
                        }
                        .onDelete { settings.remove(at: $0) }
                    }
                } header: {
                    Text("Equipos resaltados")
                } footer: {
                    Text("Los partidos de estos equipos aparecen con fondo de color. Puedes añadir varios equipos con colores distintos.")
                        .font(.caption)
                }

                Section {
                    Button {
                        showingAddTeam = true
                    } label: {
                        Label("Añadir equipo", systemImage: "plus.circle.fill")
                    }
                    .disabled(availableTeams.isEmpty)
                }

                // MARK: Avisos
                Section {
                    Toggle("Activar avisos", isOn: $settings.notifications.enabled)

                    if settings.notifications.enabled {
                        Toggle("Goles", isOn: $settings.notifications.goals)
                        Toggle("Penaltis", isOn: $settings.notifications.penalties)
                        Toggle("Expulsiones", isOn: $settings.notifications.redCards)
                        Toggle("Inicio y final", isOn: $settings.notifications.startEnd)
                    }

                    if authStatus == .denied {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.slash.fill")
                                .foregroundStyle(.orange)
                            Text("Sin permiso de notificaciones")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                        Button("Activar en Ajustes del sistema") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Avisos")
                } footer: {
                    Text("Recibirás avisos de los partidos de tus equipos resaltados, aunque la app esté cerrada.")
                        .font(.caption)
                }

                // MARK: Acerca de
                Section {
                    LabeledContent("Versión") {
                        Text(verbatim: versionInstalada)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Acerca de")
                }
            }
            .navigationTitle("Resaltado de equipos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $showingAddTeam) {
                AddHighlightSheet(teams: availableTeams) { team, color in
                    settings.add(team: team, color: color)
                }
            }
            .task {
                let s = await UNUserNotificationCenter.current().notificationSettings()
                authStatus = s.authorizationStatus
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Highlight Row

private struct HighlightRow: View {
    @Binding var highlight: TeamHighlight

    @State private var pickerColor: Color = .blue

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(highlight.color)
                .frame(width: 4, height: 36)

            TeamLogoView(teamName: highlight.team, size: 32)

            Text(highlight.team)
                .foregroundStyle(.white)
                .font(.subheadline)

            Spacer()

            ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34, height: 34)
                .onChange(of: pickerColor) { _, newColor in
                    highlight.colorHex = newColor.toHex()
                }
        }
        .padding(.vertical, 4)
        .onAppear { pickerColor = highlight.color }
    }
}

// MARK: - Add Highlight Sheet

struct AddHighlightSheet: View {
    let teams: [String]
    let onAdd: (String, Color) -> Void

    @State private var selectedTeam: String = ""
    @State private var selectedColor: Color = Color(hex: 0x004D98)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Equipo") {
                    Picker("Equipo", selection: $selectedTeam) {
                        Text("Seleccionar...").tag("")
                        ForEach(teams, id: \.self) { team in
                            HStack {
                                TeamLogoView(teamName: team, size: 24)
                                Text(team)
                            }
                            .tag(team)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Color de resaltado") {
                    ColorPicker("Color del equipo", selection: $selectedColor, supportsOpacity: false)

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(selectedColor)
                            .frame(width: 4, height: 40)
                        if !selectedTeam.isEmpty {
                            TeamLogoView(teamName: selectedTeam, size: 28)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedTeam.isEmpty ? "Nombre equipo" : selectedTeam)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(selectedColor.opacity(0.9))
                            Text("Equipo rival")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .background(selectedColor.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            .navigationTitle("Añadir resaltado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Añadir") {
                        guard !selectedTeam.isEmpty else { return }
                        onAdd(selectedTeam, selectedColor)
                        dismiss()
                    }
                    .disabled(selectedTeam.isEmpty)
                    .bold()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            selectedTeam = teams.first ?? ""
        }
    }
}

#Preview {
    HighlightSettingsSheet(
        settings: HighlightSettings(),
        allTeams: ["FC Barcelona", "Real Madrid", "Atlético", "Athletic", "Betis"]
    )
}
