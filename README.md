# Kente Retail web app (kente-app)

Small Python web app that serves the Kente Retail storefront page and a
`/health` endpoint. It depends on the internal **inventory** service.

| What | Where |
|---|---|
| Code on the server | `/opt/kente-app` |
| Data | `/opt/kente-app/data` |
| Logs | `/var/log/kente-app` |
| Service | `systemctl status kente-app` |
| Port | 8080 |

## Deploy
`sudo scripts/deploy.sh` copies the app to `/opt/kente-app` and restarts the service.

## Release notes
- v1.0: first version on the new server.
- v1.1: health check now calls the inventory service by name (inventory.kente.internal).
