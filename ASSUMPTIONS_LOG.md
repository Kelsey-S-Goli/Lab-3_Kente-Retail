# Assumptions log

**Author:** Kelsey Goli · **Last updated:** 27 November 2026 (after `policy_audit.sh`: 46 PASS, 0 FAIL)

Every assumption I made, how I tested it, and where it ended up. I wrote several of these *before* the audit (in the comprehension memo) and kept them here unchanged, so the wrong ones stay visible.

**Status key:**

- **Confirmed:** evidence shows it's true.
- **Refuted:** evidence shows it's false.
- **Open:** not yet tested, or waiting on someone else.

## Before the audit (from the comprehension memo)

| # | Assumption | Status | Evidence / outcome |
|---|---|---|---|
| A1 | The two disputed pieces of code are the lockfile in `maintenance.sh` and the schedule in `install_cron.sh` | **Open** | Nobody has named them. I chose them because each has a comment that contradicts how it looks. If the timeout in `server.py` was the disputed one instead, the verdict is the same: keep it (README v1.1.1, NOTES.md). |
| A2 | `inventory.kente.internal` doesn't resolve to 127.0.0.1, so `/health` returns 503 | **Confirmed** | `/etc/hosts` line 10 pointed at `10.20.30.40`; health returned `upstream unreachable (HTTP 503)`. Fixed. |
| A3 | `/opt/kente-app` is owned by `kentesvc` because `deploy.sh` creates it that way | **Refuted** | It was already `root:kente-ops 755`. `deploy.sh` was still fixed, because it *would* have broken it on the next deploy. |
| A4 | `app.conf` is 644 | **Refuted (worse)** | It was **666**, writable by anyone. I also hadn't predicted that `data/` was **777**. Both fixed. |
| A5 | The departed engineer's account is still active | **Confirmed** | `ydarko` (`Yaw Darko (left kente)`): in `kente-ops`, full sudo, working SSH key, never expires. Offboarded; home folder kept. |
| A6 | There's no proper systemd unit for the inventory stub | **Refuted** | `inventory-stub` was enabled and running. Not predicted: **`kente-app` itself was disabled.** Fixed. |
| A7 | The hostname is wrong or won't survive a reboot | **Confirmed** | It was `ops-test-box`, with `preserve_hostname: false`. Fixed, and made to survive reboots. |
| A8 | The firewall is misconfigured | **Refuted** | ufw was active, denied incoming by default, and allowed only 22 and 8080. A test from my laptop confirmed it. No change made. |
| A9 | Something outside the repo restarts the app or deletes logs (from "false-positive restarts" in NOTES.md) | **Refuted** | No such job. The 27 Nov 06:32 restart lines up with `apt-daily-upgrade` (automatic updates). No job deletes logs. |
| A10 | A nightly backup runs at about 01:00 (the comment in `install_cron.sh`) | **Refuted** | No backup job anywhere, and `/backups` is empty. This changed the plan: maintenance stays off. |
| A11 | "Tightened" in NOTES.md means an explicit 2 s timeout was added where there was none | **Open (low risk)** | The wording is ambiguous. The log shows the timeout works as intended (`2002ms`), so the change is safe either way. |

## During the audit and fixes

| # | Assumption | Status | Evidence / outcome |
|---|---|---|---|
| A12 | `ydarko` is the engineer who left | **Confirmed** | The account's description reads `Yaw Darko (left kente)`, and his key is labelled `yaw@yaw-thinkpad`. |
| A13 | The `/etc/hosts` change caused the outage, rather than a code change | **Confirmed** | Health passed every day until 12 Nov and failed every day after. The bad line is commented `yd 12/11`. Fixing only that line fixed health. |
| A14 | The `10.20.30.40` entry was a planned move of the inventory service that never finished | **Open** | It's based on the comment `moved to new box`. I haven't read `/home/ydarko/TODO.txt`, which may explain it. |
| A15 | `90-cloud-init-users` gives sudo to a cloud default user who shouldn't have it | **Refuted** | It only grants `instructor`, which is allowed by policy 2.4. Left as is. |
| A16 | Removing `90-ydarko` can't lock me out | **Confirmed** | Checked first: `sudo -l -U engineer` showed my sudo came from `10-engineer`. |
| A17 | Expiring the account (`chage -E 0`) blocks SSH key logins, not just password logins | **Confirmed (by design)** | His key was also moved aside, so there are two separate blocks. |
| A18 | `kentesvc` can still read `app.conf` at 640, because it's in `kente-ops` | **Confirmed** | `sudo -u kentesvc test -r` printed `readable`, and health stayed `ok`. |
| A19 | The repo's `app.conf` matches the live one, so the deploy won't change config | **Confirmed** | `sudo diff` printed nothing before the deploy. |
| A20 | Old 9-field log lines are from the note bug, not from bad requests | **Confirmed** | All 5 were failed health checks written on 27 Nov with `URLError: <…>`, with a space. Older lines used `_` and had 8 fields. |
| A21 | Maintenance can run as `kentesvc` instead of root | **Open** | `kentesvc` owns `data/snapshots`, so it should work. Not tested, because maintenance is on hold. |
| A22 | Making the app's subfolders 775 → 755 is the CTO's call, not mine | **Open (decision)** | The policy doesn't cover them. `deploy.sh` deliberately leaves their mode alone. Raised in the handover. |
| A23 | The EC2 security group allows only ports 22 and 8080 | **Open (not tested)** | Not checked in the AWS console. Indirect evidence: from my laptop, ports 22 and 8080 connect and 9090 times out. Left for the next engineer. |
| A24 | The fixes survive a reboot | **Open (not tested)** | No reboot done. The settings that make them persist are in place and checked: `preserve_hostname: true`, both services `enabled`, the `/etc/hosts` entry. |
| A25 | The instructor account matches the values `policy_audit.sh` expects (uid 1000, `/bin/bash`, group `instructor`) | **Confirmed** | `policy_audit.sh` check 2.4 PASS on 27 Nov. |
| A26 | The storefront errors (`500 FileNotFoundError`, 3–17 Nov) are a separate issue from the health outage | **Open** | `catalog.json` exists now, and `/` returns 200. The cause of the intermittent missing file is unknown. Recorded in the incident note as a follow-up. |
| A27 | After all fixes and the `v1.1.2` deploy, the server fully matches policy v2.1 | **Confirmed** | `sudo scripts/policy_audit.sh`: 46 PASS, 0 FAIL, 0 WARN on 27 Nov. |