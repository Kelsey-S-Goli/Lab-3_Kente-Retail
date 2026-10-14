#!/usr/bin/env bash
# Installs the nightly maintenance cron job.
set -euo pipefail
# The maintenance script assumes it runs AFTER the nightly backup (~1am).
echo "0 0 * * * /opt/kente-app/scripts/maintenance.sh" | crontab -
