#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f .active-scenario ]; then
  echo "No active scenario. Start one with ./run.sh"
  exit 1
fi
PICK=$(cat .active-scenario)
if [ ! -f "scenarios/$PICK/.answer" ]; then
  echo "Scenario '$PICK' has no answer file. Was it started?"
  exit 1
fi
cat "scenarios/$PICK/.answer"
