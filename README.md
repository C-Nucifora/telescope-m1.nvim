# telescope-m1.nvim

[Telescope](https://github.com/nvim-telescope/telescope.nvim) extension for [M1 script](https://github.com/C-Nucifora/m1-tools). Adds pickers for:

- **Workspace symbols** — fuzzy-search all channels, parameters, and enums in the loaded project
- **Component browser** — browse the `.m1prj` component hierarchy
- **Lint rules** — pick an `m1-lint` rule to jump to its documentation or toggle it

## Requirements

- Neovim ≥ 0.10
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [m1-lsp](https://github.com/C-Nucifora/m1-lsp) running in the workspace

## Installation

```lua
-- lazy.nvim
{
  "C-Nucifora/telescope-m1.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
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
```

## Status

> **Scaffold.** Extension skeleton is in place; pickers not yet implemented.
> Track progress in the [open issues](https://github.com/C-Nucifora/telescope-m1.nvim/issues).

## License

GPL-3.0-or-later — see [LICENSE](LICENSE).
