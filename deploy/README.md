# GATED Deploy (Simple)

This folder is intentionally flat and minimal.

## Files

- `build_release_package.sh`: creates `gated-release.tar.gz` + checksum
- `deploy_release.sh`: pulls latest GitHub release and deploys it on the Pi
- `gated-backend.service`: backend systemd service
- `gated-deploy.service`: one-shot deploy trigger service
- `gated-deploy.timer`: runs deploy check every 10 minutes
- `gated.conf`: nginx config (`/` static web, `/api/` backend proxy)
- `backend.env.example`: backend runtime env template
- `deploy.env.example`: deploy runtime env template

## CI/CD

Workflows:

- `.github/workflows/ci.yml`: runs Flutter + backend analyze/test on every push
  and pull request
- `.github/workflows/release.yml`: builds the production web bundle and release
  package for release publish / manual dispatch

On release publish:

1. Build Flutter web (`API_BASE_URL=/api`)
2. Build release package
3. Upload package to GitHub release

GitHub Actions secrets / variables:

- No custom repository secrets or variables are currently required for these
  workflows.
- The release upload uses the GitHub-provided `GITHUB_TOKEN`.
- `deploy.env` on the Raspberry Pi is runtime/deploy configuration on the
  target machine, not a GitHub Actions secret.

## Environment files

Local development:

- `gated/backend/.env.example` is the template for local backend development.
- Create `gated/backend/.env` only on your local machine when you run
  `dart run server.dart` directly.
- That local file stays inside the repo directory but is ignored by
  `gated/.gitignore`.

Production / Raspberry Pi:

- `deploy/backend.env.example` and `deploy/deploy.env.example` are templates
  only.
- The real production files must live outside the repo at
  `/home/gated/gated-frontend/shared/backend.env` and
  `/home/gated/gated-frontend/shared/deploy.env`.
- Do not store production secrets in `deploy/backend.env` or
  `deploy/deploy.env` inside the repository checkout.

## Raspberry Pi setup (manual, minimal)

Prerequisites:

- `dart`, `curl`, `tar`, `python3`, `nginx`, `systemd`

Create layout:

```bash
sudo mkdir -p /home/gated/gated-frontend/{bin,releases,shared,state,tmp}
```

Install files:

```bash
sudo install -m 0750 deploy/deploy_release.sh /home/gated/gated-frontend/bin/gated-deploy.sh
sudo install -m 0644 deploy/gated-backend.service /etc/systemd/system/gated-backend.service
sudo install -m 0644 deploy/gated-deploy.service /etc/systemd/system/gated-deploy.service
sudo install -m 0644 deploy/gated-deploy.timer /etc/systemd/system/gated-deploy.timer
sudo install -m 0644 deploy/gated.conf /etc/nginx/sites-available/gated
sudo ln -sfn /etc/nginx/sites-available/gated /etc/nginx/sites-enabled/gated
```

Create env files:

```bash
sudo cp deploy/backend.env.example /home/gated/gated-frontend/shared/backend.env
sudo cp deploy/deploy.env.example /home/gated/gated-frontend/shared/deploy.env
```

These commands copy the tracked templates into the Pi's shared runtime
directory. The real runtime files stay outside the repository checkout.

Edit values (important):

- `/home/gated/gated-frontend/shared/backend.env` -> set `JWT_SECRET`
- `/home/gated/gated-frontend/shared/deploy.env` -> check `GITHUB_REPO`
- optional in `deploy.env`: `APP_USER` / `APP_GROUP` if the service should not run as `gated`

Enable/start services:

```bash
sudo systemctl daemon-reload
sudo systemctl enable gated-backend.service
sudo systemctl enable --now gated-deploy.timer
sudo systemctl start gated-deploy.service
sudo nginx -t && sudo systemctl restart nginx
```

Frontend URL:

- `http://<pi-ip>:8090`

## Installierbare Web-App im LAN

Damit Browser GATED als installierbare Web-App anbieten, braucht die
Auslieferung einen sicheren Kontext:

- `http://localhost` fuer lokale Entwicklung
- `https://<hostname>` fuer Zugriffe im LAN

Wichtig:

- Die normale HTTP-URL `http://<pi-ip>:8090` funktioniert weiterhin als Website.
- Chrome, Edge und andere Chromium-Browser bieten die PWA-Installation auf
  einer LAN-IP ohne HTTPS in der Regel nicht an.
- Fuer eine echte Browser-Installation im Netzwerk ist daher ein Zertifikat
  auf einem vertrauenswuerdigen Hostnamen notwendig.

## Smoke checks

```bash
systemctl status gated-backend.service
curl -i http://127.0.0.1:8091/health
curl -i http://127.0.0.1:8090
curl -i http://<pi-ip>:8090
```
