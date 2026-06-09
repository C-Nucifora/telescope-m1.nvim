# telescope-m1.nvim

[Telescope](https://github.com/nvim-telescope/telescope.nvim) extension for [M1 script](https://github.com/C-Nucifora/m1-tools). Adds pickers for:

- **Workspace symbols** — fuzzy-search all channels, parameters, enums and functions in the loaded project
- **Component browser** — browse the project's component tree as an indented hierarchy
- **Lint rules** — pick an `m1-lint` rule to open its docs, yank its code, or ignore it

The symbol and component pickers are powered by `m1-lsp`'s `workspace/symbol` —
the component browser presents the *same* data the toolchain builds from
`Project.m1prj`, so it never drifts from the project. The lint-rule list is kept
in sync with `m1-lint` (see [Staying in sync](#staying-in-sync)).

## Requirements

- Neovim ≥ 0.10
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [m1-lsp](https://github.com/C-Nucifora/m1-lsp) running in the workspace (symbol/component pickers)
- Recommended: [nvim-m1](https://github.com/C-Nucifora/nvim-m1) — sets up `m1-lsp` and shares the
  canonical client name so the pickers find it automatically. Works with any
  setup that runs `m1-lsp`, but nvim-m1 is the turn-key path.

## Installation

```lua
-- lazy.nvim
{
  "C-Nucifora/telescope-m1.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "C-Nucifora/nvim-m1", -- recommended: starts m1-lsp + shares the client name
  },
  config = function()
    require("telescope").load_extension("m1")
  end,
}
```

## Usage

```lua
-- Workspace symbol picker
require("telescope").extensions.m1.workspace_symbols()

-- Project component browser
require("telescope").extensions.m1.components()

-- Lint rule picker
require("telescope").extensions.m1.lint_rules()
```

Or via command palette:
```
:Telescope m1 workspace_symbols
:Telescope m1 components
:Telescope m1 lint_rules
:Telescope m1 call_rates
```

### Picker mappings

| Picker | Key | Action |
| --- | --- | --- |
| workspace_symbols / components | `<CR>` | jump to the symbol's definition |
| components | `<C-f>` | (functions) jump to the backing script |
| components | `<C-s>` / `<C-t>` / `<C-u>` | set the entry's security / storage type / display unit (via nvim-m1 + m1-project) |
| call_rates | `<CR>` | browse the scripts scheduled at the picked rate |
| call_rates | `<C-a>` | assign a script to the picked rate |
| lint_rules | `<CR>` | open the rule's documentation |
| lint_rules | `<C-y>` | yank the rule code (e.g. `L004`) |
| lint_rules | `<C-i>` | append the code to the project's `.m1lint.toml` ignore list |

## Staying in sync

This extension deliberately avoids re-implementing what the toolchain already
owns, so new M1 features show up here without code changes:

- **Symbols & components** come from `m1-lsp` (`workspace/symbol`). There is no
  separate `.m1prj` parser to fall out of date.
- **The lint-rule catalogue** is sourced from `m1-lint`: a test runs
  `m1-lint --rules --format json` and fails if `lua/telescope-m1/rules.lua`
  drifts from the binary (codes, names, fixability).
- **The LSP client name** is read from `nvim-m1` when present, so the two plugins
  can never disagree about which client to talk to.

## Development

```sh
scripts/test.sh   # headless plenary-busted suite
```

Tests use synthetic fixtures only — no project data is checked in.

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).

## Trademark

Independent, community-built open-source tooling for the MoTeC® M1 script
language. Not affiliated with, authorised, or endorsed by MoTeC Pty Ltd.
"MoTeC" and "M1" are trademarks of MoTeC Pty Ltd.
