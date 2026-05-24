local gh = require("unified_review.integrations.gh")
local review_comment = require("unified_review.domain.review_comment")
local review_thread = require("unified_review.domain.review_thread")

local M = {}

local review_threads_query = [[
query UnifiedReviewThreads($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      id
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          originalLine
          originalStartLine
          diffSide
          comments(first: 100) {
            nodes {
              id
              databaseId
              body
              createdAt
              updatedAt
              url
              state
              viewerCanDelete
              pullRequestReview { id state }
              author { login }
            }
          }
        }
      }
    }
  }
}
]]

local add_review_mutation = [[
mutation UnifiedReviewAddReview($input: AddPullRequestReviewInput!) {
  addPullRequestReview(input: $input) {
    pullRequestReview { id }
  }
}
]]

local add_thread_mutation = [[
mutation UnifiedReviewAddThread($input: AddPullRequestReviewThreadInput!) {
  addPullRequestReviewThread(input: $input) {
    thread {
      id
      isResolved
      isOutdated
      path
      line
      startLine
      originalLine
      originalStartLine
      diffSide
      comments(first: 100) {
        nodes {
          id
          databaseId
          body
          createdAt
          updatedAt
          url
          state
          viewerCanDelete
          pullRequestReview { id state }
          author { login }
        }
      }
    }
  }
}
]]

local add_reply_mutation = [[
mutation UnifiedReviewAddReply($input: AddPullRequestReviewThreadReplyInput!) {
  addPullRequestReviewThreadReply(input: $input) {
    comment {
      id
      databaseId
      body
      createdAt
      updatedAt
      url
      state
      viewerCanDelete
      pullRequestReview { id state }
      author { login }
    }
  }
}
]]

local delete_review_comment_mutation = [[
mutation UnifiedReviewDeleteReviewComment($input: DeletePullRequestReviewCommentInput!) {
  deletePullRequestReviewComment(input: $input) {
    pullRequestReview { id }
    pullRequestReviewComment { id }
  }
}
]]

local submit_review_mutation = [[
mutation UnifiedReviewSubmitReview($input: SubmitPullRequestReviewInput!) {
  submitPullRequestReview(input: $input) {
    pullRequestReview { id state }
  }
}
]]

local resolve_thread_mutation = [[
mutation UnifiedReviewResolveThread($input: ResolveReviewThreadInput!) {
  resolveReviewThread(input: $input) {
    thread { id isResolved }
  }
}
]]

local unresolve_thread_mutation = [[
mutation UnifiedReviewUnresolveThread($input: UnresolveReviewThreadInput!) {
  unresolveReviewThread(input: $input) {
    thread { id isResolved }
  }
}
]]

local function nil_if_null(value)
	if value == vim.NIL then
		return nil
	end
	return value
end

local function string_value(value)
	value = nil_if_null(value)
	if value == nil then
		return nil
	end
	return tostring(value)
end

local function number_value(value)
	value = nil_if_null(value)
	if type(value) == "number" then
		return value
	end
	return tonumber(value)
end

local function boolean_value(value)
	value = nil_if_null(value)
	return value == true
end

local function side_from_github(value)
	return string_value(value) == "LEFT" and "left" or "right"
end

local function side_to_github(value)
	return value == "left" and "LEFT" or "RIGHT"
end

local function state_from_thread(node)
	if boolean_value(node.isResolved) then
		return "resolved"
	end
	if boolean_value(node.isOutdated) then
		return "stale"
	end
	return "open"
end

local function payload_data(response)
	response = response or {}
	if response.errors and #response.errors > 0 then
		local first = response.errors[1] or {}
		return nil, { message = first.message or "GitHub GraphQL request failed" }
	end
	return response.data or response, nil
end

local function target_from_thread(node)
	local path = string_value(node.path)
	local side = side_from_github(node.diffSide)
	local line = number_value(node.line) or number_value(node.originalLine)
	local start_line = number_value(node.startLine) or number_value(node.originalStartLine)
	if not path then
		return nil
	end
	if start_line and line and start_line ~= line then
		return {
			kind = "range",
			path = path,
			start_line = start_line,
			start_side = side,
			line = line,
			side = side,
		}
	end
	if line then
		return { kind = "line", path = path, side = side, line = line }
	end
	return { kind = "file", path = path }
end

function M.normalize_comment(node, thread_id, target)
	node = node or {}
	local database_id = nil_if_null(node.databaseId)
	local author = nil_if_null(node.author)
	local review = nil_if_null(node.pullRequestReview)
	local review_state = review and string_value(review.state)
	local comment_state = string_value(node.state)
	local pending = review_state == "PENDING" or comment_state == "PENDING"
	return review_comment.new({
		id = string_value(node.id) or (database_id and ("github-comment-" .. tostring(database_id))),
		thread_id = thread_id,
		body = string_value(node.body) or " ",
		author = author and string_value(author.login) or "github",
		created_at = string_value(node.createdAt),
		updated_at = string_value(node.updatedAt),
		state = pending and "draft" or "remote",
		target = target,
		metadata = {
			github = node,
			github_pending_review_id = pending and review and string_value(review.id) or nil,
			url = string_value(node.url),
			database_id = database_id,
		},
	})
end

function M.normalize_thread(node)
	node = node or {}
	local target = target_from_thread(node)
	local comments = {}
	for _, comment in ipairs((node.comments or {}).nodes or {}) do
		table.insert(comments, M.normalize_comment(comment, node.id, target))
	end
	return review_thread.new({
		id = string_value(node.id),
		target = target or { kind = "file", path = string_value(node.path) or "" },
		comments = comments,
		state = state_from_thread(node),
		is_outdated = boolean_value(node.isOutdated),
		metadata = {
			github = node,
			possibly_outdated = nil_if_null(node.isOutdated) == nil,
		},
	})
end

local function required_pr(target)
	target = target or {}
	if not target.owner or not target.repo or not target.number then
		return nil, { message = "GitHub PR target is missing owner, repo, or number" }
	end
	return target, nil
end

function M.fetch_review_threads(target, opts)
	opts = opts or {}
	local pr, err = required_pr(target)
	if not pr then
		return nil, err
	end
	local threads = {}
	local after = nil
	repeat
		local response, graph_err = gh.graphql(review_threads_query, {
			owner = pr.owner,
			name = pr.repo,
			number = tonumber(pr.number),
			after = after,
		}, vim.tbl_extend("force", opts, { cwd = opts.cwd or pr.root }))
		if not response then
			return nil, graph_err
		end
		local data, payload_err = payload_data(response)
		if not data then
			return nil, payload_err
		end
		local review_threads = data.repository
				and data.repository.pullRequest
				and data.repository.pullRequest.reviewThreads
			or {}
		for _, node in ipairs(review_threads.nodes or {}) do
			table.insert(threads, M.normalize_thread(node))
		end
		local page_info = review_threads.pageInfo or {}
		after = page_info.hasNextPage and page_info.endCursor or nil
	until not after
	return threads, nil
end

function M.create_pending_review(target, opts)
	opts = opts or {}
	target = target or {}
	local pull_request_id = target.pull_request_id or target.id
	if not pull_request_id then
		return nil, { message = "GitHub pull request GraphQL id is required to create a pending review" }
	end
	local response, err = gh.graphql(add_review_mutation, {
		input = {
			pullRequestId = pull_request_id,
		},
	}, vim.tbl_extend("force", opts, { cwd = opts.cwd or target.root }))
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	local review = data.addPullRequestReview and data.addPullRequestReview.pullRequestReview
	if not review or not review.id then
		return nil, { message = "GitHub did not return a pending review id" }
	end
	return review.id, nil
end

local function thread_input(review_id, target, body)
	if not review_id then
		return nil, { message = "pending review id is required" }
	end
	if not target or not target.path then
		return nil, { message = "comment target path is required" }
	end
	local input = {
		pullRequestReviewId = review_id,
		body = body,
		path = target.path,
	}
	if target.kind == "file" then
		return nil, { message = "GitHub file-level PR comments are not supported by the GraphQL review thread API" }
	end
	input.line = target.line
	input.side = side_to_github(target.side)
	if target.kind == "range" then
		input.startLine = target.start_line
		input.startSide = side_to_github(target.start_side)
	end
	return input, nil
end

function M.add_thread(review_id, target, body, opts)
	opts = opts or {}
	local input, input_err = thread_input(review_id, target, body)
	if not input then
		return nil, input_err
	end
	local response, err = gh.graphql(add_thread_mutation, { input = input }, opts)
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	local node = data.addPullRequestReviewThread and data.addPullRequestReviewThread.thread
	if not node then
		return nil, { message = "GitHub did not return the created review thread" }
	end
	return M.normalize_thread(node), nil
end

function M.add_reply(thread_id, body, opts)
	opts = opts or {}
	if not thread_id then
		return nil, { message = "thread id is required" }
	end
	local response, err = gh.graphql(add_reply_mutation, {
		input = {
			pullRequestReviewThreadId = thread_id,
			body = body,
		},
	}, opts)
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	local node = data.addPullRequestReviewThreadReply and data.addPullRequestReviewThreadReply.comment
	if not node then
		return nil, { message = "GitHub did not return the created reply" }
	end
	return M.normalize_comment(node, thread_id), nil
end

function M.delete_review_comment(comment_id, opts)
	opts = opts or {}
	if not comment_id then
		return nil, { message = "comment id is required" }
	end
	local response, err = gh.graphql(delete_review_comment_mutation, { input = { id = comment_id } }, opts)
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	return data.deletePullRequestReviewComment or true, nil
end

function M.submit_review(review_id, event, body, opts)
	opts = opts or {}
	if not review_id then
		return nil, { message = "pending review id is required" }
	end
	local response, err = gh.graphql(submit_review_mutation, {
		input = {
			pullRequestReviewId = review_id,
			event = event or "COMMENT",
			body = body or "",
		},
	}, opts)
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	return data.submitPullRequestReview and data.submitPullRequestReview.pullRequestReview, nil
end

function M.resolve_thread(thread_id, opts)
	opts = opts or {}
	local response, err = gh.graphql(resolve_thread_mutation, { input = { threadId = thread_id } }, opts)
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	return data.resolveReviewThread and data.resolveReviewThread.thread, nil
end

function M.unresolve_thread(thread_id, opts)
	opts = opts or {}
	local response, err = gh.graphql(unresolve_thread_mutation, { input = { threadId = thread_id } }, opts)
	if not response then
		return nil, err
	end
	local data, payload_err = payload_data(response)
	if not data then
		return nil, payload_err
	end
	return data.unresolveReviewThread and data.unresolveReviewThread.thread, nil
end

return M
