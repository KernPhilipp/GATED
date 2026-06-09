# GATED Deployment

Dieser Ordner enthält die Deployment-Dateien für den Raspberry Pi.

## Dateien

- `build_release_package.sh`: erstellt das Release-Paket
- `deploy_release.sh`: lädt und aktiviert GitHub Releases auf dem Pi
- `gated-backend.service`: systemd Service für das Backend
- `gated-deploy.service`: manueller Deploy-Trigger
- `gated-deploy.timer`: regelmäßige Deploy-Prüfung
- `gated.conf`: nginx Frontend-Auslieferung und `/api/` Proxy
- `backend.env.example`: Backend-Env-Vorlage
- `deploy.env.example`: Deploy-Env-Vorlage

## Release-Ablauf

1. GitHub Actions baut Flutter Web mit `API_BASE_URL=/api` und `--no-web-resources-cdn`.
2. `build_release_package.sh` packt das Frontend und Backend.
3. Das Paket wird an ein GitHub Release gehängt.
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

Die HTTP-URL funktioniert als Website. Für eine installierbare PWA im LAN
braucht der Browser in der Regel `https://<hostname>` mit vertrauenswuerdigem
Zertifikat.

## Offline/LAN-Betrieb

Das Frontend muss ohne Google-CDN-Zugriffe gebaut werden:

`flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=/api`

CanvasKit wird dadurch im Release-Paket mitgeliefert. Die Barlow-Schriften
liegen unter `gated/assets/fonts/`; Runtime-Font-Downloads sind in der App
deaktiviert. Flutter-Webs Roboto-Fallback liegt unter
`gated/web/fallback_fonts/` und wird per `fontFallbackBaseUrl` lokal geladen.

Konkrete Setup- und Diagnosebefehle stehen in `informationen/PiSetupBefehle.txt`.
