#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
source "${repo_root}/scripts/lib/versions.sh"

image_tag="${IMAGE_TAG:-${DEFAULT_FIRST_PARTY_IMAGE_TAG}}"
rootfs_image="${ROOTFS_IMAGE:-${ROOTFS_IMAGE_REPO}:${image_tag}}"
push_rootfs_image="${PUSH_ROOTFS_IMAGE:-${PUSH_IMAGE:-0}}"
use_tool_version="${USE_TOOL_VERSION:-${USE_TOOL_RELEASE_VERSION}}"
use_tool_arch="${USE_TOOL_ARCH:-}"

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

detect_release_arch() {
  local arch="${1:-$(uname -m)}"

  case "${arch}" in
    amd64|x86_64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) echo "error: unsupported use-tool release architecture '${arch}'." >&2; exit 1 ;;
  esac
}

latest_use_tool_tag() {
  curl -fsSL "https://api.github.com/repos/${USE_TOOL_RELEASE_REPO}/releases/latest" |
    sed -n 's/^[[:space:]]*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' |
    head -n1
}

install_use_tool_release() {
  local destination="$1"
  local tag version arch asset base_url tmp

  if [[ "${use_tool_version}" == "latest" ]]; then
    tag="$(latest_use_tool_tag)"
  else
    tag="${use_tool_version}"
  fi
  [[ -n "${tag}" ]] || { echo "error: could not resolve latest use-tool release tag." >&2; exit 1; }

  version="${tag#v}"
  arch="$(detect_release_arch "${use_tool_arch:-}")"
  asset="use-tool_${version}_linux_${arch}.tar.gz"
  base_url="https://github.com/${USE_TOOL_RELEASE_REPO}/releases/download/${tag}"
  tmp="$(mktemp -d /tmp/use-tool-release.XXXXXX)"

  echo "Downloading use-tool ${tag} (${arch}) from GitHub releases..."
  curl -fsSL -o "${tmp}/${asset}" "${base_url}/${asset}"
  curl -fsSL -o "${tmp}/checksums.txt" "${base_url}/checksums.txt"

  (cd "${tmp}" && grep -F "  ${asset}" checksums.txt | sha256sum -c -)
  tar -xzf "${tmp}/${asset}" -C "${tmp}" use-tool
  install -m 0755 "${tmp}/use-tool" "${destination}"
  rm -rf "${tmp}"

  echo "Installed use-tool ${tag} into the rootfs build context."
}

build_context="$(mktemp -d /tmp/use-practice-rootfs-build.XXXXXX)"
trap 'rm -rf "${build_context}"' EXIT

mkdir -p "${build_context}/use-practice" "${build_context}/use-tool" "${build_context}/playground/iximiuz"
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

install_use_tool_release "${build_context}/use-tool/use-tool"

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
