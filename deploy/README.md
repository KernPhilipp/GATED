# GATED Deployment

Dieser Ordner enthaelt die Deployment-Dateien fuer den Raspberry Pi.

## Dateien

- `build_release_package.sh`: erstellt das Release-Paket
- `deploy_release.sh`: laedt und aktiviert GitHub Releases auf dem Pi
- `gated-backend.service`: systemd Service fuer das Backend
- `gated-deploy.service`: manueller Deploy-Trigger
- `gated-deploy.timer`: regelmaessige Deploy-Pruefung
- `gated.conf`: nginx Frontend-Auslieferung und `/api/` Proxy
- `backend.env.example`: Backend-Env-Vorlage
- `deploy.env.example`: Deploy-Env-Vorlage

## Release-Ablauf

1. GitHub Actions baut Flutter Web mit `API_BASE_URL=/api`.
2. `build_release_package.sh` packt das Frontend und Backend.
3. Das Paket wird an ein GitHub Release gehaengt.
4. `deploy_release.sh` entpackt neue Releases auf dem Pi.
5. Der `current`-Symlink wird auf das neue Release gesetzt.

Alte Releases bleiben nur als Rollback-Fenster erhalten. Die Anzahl steuert
`KEEP_RELEASES`.

## Runtime-Dateien

Auf dem Pi liegen echte Laufzeitdateien ausserhalb des Repository-Checkouts:

`/home/gated/gated-frontend/shared/`

Dort liegen insbesondere:

- `backend.env`
- `deploy.env`
- `allowed_emails.txt`
- `gated.db`
- `kennzeichen.db`

Die Dateien `*.env.example` im Repository sind nur Vorlagen. Echte Secrets
nicht in den Repository-Checkout schreiben.

## URLs

- Frontend im LAN: `http://<pi-ip>:8090`
- Backend intern: `http://127.0.0.1:8091`
- Backend Health: `http://127.0.0.1:8091/health`

## PWA im LAN

Die HTTP-URL funktioniert als Website. Fuer eine installierbare PWA im LAN
braucht der Browser in der Regel `https://<hostname>` mit vertrauenswuerdigem
Zertifikat.

Konkrete Setup- und Diagnosebefehle stehen in `informationen/PiSetupBefehle.txt`.
