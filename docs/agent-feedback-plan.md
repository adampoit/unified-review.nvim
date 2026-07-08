# Agent-to-Human Review Feedback Plan

> **Status:** The v1 artifact APIs and pi workflows are implemented. The canonical pi extensions now live in [`extensions/`](../extensions/), with shared contract and real-Neovim bridge tests in [`tests/extensions/`](../tests/extensions/).

## Goal

Add a stable, scriptable API that lets coding agents leave review feedback for a human in `unified-review.nvim`, mirroring the existing human-to-agent flow powered by `diff-review.ts`.

The main design constraint is that agents should not need to know Neovim UI internals. They should be able to emit a small, well-documented review artifact, ask the plugin to import it, and then the human can inspect the feedback in the normal unified-review UI: inline comments, thread panel, summary, resolve/reopen, delete, etc.

## Non-goals

- Building a new review UI for agents.
- Replacing existing local/GitHub comment providers.
- Publishing agent comments directly to GitHub without human review.
- Requiring agents to run an interactive Neovim instance.

## Intended Interaction Flow

There are three plausible flows for requesting AI review from pi or another agent. The recommended v1 flow is **pi-native target selection, then Neovim only for review consumption**.

### Flow A: Neovim target picker first

Sequence:

1. User runs `/ai-review` in pi.
2. pi launches Neovim.
3. User selects a review target in the plugin picker.
4. Neovim exits and returns the selected target to pi.
5. pi asks the agent to review that target.
6. Agent writes feedback JSON.
7. pi imports the feedback and prompts the user to open Neovim to inspect it.

Pros:

- Reuses the plugin’s existing target picker and target discovery logic.
- Avoids duplicating picker UI in pi.

Cons:

- It is a disruptive terminal handoff before the agent has done anything.
- Neovim becomes an input dialog rather than the place where review happens.
- Headless/RPC/non-TUI pi modes are awkward.
- Returning a selected target from an interactive Neovim session requires an additional “select and quit” API.

This is viable as a fallback, but should not be the primary design.

### Flow B: pi-native target selection, Neovim after review

Sequence:

1. User runs `/ai-review` in pi.
2. pi discovers review targets without launching interactive Neovim.
3. pi shows target options using `ctx.ui.select`.
4. User selects a target.
5. pi gives the agent a machine-readable review context for that target.
6. Agent performs the review and writes feedback JSON.
7. pi imports the feedback via headless Neovim or a small CLI wrapper.
8. pi prompts the user to open Neovim to inspect comments.
9. User opens `:UnifiedReview current` / `:UnifiedReview threads` and triages comments.

Pros:

- Best fit for pi’s interaction model: slash command, `ctx.ui.select`, status/widget updates, and a normal agent turn.
- Keeps Neovim focused on code review consumption, not command orchestration.
- Works better in TUI, RPC, and future non-interactive modes.
- Easier to support other agents: they only need target context in and feedback JSON out.

Cons:

- Requires target discovery/context APIs that can be called headlessly.
- pi may need lightweight target presentation logic.

This should be the **v1 default**.

### Flow C: Neovim stays open while pi reviews in the background

Sequence:

1. User runs `/ai-review`.
2. Neovim opens the review target picker or review UI.
3. User selects a target in Neovim.
4. pi starts the agent review in the background.
5. Neovim shows a loading state.
6. When feedback arrives, Neovim imports and refreshes automatically.

Pros:

- Most integrated long-term experience.
- User can stay in the code review UI while the agent works.
- Enables live refresh, progress, cancellation, and follow-up actions.

Cons:

- Requires a more complex bridge between Neovim and pi: file watcher, RPC socket, or pi extension protocol.
- Requires lifecycle handling for cancellation, retries, background process status, and stale targets.
- Harder to make robust across terminal layouts because both pi and Neovim want interactive control.

This is a good **v2/v3 direction**, but it should build on the same artifact APIs rather than drive the v1 implementation.

### Recommended v1 sequence

Use a **Neovim-first target selection flow**. We have invested in a rich target picker inside the plugin, and that should remain the canonical way to choose what is being reviewed. pi should orchestrate the workflow around that picker, not reimplement it.

```text
/pi /ai-review
  -> pi temporarily hands terminal control to Neovim
  -> plugin opens the normal unified-review target picker in "agent selection" mode
  -> user selects a target in Neovim
  -> plugin writes a selected-target artifact and exits back to pi
  -> pi asks plugin/headless Neovim to export diff context for that target
  -> agent reviews
  -> agent submits unified-review.agent-feedback.v1 JSON through a pi tool
  -> pi imports JSON headlessly
  -> pi offers: "Open Neovim review now?"
  -> if yes, launch Neovim with the selected target/review session
```

The important architectural choice is that **the picker remains in Neovim**, while the handoff points are serialized artifacts: selected target, diff context, and feedback. That gives us a clean bridge for pi and other agents without duplicating picker behavior outside the plugin.

The pi command should orchestrate the workflow. The agent’s role is only to review the provided context and return structured feedback.

## Proposed API Surface

Implement a small public Lua module plus a user command wrapper:

```lua
local agent_feedback = require("unified_review.agent_feedback")
```

### 1. Import review feedback from a file

```lua
local result, err = agent_feedback.import_file(path, opts)
```

`path` points to JSON. `opts` controls session selection and UI behavior.

```lua
agent_feedback.import_file("/tmp/agent-review.json", {
  target = "current",       -- default; open current jj/Git change if needed
  author = "agent",         -- default author when omitted per-comment
  source = "pi",            -- stored in metadata
  refresh_ui = true,         -- refresh inline comments/thread panel
  open = true,               -- open review UI if no session is active
})
```

Returns:

```lua
{
  imported_threads = 3,
  imported_comments = 3,
  skipped = {},
  warnings = {},
  session_id = "local:...",
}
```

Errors use the project’s existing `{ message = ... }` convention.

### 2. Import already-decoded feedback

```lua
local result, err = agent_feedback.import(review, opts)
```

This is the core API used by tests and by `import_file`. It accepts a Lua table matching the JSON schema below.

### 3. Select a target and export machine-readable diff context for agents

For the recommended Neovim-first flow, target selection and context export should be first-class APIs rather than incidental UI behavior:

```lua
local result, err = agent_feedback.select_target(opts)
local context, err = agent_feedback.context(opts)
local result, err = agent_feedback.write_context(path, opts)
```

`select_target()` opens the normal Neovim target picker in an agent-selection mode. On selection, it writes a selected-target artifact and optionally exits Neovim so pi can resume control.

Example selected-target artifact:

```lua
{
  schema = "unified-review.agent-selection.v1",
  selected_at = "2026-07-08T00:00:00Z",
  label = "Current jj change",
  description = "Review changes from trunk() to @",
  target = { kind = "jj", base = "trunk()", head = "@" },
  open_command = "UnifiedReview current"
}
```

This keeps richer target semantics and all custom selection behavior inside the plugin. pi and other agent harnesses do not need to reimplement target picking; they only need to launch Neovim, wait for the selected-target artifact, and continue.

`context()` and `write_context()` give agents a reliable way to reference the review target without scraping either the Neovim UI or raw command output.

`context` should include:

- session kind and id
- base/head metadata
- changed files
- unified diff or parsed hunks
- changed line ranges on both `left` and `right` sides
- accepted target shape examples

Do not export full file contents in v1. Agents can read files directly if they need broader context. The default context artifact should be diff-focused and line-addressable.

### 4. User commands

Add subcommands to `:UnifiedReview`:

```vim
:UnifiedReview import-feedback /tmp/agent-review.json
:UnifiedReview agent-select /tmp/unified-review-selection.json
:UnifiedReview agent-context /tmp/unified-review-context.json
```

These are thin wrappers over the Lua API. They make the feature easy to call from shell scripts and future pi extensions. `agent-select` is especially important because it lets the existing Neovim picker produce a selected-target artifact for pi.

## JSON Schema v1

Agents should write one JSON object:

```json
{
  "schema": "unified-review.agent-feedback.v1",
  "author": "pi-agent",
  "source": {
    "name": "pi-coding-agent",
    "run_id": "optional-run-id",
    "model": "optional-model-name"
  },
  "summary": "Optional overall review summary for the human.",
  "comments": [
    {
      "id": "stable-agent-comment-id-1",
      "body": "This condition can panic when config is nil.",
      "severity": "warning",
      "category": "bug",
      "target": {
        "kind": "line",
        "path": "lua/example.lua",
        "side": "right",
        "line": 42
      }
    },
    {
      "body": "Consider extracting this block into a named helper.",
      "target": {
        "kind": "range",
        "path": "lua/example.lua",
        "start_line": 50,
        "start_side": "right",
        "line": 58,
        "side": "right"
      }
    },
    {
      "body": "This file needs coverage for the new behavior.",
      "target": {
        "kind": "file",
        "path": "tests/example_spec.lua"
      }
    }
  ]
}
```

### Target rules

Use the existing `comment_target` model:

- `kind = "file"`: requires `path`.
- `kind = "line"`: requires `path`, `side`, `line`.
- `kind = "range"`: requires `path`, `start_line`, `start_side`, `line`, `side`.
- `side` is usually `"right"` for agent feedback on the proposed/current code.

### Review-level notes

The `summary` field should become a first-class review-level draft note rather than being discarded or forced onto a file target. This likely requires a small new domain abstraction such as:

```lua
review_note.new({
  kind = "summary", -- or "general"
  body = "Overall review text",
  author = "pi-agent",
  state = "draft",
  metadata = { agent_feedback = {...} },
})
```

This abstraction also helps GitHub support because GitHub pending reviews have a review body in addition to line comments. Local reviews, GitHub PR reviews, and imported agent feedback should all be able to carry review-level notes.

### Metadata mapping

Each imported thread/comment should store agent-specific fields in metadata, not as top-level domain fields:

```lua
thread.metadata.agent_feedback = {
  schema = "unified-review.agent-feedback.v1",
  source = review.source,
  severity = comment.severity,
  category = comment.category,
}
```

Comments should be authored by `comment.author or review.author or opts.author or "agent"`.

Imported comments should remain `state = "draft"` so they are visible/exportable but safe to delete or publish manually.

Imported feedback should support stable agent comment ids. When `comment.id` and `source.run_id` are present, imports should deduplicate by `(source.name, source.run_id, comment.id)`. A repeated import should update the existing draft rather than create duplicate comments.

## Session Behavior

`agent_feedback.import()` should support three modes:

1. **Active session mode**: if a review session is already active, import into it.
2. **Current target mode**: if no session is active and `opts.target == "current"`, call `manager.open_current_change({})`, then import.
3. **Explicit target mode**: allow `opts.target` to be a normal `review_target` table and call `manager.open_target(opts.target)`.

Default mode should be current target. This makes the shell path straightforward:

```sh
nvim --headless +'lua require("unified_review.agent_feedback").import_file("/tmp/agent-review.json", { target = "current", open = false })' +qa
```

## Import Semantics

For each incoming comment:

1. Validate schema and required fields.
2. Normalize `target` through `unified_review.domain.comment_target.new`.
3. Verify the target file exists in `session.files`; return a warning or skip if not.
4. Create a local draft thread via the existing comment provider/manager path.
5. Attach content anchors using the existing local store behavior.
6. Mark imported threads for export by default (`metadata.export = true`).
7. Refresh signs, inline comments, thread panel, and summary if `opts.refresh_ui ~= false`.

Prefer reusing `manager.create_comment(body, target)` initially. If we need richer metadata at creation time, add a narrowly-scoped manager/provider function such as:

```lua
manager.create_comment(body, target, {
  author = "agent",
  metadata = {...},
  thread_metadata = {...},
  notify = false,
})
```

That signature should stay backward compatible.

## Human Experience

After import, humans should use the existing UI:

```vim
:UnifiedReview current
:UnifiedReview threads
```

Agent comments appear as normal draft threads with author `pi-agent` or similar. The thread panel can later add visual badges from metadata, for example:

- `🤖` agent-authored
- severity labels: `error`, `warning`, `info`, `nit`
- category labels: `bug`, `test`, `style`, `question`

This can be a follow-up; the first implementation only needs reliable import and display.

## pi Extension Integration Sketch

A future `/ai-review` pi command should orchestrate the workflow:

1. Temporarily stop pi's TUI and launch Neovim.
2. Run `:UnifiedReview agent-select /tmp/selection.json` to open the plugin's normal target picker in agent-selection mode.
3. When the user selects a target, Neovim writes the selected-target artifact and exits.
4. Call the plugin headlessly to write diff context for the selected target.
5. Ask the agent to review only that context.
6. Receive structured feedback through the pi feedback-submission tool.
7. Import feedback headlessly.
8. Prompt the user to open Neovim.

The feedback handoff has two plausible designs:

### Option 1: custom pi tool for feedback submission

Register a temporary or always-available tool such as `submit_ai_review_feedback` with a TypeBox schema matching `unified-review.agent-feedback.v1`. The agent calls the tool when it is done reviewing. The tool validates payload shape, writes JSON, runs the headless import, and returns an import summary.

Pros:

- Strongly structured handoff; no scraping the final assistant message.
- pi stays in charge of import, dedupe, notifications, and error display.
- Easier to mark the review as complete exactly when the tool is called.

Cons:

- Requires a pi-specific tool, so other harnesses need an equivalent mechanism.

### Option 2: agent calls headless Neovim directly

The agent writes feedback JSON and runs:

```ts
await pi.exec(
  "nvim",
  [
    "--headless",
    "+lua require('unified_review.agent_feedback').import_file('/tmp/review.json', { target = 'current', open = false })",
    "+qa",
  ],
  { cwd: ctx.cwd },
);
```

Pros:

- Fewer pi-specific moving parts.
- Other agents can use the same shell contract.

Cons:

- More brittle: quoting, file paths, import errors, and dedupe reporting become agent responsibilities.
- The agent directly mutates review state instead of returning feedback to the orchestrating command.
- Harder for `/ai-review` to know when the review is complete and prompt the user.

Recommended v1 direction: **custom pi tool for pi**, while keeping `import_file` as the harness-neutral fallback. This gives pi the cleanest UX without locking the plugin API to pi.

This complements the existing `/review` command in `diff-review.ts`, which exports human review comments back to the agent.

## Implementation Steps

1. **Add schema validation module**
   - New file: `lua/unified_review/agent_feedback/schema.lua` or keep private in `agent_feedback.lua`.
   - Validate schema string, comments list, body, and target shape.

2. **Add import/context/selection module**
   - New file: `lua/unified_review/agent_feedback.lua`.
   - Public functions: `select_target`, `import`, `import_file`, `context`, `write_context`.
   - `select_target` should reuse the existing Neovim target picker and write a selected-target artifact.

3. **Define the pi command around Neovim-first selection**
   - `/ai-review` launches Neovim in agent-selection mode.
   - Neovim writes a selected-target artifact and exits.
   - pi writes context for the selected target.
   - pi prompts the agent to review using that context and produce feedback JSON.
   - pi imports the JSON headlessly and offers to open Neovim.

4. **Add review-level notes**
   - Add a domain model for review notes / review body drafts.
   - Persist notes alongside threads in the local session store.
   - Include notes in summary/export output.
   - Map GitHub pending-review bodies onto this abstraction where possible.

5. **Extend manager creation path if needed**
   - Start by using `manager.create_comment`.
   - If metadata/author cannot be represented cleanly, add optional `opts` to `manager.create_comment` and `local_store.create_thread`.
   - Support dedupe/update by stable agent ids.

6. **Add agent visual treatment**
   - Show an agent/robot icon for threads and review notes with `metadata.agent_feedback`.
   - Keep this presentation-only; the stored state remains normal draft comments/notes.

7. **Add commands**
   - Extend `lua/unified_review/commands.lua` with `import-feedback`, `agent-select`, and `agent-context`.
   - Update completion and help text.

8. **Tests**
   - Unit tests for schema validation.
   - Integration test importing file, line, and range comments into a local review.
   - Test skipped/warning behavior for unknown files.
   - Test command wrapper calls the module.

9. **Docs**
   - Add README section for agent feedback.
   - Document schema v1, the recommended pi flow, and headless Neovim invocations.

## Open Questions

- Should imported agent comments be visually distinguished immediately, or is metadata enough for v1?
- Should duplicate imports be deduplicated by source/run/comment id?
- Should an overall `summary` become a file-level thread, a session-level note, or remain only in metadata until the domain model has review-level comments?
- Should `agent-context` be implemented in v1, or can agents rely on their own diff parsing initially?
