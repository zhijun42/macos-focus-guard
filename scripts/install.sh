#!/bin/bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
exec "$repo/scripts/install-opera-guard.sh" "$@"
