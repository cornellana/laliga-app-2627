#!/usr/bin/env python3
"""
Fetches top scorers for a historical La Liga season by parsing goal events
from ESPN match summaries. Uses concurrent requests for speed.
Usage: python3 scripts/fetch_scorers.py 2024   # (for 24/25 season)
       python3 scripts/fetch_scorers.py 2025   # (for 25/26 season)
"""
import json, sys, re, os
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.request import urlopen
from collections import defaultdict

SEASON_CODE = {"2024": "2425", "2025": "2526"}

TEAM_NAME_MAP = {
    "FC Barcelona": "FC Barcelona",
    "Barcelona": "FC Barcelona",
    "Real Madrid": "Real Madrid",
    "Atletico de Madrid": "Atlético",
    "Atlético de Madrid": "Atlético",
    "Atletico Madrid": "Atlético",
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
    "Cádiz": "Cádiz",
    "Granada CF": "Granada",
    "Granada": "Granada",
    "UD Almería": "Almería",
    "Almería": "Almería",
    "Real Oviedo": "Real Oviedo",
}

def normalize_team(name):
    return TEAM_NAME_MAP.get(name, name)

# Format: "Goal! Team A N, Team B M. Player Name (ESPN Team Name) description"
GOAL_FULL_RE = re.compile(r'Goal!.*?\.\s+(.+?)\s+\(([^)]+)\)', re.IGNORECASE)
OWN_GOAL_MARKER_RE = re.compile(r'own goal', re.IGNORECASE)
PENALTY_MARKER_RE = re.compile(r'\(penalty\)|\bpenalty goal\b', re.IGNORECASE)

def fetch_summary(event_id):
    url = f"https://site.api.espn.com/apis/site/v2/sports/soccer/esp.1/summary?event={event_id}"
    try:
        with urlopen(url, timeout=10) as r:
            return json.loads(r.read())
    except Exception:
        return None

def parse_goals(summary):
    """Returns list of (player_name, app_team_name, is_own_goal, is_penalty)"""
    goals = []
    events = summary.get("keyEvents", [])
    for e in events:
        type_id = str(e.get("type", {}).get("id", ""))
        # 70=gol normal, 72=en propia, 98=penalti
        if type_id not in ("70", "72", "98"):
            continue
        text = e.get("text", "")
        m = GOAL_FULL_RE.search(text)
        if not m:
            continue
        player = m.group(1).strip()
        espn_team = m.group(2).strip()
        app_team = normalize_team(espn_team)
        is_own = type_id == "72" or bool(OWN_GOAL_MARKER_RE.search(text))
        is_pen = type_id == "98" or bool(PENALTY_MARKER_RE.search(text))
        goals.append((player, app_team, is_own, is_pen))
    return goals

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 fetch_scorers.py 2024|2025")
        sys.exit(1)

    espn_year = sys.argv[1]
    code = SEASON_CODE.get(espn_year)
    if not code:
        print(f"Unknown year: {espn_year}. Use 2024 or 2025.")
        sys.exit(1)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(script_dir, "..", "data")
    seed_dir = os.path.join(script_dir, "..", "27")
    json_path = os.path.join(data_dir, f"laliga{code}.json")

    with open(json_path) as f:
        data = json.load(f)

    matches = [g for md in data["matchDays"] for g in md["games"]
               if g.get("espnEventID") and g.get("done")]
    print(f"🔄 Fetching summaries for {len(matches)} matches (LaLiga {code})...")

    goals_by_player = defaultdict(lambda: {"goals": 0, "penalties": 0, "team": None})
    failed = 0

    with ThreadPoolExecutor(max_workers=15) as executor:
        futures = {executor.submit(fetch_summary, g["espnEventID"]): g for g in matches}
        done = 0
        for future in as_completed(futures):
            done += 1
            if done % 50 == 0:
                print(f"  [{done}/{len(matches)}]")
            summary = future.result()
            if not summary:
                failed += 1
                continue
            for player, team, is_own, is_pen in parse_goals(summary):
                if is_own:
                    continue
                entry = goals_by_player[player]
                entry["goals"] += 1
                if is_pen:
                    entry["penalties"] += 1
                if team and not entry["team"]:
                    entry["team"] = team

    print(f"  ✓ Done. Failed: {failed}")

    top_scorers = []
    for player, stats in goals_by_player.items():
        if stats["goals"] < 1:
            continue
        top_scorers.append({
            "player": player,
            "team": stats["team"] or "?",
            "goals": stats["goals"],
            "penalties": stats["penalties"] if stats["penalties"] > 0 else None,
        })

    top_scorers.sort(key=lambda x: (-x["goals"], x["player"]))
    print(f"\n🏆 Top 10 goleadores:")
    for i, s in enumerate(top_scorers[:10], 1):
        pen = f" ({s['penalties']} pen)" if s.get("penalties") else ""
        print(f"  {i:2}. {s['player']} ({s['team']}) — {s['goals']} goles{pen}")

    for s in top_scorers:
        if s["penalties"] is None:
            del s["penalties"]

    data["topScorers"] = top_scorers
    out = json.dumps(data, ensure_ascii=False, indent=2)
    with open(json_path, "w") as f:
        f.write(out)
    seed_path = os.path.join(seed_dir, f"laliga{code}-seed.json")
    with open(seed_path, "w") as f:
        f.write(out)
    print(f"\n💾 Updated: {json_path}")
    print(f"🌱 Seed: {seed_path} ({len(out)//1024} KB, {len(top_scorers)} goleadores)")

if __name__ == "__main__":
    main()
