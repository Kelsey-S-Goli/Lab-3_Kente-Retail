# Contributing to kente-app

## Branching: trunk-based, short-lived branches

`main` is always deployable. All work happens on short branches that are merged
back through a pull request within a day or two.

We chose this over Git flow because the setup is one app, one server and one or
two engineers. Git flow's `develop`, `release` and `hotfix` branches would add
merge work without adding safety. A single always-green `main` is also what CI needs.

### Rules

1. **Never commit directly to `main`.** Every change, even docs, goes through a PR.
2. **Branch from an up-to-date `main`:**
   ```bash
   git checkout main && git pull
   git checkout -b fix/short-description
   ```
3. **Branch names:** `feat/` new behaviour, `fix/` something broken,
   `docs/` documentation only, `chore/` tidy-up with no behaviour change.
4. **One change per branch**, so each can be reviewed and reverted on its own.
5. **Keep branches short-lived.** Merge or close within 2 days.
6. **Commit messages say why** and point to the policy item or incident:
   `fix: set app.conf to 640 on deploy (policy 3.3)`.
7. **Every PR fills in the template:** why, risk, how to revert.
8. **Squash-merge, then delete the branch.**
9. **Tag releases on `main`:** `git tag v1.1.2 && git push --tags`.

## Load-bearing code: read before "cleaning up"

Do not remove or simplify these without reading the handover document and
getting the CTO's approval on the PR:

| Code | Why it stays |
|---|---|
| Lockfile check in `scripts/maintenance.sh` | Incident 2026-01-08: overlapping runs corrupted state |
| `timeout=2` in `app/server.py` | Without it `/health` hangs forever when upstream is down (v1.1.1) |
| `UPSTREAM_URL` uses a hostname, not an IP | Intentional since v1.1. Fix name resolution on the server, not here |
| Inventory stub binds `127.0.0.1` only | Keeps port 9090 off the internet (policy 5.1) |
| `deploy.sh` does not copy `data/` | Deploys must never overwrite live data |
| `install_cron.sh` refuses without `--backup-confirmed` | No backup job exists yet; maintenance would delete unbacked-up snapshots |

## Never commit

Secrets, keys, `.env` files, server logs or audit evidence containing IPs or
usernames. If a secret is ever committed, rotate it first, then clean it up.
