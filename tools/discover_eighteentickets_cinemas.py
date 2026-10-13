"""Discovers 18tickets venues missing from assets/cinemas.json.

18tickets has no public venue list (confirmed 13 Oct 2026). Every circuit
gets a wildcard certificate *.CIRCUIT.18tickets.it, so Certificate
Transparency (Cert Spotter API) lists the circuits; each circuit's
/select_cinema?mandatory=true page links its venues (VENUE.CIRCUIT.18tickets.it);
a label with no sub-hosts is a single venue (LABEL.18tickets.it).
A venue homepage gives its name in <title> and its address in the
maps.google.com/?q=ADDRESS link.

Writes build/candidates_eighteentickets.json and build/discovery_report.txt.
Never modifies assets/cinemas.json - candidates must pass the navigability
check first (see README "Sviluppo"). 18tickets answers 429 to bursts: one
request every 3 s, 60 s back-off on 429.
"""
import html
import json
import os
import re
import time
import urllib.parse
import urllib.request
import urllib.error

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/126.0 Safari/537.36")
UA_GEO = ("CinemaDisponibilitaPosti-catalog/1.0 "
          "(github.com/mauronofrio/cinema-disponibilita-posti)")
CATALOG = "assets/cinemas.json"
OUT = "build/candidates_eighteentickets.json"
REPORT = "build/discovery_report.txt"
INFRA = {"www", "demo", "dmo", "staging", "external", "organizzatori", "api"}

report = []


def log(line):
    print(line, flush=True)
    report.append(line)


def get(url, ua=UA, delay=3.0):
    for attempt in range(4):
        req = urllib.request.Request(url, headers={"User-Agent": ua})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                body = r.read().decode("utf-8", "replace")
                time.sleep(delay)
                return r.status, r.geturl(), body
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < 3:
                log(f"  429 on {url}, waiting 60 s")
                time.sleep(60)
                continue
            time.sleep(delay)
            return e.code, url, ""
        except Exception as e:  # network error: report, move on
            time.sleep(delay)
            return type(e).__name__, url, ""
    return 429, url, ""


def circuit_labels():
    labels, after = set(), None
    while True:
        url = ("https://api.certspotter.com/v1/issuances?domain=18tickets.it"
               "&include_subdomains=true&expand=dns_names")
        if after:
            url += f"&after={after}"
        _, _, body = get(url, ua=UA_GEO, delay=2.0)
        rows = json.loads(body or "[]")
        if not rows:
            break
        for row in rows:
            for name in row.get("dns_names", []):
                m = re.match(r"^(?:\*\.|api\.)?([a-z0-9-]+)\.18tickets\.it$", name.lower())
                if m and m.group(1) not in INFRA:
                    labels.add(m.group(1))
        after = rows[-1]["id"]
    return sorted(labels)


def venue_hosts(label):
    hosts = set()
    for path in ("/", "/select_cinema?mandatory=true"):
        _, _, body = get(f"https://{label}.18tickets.it{path}")
        hosts |= set(re.findall(r"https?://([a-z0-9-]+\." + re.escape(label) + r"\.18tickets\.it)", body))
        if hosts:
            break
    return sorted(hosts) or [f"{label}.18tickets.it"]


def venue_info(host):
    code, final, body = get(f"https://{host}/")
    # Skip non-200 answers and pages that redirected to the www.18tickets.it
    # marketing site (the host is not a venue).
    redirected_to_www = ("18tickets.it/" in final
                         and final.rstrip("/").endswith("www.18tickets.it"))
    if code != 200 or redirected_to_www:
        return None
    title = re.search(r"<title>(.*?)</title>", body, re.S)
    addr = re.search(r"maps\.google\.com/\?q=([^'\"]+)['\"]", body)
    if not title or not addr:
        return None
    return {"name": html.unescape(title.group(1)).strip(),
            "address": html.unescape(urllib.parse.unquote_plus(addr.group(1))).strip()}


def city_of(address):
    # "Via Baione, snc, 70043, Monopoli, BA" -> "Monopoli"
    parts = [p.strip() for p in address.split(",") if p.strip()]
    for p in reversed(parts):
        if not re.fullmatch(r"\d{5}|[A-Z]{2}|snc", p) and not re.search(r"\d", p):
            return p
    # Space-separated "Via Milazzo 9, 20121 Milano MI" -> "Milano"
    m = re.search(r"\b\d{5}\s+([^\d,]+?)(?:\s+[A-Z]{2})?\s*$", address.strip())
    return m.group(1).strip() if m else ""


def geocode(address):
    city = city_of(address).casefold()
    q = urllib.parse.urlencode({"q": address, "format": "json", "limit": 5, "addressdetails": 1})
    _, _, body = get(f"https://nominatim.openstreetmap.org/search?{q}", ua=UA_GEO, delay=1.1)
    for hit in json.loads(body or "[]"):
        a = hit.get("address", {})
        names = {str(a.get(k, "")).casefold() for k in ("city", "town", "village", "municipality")}
        if city and city in names:
            return float(hit["lat"]), float(hit["lon"])
    return None


def cinema_id_of(host):
    # "metropolis.multicine.18tickets.it" -> "metropolis-multicine"
    # "ascona.18tickets.it" -> "ascona"
    sub, circuit = (host.split(".")[0], host.split(".")[1]) if host.count(".") > 2 else (host.split(".")[0], "")
    return f"{sub}-{circuit}" if circuit else sub


def main():
    os.makedirs("build", exist_ok=True)
    catalog = json.load(open(CATALOG, encoding="utf-8"))
    known_hosts = {c.get("host") for c in catalog if c.get("chain") == "eighteenTickets"}
    known_ids = {c["cinemaId"] for c in catalog}
    candidates = []
    for label in circuit_labels():
        for host in venue_hosts(label):
            if host in known_hosts:
                continue
            info = venue_info(host)
            if info is None:
                log(f"skip {host}: no name/address on homepage (not a venue page)")
                continue
            coords = geocode(info["address"])
            if coords is None:
                log(f"NOT GEOCODED {host}: {info['name']} - {info['address']}")
                continue
            # Review Focus 5: same building already in the catalog (any chain,
            # e.g. a custom-domain 18tickets site) -> duplicate, not a candidate.
            near = [c for c in catalog
                    if abs(c["lat"] - coords[0]) < 0.0015 and abs(c["lng"] - coords[1]) < 0.002]
            if near:
                log(f"POSSIBLE DUPLICATE {host} ({info['name']}) ~ "
                    + ", ".join(f"{c['name']} [{c.get('chain')}:{c['cinemaId']}]" for c in near))
                continue
            cid = cinema_id_of(host)
            while cid in known_ids:
                cid += "-2"
            known_ids.add(cid)
            candidates.append({"cinemaId": cid, "name": f"{info['name']} - {city_of(info['address'])}",
                               "slug": cid, "address": info["address"], "lat": coords[0],
                               "lng": coords[1], "chain": "eighteenTickets", "host": host})
            log(f"candidate {cid}: {info['name']} - {info['address']}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(candidates, f, ensure_ascii=False, indent=2)
    with open(REPORT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report) + "\n")
    print(f"{len(candidates)} candidates -> {OUT}")


if __name__ == "__main__":
    main()
