#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

default_rootfs_image_repo="ghcr.io/lpmi-13/use-practice-rootfs"
default_first_party_image_tag="v10"

rootfs_image_repo="${ROOTFS_IMAGE_REPO:-${default_rootfs_image_repo}}"
image_tag="${IMAGE_TAG:-${default_first_party_image_tag}}"
rootfs_image="${ROOTFS_IMAGE:-${rootfs_image_repo}:${image_tag}}"
push_rootfs_image="${PUSH_ROOTFS_IMAGE:-${PUSH_IMAGE:-0}}"
dry_run="${DRY_RUN:-0}"
update_manifest="${UPDATE_MANIFEST:-1}"

if [[ "${rootfs_image}" == oci://* ]]; then
  rootfs_image="${rootfs_image#oci://}"
fi

if [[ -z "${IMAGE_TAG:-}" ]]; then
  derived_image_tag="${rootfs_image##*:}"
  if [[ "${derived_image_tag}" != "${rootfs_image}" && -n "${derived_image_tag}" && "${derived_image_tag}" != */* ]]; then
    image_tag="${derived_image_tag}"
  fi
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
  cmd \
  go.mod \
  internal \
  loadgen \
  scenarios
do
  copy_path "${repo_root}/${item}" "${build_context}/use-practice/${item}"
done
copy_path "${repo_root}/scripts/lib.sh" "${build_context}/use-practice/scripts/lib.sh"

find "${build_context}/use-practice" \
  \( -name .runtime -o -name .logs -o -name __pycache__ -o -name target -o -name bin \) \
  -prune -exec rm -rf {} +
find "${build_context}/use-practice" \
  \( -name .env -o -name .answer -o -name .run-id -o -name .pids -o -name .processes -o -name .netns -o -name .links \) \
  -type f -delete

echo "Rootfs package: ${rootfs_image_repo}"
echo "Rootfs image:   ${rootfs_image}"
if [[ "${dry_run}" != "0" ]]; then
  echo "Dry run: build context contents:"
  find "${build_context}" -maxdepth 10 -type f | sort
  exit 0
fi

echo "Building ${rootfs_image}..."
docker build -t "${rootfs_image}" "${build_context}"

if [[ "${push_rootfs_image}" != "0" ]]; then
  echo "Pushing ${rootfs_image}..."
  docker push "${rootfs_image}"
fi

if [[ "${update_manifest}" != "0" ]]; then
  echo "Updating checked-in iximiuz manifest..."
  escaped_rootfs_source="$(printf '%s' "oci://${rootfs_image}" | sed -e 's/[\/&]/\\&/g')"
  escaped_image_tag="$(printf '%s' "${image_tag}" | sed -e 's/[\/&]/\\&/g')"
  sed -i -E \
    "s#^([[:space:]]*-[[:space:]]*source:[[:space:]]*).+#\1${escaped_rootfs_source}#" \
    "${repo_root}/playground/iximiuz/manifest.yaml"
  sed -i -E \
    "s#^(default_first_party_image_tag=\").*(\")#\1${escaped_image_tag}\2#" \
    "${repo_root}/scripts/build-rootfs-image.sh"
else
  echo "Skipping checked-in iximiuz manifest update."
fi

echo
echo "Built rootfs image ${rootfs_image}"
if [[ "${push_rootfs_image}" != "0" ]]; then
  echo "Pushed ${rootfs_image}"
fi
