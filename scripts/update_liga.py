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
import unicodedata
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

# ESPN identifica los keyEvents con ids numéricos, no con nombres.
# Los goles no tienen un id fijo (hay 6 variantes), se detectan con `scoringPlay`.
NON_GOAL_TYPE_IDS = {
    "76": "SUBSTITUTION",
    "94": "YELLOW_CARD",
    "95": "RED_CARD",
    "96": "RED_CARD",
}
OWN_GOAL_TYPE_ID = "97"
PENALTY_TYPE_ID  = "98"

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

def fold(s):
    """Minúsculas sin tildes, para comparar nombres de equipo."""
    return "".join(
        c for c in unicodedata.normalize("NFKD", (s or "").lower())
        if not unicodedata.combining(c)
    )

def resolve_team(espn_name, home, away):
    """Mapea el nombre de equipo de ESPN al nombre usado en la app."""
    if not espn_name:
        return None
    n = fold(normalize_team(espn_name))
    for team in (home, away):
        t = fold(team)
        if t and (t == n or t in n or n in t):
            return team
    return espn_name

def parse_clock(display):
    """'90'+9'' -> (90, 9);  '23'' -> (23, None);  '' -> (0, None)."""
    clean = (display or "").replace("'", "").strip()
    if not clean:
        return 0, None
    if "+" in clean:
        base, _, extra = clean.partition("+")
        base, extra = base.strip(), extra.strip()
        return (int(base) if base.isdigit() else 0,
                int(extra) if extra.isdigit() else None)
    return (int(clean) if clean.isdigit() else 0), None

def team_from_text(text, type_id):
    """ESPN deja `team` a null en muchos eventos; el nombre va dentro del texto."""
    if not text:
        return None
    if type_id == "76" and text.startswith("Substitution, "):
        return text[len("Substitution, "):].split(". ")[0] or None
    if type_id in ("94", "95", "96") and "(" in text and ")" in text:
        return text[text.index("(") + 1:text.index(")")] or None
    return None

def extract_player(text, type_id):
    """ESPN deja `athlete` a null en los keyEvents; el jugador va dentro del texto."""
    if not text:
        return None
    if type_id == OWN_GOAL_TYPE_ID:
        if text.lower().startswith("own goal by "):
            after = text[len("Own Goal by "):]
            return after.split(",")[0].strip() or None
        return None
    if type_id == "76":
        parts = text.split(". ")
        if len(parts) > 1:
            return parts[1].split(" replaces ")[0].strip() or None
        return None
    if type_id in ("94", "95", "96"):
        if "(" in text:
            return text[:text.index("(")].strip() or None
        return None
    # Goles: "Goal! Alavés 1, Getafe 0. Jugador (Alavés) right footed shot..."
    parts = text.split(". ")
    if len(parts) > 1:
        after_score = ". ".join(parts[1:])
        if "(" in after_score:
            return after_score[:after_score.index("(")].strip() or None
    return None

def build_jornada_index(data):
    """(local, visitante) -> jornada, tomado del calendario ya guardado.

    ESPN dejó de exponer `week` en el scoreboard de LaLiga, así que la jornada
    se recupera del JSON existente, que tiene el calendario completo 1-38.
    """
    index = {}
    for day in data.get("matchDays", []):
        for game in day.get("games", []):
            jornada = game.get("jornada")
            if jornada:
                index[(game.get("home"), game.get("away"))] = jornada
    return index

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

def parse_event(event, jornada_index):
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

    # Jornada (matchweek): ESPN ya no la publica, se recupera del calendario guardado
    week = jornada_index.get((home_team, away_team))
    if week is None:
        raw_week = event.get("week")
        if isinstance(raw_week, dict):
            week = raw_week.get("number")
    if week is None:
        week = 1
        print(f"  ⚠️  Jornada desconocida para {home_team} vs {away_team}, usando 1")

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

def parse_summary_details(summary, home, away):
    """Extrae detalles del resumen (alineaciones, eventos)."""
    if not summary:
        return None

    events = []
    for idx, ev in enumerate(summary.get("keyEvents") or []):
        type_id = str(((ev.get("type") or {}).get("id")) or "")
        is_goal = ev.get("scoringPlay") is True
        if not is_goal and type_id not in NON_GOAL_TYPE_IDS:
            continue

        text = ev.get("text")
        if is_goal:
            if type_id == OWN_GOAL_TYPE_ID or (text or "").lower().startswith("own goal"):
                mapped = "OWN_GOAL"
            elif type_id == PENALTY_TYPE_ID:
                mapped = "PENALTY"
            else:
                mapped = "GOAL"
        else:
            mapped = NON_GOAL_TYPE_IDS[type_id]

        minute, extra_time = parse_clock((ev.get("clock") or {}).get("displayValue"))
        raw_team = team_from_text(text, type_id) or (ev.get("team") or {}).get("displayName")

        # En los cambios, guardar solo el jugador que entra como texto auxiliar
        short_text = None
        if type_id == "76" and text:
            parts = text.split(". ")
            if len(parts) > 1:
                sub = parts[1].split(" replaces ")
                if len(sub) > 1:
                    short_text = sub[1].strip().strip(".,;:!?") or None

        events.append({
            "id":         f"{ev.get('id', '')}_{idx}",
            "type":       mapped,
            "minute":     minute,
            "extraTime":  extra_time,
            "playerName": extract_player(text, type_id),
            "teamName":   resolve_team(raw_team, home, away),
            "text":       short_text,
        })

    # Lineups
    home_lineup = away_lineup = None
    for roster in summary.get("rosters") or []:
        # ESPN devuelve `formation` como string plano ("3-5-2"), no como objeto
        raw_formation = roster.get("formation")
        formation = (raw_formation.get("displayName")
                     if isinstance(raw_formation, dict) else raw_formation)

        players = []
        for p in (roster.get("roster") or roster.get("athletes") or []):
            athlete = p.get("athlete") or {}
            name = athlete.get("displayName") or athlete.get("fullName") or ""
            if not name:
                continue
            jersey = p.get("jersey")
            players.append({
                "id":        str(athlete.get("id", "")),
                "jersey":    int(jersey) if str(jersey or "").isdigit() else None,
                "name":      name,
                "position":  (p.get("position") or {}).get("abbreviation"),
                "isStarter": bool(p.get("starter", False)),
                "events":    None,
            })

        lineup = {"formation": formation, "players": players}
        if roster.get("homeAway") == "home":
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
    jornada_index = build_jornada_index(data)

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
            try:
                parsed = parse_event(event, jornada_index)
            except Exception as e:
                print(f"  ⚠️  Evento ESPN ilegible en {date_str}: {e}")
                continue
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

            # Obtener detalles si el partido terminó y tenemos ID.
            # Nunca debe abortar el run: el marcador es más importante que los detalles.
            if game.get("done") and game_id:
                print(f"  Fetchando detalles: {game['home']} vs {game['away']} ({date})")
                try:
                    summary = fetch_summary(game_id)
                    game["details"] = parse_summary_details(summary, game["home"], game["away"])
                except Exception as e:
                    print(f"  ⚠️  Detalles no parseables ({game['home']} vs {game['away']}): {e}")
                    game["details"] = existing[key][1].get("details") if key in existing else None

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
        # Jornada del día = la más frecuente entre sus partidos (hay días a caballo
        # entre dos jornadas y games[0] no siempre es representativo)
        counts = {}
        for g in games:
            j = g.get("jornada", 1)
            counts[j] = counts.get(j, 0) + 1
        jornada = max(counts, key=counts.get)
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
