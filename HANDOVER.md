# Handover: kente-app server and repo

**Written by:** Kelsey Goli · **Date:** 27 November 2026 · **Release at handover:** `v1.1.2`

If you only read one section, read [Section 3: Do not "clean up" these](#3-do-not-clean-up-these). Everything in it looks like cruft and isn't.

---

## 1. Where things stand

The server matches the Server Configuration Policy v2.1, and `/health` returns `ok`. The release that was blocked is unblocked. One decision is still open: there is **no backup job**, so nightly maintenance is switched off on purpose (Section 5).

To check this yourself at any time:

```bash
sudo scripts/policy_audit.sh
```

Every line should say PASS. If one says FAIL, it tells you which policy item is wrong and what it found.

### The system at a glance

| Piece | Where | Notes |
|---|---|---|
| Web app (`kente-app`) | `/opt/kente-app/app/server.py`, port 8080 | systemd service, runs as `kentesvc` |
| Inventory stand-in (`inventory-stub`) | `/opt/kente-app/services/inventory_stub.py`, port 9090 | Listens on 127.0.0.1 only |
| App config | `/opt/kente-app/config/app.conf` | `root:kente-ops 640` |
| Data (catalogue, snapshots) | `/opt/kente-app/data` | Never overwritten by deploys |
| Access log | `/var/log/kente-app/access.log` | One line per request, 8 fields |
| Backups | `/backups` | **Empty, no job writes here yet** |
| Repo | `github.com/Kelsey-S-Goli/Lab-3_Kente-Retail` | `main` is always deployable |

The app's `/health` check calls `http://inventory.kente.internal:9090/ping`. That name must resolve to `127.0.0.1` through `/etc/hosts`. If it doesn't, health fails, which is exactly what happened in November.

---

## 2. What happened before I arrived

The previous engineer left without notes. The audit found this:

| Date | Event |
|---|---|
| 2–11 Nov | Health checks all pass |
| **12 Nov** | `/etc/hosts` is edited to point `inventory.kente.internal` at `10.20.30.40`, with the comment `# moved to new box -- yd 12/11`. The stub only listens on 127.0.0.1, so every health check now times out. |
| 12–26 Nov | Health fails on every check. Nobody notices for **15 days**. |
| 27 Nov | Audit finds the cause; fixed in `/etc/hosts`; health back to `ok` |

The same audit also found:

- the departed engineer's account still had a working SSH key and full sudo;
- `data/` was world-writable (777), and `app.conf` (666) was writable by everyone;
- `kente-app` was not set to start after a reboot;
- the hostname was wrong.

All of these are fixed, and the commands and their output are in the evidence logs (Section 9).

The lesson isn't that someone made a mistake. It's that **nothing would have told us**. That's why the audit script exists (Section 8).

---

## 3. Do not "clean up" these

These are load-bearing workarounds. Each one looks odd, and each one has a reason. If you want to change one, open a PR, explain why the reason no longer applies, and get the CTO's approval.

### 3.1 The lockfile in `scripts/maintenance.sh`

```bash
if [ -e "$LOCKFILE" ]; then
  echo "Previous maintenance run still in progress, exiting."
  exit 0
fi
```

- **Why it looks wrong:** it reports success without doing anything. If a run is killed hard, the stale lock makes maintenance skip silently every night.
- **Why it stays:** the comment points to **incident 2026-01-08, where overlapping runs corrupted state**. This guard is the fix for that incident.
- **If you want to improve it:** replace it with `flock -n`, which releases the lock automatically when the process dies, and log the skip. Don't just delete it.

### 3.2 `timeout=2` in `app/server.py`

- **Why it looks wrong:** someone may think 2 seconds is too short and causes false alarms.
- **Why it stays:** without a timeout, `urlopen` waits forever, so `/health` would hang instead of failing. The README (v1.1.1) and NOTES.md record it as deliberate. During the November outage it did its job: each check failed in about 2 s (`2002ms` in the log) instead of hanging.

### 3.3 `UPSTREAM_URL` uses a hostname, not an IP

- **Why it looks wrong:** the outage was a hostname problem, so it's tempting to hard-code `127.0.0.1` in `app.conf`.
- **Why it stays:** v1.1 moved to a hostname on purpose, so the inventory service can move without a code change. Fix name resolution on the server (`/etc/hosts`), not the config.

### 3.4 The inventory stub listens on `127.0.0.1` only

- **Why it looks wrong:** it's the reason health couldn't reach the stub when the hostname pointed elsewhere.
- **Why it stays:** it keeps port 9090 off the internet (policy 5.1). Don't change it to `0.0.0.0`.

### 3.5 `deploy.sh` does not copy `data/`

- **Why it looks wrong:** it looks like an incomplete deploy.
- **Why it stays:** `data/` holds the live catalogue and snapshots. A deploy must never overwrite real data with repo samples.

### 3.6 `install_cron.sh` refuses to run without `--backup-confirmed`

- **Why it looks wrong:** a script that won't do its job.
- **Why it stays:** `maintenance.sh` deletes snapshots older than 14 days and assumes the ~01:00 backup has already copied them. **There is no backup job.** Scheduling maintenance now would delete data that was never backed up. The audit script also fails check `LB.1` if anyone schedules it anyway.

### 3.7 The access-log line format

- **Why it looks wrong:** it's a hand-written format, not a standard one.
- **Why it stays:** policy 6.1 requires exactly these 8 fields, and tools (`awk`, the audit script) depend on it. The 27 Nov fix only made the `note` field stay a single word; the order is unchanged.

### 3.8 The instructor account and its two sudo files

`10-instructor` and `90-cloud-init-users` both give `instructor` sudo. One looks like a duplicate.

- **Why it stays:** policy 2.4 says this account must stay **exactly** as it is. Don't tidy it.

---

## 4. Things that look wrong but are fine

| What you'll see | Why it's fine |
|---|---|
| `ConnectionResetError` tracebacks in `journalctl -u kente-app` | Internet scanners hanging up mid-request. The app keeps serving. |
| 404s for `/.env`, `/hachk.php`, `/@vite/client` in `access.log` | Bots probing for secrets. The 404 means they found nothing. |
| `%sudo` and `%admin` lines in `/etc/sudoers` | Ubuntu defaults. Both groups are empty, so they grant nothing. |
| `access.log.1` from 1 November | Policy 6.2 says old logs *may* be deleted, not *must*. |
| No log lines 18–22 Nov | The server was rebuilt on 23 Nov (`wtmp begins Mon Nov 23`). |
| Services restarted at 06:32 on 27 Nov | Automatic security updates (`apt-daily-upgrade`). Not a leftover script. |
| `systemd-resolved` listening on 127.0.0.53 and 127.0.0.54 | Ubuntu's local DNS helper; it can't be reached from outside. |

---

## 5. Open decisions (waiting on the CTO)

| Decision | Status | Tracked in |
|---|---|---|
| **No backup job, `/backups` empty.** Set up a nightly backup before maintenance is switched on? | Maintenance is off until this is answered | GitHub issue #1 |
| App subfolders (`app/`, `config/`, `deploy/`, `services/`) are 775, so `kentesvc` can change its own code. The policy doesn't cover them. Tighten to 755? | Left as is; `deploy.sh` deliberately doesn't change them | Raise with CTO |
| `app.conf` says `VERSION=1.1`, but the README says v1.1.1 (now v1.1.2) | Cosmetic; nothing reads `VERSION` | Raise with CTO |

---

## 6. DevOps in plain language, using this incident

### The DevOps lifecycle

DevOps is a loop, not a line: **plan → code → build → test → release → deploy → operate → monitor → back to plan.**

Here, the loop was broken in two places:

- **Operate → monitor.** The app was running, but nobody was watching whether it was healthy, so a broken health check went unseen for 15 days.
- **Code → release.** A change was made by hand on the server (`/etc/hosts`). It never went through the repo, a review or a release, so there was no record of it and no way to undo it cleanly.

What I changed closes those gaps. Server changes go through the repo and a PR, `deploy.sh` checks health after every deploy, and the audit script is the "monitor" step for configuration.

### CALMS: the five things a DevOps team needs

| Letter | Means | What it looked like here |
|---|---|---|
| **C**ulture | Shared ownership; it's safe to ask "why is this here?" | One person held all the knowledge, then left. The CTO was rightly wary of "clean-ups". |
| **A**utomation | Let scripts do repeatable work the same way every time | `deploy.sh` used to break permissions on every run; now it sets them correctly and tests health. The audit script automates the policy check. |
| **L**ean | Small changes, fast feedback, less waste | One fix per branch, one small PR each, so any change can be reverted alone. |
| **M**easurement | Know how you're doing with numbers, not feelings | Nobody measured health, so a 15-day outage was invisible. The audit script and access log now give hard evidence. |
| **S**haring | Write it down where the next person will find it | This document, `CONTRIBUTING.md`, PR templates and comments in the scripts explaining *why*. |

### DORA: four numbers that show how well a team delivers

| Metric | Plain meaning | This incident |
|---|---|---|
| **Deployment frequency** | How often you ship | Unknown before; now every merge to `main` can be deployed with one command. |
| **Lead time for changes** | Commit to production | The `/etc/hosts` change skipped the repo entirely, so it had no lead time and no record. |
| **Change failure rate** | Share of changes that break something | At least one hand-made change (12 Nov) broke production. |
| **Time to restore service** | How long an outage lasts | **About 15 days** (12 Nov → 27 Nov). Most of that was time to *notice*, not to fix: the fix took minutes once found. |

The cheapest way to improve DORA here is to shorten time to restore by **detecting problems sooner**. That's the reason for the value-add feature.

---

## 7. Branching: trunk-based

**Recommendation:** trunk-based development with short-lived branches. The full rules are in [`CONTRIBUTING.md`](CONTRIBUTING.md).

- `main` is always deployable and protected. No direct pushes.
- Every change goes on a short branch (`fix/…`, `feat/…`, `docs/…`, `chore/…`) and merges through a PR within a day or two.
- One change per branch, so each can be reviewed and reverted alone.
- Releases are tags on `main` (`v1.1.2`).

**Why not Git flow?** Git flow's `develop`, `release` and `hotfix` branches are designed for big teams shipping versioned products. Here there's one app, one server and one or two engineers. Extra long-lived branches would mean more merging and more places for changes to hide, which is the opposite of what this repo needs. Trunk-based also suits CI: one branch to test, one branch to deploy.

**Rule that matters most:** *no change on the server that isn't in the repo.* The November outage happened because one was made.

---

## 8. Value-add feature: `scripts/policy_audit.sh`

### What it does

It checks every item of the Server Configuration Policy v2.1, plus the backup guard from Section 3.6, and prints PASS, FAIL or WARN for each.

- **It's read-only.** Its only side effect is one `/health` request, which logs one line like any visitor.
- **It exits** `0` if everything passes, `1` if anything fails, and `2` if it isn't run with sudo.

```text
== 5. Network
PASS  5.1   TCP ports listening on public addresses: 22 8080
PASS  5.2   ufw is active
PASS  5.3   inventory.kente.internal resolves to: 127.0.0.1
PASS  5.4   http://localhost:8080/health returns ok (200)
...
Summary: 46 PASS, 0 FAIL, 0 WARN
```

### Why this one

- **It attacks the real failure.** The outage lasted 15 days because nothing checked. With the policy as a command, the same fault is a FAIL on line `5.3` the next time anyone runs it.
- **It turns the policy into something you can test.** The policy PDF says what "correct" means. This script *checks* it, and the settings at the top of the script are the single place to update when the policy changes.
- **It protects the load-bearing decisions.** Check `LB.1` fails if someone schedules maintenance without a backup. That puts Section 3.6 into code, not just into this document.
- **It makes handovers cheap.** The next engineer runs one command on day one and knows the state of the server, instead of spending a day auditing by hand like I did.
- **It fits CALMS and DORA:** automation and measurement, and a shorter time to restore.

### How to use it

```bash
cd ~/Lab-3_Kente-Retail && git pull
sudo scripts/policy_audit.sh                                   # read the result
sudo scripts/policy_audit.sh | tee ~/audit/policy-$(date +%F).txt   # keep it as evidence
```

Run it **after every deploy** and **after any change by hand**.

### How to change it

- **When staff change:** edit `CURRENT_ENGINEERS` and `FORMER_STAFF` at the top of the script, then open a PR.
- **When the policy changes:** update the settings or add a check in the matching section. Each check is a few lines and uses `pass` or `fail`.

### Next step (not done yet; needs CTO approval)

Run it nightly and keep the results:

```text
# /etc/cron.d/kente-policy-audit
15 3 * * * root /opt/kente-app/scripts/policy_audit.sh > /var/log/kente-policy-audit.log 2>&1
```

This needs `deploy.sh` to copy the script into `/opt/kente-app/scripts`. Someone also needs to read that log, or it should send an alert on FAIL.

---

## 9. How to do common jobs

**Deploy**

```bash
cd ~/Lab-3_Kente-Retail && git pull
sudo diff /opt/kente-app/config/app.conf config/app.conf   # check what config will change
sudo scripts/deploy.sh                                     # ends with "Deploy OK"
sudo scripts/policy_audit.sh
```

**Health is failing**

```bash
getent hosts inventory.kente.internal       # must be 127.0.0.1
curl -s http://127.0.0.1:9090/ping          # is the stub up?
systemctl status inventory-stub kente-app --no-pager
sudo tail -n 20 /var/log/kente-app/access.log   # the note field says why
```

**Someone leaves**

Lock the account, keep the home folder, and remove group membership, sudo and SSH keys:

```bash
sudo gpasswd -d USER kente-ops
sudo mv /etc/sudoers.d/<their file> /root/<file>.removed-$(date +%F) && sudo visudo -c
sudo usermod -L -s /usr/sbin/nologin USER && sudo chage -E 0 USER
sudo mv /home/USER/.ssh/authorized_keys /home/USER/.ssh/authorized_keys.disabled-$(date +%F)
```

Then add them to `FORMER_STAFF` in `policy_audit.sh` and run it.

**Never** fix a permission problem with `chmod 777`. Find which user needs access and grant exactly that.

---

## 10. Evidence index

These are kept outside the repo because they contain IPs and usernames:

| File | What it shows |
|---|---|
| `COMPREHENSION_MEMO.md` (in repo, first commit) | What I believed *before* touching anything |
| `session-2026-11-27.log` + screenshots | The read-only audit, steps 1–7 |
| Pre-fix check screenshots | Sudo rules, when health started failing |
| `fixes-2026-11-27.log` + screenshots | Each fix and its check |
| `deploy-2026-11-27.log` | The repo deploy and the final check |
| GitHub PRs and tag `v1.1.2` | Every code change, reviewed and reversible |