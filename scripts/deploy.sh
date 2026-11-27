#!/usr/bin/env bash
# Deploy kente-app to /opt/kente-app and restart its services.
#
# Ownership and modes follow the Server Configuration Policy v2.1, section 3.
# Never "fix" a permission problem here by loosening modes (no chmod 777).
#
# Deliberately NOT done by this script:
#   - copying data/   : live catalogue and snapshots; never overwrite them.
#   - installing cron : see scripts/install_cron.sh (on hold until backups exist).
#
# Changed 2026-11-27 (audit): the old version created /opt/kente-app as
# kentesvc-owned and copied app.conf as 644, breaking policy 3.1/3.3 on every
# deploy. It also never copied scripts/ or services/.
set -euo pipefail
cd "$(dirname "$0")/.."          # run from anywhere

APP=/opt/kente-app

# Policy 3.1: root:kente-ops 755
sudo install -d -o root -g kente-ops -m 755 "$APP"
# Sub-folders: create if missing; leave existing modes alone.
for d in app config scripts services; do
  [ -d "$APP/$d" ] || sudo install -d -o root -g kente-ops -m 755 "$APP/$d"
done

sudo install -o root -g kente-ops -m 755 app/server.py "$APP/app/server.py"
sudo install -o root -g kente-ops -m 640 config/app.conf "$APP/config/app.conf"   # policy 3.3
sudo install -o root -g kente-ops -m 755 scripts/maintenance.sh "$APP/scripts/maintenance.sh"
sudo install -o root -g kente-ops -m 644 services/inventory_stub.py "$APP/services/inventory_stub.py"

sudo install -o root -g root -m 644 deploy/kente-app.service /etc/systemd/system/kente-app.service
sudo install -o root -g root -m 644 deploy/inventory-stub.service /etc/systemd/system/inventory-stub.service
sudo systemctl daemon-reload
sudo systemctl enable inventory-stub kente-app      # policy 4.1/4.2
sudo systemctl restart inventory-stub
sudo systemctl restart kente-app

# Smoke test: a deploy that leaves /health failing is a failed deploy.
sleep 2
if curl -fsS http://localhost:8080/health >/dev/null; then
  echo "Deploy OK: /health returned 200"
else
  echo "Deploy finished but /health is FAILING." >&2
  echo "First check: getent hosts inventory.kente.internal (must be 127.0.0.1)" >&2
  exit 1
fi