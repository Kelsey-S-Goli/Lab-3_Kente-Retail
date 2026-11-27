# Incident note: inventory health check failing for 15 days

**Author:** Kelsey Goli · **Written:** 27 November 2026 · **Status:** Resolved
**Severity:** Medium. The release was blocked and monitoring was blind. The storefront kept serving.

This is a blameless review. It's about how the system let this happen and how we stop it happening again, not about who typed what.

## Summary

On 12 November someone edited `/etc/hosts` on the app server by hand, pointing `inventory.kente.internal` at `10.20.30.40`. The inventory service only listens on `127.0.0.1`, so from that moment every `/health` check timed out after 2 seconds and returned **503**. Nobody noticed for 15 days. I found it during the handover audit on 27 November and fixed it by pointing the name back at `127.0.0.1`. Health has returned `ok` since.

## Impact

- **`/health` returned 503 on every check from 12 Nov to 27 Nov**: 170 failed checks are in the log (12–17 Nov and 26–27 Nov).
- **Monday's release was blocked**, because the health check is part of release readiness.
- **The storefront (`/`) kept working.** It doesn't call the inventory service, so customers could still see the catalogue. As far as the logs show, there was no customer-facing outage from this fault.
- **Monitoring was effectively blind.** A health check that always fails tells you nothing about real problems.

## Timeline (UTC)

| When | What happened |
|---|---|
| 2–11 Nov | Health checks pass every day (17–36 per day, all 200) |
| **12 Nov** | 23 checks pass, then `/etc/hosts` is changed (`# moved to new box -- yd 12/11`). The next 5 checks fail. |
| 13–17 Nov | Every check fails (26–37 per day) |
| 18–22 Nov | No logs; the server is rebuilt on 23 Nov and the bad `/etc/hosts` line is carried over |
| 26–27 Nov | Checks still failing. The engineer has left without handover notes ("on Friday", per the CTO). |
| 27 Nov ~14:13 | **Detected:** the audit's log analysis shows 167 failures, `URLError … timed_out host=inventory.kente.internal` |
| 27 Nov ~14:54 | **Root cause found:** `getent hosts inventory.kente.internal` returns `10.20.30.40`. The stub works by IP (200) but not by name (000). |
| 27 Nov ~16:30 | **Fixed:** the line changed to `127.0.0.1`. The stub answers by name (200) and `/health` returns `ok (HTTP 200)`. |
| 27 Nov ~17:25 | Repo fixes deployed (`v1.1.2`); health still `ok` |

To get the exact time of the first failure for the record:

```bash
sudo awk '$5=="/health" && $6==503 {print $1, $2; exit}' /var/log/kente-app/access.log
```

**Time to restore:** about 15 days from start to fix. Almost all of it was **time to detect**. Once someone looked, finding the cause took about 40 minutes and fixing it took minutes. I deliberately waited about 1.5 hours between finding the cause and changing anything, to finish the read-only audit first.

## Root cause

`inventory.kente.internal` was mapped to `10.20.30.40` in `/etc/hosts`. The app reaches the inventory service by that name (on purpose, since v1.1). The stand-in service only listens on `127.0.0.1:9090`, so the connection never succeeded.

## Contributing factors

Why it happened, and why it lasted:

1. **A change made by hand on the server, outside the repo.** No pull request, no review, no record beyond a comment, and no easy way to undo it.
2. **Nobody acted on the health check.** Nothing alerted on repeated 503s, so a failing check was the same as no check.
3. **Knowledge sat with one person.** The engineer who knew about the move left without notes, and the move never finished.
4. **No routine check of the server against its policy.** Several other problems had built up too: world-writable `data/` and `app.conf`, the departed engineer's sudo and SSH key, the wrong hostname, and an app not set to start on boot.
5. **The log format bug made failures harder to analyse.** Failed-health notes contained a space, which split their log lines into 9 fields.

## What went well

- **The 2-second timeout in `server.py` did its job.** Health failed fast and clearly instead of hanging.
- **The log's note field recorded the exact error** (`timed_out`, `host=inventory.kente.internal`), which pointed straight at name resolution.
- **The comment on the bad line gave the date and initials,** which made the timeline easy to confirm.
- **Auditing before changing anything** meant the cause was proven before the fix, and nothing else was disturbed.

## What I changed

| Action | Status |
|---|---|
| `/etc/hosts` corrected to `127.0.0.1` (policy 5.3) | Done 27 Nov |
| Log note fixed so every line has 8 fields (`server.py`, PR `fix/log-note-format`) | Done, deployed in `v1.1.2` |
| `deploy.sh` now fails loudly if `/health` isn't `ok` after a deploy | Done, `v1.1.2` |
| `scripts/policy_audit.sh` checks every policy item, including this one (check 5.3) | Done |
| Rule in `CONTRIBUTING.md`: no change on the server that isn't in the repo | Done |
| Handover document explains the hostname design and why not to hard-code an IP | Done |

## Follow-ups

| Action | Owner | Status |
|---|---|---|
| Run `policy_audit.sh` nightly and alert on any FAIL | Next engineer, after CTO approval | Open |
| Alert when `/health` fails, e.g. 3 times in a row | Next engineer | Open |
| Find out whether the inventory service was meant to move to `10.20.30.40` (check `/home/ydarko/TODO.txt`, ask the CTO) | Kelsey / CTO | Open |
| Investigate the storefront `500 FileNotFoundError` errors between 3 and 17 Nov (30 requests). `catalog.json` was missing at times; the cause is unknown. | Next engineer | Open |
| Set up a nightly backup job (no backups exist today) | CTO decision | Open (GitHub issue #1) |