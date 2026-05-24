# unified-review.nvim

A Neovim plugin for reviewing local changes, jj changes, and GitHub pull requests from one review UI.

`unified-review.nvim` combines CodeDiff-powered side-by-side diffs with persistent review threads, inline comments, a target picker, review summaries, and optional GitHub draft publishing.

## Features

- Local Git reviews with `:UnifiedReview local [base] [head]`
- jj-aware current-change reviews with `:UnifiedReview current`
- GitHub PR reviews with `:UnifiedReview pr [number|url]`
- Native target picker via bare `:UnifiedReview`
- Side-by-side diffs through `codediff.nvim`
- Persistent local review threads and replies
- Line, range, and file-level comments
- Inline comment blocks aligned across side-by-side diffs
- Thread panel with filtering, preview, reply, resolve/reopen, and delete actions
- Markdown/minimal review summary export
- Optional GitHub pending-review submission and local-draft publishing

## Requirements

- Neovim 0.10+ with Lua support and `vim.uv` available
- `codediff.nvim` on runtimepath
- `git` for local Git reviews
- `jj` for jj workspace reviews
- `gh` authenticated with GitHub for PR reviews and draft publishing

## Installation

```lua
{
  "adampoit/unified-review.nvim",
  dependencies = {
    "adampoit/codediff.nvim",
  },
  config = function()
    require("unified_review").setup({})
  end,
}
```

Packer users: adapt the above with `use({ ... })` and `requires = { ... }`.

## Quick start

- Target picker:

  ```vim
  :UnifiedReview
  ```

- Current jj change (or Git working target):

  ```vim
  :UnifiedReview current
  ```

- Explicit local Git range:

  ```vim
  :UnifiedReview local origin/main HEAD
  ```

- GitHub pull request (number or URL):

  ```vim
  :UnifiedReview pr 123
  ```

## Commands

| Command                              | Description                                         |
| ------------------------------------ | --------------------------------------------------- |
| `:UnifiedReview`                     | Open the target picker                              |
| `:UnifiedReview local [base] [head]` | Open a local Git review                             |
| `:UnifiedReview current`             | Open the current jj change or Git working target    |
| `:UnifiedReview pr [number\|url]`    | Open an explicit PR, or infer the current branch PR |

Run `:UnifiedReview help` for the full list: `comment`, `reply`, `threads`, `summary`, `save`, `submit`, `publish-drafts`, `toggle-export`, `resolve-thread`, `reopen-thread`, `edit-draft`, `delete-draft`, `clear`, `undo`, `status`, `close`.

## Default keymaps

| Key          | Action                                   |
| ------------ | ---------------------------------------- |
| `<CR>`       | Open selected file in the file panel     |
| `]f` / `[f`  | Next / previous file                     |
| `]h` / `[h`  | Next / previous hunk                     |
| `]t` / `[t`  | Next / previous thread                   |
| `<leader>rc` | New comment                              |
| `<leader>rr` | Reply                                    |
| `<leader>rt` | Thread panel                             |
| `<leader>rS` | Review summary                           |
| `<leader>re` | Toggle export marker                     |
| `q`          | Close the current review surface/session |

## Configuration

Defaults are intentionally small and can be partially overridden:

```lua
require("unified_review").setup({
  codediff = {
    auto_attach = true,
  },
  ui = {
    tabline_format = "full", -- "full", "compact", or false
    keymaps = {
      enabled = true,
      comment = "<leader>rc",
      reply = "<leader>rr",
      threads = "<leader>rt",
      summary = "<leader>rS",
      toggle_export = "<leader>re",
      close = "q",
    },
  },
  local_git = {
    base_ref = "origin/main",
    head_ref = "HEAD",
    state_dir = vim.fn.stdpath("state") .. "/unified-review",
    auto_copy_on_add = false,
  },
  jj = {
    enabled = true,
    base_revset = "trunk()",
    prefer_jj_for_local = true,
    editable_checkout_strategy = "never",
  },
  github = {
    checkout_mode = "none",
    transport_command = "gh",
    no_checkout_readonly = true,
  },
})
```

## Persistence

Local review state is stored below:

```text
stdpath("state")/unified-review/<repo-id>/
```

Each thread records a **content anchor** so comments survive rebases and edits:

- On reload the store matches by file content fingerprint, then exact selected lines, then surrounding context, remapping the comment to its new location when lines moved.
- Ambiguous matches or missing files mark the thread **stale** rather than silently attaching to the wrong line, so you can re-anchor or delete it deliberately.
- File-level comments are reattached by path and don't participate in line remapping.

## Testing

Common commands:

```sh
nix run .                 # all Lua/plenary tests
nix run .#test-plugin     # plugin tests, excluding component specs
nix run .#test-components # component specs
npm run test:e2e          # TUI E2E plugin + component/storybook tests
nix flake check           # standard flake validation
```

## License

MIT. See [`LICENSE`](LICENSE).
