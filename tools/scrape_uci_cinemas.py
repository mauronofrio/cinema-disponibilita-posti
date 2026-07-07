"""Standalone, rerunnable scraper for UCI Cinemas locations.

Not part of the Flutter app runtime. Run manually whenever the chain opens or
closes a location:

    python tools/scrape_uci_cinemas.py

UCI's showtimes/programming come from one public backend ("myuci") that
knows cinemas by a numeric id/slug, while the seat map comes from a
*different* public backend (a WebTic Api2 proxy) that knows the very same
cinemas by an unrelated "LocalId". Neither system's id lines up with the
other's, so this script fetches both lists and matches entries by nearest
coordinates (they're the same physical address, just entered independently
into two systems - a few tenths of a degree apart in these two sources,
nowhere near enough to be confused with a different cinema).

Merges into assets/cinemas.json alongside The Space Cinema entries (see
scrape_cinemas.py), leaving those untouched.

Matching is done by normalized name, not coordinates: the two systems were
geocoded independently and can disagree by tens of kilometres for the exact
same address (seen for real on 3 of 33 cinemas), while the name each system
uses for a given cinema is otherwise identical bar punctuation ("UCI Cinemas
Meridiana | Bologna" vs "UCI Cinemas Meridiana  Bologna").
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.request import Request, urlopen

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)
MYUCI_THEATRES_URL = "https://myuci---uci-backend-production-nfluwp7wga-oc.a.run.app/api/theatres"
WEBTIC_LOCALS_URL = "https://uci-website-webtic-proxy-production-1042268733238.europe-west8.run.app/Api2/Locals"
WEBTIC_LOCAL_GROUP_ID = "2378"

# Fallback only, for the rare cinema whose name doesn't line up between the
# two systems - generous because the two were geocoded independently and can
# legitimately disagree by tens of kilometres for the very same address.
MAX_FALLBACK_DISTANCE_DEG = 0.5

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "assets" / "cinemas.json"

_TAG_RE = re.compile(r"<[^>]+>")


def fetch_json(url: str, *, body: bytes | None = None) -> dict:
    headers = {"User-Agent": USER_AGENT, "Content-Type": "application/json"}
    request = Request(url, data=body, headers=headers)
    with urlopen(request, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def clean_address(html_address: str) -> str:
    return _TAG_RE.sub("", html_address).strip()


def normalize_name(name: str) -> str:
    name = name.replace("UCI Cinemas", "").replace("|", " ")
    name = re.sub(r"\s+", " ", name).strip().lower()
    return name


def fetch_theatres() -> list[dict]:
    data = fetch_json(MYUCI_THEATRES_URL)
    return data["data"]


def fetch_locals() -> list[dict]:
    body = json.dumps({"LocalGroupId": WEBTIC_LOCAL_GROUP_ID}).encode("utf-8")
    data = fetch_json(WEBTIC_LOCALS_URL, body=body)
    return data["Data"]["Locals"]


def find_local(theatre: dict, locals_: list[dict]) -> dict | None:
    target_name = normalize_name(theatre["name"])
    for local in locals_:
        if normalize_name(local["Description"]) == target_name:
            return local

    # Fallback for the odd cinema whose name doesn't line up between the two
    # systems: nearest by coordinates, generously thresholded.
    t_lat, t_lng = float(theatre["latitude"]), float(theatre["longitude"])
    best, best_dist = None, MAX_FALLBACK_DISTANCE_DEG
    for local in locals_:
        l_lat, l_lng = float(local["Latitude"]), float(local["Longitude"])
        dist = ((t_lat - l_lat) ** 2 + (t_lng - l_lng) ** 2) ** 0.5
        if dist < best_dist:
            best, best_dist = local, dist
    return best


def main() -> None:
    print(f"Fetching {MYUCI_THEATRES_URL}")
    theatres = fetch_theatres()
    print(f"Found {len(theatres)} myuci theatres")

    print(f"Fetching {WEBTIC_LOCALS_URL}")
    locals_ = fetch_locals()
    print(f"Found {len(locals_)} WebTic locals")

    cinemas = []
    for theatre in theatres:
        local = find_local(theatre, locals_)
        if local is None:
            print(
                f"  ! no WebTic match for {theatre['name']!r} "
                f"(seat maps won't work for this cinema)",
                file=sys.stderr,
            )
        cinemas.append(
            {
                "cinemaId": theatre["slug"],
                "name": theatre["name"].replace(" | ", " – "),
                "slug": theatre["slug"],
                "address": clean_address(theatre["address"]),
                "lat": float(theatre["latitude"]),
                "lng": float(theatre["longitude"]),
                "chain": "uci",
                "webticLocalId": local["LocalId"] if local else None,
            }
        )

    existing: list[dict] = []
    if OUTPUT_PATH.exists():
        existing = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
    other_chains = [c for c in existing if c.get("chain", "theSpace") != "uci"]
    merged = other_chains + cinemas
    merged.sort(key=lambda c: c["name"])
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(cinemas)} UCI cinemas ({len(merged)} total) to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
