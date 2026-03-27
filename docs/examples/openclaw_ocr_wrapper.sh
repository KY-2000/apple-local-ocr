#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OCR_BIN="${OCR_BIN:-$REPO_ROOT/.build/release/apple-local-ocr}"

usage() {
  cat <<'EOF'
Usage:
  openclaw_ocr_wrapper.sh version
  openclaw_ocr_wrapper.sh inspect <path...>
  openclaw_ocr_wrapper.sh json <path...>

Commands:
  version  Print the OCR tool version.
  inspect  Preview OCR jobs with recursive folder handling.
  json     Run OCR with --stdout --format json --error-format json --recursive.

Environment:
  OCR_BIN  Optional path to the apple-local-ocr binary.
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 64
fi

command="$1"
shift

if [[ ! -x "$OCR_BIN" ]]; then
  echo "OCR binary not found or not executable: $OCR_BIN" >&2
  exit 66
fi

case "$command" in
  version)
    exec "$OCR_BIN" --version
    ;;
  inspect)
    if [[ $# -lt 1 ]]; then
      echo "inspect requires at least one input path" >&2
      exit 64
    fi
    exec "$OCR_BIN" inspect --recursive "$@"
    ;;
  json)
    if [[ $# -lt 1 ]]; then
      echo "json requires at least one input path" >&2
      exit 64
    fi
    exec "$OCR_BIN" --stdout --format json --error-format json --recursive "$@"
    ;;
  *)
    usage
    exit 64
    ;;
esac
