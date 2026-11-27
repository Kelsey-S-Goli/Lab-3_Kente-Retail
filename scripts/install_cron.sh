#!/usr/bin/env bash
# Installs the nightly maintenance job.
#
# ON HOLD: do not run until a nightly backup job exists (see the GitHub issue
# "Decision needed: no backup job exists"). maintenance.sh deletes snapshots
# older than 14 days and assumes the ~01:00 backup has already copied them.
# As of the 2026-11-27 audit there is no backup job and /backups is empty.
#
# Changes from the original (audit 2026-11-27):
#   - 00:00 -> 02:30. The old time ran BEFORE the backup it depends on.
#   - /etc/cron.d instead of `crontab -`. The old pipe replaced the caller's
#     whole crontab, silently deleting any other job in it.
#   - Runs as kentesvc (owner of data/) instead of root: least privilege.
set -euo pipefail

if [ "${1:-}" != "--backup-confirmed" ]; then
  echo "Refusing to install: confirm a nightly backup exists, then re-run with --backup-confirmed" >&2
  exit 1
fi

echo '30 2 * * * kentesvc /opt/kente-app/scripts/maintenance.sh' | sudo tee /etc/cron.d/kente-maintenance >/dev/null
sudo chmod 644 /etc/cron.d/kente-maintenance
echo "Installed /etc/cron.d/kente-maintenance (02:30 daily, as kentesvc)"