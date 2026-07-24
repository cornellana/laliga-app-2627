#!/usr/bin/env python3
"""
fetch_season.py — Genera datos históricos de LaLiga desde la ESPN API.

Uso:
    python3 scripts/fetch_season.py 2024   # LaLiga 2024-25 → data/laliga2425.json
    python3 scripts/fetch_season.py 2025   # LaLiga 2025-26 → data/laliga2526.json
"""

import json, time, datetime, sys, os
import urllib.request, urllib.error

LEAGUE = "esp.1"
BASE = f"https://site.api.espn.com/apis/site/v2/sports/soccer/{LEAGUE}"

SEASON_DATES = {
    2024: ("2024-08-01", "2025-06-15"),
    2025: ("2025-08-01", "2026-06-15"),
}

# Normalización de nombres ESPN → nombres en la app
TEAM_NAME_MAP = {
    "FC Barcelona": "FC Barcelona",
    "Real Madrid": "Real Madrid",
    "Atletico de Madrid": "Atlético",
    "Atlético de Madrid": "Atlético",
    "Athletic Club": "Athletic",
    "Athletic Club Bilbao": "Athletic",
    "Real Sociedad": "R. Sociedad",
    "Real Betis": "Betis",
    "Real Betis Balompié": "Betis",
    "Villarreal CF": "Villarreal",
    "Valencia CF": "Valencia",
    "Valencia": "Valencia",
    "Sevilla FC": "Sevilla",
    "CA Osasuna": "Osasuna",
    "Osasuna": "Osasuna",
    "RC Celta de Vigo": "Celta",
    "Celta de Vigo": "Celta",
    "Celta Vigo": "Celta",
    "Getafe CF": "Getafe",
    "Getafe": "Getafe",
    "Rayo Vallecano": "Rayo",
    "Deportivo Alavés": "Alavés",
    "Alavés": "Alavés",
    "RCD Espanyol": "Espanyol",
    "Espanyol": "Espanyol",
    "Levante UD": "Levante",
    "Levante": "Levante",
    "Racing de Santander": "Racing",
    "Racing Santander": "Racing",
    "RC Deportivo de La Coruña": "Deportivo",
    "Deportivo de La Coruña": "Deportivo",
    "Deportivo": "Deportivo",
    "Elche CF": "Elche",
    "Elche": "Elche",
    "Málaga CF": "Málaga",
    "Málaga": "Málaga",
    # Equipos históricos temporadas 24-25 y 25-26
    "RCD Mallorca": "Mallorca",
    "Mallorca": "Mallorca",
    "UD Las Palmas": "Las Palmas",
    "Las Palmas": "Las Palmas",
    "Girona FC": "Girona",
    "Girona": "Girona",
    "Real Valladolid": "Valladolid",
    "Valladolid": "Valladolid",
    "CD Leganés": "Leganés",
    "Leganés": "Leganés",
    "Cádiz CF": "Cádiz",
    "Cadiz CF": "Cádiz",
    "Cádiz": "Cádiz",
    "Granada CF": "Granada",
    "Granada": "Granada",
    "UD Almería": "Almería",
    "Almería": "Almería",
    "CD Alavés": "Alavés",
    "Real Sporting de Gijón": "Sporting",
    "Sporting de Gijón": "Sporting",
    "SD Huesca": "Huesca",
    "Real Zaragoza": "Zaragoza",
}


def normalize_team(name: str) -> str:
    return TEAM_NAME_MAP.get(name, name)


def fetch_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 LaLigaApp/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def parse_minute(clock_str: str) -> tuple[int, int | None]:
    """Parses '27'', '45'+2'' → (minute, extraTime)."""
    clean = clock_str.replace("'", "").strip()
    if "+" in clean:
        parts = clean.split("+", 1)
        return int(parts[0]) if parts[0].isdigit() else 0, int(parts[1]) if parts[1].isdigit() else None
    return int(clean) if clean.isdigit() else 0, None


def fetch_season(year: int):
    start_str, end_str = SEASON_DATES[year]
    start = datetime.date.fromisoformat(start_str)
    end = datetime.date.fromisoformat(end_str)

    date_to_matches: dict[str, list] = {}
    team_ids: dict[int, str] = {}  # ESPN team ID → app name

    current = start
    total_days = (end - start).days
    processed = 0

    while current <= end:
        date_str = current.strftime("%Y%m%d")
        url = f"{BASE}/scoreboard?dates={date_str}&lang=es&region=es"

        try:
            data = fetch_json(url)
            events = data.get("events", [])

            for event in events:
                # Only include events of the target season year
                ev_year = event.get("season", {}).get("year")
                if ev_year and ev_year != year:
                    continue

                comps = event.get("competitions", [{}])
                if not comps:
                    continue
                comp = comps[0]

                competitors = comp.get("competitors", [])
                if len(competitors) < 2:
                    continue

                home = next((c for c in competitors if c.get("homeAway") == "home"), competitors[0])
                away = next((c for c in competitors if c.get("homeAway") == "away"), competitors[1])

                home_display = home.get("team", {}).get("displayName", "")
                away_display = away.get("team", {}).get("displayName", "")
                home_name = normalize_team(home_display)
                away_name = normalize_team(away_display)

                if not home_name or not away_name:
                    continue

                # Recoger IDs de equipo para los logos
                home_tid = home.get("team", {}).get("id")
                away_tid = away.get("team", {}).get("id")
                if home_tid:
                    team_ids[int(home_tid)] = home_name
                if away_tid:
                    team_ids[int(away_tid)] = away_name

                status = comp.get("status", {}).get("type", {})
                is_done = status.get("completed", False)

                home_score = int(home.get("score", 0) or 0) if is_done else None
                away_score = int(away.get("score", 0) or 0) if is_done else None
                result = f"{home_score}-{away_score}" if is_done and home_score is not None else None

                # Hora en Madrid (UTC+1 invierno / UTC+2 verano)
                event_date = event.get("date", "")
                match_time = ""
                if event_date:
                    try:
                        dt_utc = datetime.datetime.fromisoformat(event_date.replace("Z", "+00:00"))
                        month = dt_utc.month
                        offset = 2 if 3 <= month <= 10 else 1
                        dt_madrid = dt_utc + datetime.timedelta(hours=offset)
                        match_time = dt_madrid.strftime("%H:%M")
                    except Exception:
                        pass

                match = {
                    "id": event.get("id", ""),
                    "time": match_time,
                    "home": home_name,
                    "away": away_name,
                    "jornada": 0,
                    "tv": None,
                    "done": is_done,
                    "result": result,
                    "details": None,
                    "stadium": comp.get("venue", {}).get("fullName"),
                    "venueCity": comp.get("venue", {}).get("address", {}).get("city"),
                    "espnEventID": event.get("id"),
                }

                d_key = current.isoformat()
                if d_key not in date_to_matches:
                    date_to_matches[d_key] = []
                date_to_matches[d_key].append(match)

        except urllib.error.URLError as e:
            print(f"  ⚠ Error fetching {date_str}: {e}")
        except Exception as e:
            print(f"  ⚠ Parse error {date_str}: {e}")

        current += datetime.timedelta(days=1)
        processed += 1
        time.sleep(0.08)  # rate limiting

        # Progreso mensual
        if current.day == 1:
            total_matches = sum(len(v) for v in date_to_matches.values())
            pct = processed * 100 // total_days
            print(f"  [{pct:3d}%] hasta {current.strftime('%b %Y')} — {total_matches} partidos")

    return date_to_matches, team_ids


def assign_jornadas(date_to_matches: dict) -> list[dict]:
    """
    Agrupa fechas en jornadas. Una jornada nueva empieza cuando:
    - El salto entre fechas consecutivas es > 4 días, O
    - La jornada actual ya tiene ≥ 10 partidos (jornada completa LaLiga = 10)
    """
    sorted_dates = sorted(date_to_matches.keys())
    if not sorted_dates:
        return []

    jornada_groups: list[list[str]] = [[sorted_dates[0]]]
    current_count = len(date_to_matches[sorted_dates[0]])

    for i in range(1, len(sorted_dates)):
        prev_d = datetime.date.fromisoformat(sorted_dates[i - 1])
        curr_d = datetime.date.fromisoformat(sorted_dates[i])
        gap = (curr_d - prev_d).days

        if gap > 4 or current_count >= 10:
            jornada_groups.append([sorted_dates[i]])
            current_count = len(date_to_matches[sorted_dates[i]])
        else:
            jornada_groups[-1].append(sorted_dates[i])
            current_count += len(date_to_matches[sorted_dates[i]])

    # Construir match days
    match_days = []
    for jornada_num, dates in enumerate(jornada_groups, 1):
        for date_str in sorted(dates):
            games = date_to_matches[date_str]
            for g in games:
                g["jornada"] = jornada_num
            match_days.append({
                "date": date_str,
                "jornada": jornada_num,
                "games": games,
            })

    return match_days


def main():
    if len(sys.argv) < 2 or not sys.argv[1].isdigit():
        print("Uso: python3 scripts/fetch_season.py 2024")
        sys.exit(1)

    year = int(sys.argv[1])
    if year not in SEASON_DATES:
        print(f"Temporada no soportada: {year}. Usa 2024 o 2025.")
        sys.exit(1)

    next_year = year + 1
    code = f"{str(year)[2:]}{str(next_year)[2:]}"  # "2425" o "2526"

    print(f"\n🔄 Fetching LaLiga {year}-{next_year} desde ESPN API...")
    date_to_matches, team_ids = fetch_season(year)

    total_matches = sum(len(v) for v in date_to_matches.values())
    print(f"\n✅ Total partidos: {total_matches}")
    print(f"📅 Fechas con partidos: {len(date_to_matches)}")

    match_days = assign_jornadas(date_to_matches)
    jornada_count = len(set(d["jornada"] for d in match_days))
    print(f"📋 Jornadas detectadas: {jornada_count}")

    print(f"\n🏟 Equipos y ESPN IDs:")
    for tid, name in sorted(team_ids.items(), key=lambda x: x[1]):
        print(f"  \"{name}\": {tid},")

    snapshot = {
        "lastUpdated": datetime.date.today().isoformat(),
        "season": f"{year}-{next_year}",
        "matchDays": match_days,
        "standings": [],
        "topScorers": [],
    }

    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(script_dir, "..", "data")
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, f"laliga{code}.json")

    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, separators=(",", ":"))

    size_kb = os.path.getsize(out_file) // 1024
    print(f"\n💾 Guardado en {out_file} ({size_kb} KB)")

    # Seed (copia sin detalles — ya los tiene el snapshot)
    seed_dir = os.path.join(script_dir, "..", "27")
    seed_file = os.path.join(seed_dir, f"laliga{code}-seed.json")
    with open(seed_file, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, separators=(",", ":"))
    seed_kb = os.path.getsize(seed_file) // 1024
    print(f"🌱 Seed en {seed_file} ({seed_kb} KB)")


if __name__ == "__main__":
    main()
