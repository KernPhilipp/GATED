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

Workflow: `.github/workflows/release.yml`

On release publish:

1. Build Flutter web (`API_BASE_URL=/api`)
2. Build release package
3. Upload package to GitHub release

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

Edit values (important):

- `/home/gated/gated-frontend/shared/backend.env` -> set `JWT_SECRET`
- `/home/gated/gated-frontend/shared/deploy.env` -> check `GITHUB_REPO`

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

## Smoke checks

```bash
systemctl status gated-backend.service
curl -i http://127.0.0.1:8080/health
curl -i http://127.0.0.1:8090
curl -i http://<pi-ip>:8090
```
