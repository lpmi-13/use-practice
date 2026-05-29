#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
source "${repo_root}/scripts/lib/versions.sh"

image_tag="${IMAGE_TAG:-${DEFAULT_FIRST_PARTY_IMAGE_TAG}}"
rootfs_image="${ROOTFS_IMAGE:-${ROOTFS_IMAGE_REPO}:${image_tag}}"
push_rootfs_image="${PUSH_ROOTFS_IMAGE:-${PUSH_IMAGE:-0}}"
use_tool_root="${USE_TOOL_ROOT:-$(cd "${repo_root}/../use-tool" 2>/dev/null && pwd || true)}"
use_tool_bin="${USE_TOOL_BIN:-}"

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

mkdir -p "${build_context}/use-practice" "${build_context}/use-tool" "${build_context}/playground/iximiuz"
cp "${repo_root}/playground/iximiuz/Dockerfile" "${build_context}/Dockerfile"
cp -R "${repo_root}/playground/iximiuz/image" "${build_context}/playground/iximiuz/"

for item in \
  LICENSE \
  PLAN.md \
  README.md \
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
  \( -name .runtime -o -name .logs -o -name __pycache__ \) \
  -prune -exec rm -rf {} +
find "${build_context}/use-practice" \
  \( -name .env -o -name .answer -o -name .run-id -o -name .pids -o -name .processes -o -name .netns -o -name .links \) \
  -type f -delete

if [[ -z "${use_tool_bin}" && -n "${use_tool_root}" && -x "${use_tool_root}/use-tool" ]]; then
  use_tool_bin="${use_tool_root}/use-tool"
fi

if [[ -n "${use_tool_bin}" ]]; then
  [[ -x "${use_tool_bin}" ]] || { echo "error: USE_TOOL_BIN is not executable: ${use_tool_bin}" >&2; exit 1; }
  cp "${use_tool_bin}" "${build_context}/use-tool/use-tool"
elif [[ -n "${use_tool_root}" && -f "${use_tool_root}/go.mod" ]] && command -v go >/dev/null 2>&1; then
  echo "Building use-tool from ${use_tool_root}..."
  (cd "${use_tool_root}" && go build -o "${build_context}/use-tool/use-tool" ./...)
else
  echo "error: could not find use-tool binary." >&2
  echo "Set USE_TOOL_BIN=/path/to/use-tool or USE_TOOL_ROOT=/path/to/use-tool." >&2
  exit 1
fi

chmod 755 "${build_context}/use-tool/use-tool"

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
