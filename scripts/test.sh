#!/usr/bin/env bash
set -euo pipefail

NVIM_BIN="${NVIM_BIN:-nvim}"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for spec in "$ROOT"/tests/*_spec.lua; do
  SPEC_PATH="$spec" "$NVIM_BIN" --headless -u "$ROOT/tests/minimal_init.lua" \
    -c "lua dofile(vim.env.SPEC_PATH)" \
    -c qa
done
