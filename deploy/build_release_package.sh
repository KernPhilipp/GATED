#!/usr/bin/env bash
set -euo pipefail

TAG_NAME="${1:-dev}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${REPO_ROOT}/.release-build"
DIST_ROOT="${REPO_ROOT}/.release-dist"
PACKAGE_NAME="gated-release.tar.gz"

echo "Preparing release package for tag: ${TAG_NAME}"

rm -rf "${BUILD_ROOT}" "${DIST_ROOT}"
mkdir -p "${BUILD_ROOT}" "${DIST_ROOT}"

if [[ ! -d "${REPO_ROOT}/gated/build/web" ]]; then
  echo "Missing Flutter web build at gated/build/web."
  echo "Run flutter build web before packaging."
  exit 1
fi

echo "Copying Flutter web build..."
cp -R "${REPO_ROOT}/gated/build/web" "${BUILD_ROOT}/web"

echo "Copying backend sources..."
rsync -a \
  --exclude '.env' \
  --exclude '*.db' \
  --exclude '.dart_tool' \
  --exclude 'build' \
  --exclude '.packages' \
  "${REPO_ROOT}/gated/backend/" "${BUILD_ROOT}/backend/"

echo "Copying deploy assets..."
cp -R "${REPO_ROOT}/deploy" "${BUILD_ROOT}/deploy"

echo "${TAG_NAME}" > "${BUILD_ROOT}/VERSION"

echo "Creating package archive..."
tar -czf "${DIST_ROOT}/${PACKAGE_NAME}" -C "${BUILD_ROOT}" .

echo "Creating checksum..."
sha256sum "${DIST_ROOT}/${PACKAGE_NAME}" > "${DIST_ROOT}/${PACKAGE_NAME}.sha256"

echo "Release package created:"
echo "  ${DIST_ROOT}/${PACKAGE_NAME}"
echo "  ${DIST_ROOT}/${PACKAGE_NAME}.sha256"
