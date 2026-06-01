#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
source "${repo_root}/scripts/lib/versions.sh"

image_tag="${IMAGE_TAG:-${DEFAULT_FIRST_PARTY_IMAGE_TAG}}"
rootfs_image="${ROOTFS_IMAGE:-${ROOTFS_IMAGE_REPO}:${image_tag}}"
push_rootfs_image="${PUSH_ROOTFS_IMAGE:-${PUSH_IMAGE:-0}}"

if [[ "${rootfs_image}" == oci://* ]]; then
  rootfs_image="${rootfs_image#oci://}"
fi

if [[ ! "${image_tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  echo "error: invalid IMAGE_TAG '${image_tag}'." >&2
  exit 1
fi

copy_path() {
  local source="$1"
  local destination="$2"

  [[ -e "${source}" ]] || { echo "error: missing ${source}." >&2; exit 1; }
  mkdir -p "$(dirname "${destination}")"
  cp -R "${source}" "${destination}"
}

build_context="$(mktemp -d /tmp/use-practice-rootfs-build.XXXXXX)"
trap 'rm -rf "${build_context}"' EXIT

mkdir -p "${build_context}/use-practice" "${build_context}/playground/iximiuz"
cp "${repo_root}/playground/iximiuz/Dockerfile" "${build_context}/Dockerfile"
cp -R "${repo_root}/playground/iximiuz/image" "${build_context}/playground/iximiuz/"

for item in \
  loadgen \
  reveal.sh \
  run.sh \
  scenarios \
  scripts \
  stop-all.sh \
  use-practice
do
  copy_path "${repo_root}/${item}" "${build_context}/use-practice/${item}"
done

find "${build_context}/use-practice" \
  \( -name .runtime -o -name .logs -o -name __pycache__ -o -name target -o -name bin \) \
  -prune -exec rm -rf {} +
find "${build_context}/use-practice" \
  \( -name .env -o -name .answer -o -name .run-id -o -name .pids -o -name .processes -o -name .netns -o -name .links \) \
  -type f -delete

echo "Rootfs package: ${ROOTFS_IMAGE_REPO}"
echo "Rootfs image:   ${rootfs_image}"
echo "Building ${rootfs_image}..."
docker build -t "${rootfs_image}" "${build_context}"

if [[ "${push_rootfs_image}" != "0" ]]; then
  echo "Pushing ${rootfs_image}..."
  docker push "${rootfs_image}"
fi

echo "Updating checked-in iximiuz manifest..."
bash "${repo_root}/scripts/update-version-refs.sh" --rootfs-image "${rootfs_image}"

echo
echo "Built rootfs image ${rootfs_image}"
if [[ "${push_rootfs_image}" != "0" ]]; then
  echo "Pushed ${rootfs_image}"
fi
