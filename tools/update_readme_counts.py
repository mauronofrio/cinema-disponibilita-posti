"""Rewrites the cinema-counts block in README.md from assets/cinemas.json.
Run after every catalog change; test/core/readme_counts_test.dart fails
until you do."""
import json
import re

entries = json.load(open("assets/cinemas.json", encoding="utf-8"))
counts = {}
for e in entries:
    chain = e.get("chain") or "theSpace"
    counts[chain] = counts.get(chain, 0) + 1
n = lambda k: counts.get(k, 0)
block = (
    "<!-- cinema-counts:start -->\n"
    f"**{len(entries)} cinema supportati** · The Space {n('theSpace')} · "
    f"UCI {n('uci')} · 18tickets {n('eighteenTickets')} · "
    f"Webtic {n('webtic')} · 2Tickets {n('twoTickets')}\n"
    "<!-- cinema-counts:end -->"
)
readme = open("README.md", encoding="utf-8", newline="").read()
pattern = re.compile(r"<!-- cinema-counts:start -->.*?<!-- cinema-counts:end -->", re.S)
if pattern.search(readme):
    readme = pattern.sub(lambda _: block, readme)
else:
    readme = readme.replace("## Cinema supportati\n", "## Cinema supportati\n\n" + block + "\n", 1)
open("README.md", "w", encoding="utf-8", newline="\n").write(readme)
print(block)
