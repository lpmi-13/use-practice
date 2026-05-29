#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rootfs_image=""

usage() {
  cat <<'EOF'
Usage: scripts/update-version-refs.sh --rootfs-image ghcr.io/owner/use-practice-rootfs:v1

Updates iximiuz deployment files after building or publishing a rootfs image.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root)
      shift
      [[ $# -gt 0 ]] || { echo "error: --repo-root requires a value." >&2; exit 1; }
      repo_root="$1"
      ;;
    --rootfs-image)
      shift
      [[ $# -gt 0 ]] || { echo "error: --rootfs-image requires a value." >&2; exit 1; }
      rootfs_image="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'." >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${rootfs_image}" ]]; then
  echo "error: --rootfs-image is required." >&2
  usage >&2
  exit 1
fi

rootfs_image="${rootfs_image#oci://}"
manifest="${repo_root}/playground/iximiuz/manifest.yaml"
versions="${repo_root}/scripts/lib/versions.sh"

[[ -f "${manifest}" ]] || { echo "error: missing ${manifest}." >&2; exit 1; }
[[ -f "${versions}" ]] || { echo "error: missing ${versions}." >&2; exit 1; }

escaped_rootfs="$(printf '%s' "${rootfs_image}" | sed -e 's/[\/&]/\\&/g')"
escaped_source="$(printf '%s' "oci://${rootfs_image}" | sed -e 's/[\/&]/\\&/g')"

sed -i -E \
  "s#^(readonly DEFAULT_IXIMIUZ_ROOTFS_IMAGE=\").*(\")#\1${escaped_rootfs}\2#" \
  "${versions}"

sed -i -E \
  "s#^([[:space:]]*-[[:space:]]*source:[[:space:]]*).+#\1${escaped_source}#" \
  "${manifest}"

echo "Updated iximiuz rootfs image reference:"
echo "  ${rootfs_image}"
