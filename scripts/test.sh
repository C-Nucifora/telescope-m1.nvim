#!/usr/bin/env bash
# Run the telescope-m1.nvim test suite headless with plenary-busted.
#
#   scripts/test.sh
#
# plenary and telescope are located via $PLENARY_PATH / $TELESCOPE_PATH or the
# lazy.nvim data dir.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PLENARY_PATH="${PLENARY_PATH:-$HOME/.local/share/nvim/lazy/plenary.nvim}"
export TELESCOPE_PATH="${TELESCOPE_PATH:-$HOME/.local/share/nvim/lazy/telescope.nvim}"

nvim --headless --noplugin -u "$here/tests/minimal_init.lua" \
  -c "PlenaryBustedDirectory $here/tests { minimal_init = '$here/tests/minimal_init.lua', sequential = true }" \
  "$@"
