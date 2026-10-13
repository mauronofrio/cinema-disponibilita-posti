"""Builds the 2Tickets.it part of assets/cinemas.json.

2Tickets publishes no venue list and no coordinates (confirmed 13 Oct 2026),
so venues are discovered from the films currently on sale - every film's
detail page lists each venue showing it - and geocoded once via
OpenStreetMap Nominatim. Results are MERGED into the existing catalog,
never replacing it: a venue with nothing on sale today keeps its entry
from an earlier run. Pass extra venue ids by hand for venues known to
exist but not currently discoverable:

    python tools/scrape_twotickets_cinemas.py 609

A venue is included only if it has at least one CINEMA title
(link settore=C and tag "CINEMA") - pure theatres are skipped. Never
filter by name: "Cine Teatro Norba" and "Cinema Teatro Orfeo" are cinemas.

Polite by design: one request per second to 2Tickets, and Nominatim's own
1 req/s policy. Reads nothing but public GET pages.
"""

import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request

BASE = "https://www.2tickets.it/biglietto"
CATALOG = "assets/cinemas.json"
UA_SITE = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
           "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
UA_GEO = ("CinemaDisponibilitaPosti-catalog/1.0 "
          "(github.com/mauronofrio/cinema-disponibilita-posti)")

# Venues deliberately left out of the 2Tickets catalog (id -> reason). They
# are skipped with a printed note so regeneration never re-adds them.
EXCLUDED_VENUES = {
    "1633": "Cinema Esperia Padova - already in the catalog via 18tickets "
            "(cinema-esperia-padova)",
}


def get(url, ua=UA_SITE):
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read().decode("utf-8", errors="replace")
    time.sleep(1.0)
    return body


def film_ids():
    ids = set()
    for page in ("", "/cinema"):
        ids |= set(re.findall(r"/biglietto/Evento/Dettaglio/(\d+)/C", get(BASE + page)))
    return sorted(ids, key=int)


def venue_ids_from_film(film_id):
    page = get(f"{BASE}/Evento/Dettaglio/{film_id}/C")
    return set(re.findall(r"/Acquisto/Checkout/\d+/(\d+)/\d+", page)) - {"0"}


def clean(s):
    s = html.unescape(re.sub(r"<[^>]*>", " ", s)).replace("''", "'")
    return re.sub(r"\s+", " ", s).strip()


def venue(venue_id):
    page = get(f"{BASE}/esercizio/titoli/{venue_id}")
    m = re.search(r'<div class="cinema-header">\s*<h1>(.*?)</h1>\s*<p>(.*?)</p>', page, re.S)
    if not m:
        return None
    has_cinema = False
    for card in re.findall(r'<div class="titolo-card"(.*?)<div class="btn-fasticket-container">', page, re.S):
        link = re.search(r"Checkout/\d+/\d+\?settore=(\w)", card)
        tag = re.search(r'bi-tag-fill"></i>\s*([^<]+)<', card)
        if link and link.group(1) == "C" and tag and "CINEMA" in tag.group(1).upper():
            has_cinema = True
            break
    return {"name": clean(m.group(1)), "address": clean(m.group(2)), "has_cinema": has_cinema}


def pretty_address(raw):
    # "Piazza della Repubblica, 29 CONVERSANO (BA)" -> "... 29 Conversano (BA)"
    m = re.match(r"^(.*?)\s+([A-ZÀ-Ù' ]{2,}?)\s*\((\w{2})\)\s*$", raw)
    if not m:
        return raw
    return f"{m.group(1)} {m.group(2).title()} ({m.group(3)})"


def city_of(address):
    """Returns (street part, city) of "STREET CITY (PROV)"; street may be ''."""
    m = re.search(r"([A-Za-zÀ-ù' ]+?)\s*\((\w{2})\)\s*$", address)
    if not m:
        return address, ""
    return address[:m.start()].strip(), m.group(1).strip()


def search(query, address):
    """First Nominatim hit whose town matches the venue's address, else None.

    Nominatim happily returns a same-named street in another town (Via
    Pitagora in Martina Franca for a Taranto venue), so a hit is accepted
    only if its city/town/village/municipality appears in the address.
    """
    q = urllib.parse.urlencode({"q": f"{query}, Italia", "format": "json",
                                "limit": 5, "addressdetails": 1})
    hits = json.loads(get(f"https://nominatim.openstreetmap.org/search?{q}", UA_GEO))
    wanted = address.casefold()
    for h in hits:
        a = h.get("address", {})
        place = a.get("city") or a.get("town") or a.get("village") or a.get("municipality")
        if place and place.casefold() in wanted:
            return float(h["lat"]), float(h["lon"])
    if hits:
        print(f"  ! rejected hits in the wrong town for: {query}")
    return None


def geocode(address):
    coords = search(address, address)
    if coords is None:
        # Retry with just "CITY (PROV)" - better a town-centre pin than none.
        _, city = city_of(address)
        prov = re.search(r"\((\w{2})\)\s*$", address)
        if city and prov:
            coords = search(f"{city}, {prov.group(1)}", address)
            if coords:
                print(f"  ! only town-level coordinates for: {address}")
    return coords


def main():
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    existing = {c["cinemaId"]: c for c in catalog if c.get("chain") == "twoTickets"}
    ids = set(existing) | set(sys.argv[1:])
    for fid in film_ids():
        ids |= venue_ids_from_film(fid)

    added, updated, skipped = [], [], []
    for vid in sorted(ids, key=int):
        if vid in EXCLUDED_VENUES:
            print(f"  = {vid} excluded: {EXCLUDED_VENUES[vid]}")
            skipped.append((vid, f"excluded: {EXCLUDED_VENUES[vid]}"))
            continue
        v = venue(vid)
        if v is None:
            skipped.append((vid, "no header"))
            continue
        if not v["has_cinema"] and vid not in existing:
            skipped.append((vid, f"theatre only: {v['name']}"))
            continue
        address = pretty_address(v["address"])
        if vid in existing:
            # Name only: the address and coordinates may have been fixed by hand.
            existing[vid]["name"] = v["name"]
            updated.append(vid)
            continue
        if not city_of(address)[0]:
            print(f"  ! no street in address (town-centre pin, review): {vid} {address}")
        coords = geocode(address)
        if coords is None:
            skipped.append((vid, f"NOT GEOCODED, add by hand: {v['name']} - {address}"))
            continue
        entry = {"cinemaId": vid, "name": v["name"], "slug": vid, "address": address,
                 "lat": coords[0], "lng": coords[1], "chain": "twoTickets"}
        catalog.append(entry)
        existing[vid] = entry
        added.append(vid)

    # Same building on two platforms? Flag anything within ~300 m of a
    # cinema from another chain for a manual look - never auto-dropped.
    others = [c for c in catalog if c.get("chain") != "twoTickets"]
    for vid in added:
        e = existing[vid]
        for o in others:
            if abs(o["lat"] - e["lat"]) < 0.003 and abs(o["lng"] - e["lng"]) < 0.004:
                print(f"  ? {e['name']} is next to {o['name']} ({o['chain']}) - same cinema?")

    with open(CATALOG, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(f"added {len(added)}, updated {len(updated)}, skipped {len(skipped)}")
    for vid, why in skipped:
        print(f"  - {vid}: {why}")


if __name__ == "__main__":
    main()
