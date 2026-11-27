# Comprehension Memo

**To:** CTO, Kente Retail
**From:** Kelsey Goli
**Date:** 27 November 2026
**Re:** What I found in the inherited repo, before I change anything

---

I've read every file in the repo against the Server Configuration Policy (v2.1). I haven't changed a line yet. This memo covers the two scripts the team has been arguing about, what I plan to do with each, and what I expect to find when I audit the server.

## 1. The lockfile in `scripts/maintenance.sh`: keep it

**What it does.** Before it does anything else, the script checks for `/tmp/kente-maintenance.lock`. If the file is there, it prints a message and exits quietly. If not, it creates the lock, deletes data snapshots older than 14 days, and removes the lock when it finishes.

**Why it looks like a bug.** It reports success without doing any work. If the script is ever killed mid-run, the lock stays behind and maintenance silently skips every night after that.

**Why I'm keeping it.** The comment next to it reads *"do not remove: see incident 2026-01-08, overlapping runs corrupted state."* That points to a real incident with a date, not someone's style preference. The guard is there so that two runs can never overlap again. The stale-lock risk is real but small, since `/tmp` is cleared on reboot. It's something to monitor, not a reason to rip the guard out. If we want to improve it later, swapping it for `flock` would do the same job more safely. That should be a reviewed change, not something rushed in before Monday.

## 2. The schedule in `scripts/install_cron.sh`: fix it

**What it does.** It installs a cron job that runs maintenance every night at midnight (`0 0 * * *`).

**Why it looks fine.** It's one line, it runs, and nothing obviously breaks.

**Why it's actually wrong.** The script's own comment says maintenance *"assumes it runs AFTER the nightly backup (~1am)."* Midnight comes before 1am, so we're deleting old snapshots before the backup has had a chance to copy them. I also found two quieter problems:

- It pipes into `crontab -`, which replaces that user's entire crontab. If the backup job lives in the same crontab, running this script deletes it.
- It points to `/opt/kente-app/scripts/maintenance.sh`, but `deploy.sh` never copies the `scripts/` folder there. The job may be calling a file that doesn't exist.

My plan is to move the job to about 02:30 and put it in its own file under `/etc/cron.d/`, so it can't overwrite anything else.

## 3. Other things I'm deliberately leaving alone

- **The 2-second health-check timeout in `server.py`.** The README (v1.1.1) and NOTES.md both say it was set on purpose after false alarms. Without it, the health check could hang forever.
- **The access-log format.** It already matches policy item 6.1 exactly.
- **The inventory stub listening only on `127.0.0.1`.** That's what keeps port 9090 off the internet.

## 4. What I expect the server audit to show

These are my predictions, written before running a single command:

1. **The network fault:** `inventory.kente.internal` doesn't resolve to `127.0.0.1`, so `/health` returns 503. I think this is what's blocking Monday.
2. `/opt/kente-app` owned by `kentesvc` instead of `root:kente-ops`, and `app.conf` readable by everyone (644 instead of 640). `deploy.sh` causes both of these, so they come back on every deploy.
3. The departed engineer's account is still active: still in `kente-ops`, with sudo rights and a working SSH key.
4. No proper systemd service for the inventory stub, or one that isn't enabled.
5. The hostname isn't `kente-app-01`, or doesn't survive a reboot.
6. The firewall is off, too open, or running alongside a second firewall.
7. Something outside the repo restarts the app or deletes logs. The notes mention restarts, but nothing in the repo does that.

I'll record what I actually find against each of these, including where I was wrong.
