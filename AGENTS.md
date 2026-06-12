# AGENTS.md — telescope-m1.nvim

Guidance for coding agents working in this repository.

## Purpose

Telescope pickers over the M1 project model: workspace symbols, the component
tree, call rates, and the lint-rule catalogue. It is a *presentation* layer —
the data always comes from the toolchain, never from logic re-implemented
here.

## The no-duplication contract (deliberate — don't "fix" it)

- **Symbols and components come from `m1-lsp`** (`workspace/symbol`). There
  is no local `.m1prj` parser, and there must never be one — that's how the
  pickers stay correct as the toolchain evolves.
- **The lint-rule list mirrors `m1-lint --rules`.** A sync test downloads the
  latest released `m1-lint` and fails if `lua/telescope-m1/rules.lua` drifts
  (codes, names, fixability). Consequence: **an m1-lint release that adds
  rules breaks this repo's CI** until `rules.lua` (and the test's expected
  list) is synced — that sync belongs in the same release cascade, and a red
  CI here after a lint release is the contract working, not a flake.
- **The LSP client name is read from `nvim-m1`** when present, so the two
  plugins can't disagree about which client to query.
- **Mutations go through nvim-m1 → m1-project** (the set/rename/delete
  mappings). Don't write project XML from this repo.
- The picker UI should tolerate a model that's mid-reload: prefer
  re-querying over caching project state across picker invocations.

## Build / test gate

```sh
scripts/test.sh                          # headless plenary-busted suite
stylua --check lua/                      # separate CI job
```

Tests use synthetic fixtures only — no project data is checked in. The
rules-sync spec needs network access to fetch the released `m1-lint`.

## Releases

Cut from the `VERSION` file on `main` (release.yml tags `vX.Y.Z`). Most
releases here are reactive: syncing `rules.lua` after an m1-lint release, or
picking up nvim-m1 API changes.
