#!/usr/bin/env bash
# Copy the app to the server folder and restart the service.
set -euo pipefail
sudo install -d -o kentesvc -g kente-ops /opt/kente-app
sudo cp -r app config /opt/kente-app/
sudo cp deploy/kente-app.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart kente-app
