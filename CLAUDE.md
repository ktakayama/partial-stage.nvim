# CLAUDE.md

## Project Overview

partial-stage.nvim is a Neovim plugin for interactive partial staging of Git changes from a status buffer.

- Language: Lua
- Requires: Neovim >= 0.10.0, Git, plenary.nvim (for testing)

## Project Structure

```
plugin/              -- Neovim plugin entry point
lua/partial-stage/   -- Main source code
test/                -- Test files (plenary busted)
doc/                 -- Help documentation
```

## Documentation Guidelines

- When adding or changing features, update both README.md and doc/partial-stage.txt to reflect the actual behavior

## Development Commands

```bash
# Run all tests
make test

# Run a specific test file
make test-file FILE=test/partial-stage/patch_parser_spec.lua
```