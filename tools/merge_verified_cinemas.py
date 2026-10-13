"""Appends verified candidates to assets/cinemas.json (never reorders or
reformats existing entries). Usage:
  python tools/merge_verified_cinemas.py --report build/navigability_report.json \
      --candidates build/candidates_eighteentickets.json [--approve a,b] [--hold c]
navigable -> added; programmeOnly + --approve -> added with hasSeatMap false;
--hold -> left out on purpose (e.g. kept back to test the remote update).
Every --approve/--hold id that had no effect is reported as a WARN line.
--catalog defaults to assets/cinemas.json (override only for testing)."""
import argparse
import json

p = argparse.ArgumentParser()
p.add_argument("--report", required=True)
p.add_argument("--candidates", required=True)
p.add_argument("--approve", default="")
p.add_argument("--hold", default="")
p.add_argument("--catalog", default="assets/cinemas.json")
a = p.parse_args()
approve = {x for x in a.approve.split(",") if x}
hold = {x for x in a.hold.split(",") if x}
verdicts = {r["cinemaId"]: r for r in json.load(open(a.report, encoding="utf-8"))}
catalog = json.load(open(a.catalog, encoding="utf-8"))
keys = {(c.get("chain") or "theSpace", c["cinemaId"]) for c in catalog}
candidates = json.load(open(a.candidates, encoding="utf-8"))
used_approve, used_hold = set(), set()
for cand in candidates:
    cid, v = cand["cinemaId"], verdicts.get(cand["cinemaId"], {})
    verdict = v.get("verdict", "unchecked")
    if cid in hold:
        used_hold.add(cid)
        print(f"HELD   {cid} ({verdict})")
        continue
    if (cand["chain"], cid) in keys:
        print(f"EXISTS {cid}")
        continue
    if verdict == "navigable" or (verdict == "programmeOnly" and cid in approve):
        if verdict == "programmeOnly":
            cand["hasSeatMap"] = False
            used_approve.add(cid)
        catalog.append(cand)
        keys.add((cand["chain"], cid))
        print(f"ADDED  {cid} ({verdict})")
    else:
        print(f"LEFT   {cid} ({verdict}: {v.get('reason', '')})")
# A typo'd or pointless --approve/--hold id must not pass silently.
candidate_ids = {c["cinemaId"] for c in candidates}
for flag, ids, used in (("approve", approve, used_approve), ("hold", hold, used_hold)):
    for cid in sorted(ids - used):
        if cid in candidate_ids:
            why = f"verdict {verdicts.get(cid, {}).get('verdict', 'unchecked')}"
        else:
            why = "not in candidates"
        print(f"WARN unused --{flag} id: {cid} ({why})")
with open(a.catalog, "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
