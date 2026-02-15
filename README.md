# partial-stage.nvim

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![test](https://github.com/ktakayama/partial-stage.nvim/actions/workflows/test.yml/badge.svg)](https://github.com/ktakayama/partial-stage.nvim/actions/workflows/test.yml)

A Neovim plugin that provides `git add -p` style staging with an interactive UI.

## Requirements

- Neovim >= 0.10.0
- Git

## Installation

### lazy.nvim

```lua
{
  "ktakayama/partial-stage.nvim",
  cmd = { "PartialStage", "PartialStageClose" },
  opts = {},
}
```

### Other plugin managers

```lua
require("partial-stage").setup()
```

## Usage

Run `:PartialStage` to open the status buffer. Use `:PartialStageClose` to close it.

```
s:stage/unstage  x:discard  <Tab>:fold  gs:split  <CR>:jump  q:close

Untracked (1)
    src/new_file.lua

Unstaged (2)
  v src/file_a.lua
    @@ -16,10 +17,14 @@
    - old line
    + new line
     context line
  > src/file_b.lua

Staged (1)
  > src/file_c.lua
```

## Keymaps

All keymaps are active only in the status buffer.

| Key | Mode | Action |
|-----|------|--------|
| `s` | n/v | Stage (unstaged/untracked sections) or unstage (staged section). Visual mode for partial hunk. |
| `x` | n/v | Discard hunk. Unstaged section only. Visual mode for partial discard. |
| `<Tab>` | n | Toggle fold on file node |
| `<CR>` | n | Jump to file at hunk location |
| `gs` | n | Split hunk into smaller hunks |
| `q` | n | Close window |

## Configuration

```lua
require("partial-stage").setup({
  window = {
    position = "topleft vsplit",
    width = 60,
  },
  signs = {
    collapsed = ">",
    expanded = "v",
  },
  keymaps = {
    toggle_stage = "s",
    discard = "x",
    toggle_fold = "<Tab>",
    jump = "<CR>",
    split_hunk = "gs",
    close = "q",
  },
})
```

Set any keymap to `false` to disable it.

### Examples

#### Commit from the status buffer

Add commit shortcuts directly in the partial-stage buffer.
This example uses [vim-gin](https://github.com/lambdalisue/vim-gin):

```vim
augroup partial_stage_keymap
  autocmd!
  autocmd FileType partial-stage nnoremap <buffer> cc <Cmd>Gin commit<CR>
  autocmd FileType partial-stage nnoremap <buffer> ca <Cmd>Gin commit --amend<CR>
augroup END
```

With this setup, you can stage hunks with `s` and then press `cc` to commit.

#### Custom highlight colors

The following highlight groups are available, each linked to a default group:

| Highlight Group | Default Link |
|---|---|
| `PartialStageSection` | `Label` |
| `PartialStageFile` | `Directory` |
| `PartialStageHunkHeader` | `Function` |
| `PartialStageHelp` | `Comment` |

Override them in your config to match your preferred color scheme:

```vim
augroup partial_stage_colors
  autocmd!
  autocmd ColorScheme * highlight PartialStageSection guifg=#e0af68 gui=bold
  autocmd ColorScheme * highlight PartialStageHunkHeader guifg=#7aa2f7 gui=italic
augroup END
```

## Acknowledgements

- [gitabra](https://github.com/Odie/gitabra) - tree-based status buffer design

## License

MIT
