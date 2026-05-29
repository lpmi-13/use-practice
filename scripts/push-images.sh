#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_root}/scripts/lib/versions.sh"

usage() {
  cat <<'EOF'
Usage: IMAGE_TAG=v1 bash scripts/push-images.sh

Pushes the iximiuz rootfs image to the configured registry.

Environment:
  IMAGE_TAG      Image tag to push. Defaults to DEFAULT_FIRST_PARTY_IMAGE_TAG.
  ROOTFS_IMAGE   Full rootfs image reference. Defaults to ROOTFS_IMAGE_REPO:IMAGE_TAG.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 0 ]]; then
  echo "error: unknown argument '$1'." >&2
  usage >&2
  exit 1
fi

image_tag="${IMAGE_TAG:-${DEFAULT_FIRST_PARTY_IMAGE_TAG}}"
rootfs_image="${ROOTFS_IMAGE:-${ROOTFS_IMAGE_REPO}:${image_tag}}"
rootfs_image="${rootfs_image#oci://}"

if [[ ! "${image_tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo "error: invalid IMAGE_TAG '${image_tag}'." >&2
  exit 1
fi

if ! docker image inspect "${rootfs_image}" >/dev/null 2>&1; then
  echo "error: Docker image ${rootfs_image} does not exist locally." >&2
  exit 1
fi

echo "Pushing ${rootfs_image}..."
docker push "${rootfs_image}"
