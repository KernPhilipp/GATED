#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/tmp/gated-deploy.lock"
exec 200>"${LOCK_FILE}"
if ! flock -n 200; then
  echo "Another deploy is already running. Exiting."
  exit 0
fi

GATED_ROOT="${GATED_ROOT:-/home/gated/gated-frontend}"
RELEASES_DIR="${RELEASES_DIR:-${GATED_ROOT}/releases}"
CURRENT_LINK="${CURRENT_LINK:-${GATED_ROOT}/current}"
SHARED_DIR="${SHARED_DIR:-${GATED_ROOT}/shared}"
STATE_DIR="${STATE_DIR:-${GATED_ROOT}/state}"
TMP_DIR="${TMP_DIR:-${GATED_ROOT}/tmp}"
BACKEND_ENV_FILE="${BACKEND_ENV_FILE:-${SHARED_DIR}/backend.env}"
BACKEND_SERVICE_NAME="${BACKEND_SERVICE_NAME:-gated-backend.service}"
BACKEND_HEALTH_URL="${BACKEND_HEALTH_URL:-http://127.0.0.1:8091/health}"
APP_USER="${APP_USER:-gated}"
APP_GROUP="${APP_GROUP:-${APP_USER}}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
ASSET_NAME="${ASSET_NAME:-gated-release.tar.gz}"
FORCE_DEPLOY="${FORCE_DEPLOY:-0}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "${GITHUB_REPO}" ]]; then
  echo "GITHUB_REPO is required, e.g. owner/repo."
  exit 1
fi

mkdir -p "${RELEASES_DIR}" "${SHARED_DIR}" "${STATE_DIR}" "${TMP_DIR}"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

github_api() {
  local url="$1"
  if [[ -n "${GITHUB_TOKEN}" ]]; then
    curl -fsSL \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "${url}"
  else
    curl -fsSL -H "Accept: application/vnd.github+json" "${url}"
  fi
}

extract_tag() {
  python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))"
}

extract_asset_url() {
  local asset_name="$1"
  python3 -c "import json,sys;
release=json.load(sys.stdin);
for asset in release.get('assets', []):
    if asset.get('name') == '${asset_name}':
        print(asset.get('browser_download_url',''));
        break
"
}

healthcheck() {
  local attempt=1
  while [[ "${attempt}" -le 20 ]]; do
    if curl -fsS "${BACKEND_HEALTH_URL}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done
  return 1
}

cleanup_old_releases() {
  local keep="$1"
  mapfile -t release_dirs < <(find "${RELEASES_DIR}" -mindepth 1 -maxdepth 1 -type d -print | sort -r)
  if [[ "${#release_dirs[@]}" -le "${keep}" ]]; then
    return
  fi

  local index=0
  for dir_path in "${release_dirs[@]}"; do
    index=$((index + 1))
    if [[ "${index}" -le "${keep}" ]]; then
      continue
    fi
    rm -rf "${dir_path}"
    log "Removed old release ${dir_path}"
  done
}

log "Fetching latest release metadata from ${GITHUB_REPO}"
release_json="$(github_api "https://api.github.com/repos/${GITHUB_REPO}/releases/latest")"
release_tag="$(printf '%s' "${release_json}" | extract_tag)"
asset_url="$(printf '%s' "${release_json}" | extract_asset_url "${ASSET_NAME}")"

if [[ -z "${release_tag}" || -z "${asset_url}" ]]; then
  log "Release tag or asset URL could not be resolved."
  exit 1
fi

last_tag_file="${STATE_DIR}/last_tag"
last_tag=""
if [[ -f "${last_tag_file}" ]]; then
  last_tag="$(cat "${last_tag_file}")"
fi

if [[ "${FORCE_DEPLOY}" != "1" && "${release_tag}" == "${last_tag}" ]]; then
  log "Release ${release_tag} already deployed. Nothing to do."
  exit 0
fi

log "Downloading ${ASSET_NAME} for ${release_tag}"
download_path="${TMP_DIR}/${release_tag}-${ASSET_NAME}"
if [[ -n "${GITHUB_TOKEN}" ]]; then
  curl -fL --retry 3 \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -o "${download_path}" "${asset_url}"
else
  curl -fL --retry 3 -o "${download_path}" "${asset_url}"
fi

timestamp="$(date -u +'%Y%m%d%H%M%S')"
release_dir="${RELEASES_DIR}/${timestamp}-${release_tag}"
mkdir -p "${release_dir}"
tar -xzf "${download_path}" -C "${release_dir}"

if [[ ! -d "${release_dir}/backend" || ! -d "${release_dir}/web" ]]; then
  log "Downloaded package does not contain backend/ and web/."
  rm -rf "${release_dir}"
  exit 1
fi

if [[ ! -f "${BACKEND_ENV_FILE}" ]]; then
  log "Missing ${BACKEND_ENV_FILE}. Create it from deploy/backend.env.example first."
  rm -rf "${release_dir}"
  exit 1
fi

ln -sfn "${BACKEND_ENV_FILE}" "${release_dir}/backend/.env"

chown -R "${APP_USER}:${APP_GROUP}" "${release_dir}"

log "Installing backend dependencies in new release as ${APP_USER}"
su -s /bin/bash "${APP_USER}" -c "cd \"${release_dir}/backend\" && dart pub get"

previous_release=""
if [[ -L "${CURRENT_LINK}" ]]; then
  previous_release="$(readlink -f "${CURRENT_LINK}")"
fi

log "Switching current release to ${release_dir}"
ln -sfn "${release_dir}" "${CURRENT_LINK}"
systemctl restart "${BACKEND_SERVICE_NAME}"

if ! healthcheck; then
  log "Healthcheck failed for ${release_tag}. Rolling back."
  if [[ -n "${previous_release}" && -d "${previous_release}" ]]; then
    ln -sfn "${previous_release}" "${CURRENT_LINK}"
    systemctl restart "${BACKEND_SERVICE_NAME}"
  fi
  exit 1
fi

echo "${release_tag}" > "${last_tag_file}"
cleanup_old_releases "${KEEP_RELEASES}"
rm -f "${download_path}"

log "Deployment successful: ${release_tag}"
