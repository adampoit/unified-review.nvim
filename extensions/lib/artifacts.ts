import { StringEnum } from "@earendil-works/pi-ai";
import { Type, type Static } from "typebox";
import { Check } from "typebox/value";

export const AGENT_FEEDBACK_SCHEMA =
  "unified-review.agent-feedback.v1" as const;
export const AGENT_SELECTION_SCHEMA =
  "unified-review.agent-selection.v1" as const;
export const AGENT_CONTEXT_SCHEMA = "unified-review.agent-context.v1" as const;

export const sideSchema = StringEnum(["left", "right"] as const);
export const commentTargetSchema = Type.Object({
  kind: StringEnum(["file", "line", "range"] as const),
  path: Type.String({ minLength: 1 }),
  side: Type.Optional(sideSchema),
  line: Type.Optional(Type.Number()),
  start_side: Type.Optional(sideSchema),
  start_line: Type.Optional(Type.Number()),
});

export const feedbackSchema = Type.Object({
  schema: StringEnum([AGENT_FEEDBACK_SCHEMA] as const),
  author: Type.Optional(Type.String()),
  source: Type.Optional(
    Type.Object({
      name: Type.String(),
      run_id: Type.Optional(Type.String()),
      model: Type.Optional(Type.String()),
    }),
  ),
  summary: Type.Optional(Type.String()),
  comments: Type.Array(
    Type.Object({
      id: Type.Optional(Type.String()),
      body: Type.String({ minLength: 1 }),
      author: Type.Optional(Type.String()),
      severity: Type.Optional(
        StringEnum(["error", "warning", "info", "nit"] as const),
      ),
      category: Type.Optional(Type.String()),
      target: commentTargetSchema,
    }),
  ),
});

export type AgentFeedback = Static<typeof feedbackSchema>;

export function isAgentFeedback(value: unknown): value is AgentFeedback {
  if (!Check(feedbackSchema, value)) return false;
  return value.comments.every(({ target }) => {
    if (target.kind === "file") return true;
    if (target.side === undefined || target.line === undefined) return false;
    if (target.kind === "line") return true;
    return target.start_side !== undefined && target.start_line !== undefined;
  });
}

export type SelectionArtifact = {
  schema: typeof AGENT_SELECTION_SCHEMA;
  selected_at?: string;
  label?: string;
  description?: string;
  target: unknown;
  open_command?: string;
};

export type ContextArtifact = {
  schema: typeof AGENT_CONTEXT_SCHEMA;
  session?: { id?: string; kind?: string; target?: unknown };
  files?: Array<{ path?: string; raw_patch?: string }>;
};

export function isSelectionArtifact(
  value: unknown,
): value is SelectionArtifact {
  if (!value || typeof value !== "object") return false;
  const artifact = value as Partial<SelectionArtifact>;
  return (
    artifact.schema === AGENT_SELECTION_SCHEMA && artifact.target !== undefined
  );
}

export function isContextArtifact(value: unknown): value is ContextArtifact {
  if (!value || typeof value !== "object") return false;
  const artifact = value as Partial<ContextArtifact>;
  return (
    artifact.schema === AGENT_CONTEXT_SCHEMA && Array.isArray(artifact.files)
  );
}

export function formatLocalReviewForAgent(review: string): string {
  return [
    "I reviewed your code and have the following comments. Please address them.",
    "",
    review.trim(),
    "",
    "<sub>Reviewed locally with Neovim and unified-review.nvim.</sub>",
  ].join("\n");
}

export function formatReviewPrompt(context: ContextArtifact): string {
  return [
    "Review the selected unified-review target using only the diff context below plus repository files you inspect as needed.",
    "",
    "Return feedback by calling the `submit_ai_review_feedback` tool exactly once.",
    "Do not edit files as part of this review. Only submit structured review feedback.",
    "Prefer comments on changed lines on the `right` side. Use file-level comments only when no precise line applies.",
    "If there are no issues, submit an empty `comments` array with a short summary.",
    "",
    "The tool payload must match `unified-review.agent-feedback.v1`.",
    "Use stable `id` values for comments so repeated imports can update instead of duplicate them.",
    "",
    "Diff context JSON:",
    "```json",
    JSON.stringify(context, null, 2),
    "```",
  ].join("\n");
}
