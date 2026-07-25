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
- Inline comment and reply editors anchored to their diff threads
- Adaptive thread workspace with filtering, conversational details, contextual actions, and inline replies
- Markdown/minimal review summary export
- Optional GitHub pending-review submission and local-draft publishing
- Scriptable agent-feedback import and diff-context export

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
    "esmuellert/codediff.nvim",
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

- GitHub pull request comments with your local worktree on the right:

  ```vim
  :UnifiedReview pr-local 123
  ```

## Commands

| Command                                 | Description                                         |
| --------------------------------------- | --------------------------------------------------- |
| `:UnifiedReview`                        | Open the target picker                              |
| `:UnifiedReview local [base] [head]`    | Open a local Git review                             |
| `:UnifiedReview current`                | Open the current jj change or Git working target    |
| `:UnifiedReview pr [number\|url]`       | Open an explicit PR, or infer the current branch PR |
| `:UnifiedReview pr-local [number\|url]` | Open PR comments with local worktree on the right   |
| `:UnifiedReview import-feedback <json>` | Import agent feedback JSON as draft comments        |
| `:UnifiedReview agent-select <json>`    | Pick a review target and write selection JSON       |
| `:UnifiedReview agent-context <json>`   | Write diff context JSON for agents                  |

Run `:UnifiedReview help` for the full list: `pr-local`, `comment`, `reply`, `threads`, `summary`, `save`, `submit`, `publish-drafts`, `import-feedback`, `agent-select`, `agent-context`, `toggle-export`, `resolve-thread`, `reopen-thread`, `edit-draft`, `delete-draft`, `clear`, `undo`, `status`, `close`.

## Agent feedback

Agents can submit review feedback without knowing Neovim UI internals by writing `unified-review.agent-feedback.v1` JSON and importing it:

```vim
:UnifiedReview import-feedback /tmp/agent-review.json
```

Headless scripts can use the Lua API directly:

```sh
nvim --headless +'lua require("unified_review.agent_feedback").import_file("/tmp/agent-review.json", { target = "current", refresh_ui = false })' +qa
```

The JSON shape is:

```json
{
  "schema": "unified-review.agent-feedback.v1",
  "author": "pi-agent",
  "source": { "name": "pi-coding-agent", "run_id": "optional-run-id" },
  "summary": "Optional overall review summary.",
  "comments": [
    {
      "id": "stable-comment-id",
      "body": "This can panic when config is nil.",
      "severity": "warning",
      "category": "bug",
      "target": {
        "kind": "line",
        "path": "lua/example.lua",
        "side": "right",
        "line": 42
      }
    }
  ]
}
```

Supported targets are `file`, `line`, and `range`, matching the normal comment target model. Imported comments are local drafts, marked for export, and deduplicated when `source.name`, `source.run_id`, and `comment.id` are all present.

For agent workflows that start in Neovim's target picker:

```vim
:UnifiedReview agent-select /tmp/unified-review-selection.json
:UnifiedReview agent-context /tmp/unified-review-context.json
```

`agent-select` writes the chosen target artifact and exits; `agent-context` writes a diff-focused, line-addressable context artifact for the current target.

## pi integration

This repository also ships two [pi](https://github.com/earendil-works/pi-mono) extensions:

- `/review` opens Neovim for a human review and inserts the exported feedback into pi's editor.
- `/ai-review` selects a target in Neovim, asks the agent for structured feedback, imports it as local drafts, and offers to reopen the review.

Try the extensions directly from a checkout:

```sh
pi -e .
```

Tagged releases can be installed as a pi git package:

```sh
pi install git:github.com/adampoit/unified-review.nvim@<tag>
```

For local development, `pi install /absolute/path/to/unified-review` can register the checkout persistently. Remove any standalone copies of `diff-review.ts` and `ai-review.ts` first so pi does not register duplicate commands.

Both workflows require `nvim` on `PATH` and `unified-review.nvim` configured in the Neovim instance launched by pi. The extensions and Lua plugin communicate only through the versioned selection, context, and feedback JSON artifacts documented above.

## Default keymaps

| Key          | Action                                                    |
| ------------ | --------------------------------------------------------- |
| `<CR>`       | Open selected file in the file panel                      |
| `]f` / `[f`  | Next / previous file                                      |
| `]h` / `[h`  | Next / previous hunk                                      |
| `]t` / `[t`  | Next / previous thread                                    |
| `<leader>rc` | New comment                                               |
| `<leader>rr` | Reply                                                     |
| `<leader>rt` | Thread panel                                              |
| `<leader>rS` | Review summary                                            |
| `<leader>re` | Toggle export marker (disambiguates overlapping comments) |
| `q`          | Close the current review surface/session                  |

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
scripts/test.sh all         # full validation
scripts/test.sh typecheck   # TypeScript typecheck
scripts/test.sh lua         # all Lua/plenary tests
scripts/test.sh pi-unit     # pi extension unit tests
scripts/test.sh pi-bridge   # real pi/Neovim bridge integration
scripts/test.sh tui         # plugin + component TUI tests
scripts/test.sh --help      # all suites and options
```

`npm test` is a conventional shim for `scripts/test.sh`; pass a suite with `npm test -- pi-unit`, for example.

## License

MIT. See [`LICENSE`](LICENSE).
