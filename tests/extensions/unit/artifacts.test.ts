import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import test from "node:test";
import {
  formatLocalReviewForAgent,
  formatReviewPrompt,
  isAgentFeedback,
  isContextArtifact,
  isSelectionArtifact,
} from "../../../extensions/lib/artifacts.ts";

const fixtureRoot = join(process.cwd(), "tests", "fixtures", "agent-feedback");

function fixtures(kind: "valid" | "invalid") {
  return readdirSync(join(fixtureRoot, kind)).map((name) => ({
    name,
    value: JSON.parse(readFileSync(join(fixtureRoot, kind, name), "utf8")),
  }));
}

test("TypeBox accepts every valid shared feedback fixture", () => {
  for (const fixture of fixtures("valid")) {
    assert.equal(isAgentFeedback(fixture.value), true, fixture.name);
  }
});

test("TypeBox rejects every invalid shared feedback fixture", () => {
  for (const fixture of fixtures("invalid")) {
    assert.equal(isAgentFeedback(fixture.value), false, fixture.name);
  }
});

test("artifact guards require the versioned bridge contracts", () => {
  assert.equal(
    isSelectionArtifact({
      schema: "unified-review.agent-selection.v1",
      target: { kind: "local_git" },
    }),
    true,
  );
  assert.equal(
    isSelectionArtifact({ schema: "unified-review.agent-selection.v0" }),
    false,
  );
  assert.equal(
    isContextArtifact({
      schema: "unified-review.agent-context.v1",
      files: [],
    }),
    true,
  );
  assert.equal(
    isContextArtifact({ schema: "unified-review.agent-context.v1" }),
    false,
  );
});

test("human review formatting produces an editor-ready user message", () => {
  const result = formatLocalReviewForAgent("\n- `a.ts:2`: Fix this.\n");
  assert.match(result, /Please address them\./);
  assert.match(result, /- `a\.ts:2`: Fix this\./);
  assert.match(result, /unified-review\.nvim/);
});

test("AI review prompts embed the exact exported context", () => {
  const context = {
    schema: "unified-review.agent-context.v1" as const,
    files: [{ path: "a.ts", raw_patch: "@@ -1 +1 @@" }],
  };
  const result = formatReviewPrompt(context);
  assert.match(result, /submit_ai_review_feedback/);
  assert.match(result, /"path": "a\.ts"/);
  assert.match(result, /Do not edit files/);
});
