#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./use-practice run "${@:-random}"
