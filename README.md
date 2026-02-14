# partial-stage.nvim

Git `add -p` functionality within Neovim. Displays diffs from multiple files in a single buffer, allowing selective staging of hunks.

## Requirements

- Neovim >= 0.10.0
- Git

## Installation

### lazy.nvim

```lua
{
  "ktakayama/partial-stage.nvim",
  cmd = "PartialStage",
  opts = {},
}
```

### Other plugin managers

```lua
require("partial-stage").setup()
```

## Usage

Run `:PartialStage` to open the status buffer.

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

All keymaps are active only in the status buffer and are configurable.

| Key | Mode | Action |
|-----|------|--------|
| `s` | n/v | Stage (unstaged section) or unstage (staged section). Visual mode for partial hunk. |
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

## Acknowledgements

- [gitabra](https://github.com/Odie/gitabra) - tree-based status buffer design

## License

MIT
