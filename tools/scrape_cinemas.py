"""Standalone, rerunnable scraper for The Space Cinema locations.

Not part of the Flutter app runtime. Run manually whenever the chain opens or
closes a location:

    python tools/scrape_cinemas.py

It fetches the public sitemap, finds every cinema "al cinema" page, pulls the
cinema id/name/address/coordinates out of each page's embedded Next.js
__NEXT_DATA__ JSON, and writes the consolidated list to assets/cinemas.json.
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path
from urllib.request import Request, urlopen

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Safari/537.36"
)
SITEMAP_URL = "https://www.thespacecinema.it/sitemap.xml"
# Slug charset includes "'" - the Roma Parco de' Medici page's own slug is
# "roma-parco-de'medici" (confirmed live), which the old [a-z0-9-]+ charset
# silently dropped even though the URL was present in the sitemap.
CINEMA_PAGE_RE = re.compile(r"https://www\.thespacecinema\.it/cinema/([a-z0-9'-]+)/al-cinema")
NEXT_DATA_RE = re.compile(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', re.S
)

# Known cinema pages that are live but, confirmed live, not linked from the
# sitemap at all (e.g. the Torino/Parco Dora location) - fetched in addition
# to whatever the sitemap yields so a re-run doesn't silently drop them again.
EXTRA_SLUGS = ["torino"]

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "assets" / "cinemas.json"


def fetch(url: str) -> str:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=20) as response:
        return response.read().decode("utf-8", errors="ignore")


def parse_cinema(slug: str, html: str) -> dict | None:
    match = NEXT_DATA_RE.search(html)
    if not match:
        print(f"  ! no __NEXT_DATA__ found for {slug}, skipping", file=sys.stderr)
        return None
    try:
        data = json.loads(match.group(1))
        cinema = data["props"]["pageProps"]["layoutData"]["sitecore"]["context"]["cinema"]
        lat_str, lng_str = cinema["cinemaLocationCoordinates"]["value"].split(",")
        return {
            "cinemaId": cinema["cinemaId"]["value"],
            "name": cinema["cinemaName"]["value"],
            "slug": slug,
            "address": cinema["cinemaAddress"]["value"],
            "lat": float(lat_str.strip()),
            "lng": float(lng_str.strip()),
            "chain": "theSpace",
        }
    except (KeyError, ValueError, json.JSONDecodeError) as exc:
        print(f"  ! failed to parse cinema data for {slug}: {exc}", file=sys.stderr)
        return None


def main() -> None:
    print(f"Fetching sitemap: {SITEMAP_URL}")
    sitemap = fetch(SITEMAP_URL)
    slugs = sorted(set(CINEMA_PAGE_RE.findall(sitemap)) | set(EXTRA_SLUGS))
    print(f"Found {len(slugs)} cinema pages")

    cinemas = []
    for slug in slugs:
        url = f"https://www.thespacecinema.it/cinema/{slug}/al-cinema"
        print(f"  fetching {url}")
        try:
            html = fetch(url)
        except Exception as exc:  # network hiccups shouldn't abort the whole run
            print(f"  ! failed to fetch {slug}: {exc}", file=sys.stderr)
            continue
        cinema = parse_cinema(slug, html)
        if cinema:
            cinemas.append(cinema)
        time.sleep(0.4)

    # Merge into the existing file rather than overwrite it outright - UCI
    # Cinemas entries (written by scrape_uci_cinemas.py) live in the same
    # file and must survive a re-run of this script.
    existing: list[dict] = []
    if OUTPUT_PATH.exists():
        existing = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
    other_chains = [c for c in existing if c.get("chain", "theSpace") != "theSpace"]
    merged = other_chains + cinemas
    merged.sort(key=lambda c: c["name"])
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Wrote {len(cinemas)} The Space cinemas ({len(merged)} total) to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
