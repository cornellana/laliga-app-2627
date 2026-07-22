#!/usr/bin/env python3
"""
Actualización automática de datos de La Liga 2026-27 desde ESPN API.
Diseñado para ejecutarse como GitHub Actions cron job cada 15 min.

Uso manual:
    python3 scripts/update_liga.py
    FORCE_REFRESH=true python3 scripts/update_liga.py
"""

import json
import os
import sys
import requests
from datetime import datetime, timezone, timedelta

# ── Configuración ────────────────────────────────────────────────────────────

ESPN_SCOREBOARD = "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/scoreboard"
ESPN_SUMMARY    = "https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/summary"
DATA_FILE       = os.path.join(os.path.dirname(__file__), "..", "data", "laliga2627.json")
FORCE_REFRESH   = os.environ.get("FORCE_REFRESH", "false").lower() == "true"

TEAM_NAME_MAP = {
    "Real Madrid":        "Real Madrid",
    "Barcelona":          "FC Barcelona",
    "Atletico de Madrid": "Atlético",
    "Athletic Club":      "Athletic",
    "Real Sociedad":      "R. Sociedad",
    "Real Betis":         "Betis",
    "Villarreal":         "Villarreal",
    "Valencia":           "Valencia",
    "Sevilla":            "Sevilla",
    "Osasuna":            "Osasuna",
    "Girona":             "Girona",
    "Getafe":             "Getafe",
    "Celta de Vigo":      "Celta",
    "Rayo Vallecano":     "Rayo",
    "Mallorca":           "Mallorca",
    "Las Palmas":         "Las Palmas",
    "Alaves":             "Alavés",
    "Leganes":            "Leganés",
    "Real Valladolid":    "Valladolid",
    "Espanyol":           "Espanyol",
}

TV_MAP = {
    "DAZN ES": "DAZN",
    "DAZN":    "DAZN",
    "Movistar LaLiga": "MOVISTAR",
    "Movistar+": "MOVISTAR",
    "Gol":     "GOL",
    "La 1":    "TVE",
    "TVE":     "TVE",
}

# ── Utilidades ───────────────────────────────────────────────────────────────

def madrid_date_from_utc(utc_str):
    """Convierte timestamp ESPN UTC a fecha y hora en Madrid."""
    dt = datetime.fromisoformat(utc_str.replace("Z", "+00:00"))
    offset = 2 if dt.month in range(3, 11) else 1
    madrid = dt + timedelta(hours=offset)
    return madrid.strftime("%Y-%m-%d"), madrid.strftime("%H:%M")

def normalize_team(name):
    return TEAM_NAME_MAP.get(name, name)

def match_key(date, home, away):
    return f"{date}|{home}|{away}"

def load_data():
    if not os.path.exists(DATA_FILE):
        return {
            "lastUpdated": "",
            "season": "2026-27",
            "matchDays": [],
            "standings": [],
            "topScorers": []
        }
    with open(DATA_FILE, "r", encoding="utf-8") as f:
        return json.load(f)

def save_data(data):
    data["lastUpdated"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(DATA_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"✓ Guardado: {DATA_FILE}")

# ── ESPN fetching ─────────────────────────────────────────────────────────────

def fetch_scoreboard(date_str):
    """Obtiene partidos para una fecha YYYYMMDD."""
    try:
        resp = requests.get(ESPN_SCOREBOARD, params={"dates": date_str}, timeout=15)
        resp.raise_for_status()
        return resp.json().get("events", [])
    except Exception as e:
        print(f"  Error fetchando scoreboard {date_str}: {e}")
        return []

def fetch_summary(event_id):
    """Obtiene detalles de un partido por su ESPN event ID."""
    try:
        resp = requests.get(ESPN_SUMMARY, params={"event": event_id}, timeout=15)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        print(f"  Error fetchando summary {event_id}: {e}")
        return None

def parse_event(event):
    """Convierte un evento ESPN en un dict de partido."""
    comps = event.get("competitions", [{}])[0]
    competitors = comps.get("competitors", [])

    home_team = away_team = home_score = away_score = None
    for comp in competitors:
        name = normalize_team(comp.get("team", {}).get("displayName", ""))
        score = comp.get("score", "0")
        if comp.get("homeAway") == "home":
            home_team, home_score = name, score
        else:
            away_team, away_score = name, score

    if not home_team or not away_team:
        return None

    status_type = (event.get("status") or {}).get("type") or {}
    completed = status_type.get("completed", False)

    date_str = event.get("date", "")
    date, time = madrid_date_from_utc(date_str) if date_str else ("", "TBD")

    # Jornada (matchweek)
    season_type = event.get("season", {}).get("type", 2)
    week = event.get("week", {}).get("number", 1) if season_type == 2 else 1

    venue = comps.get("venue", {})
    stadium = venue.get("fullName", None)
    city    = (venue.get("address") or {}).get("city", None)

    # TV (broadcasts)
    broadcasts = comps.get("broadcasts", [])
    tv = None
    for b in broadcasts:
        for media in b.get("media", []):
            raw = media.get("shortName", "") or media.get("longName", "")
            tv = TV_MAP.get(raw, raw[:8] if raw else None)
            if tv:
                break
        if tv:
            break

    game = {
        "id":        event.get("id", ""),
        "time":      time,
        "home":      home_team,
        "away":      away_team,
        "jornada":   week,
        "tv":        tv,
        "done":      completed,
        "result":    f"{home_score}-{away_score}" if completed else None,
        "stadium":   stadium,
        "venueCity": city,
        "details":   None,
    }
    return game, date

def parse_summary_details(summary):
    """Extrae detalles del resumen (alineaciones, eventos)."""
    if not summary:
        return None

    events_raw = summary.get("keyEvents", []) or summary.get("commentary", [])
    events = []
    for ev in events_raw:
        ev_type = ev.get("type", {}).get("id", "")
        type_map = {
            "goal":        "GOAL",
            "yellowCard":  "YELLOW_CARD",
            "redCard":     "RED_CARD",
            "substitution":"SUBSTITUTION",
        }
        mapped = type_map.get(ev_type)
        if not mapped:
            continue
        events.append({
            "id":         str(ev.get("id", "")),
            "type":       mapped,
            "minute":     ev.get("clock", {}).get("value", 0),
            "extraTime":  None,
            "playerName": ev.get("athlete", {}).get("displayName"),
            "teamName":   normalize_team(ev.get("team", {}).get("displayName", "")),
            "text":       ev.get("text"),
        })

    # Lineups
    rosters = summary.get("rosters", [])
    home_lineup = away_lineup = None
    for roster in rosters:
        formation = roster.get("formation", {}).get("displayName")
        home_away = roster.get("homeAway", "")
        players = []
        for p in roster.get("athletes", []):
            players.append({
                "id":       str(p.get("athlete", {}).get("id", "")),
                "jersey":   int(p.get("jersey", 0)) if p.get("jersey") else None,
                "name":     p.get("athlete", {}).get("displayName", ""),
                "position": p.get("position", {}).get("abbreviation"),
                "isStarter":p.get("starter", False),
                "events":   None,
            })
        lineup = {"formation": formation, "players": players}
        if home_away == "home":
            home_lineup = lineup
        else:
            away_lineup = lineup

    return {
        "homeLineup": home_lineup,
        "awayLineup": away_lineup,
        "events":     events if events else None,
    }

# ── Proceso principal ─────────────────────────────────────────────────────────

def main():
    data = load_data()

    # Build lookup de partidos existentes para actualizacion incremental
    existing = {}
    for day in data.get("matchDays", []):
        for game in day.get("games", []):
            key = match_key(day["date"], game["home"], game["away"])
            existing[key] = (day["date"], game)

    # Fechas a consultar: hoy ± 4 días para capturar partidos recientes/próximos
    today = datetime.now(timezone.utc)
    dates_to_check = [
        (today + timedelta(days=d)).strftime("%Y%m%d")
        for d in range(-4, 5)
    ]

    changed = False
    new_days = {}

    print(f"Consultando {len(dates_to_check)} fechas...")
    for date_str in dates_to_check:
        events = fetch_scoreboard(date_str)
        for event in events:
            parsed = parse_event(event)
            if not parsed:
                continue
            game, date = parsed
            key = match_key(date, game["home"], game["away"])
            game_id = game.get("id", "")

            # Si ya existe y está finalizado y no forzamos, saltamos
            if key in existing and existing[key][1].get("done") and not FORCE_REFRESH:
                # Mantener detalles existentes
                game["details"] = existing[key][1].get("details")
                if date not in new_days:
                    new_days[date] = []
                if not any(g["home"] == game["home"] and g["away"] == game["away"] for g in new_days[date]):
                    new_days[date].append(game)
                continue

            # Obtener detalles si el partido terminó y tenemos ID
            if game.get("done") and game_id:
                print(f"  Fetchando detalles: {game['home']} vs {game['away']} ({date})")
                summary = fetch_summary(game_id)
                game["details"] = parse_summary_details(summary)

            if date not in new_days:
                new_days[date] = []
            new_days[date].append(game)
            changed = True

    # También conservar días fuera del rango de búsqueda
    for day in data.get("matchDays", []):
        d = day["date"]
        if d not in new_days:
            new_days[d] = day["games"]

    # Construir matchDays ordenados
    match_days_list = []
    for date in sorted(new_days.keys()):
        games = new_days[date]
        if not games:
            continue
        jornada = games[0].get("jornada", 1)
        match_days_list.append({
            "date":    date,
            "jornada": jornada,
            "games":   sorted(games, key=lambda g: g.get("time", "99:99")),
        })

    data["matchDays"] = match_days_list

    if changed or FORCE_REFRESH:
        save_data(data)
        print(f"✓ Actualizado con {len(match_days_list)} días de partido")
    else:
        print("Sin cambios — datos ya actualizados")

if __name__ == "__main__":
    main()
