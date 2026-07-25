local inline = require("unified_review.ui.inline")

local function extmarks(buf)
	local ns = vim.api.nvim_get_namespaces().unified_review_inline_virt
	return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

local function filler_extmarks(buf)
	local ns = require("codediff.ui.highlights").ns_filler
	return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

local function flatten_virt_lines(mark)
	local chunks = {}
	for _, line in ipairs(mark[4].virt_lines or {}) do
		local text = ""
		for _, chunk in ipairs(line) do
			text = text .. chunk[1]
		end
		table.insert(chunks, text)
	end
	return table.concat(chunks, "\n")
end

local function chunk_highlights(line)
	local highlights = {}
	for _, chunk in ipairs(line or {}) do
		table.insert(highlights, chunk[2])
	end
	return highlights
end

local function numbered_lines(prefix, count)
	local lines = {}
	for index = 1, count do
		lines[index] = prefix .. " " .. index
	end
	return lines
end

local function as_virt_line(text, hl)
	return { { text, hl or "CodeDiffFiller" } }
end

local function filler_mark_at(buf, row)
	for _, mark in ipairs(filler_extmarks(buf)) do
		if mark[2] == row then
			return mark
		end
	end
	return nil
end

local function first_virt_line_matching(mark, pattern)
	for index, line in ipairs((mark and mark[4] and mark[4].virt_lines) or {}) do
		local text = ""
		for _, chunk in ipairs(line) do
			text = text .. chunk[1]
		end
		if text:match(pattern) then
			return index
		end
	end
	return nil
end

local function labeled_filler_lines(prefix, count)
	local lines = {}
	for index = 1, count do
		lines[index] = as_virt_line(prefix .. " " .. index)
	end
	return lines
end

local function make_suffix_replacement_session(opts)
	opts = opts or {}
	local left_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, numbered_lines("left", opts.left_count or 60))
	local right_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, numbered_lines("right", opts.right_count or 70))
	local filler_ns = require("codediff.ui.highlights").ns_filler
	if opts.left_prior_filler_count then
		vim.api.nvim_buf_set_extmark(left_buf, filler_ns, opts.left_prior_filler_row or 4, 0, {
			virt_lines = labeled_filler_lines("left prior filler", opts.left_prior_filler_count),
		})
	end
	if opts.right_prior_filler_count then
		vim.api.nvim_buf_set_extmark(right_buf, filler_ns, opts.right_prior_filler_row or 4, 0, {
			virt_lines = labeled_filler_lines("right prior filler", opts.right_prior_filler_count),
		})
	end
	if opts.right_move_annotation then
		local highlight_ns = require("codediff.ui.highlights").ns_highlight
		vim.api.nvim_buf_set_extmark(right_buf, highlight_ns, opts.right_move_annotation.row, 0, {
			virt_lines = { as_virt_line("⇄ moved block", "CodeDiffMoveTo") },
			virt_lines_above = opts.right_move_annotation.above,
		})
	end
	local downstream_row = opts.downstream_row or 25
	vim.api.nvim_buf_set_extmark(left_buf, filler_ns, downstream_row, 0, {
		virt_lines = labeled_filler_lines("downstream filler", opts.downstream_count or 14),
	})

	local hunk_lines = { { kind = "context", old_line = 14, new_line = 13 } }
	for line = 15, 26 do
		table.insert(hunk_lines, { kind = "deleted", old_line = line })
	end
	for line = 14, 40 do
		table.insert(hunk_lines, { kind = "added", new_line = line })
	end
	table.insert(hunk_lines, { kind = "context", old_line = 28, new_line = 42 })

	return {
		downstream_row = downstream_row,
		downstream_count = opts.downstream_count or 14,
		session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = { { path = "example/config.pseudo", hunks = { { lines = hunk_lines } } } },
			selection = { file_index = 1 },
			threads = opts.threads,
		},
	}
end

describe("inline comments", function()
	it("places virtual line thread blocks at target lines", function()
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "line 2", "line 3" })
		local session = {
			ui = {
				left_buffer = vim.api.nvim_create_buf(false, true),
				right_buffer = right_buf,
			},
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 2 },
					comments = { { author = "alice", body = "check this line" } },
				},
				{
					state = "resolved",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { author = "bob", body = "fixed" } },
				},
			},
		}

		inline.place(session)

		local marks = extmarks(right_buf)
		assert.are.equal(2, #marks)

		assert.are.equal(0, marks[1][2])
		assert.is_not_nil(marks[1][4].virt_lines)
		assert.is_nil(marks[1][4].virt_text)
		assert.matches("✓ resolved", flatten_virt_lines(marks[1]))
		assert.matches("bob", flatten_virt_lines(marks[1]))
		assert.matches("fixed", flatten_virt_lines(marks[1]))

		assert.are.equal(1, marks[2][2])
		assert.matches("● open", flatten_virt_lines(marks[2]))
		assert.matches("alice", flatten_virt_lines(marks[2]))
		assert.matches("check this line", flatten_virt_lines(marks[2]))
	end)

	it("uses the thread state highlight consistently for inline borders", function()
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1" })
		local session = {
			ui = {
				left_buffer = vim.api.nvim_create_buf(false, true),
				right_buffer = right_buf,
			},
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { author = "alice", body = "check this line" } },
				},
			},
		}

		inline.place(session)

		local lines = extmarks(right_buf)[1][4].virt_lines
		assert.are.same({ "UnifiedReviewInlineOpen" }, chunk_highlights(lines[1]))
		assert.are.same(
			{ "UnifiedReviewInlineOpen", "UnifiedReviewInlineAuthor", "UnifiedReviewInlineOpen" },
			chunk_highlights(lines[2])
		)
		assert.are.same(
			{ "UnifiedReviewInlineOpen", "UnifiedReviewInlineBody", "UnifiedReviewInlineOpen" },
			chunk_highlights(lines[3])
		)
		assert.are.same({ "UnifiedReviewInlineOpen" }, chunk_highlights(lines[4]))
	end)

	it("anchors multi-line thread blocks at the last line", function()
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "line 2", "line 3" })
		local session = {
			ui = {
				left_buffer = vim.api.nvim_create_buf(false, true),
				right_buffer = right_buf,
			},
			threads = {
				{
					state = "open",
					target = {
						kind = "range",
						path = "a.lua",
						start_side = "right",
						start_line = 1,
						side = "right",
						line = 3,
					},
					comments = { { author = "alice", body = "check this range" } },
				},
			},
		}

		inline.place(session)

		local marks = extmarks(right_buf)
		assert.are.equal(1, #marks)
		assert.are.equal(2, marks[1][2])
		assert.matches("right L1%-L3", flatten_virt_lines(marks[1]))
		assert.matches("check this range", flatten_virt_lines(marks[1]))
	end)

	it("adds filler virtual lines to the opposite side to keep side-by-side diffs aligned", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "left 1", "left 2", "left 3" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "right 1", "right 2", "right 3" })
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 2 },
					comments = { { author = "alice", body = "check this line" } },
				},
			},
		}

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		assert.are.equal(1, #right_marks)
		assert.are.equal(1, #left_marks)
		assert.are.equal(right_marks[1][2], left_marks[1][2])
		assert.are.equal(#right_marks[1][4].virt_lines, #left_marks[1][4].virt_lines)
		assert.matches("╱", flatten_virt_lines(left_marks[1]))
		assert.is_nil(inline.next_inline(left_buf, 0))
	end)

	it("splices opposite spacer rows into existing codediff filler at the same anchor", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "left 1", "left 2", "left 3" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "right 1", "right 2", "right 3" })
		local filler_ns = require("codediff.ui.highlights").ns_filler
		vim.api.nvim_buf_set_extmark(left_buf, filler_ns, 0, 0, {
			virt_lines = {
				{ { "existing filler 1", "CodeDiffFiller" } },
				{ { "existing filler 2", "CodeDiffFiller" } },
			},
		})
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { author = "alice", body = "comment next to existing filler" } },
				},
			},
		}

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		local filler_marks = filler_extmarks(left_buf)
		assert.are.equal(1, #right_marks)
		assert.are.equal(0, #left_marks)
		assert.are.equal(1, #filler_marks)
		assert.matches("╱", flatten_virt_lines(filler_marks[1]))
		assert.matches("existing filler 1", flatten_virt_lines(filler_marks[1]))
		assert.is_true(
			flatten_virt_lines(filler_marks[1]):find("╱")
				< flatten_virt_lines(filler_marks[1]):find("existing filler 1")
		)
		assert.are.equal(#right_marks[1][4].virt_lines + 2, #filler_marks[1][4].virt_lines)
	end)

	it("splices comment blocks into existing codediff filler and keeps them navigable", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "left 1", "left 2" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "right 1", "right 2" })
		local filler_ns = require("codediff.ui.highlights").ns_filler
		vim.api.nvim_buf_set_extmark(right_buf, filler_ns, 0, 0, {
			virt_lines = { { { "existing target filler", "CodeDiffFiller" } } },
		})
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { author = "alice", body = "comment inside patched filler" } },
				},
			},
		}

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local right_filler_marks = filler_extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		assert.are.equal(0, #right_marks)
		assert.are.equal(1, #right_filler_marks)
		assert.are.equal(1, #left_marks)
		assert.matches("comment inside patched filler", flatten_virt_lines(right_filler_marks[1]))
		assert.are.equal(1, inline.next_inline(right_buf, 0))
	end)

	it("anchors comments in one-sided diff blocks at the target row", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, numbered_lines("left", 201))
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, numbered_lines("right", 204))
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							lines = {
								{ kind = "context", old_line = 200, new_line = 200 },
								{ kind = "added", new_line = 201 },
								{ kind = "added", new_line = 202 },
								{ kind = "added", new_line = 203 },
								{ kind = "context", old_line = 201, new_line = 204 },
							},
						},
					},
				},
			},
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 202 },
					comments = { { author = "alice", body = "comment inside an added block" } },
				},
			},
		}
		local filler_ns = require("codediff.ui.highlights").ns_filler
		vim.api.nvim_buf_set_extmark(left_buf, filler_ns, 199, 0, {
			virt_lines = {
				{ { "filler 1", "CodeDiffFiller" } },
				{ { "filler 2", "CodeDiffFiller" } },
				{ { "filler 3", "CodeDiffFiller" } },
			},
		})

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		local filler_marks = vim.api.nvim_buf_get_extmarks(left_buf, filler_ns, 0, -1, { details = true })
		assert.are.equal(1, #right_marks)
		assert.are.equal(0, #left_marks)
		assert.are.equal(201, right_marks[1][2])
		assert.is_false(right_marks[1][4].virt_lines_above)
		assert.are.equal(1, #filler_marks)
		assert.are.equal(199, filler_marks[1][2])
		assert.are.equal(3 + #right_marks[1][4].virt_lines, #filler_marks[1][4].virt_lines)
		assert.matches("right L202", flatten_virt_lines(right_marks[1]))
	end)

	it("anchors comments inside added replacement prefixes at the target row", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, numbered_lines("left", 90))
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, numbered_lines("right", 100))
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							lines = {
								{ kind = "context", old_line = 79, new_line = 79 },
								{ kind = "deleted", old_line = 80 },
								{ kind = "added", new_line = 80 },
								{ kind = "added", new_line = 81 },
								{ kind = "added", new_line = 82 },
								{ kind = "added", new_line = 83 },
								{ kind = "context", old_line = 81, new_line = 84 },
							},
						},
					},
				},
			},
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 82 },
					comments = { { author = "alice", body = "comment inside added replacement prefix" } },
				},
			},
		}
		local filler_ns = require("codediff.ui.highlights").ns_filler
		vim.api.nvim_buf_set_extmark(left_buf, filler_ns, 78, 0, {
			virt_lines = {
				{ { "filler 1", "CodeDiffFiller" } },
				{ { "filler 2", "CodeDiffFiller" } },
				{ { "filler 3", "CodeDiffFiller" } },
			},
		})

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		local filler_marks = vim.api.nvim_buf_get_extmarks(left_buf, filler_ns, 0, -1, { details = true })
		assert.are.equal(1, #right_marks)
		assert.are.equal(0, #left_marks)
		assert.are.equal(81, right_marks[1][2])
		assert.is_false(right_marks[1][4].virt_lines_above)
		assert.are.equal(1, #filler_marks)
		assert.are.equal(78, filler_marks[1][2])
		assert.are.equal(3 + #right_marks[1][4].virt_lines, #filler_marks[1][4].virt_lines)
		assert.matches("right L82", flatten_virt_lines(right_marks[1]))
	end)

	it("splices opposite spacers into the matching downstream filler for uneven replacement suffixes", function()
		local old = {
			"{",
			"  inputAlpha,",
			"  inputBeta,",
			"  inputGamma,",
			"  runtimePackage,",
			"  legacyPackage,",
			"  helperTool,",
			"  self,",
			"}: ({pkgs, ...}: {",
			"  imports = [",
			"    (import ./modules {inherit inputGamma;})",
			"  ];",
			"",
			"  service.settings = {",
			'    feature-flags = "modern-mode";',
			"    request-timeout = 300;",
			"    extra-endpoints = [",
			'      "https://legacy-cache.example.test/runtime"',
			'      "https://legacy-cache.example.test/tools"',
			"    ];",
			"    trusted-public-keys = [",
			'      "runtime-cache-1:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="',
			'      "tools-cache-1:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="',
			"    ];",
			"  };",
			"",
			"  system = {",
			'    owner = "example-user";',
			"}",
		}
		local new = {
			"{",
			"  inputAlpha,",
			"  inputBeta,",
			"  inputGamma,",
			"  runtimePackage,",
			"  helperTool,",
			"  self,",
			"}: ({pkgs, ...}: {",
			"  imports = [",
			"    (import ./modules {inherit inputGamma;})",
			"  ];",
			"",
			"  service = {",
			"    settings = {",
			'      feature-flags = "modern-mode";',
			"      request-timeout = 300;",
			"      extra-endpoints = [",
			'        "https://object-storage.example.test/runtime-cache"',
			"      ];",
			"      trusted-public-keys = [",
			'        "runtime-cache:CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC="',
			"      ];",
			"    };",
			"",
			"    extraOptions = ''",
			"      !include /etc/service/access-token.conf",
			"    '';",
			"  };",
			"",
			"  system.activationScripts.refreshToken.text = ''",
			"    token=$(example-auth token 2>/dev/null || true)",
			'    if [ -n "$token" ]; then',
			"      install -m 600 /dev/null /etc/service/access-token.conf",
			"      printf 'access-token = %s\\n' \"$token\" > /etc/service/access-token.conf",
			"    else",
			'      echo "token unavailable" >&2',
			"    fi",
			"  '';",
			"",
			"  system = {",
			'    owner = "example-user";',
			"}",
		}
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, old)
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, new)
		local diff = require("codediff.core.diff").compute_diff(old, new, {})
		require("codediff.ui.core").render_diff(left_buf, right_buf, old, new, diff)

		local hunk_lines = { { kind = "context", old_line = 14, new_line = 13 } }
		for line = 15, 26 do
			table.insert(hunk_lines, { kind = "deleted", old_line = line })
		end
		for line = 14, 40 do
			table.insert(hunk_lines, { kind = "added", new_line = line })
		end
		table.insert(hunk_lines, { kind = "context", old_line = 28, new_line = 42 })

		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = { { path = "example/config.pseudo", hunks = { { lines = hunk_lines } } } },
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "example/config.pseudo", side = "right", line = 27 },
					comments = { { author = "reviewer", body = "Does this option still belong here?" } },
				},
			},
		}
		local filler_ns = require("codediff.ui.highlights").ns_filler
		local before_filler_marks = filler_extmarks(left_buf)
		local downstream_filler_row
		local downstream_filler_count = 0
		for _, mark in ipairs(before_filler_marks) do
			local count = #(mark[4].virt_lines or {})
			if mark[2] > 20 and count > downstream_filler_count then
				downstream_filler_row = mark[2]
				downstream_filler_count = count
			end
		end
		assert.is_not_nil(downstream_filler_row)
		assert.is_true(downstream_filler_count > 0)

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		local after_filler_marks = vim.api.nvim_buf_get_extmarks(left_buf, filler_ns, 0, -1, { details = true })
		local patched_count
		for _, mark in ipairs(after_filler_marks) do
			if mark[2] == downstream_filler_row then
				patched_count = #(mark[4].virt_lines or {})
			end
		end
		assert.are.equal(1, #right_marks)
		assert.are.equal(0, #left_marks)
		assert.are.equal(26, right_marks[1][2])
		assert.are.equal(downstream_filler_count + #right_marks[1][4].virt_lines, patched_count)
		assert.matches("right L27", flatten_virt_lines(right_marks[1]))
	end)

	it("splices multiple comments at distinct offsets into the same downstream filler", function()
		local fixture = make_suffix_replacement_session({
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "example/config.pseudo", side = "right", line = 27 },
					comments = { { author = "reviewer", body = "first suffix comment" } },
				},
				{
					state = "open",
					target = { kind = "line", path = "example/config.pseudo", side = "right", line = 28 },
					comments = { { author = "reviewer", body = "second suffix comment" } },
				},
			},
		})

		inline.place(fixture.session)

		local right_marks = extmarks(fixture.session.ui.right_buffer)
		local left_marks = extmarks(fixture.session.ui.left_buffer)
		local patched = filler_mark_at(fixture.session.ui.left_buffer, fixture.downstream_row)
		assert(patched)
		local expected_count = fixture.downstream_count
		for _, mark in ipairs(right_marks) do
			expected_count = expected_count + #(mark[4].virt_lines or {})
		end
		assert.are.equal(2, #right_marks)
		assert.are.equal(0, #left_marks)
		assert.are.equal(expected_count, #(patched[4].virt_lines or {}))
		assert.matches("right L27", flatten_virt_lines(right_marks[1]))
		assert.matches("right L28", flatten_virt_lines(right_marks[2]))
	end)

	it("expands downstream filler for a wrapped range comment ending in an uneven replacement suffix", function()
		local fixture = make_suffix_replacement_session({
			downstream_count = 1,
			threads = {
				{
					state = "open",
					target = {
						kind = "range",
						path = "example/config.pseudo",
						start_side = "right",
						start_line = 25,
						side = "right",
						line = 27,
					},
					comments = {
						{
							author = "reviewer",
							body = "this deliberately long range comment wraps across several virtual lines so the spacer block is taller than the remaining filler lines",
						},
					},
				},
			},
		})

		inline.place(fixture.session)

		local right_marks = extmarks(fixture.session.ui.right_buffer)
		local patched = filler_mark_at(fixture.session.ui.left_buffer, fixture.downstream_row)
		assert(patched)
		assert.are.equal(1, #right_marks)
		assert.matches("right L25%-L27", flatten_virt_lines(right_marks[1]))
		assert.are.equal(fixture.downstream_count + #right_marks[1][4].virt_lines, #(patched[4].virt_lines or {}))
		assert.is_true(#right_marks[1][4].virt_lines > fixture.downstream_count)
	end)

	it("accounts for prior fillers on both sides before resolving downstream spacer offsets", function()
		local fixture = make_suffix_replacement_session({
			left_prior_filler_count = 2,
			right_prior_filler_count = 2,
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "example/config.pseudo", side = "right", line = 27 },
					comments = { { author = "reviewer", body = "comment after earlier fillers" } },
				},
			},
		})

		inline.place(fixture.session)

		local right_marks = extmarks(fixture.session.ui.right_buffer)
		local patched = filler_mark_at(fixture.session.ui.left_buffer, fixture.downstream_row)
		assert(patched)
		assert.are.equal(1, #right_marks)
		assert.are.equal(fixture.downstream_count + #right_marks[1][4].virt_lines, #(patched[4].virt_lines or {}))
		assert.are.equal(2, first_virt_line_matching(patched, "╱"))
	end)

	it("accounts for moved-code annotation virtual lines before resolving spacer offsets", function()
		local fixture = make_suffix_replacement_session({
			right_move_annotation = { row = 20, above = true },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "example/config.pseudo", side = "right", line = 27 },
					comments = { { author = "reviewer", body = "comment after a move annotation" } },
				},
			},
		})

		inline.place(fixture.session)

		local right_marks = extmarks(fixture.session.ui.right_buffer)
		local patched = filler_mark_at(fixture.session.ui.left_buffer, fixture.downstream_row)
		assert(patched)
		assert.are.equal(1, #right_marks)
		assert.are.equal(fixture.downstream_count + #right_marks[1][4].virt_lines, #(patched[4].virt_lines or {}))
		assert.are.equal(3, first_virt_line_matching(patched, "╱"))
	end)

	it("anchors comments at the target row inside one-sided blocks at the start of a file", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, numbered_lines("left", 10))
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, numbered_lines("right", 12))
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							lines = {
								{ kind = "added", new_line = 1 },
								{ kind = "added", new_line = 2 },
								{ kind = "context", old_line = 1, new_line = 3 },
							},
						},
					},
				},
			},
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "right", line = 1 },
					comments = { { author = "alice", body = "comment at file start" } },
				},
			},
		}
		local filler_ns = require("codediff.ui.highlights").ns_filler
		vim.api.nvim_buf_set_extmark(left_buf, filler_ns, 0, 0, {
			virt_lines = {
				{ { "filler 1", "CodeDiffFiller" } },
				{ { "filler 2", "CodeDiffFiller" } },
			},
			virt_lines_above = true,
		})

		inline.place(session)

		local right_marks = extmarks(right_buf)
		local left_marks = extmarks(left_buf)
		local filler_marks = filler_extmarks(left_buf)
		assert.are.equal(1, #right_marks)
		assert.are.equal(0, #left_marks)
		assert.are.equal(0, right_marks[1][2])
		assert.is_false(right_marks[1][4].virt_lines_above)
		assert.are.equal(1, #filler_marks)
		assert.are.equal(2 + #right_marks[1][4].virt_lines, #filler_marks[1][4].virt_lines)
		assert.are.equal(2, first_virt_line_matching(filler_marks[1], "╱"))
		assert.matches("right L1", flatten_virt_lines(right_marks[1]))
	end)

	it("falls back to regular filler lines when a one-sided target has no opposite filler", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, numbered_lines("left", 100))
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, numbered_lines("right", 100))
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = {
				{
					path = "a.lua",
					hunks = {
						{
							lines = {
								{ kind = "context", old_line = 93, new_line = 93 },
								{ kind = "deleted", old_line = 94 },
								{ kind = "deleted", old_line = 95 },
								{ kind = "deleted", old_line = 96 },
								{ kind = "added", new_line = 94 },
								{ kind = "added", new_line = 95 },
								{ kind = "added", new_line = 96 },
								{ kind = "context", old_line = 97, new_line = 97 },
							},
						},
					},
				},
			},
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = { kind = "line", path = "a.lua", side = "left", line = 96 },
					comments = { { author = "alice", body = "comment inside a deleted block" } },
				},
			},
		}

		inline.place(session)

		local left_marks = extmarks(left_buf)
		local right_marks = extmarks(right_buf)
		assert.are.equal(1, #left_marks)
		assert.are.equal(1, #right_marks)
		assert.are.equal(95, left_marks[1][2])
		assert.are.equal(95, right_marks[1][2])
		assert.matches("left L96", flatten_virt_lines(left_marks[1]))
		assert.matches("╱", flatten_virt_lines(right_marks[1]))
	end)

	it("keeps inline blocks inside the text area", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line" })
		local win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(win, buf)
		local old_number = vim.wo[win].number
		local old_signcolumn = vim.wo[win].signcolumn
		local old_foldcolumn = vim.wo[win].foldcolumn
		vim.wo[win].number = true
		vim.wo[win].signcolumn = "yes"
		vim.wo[win].foldcolumn = "1"
		local session = {
			ui = { left_buffer = vim.api.nvim_create_buf(false, true), right_buffer = buf, right_window = win },
			threads = {
				{
					state = "open",
					target = { path = "a.lua", side = "right", line = 1 },
					comments = { { body = "rendered in a bounded inline block" } },
				},
			},
		}

		inline.place(session)

		local mark = extmarks(buf)[1]
		local first_line = mark[4].virt_lines[1][1][1]
		local info = vim.fn.getwininfo(win)[1]
		local max_width = vim.api.nvim_win_get_width(win) - info.textoff - 4
		assert.is_true(vim.fn.strdisplaywidth(first_line) <= max_width)
		vim.wo[win].number = old_number
		vim.wo[win].signcolumn = old_signcolumn
		vim.wo[win].foldcolumn = old_foldcolumn
	end)

	it("reserves aligned virtual rows for an inline composer", function()
		local left_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, { "left 1", "left 2", "left 3" })
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "right 1", "right 2", "right 3" })
		local editor = {
			target = { kind = "line", path = "a.lua", side = "right", line = 2 },
			total_height = 6,
		}
		local session = {
			ui = { left_buffer = left_buf, right_buffer = right_buf },
			files = { { path = "a.lua", hunks = {} } },
			selection = { file_index = 1 },
			threads = {},
			_inline_editor = editor,
		}

		inline.place(session)

		local left_marks = extmarks(left_buf)
		local right_marks = extmarks(right_buf)
		assert.are.equal(1, #left_marks)
		assert.are.equal(1, #right_marks)
		assert.are.equal(6, #left_marks[1][4].virt_lines)
		assert.are.equal(6, #right_marks[1][4].virt_lines)
		assert.matches("╱", flatten_virt_lines(left_marks[1]))
		assert.is_not_nil(editor.geometry)
		assert.are.equal(right_buf, editor.geometry.buffer)
		assert.are.equal(1, editor.geometry.row)
		assert.are.equal(0, editor.geometry.row_offset)
	end)

	it("places a reply composer after the existing thread block", function()
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "line 2" })
		local target = { kind = "line", path = "a.lua", side = "right", line = 1 }
		local editor = { target = target, total_height = 6 }
		local session = {
			ui = { left_buffer = vim.api.nvim_create_buf(false, true), right_buffer = right_buf },
			files = { { path = "a.lua", hunks = {} } },
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = target,
					comments = { { author = "alice", body = "existing comment" } },
				},
			},
			_inline_editor = editor,
		}

		inline.place(session)

		local mark = extmarks(right_buf)[1]
		assert.matches("existing comment", flatten_virt_lines(mark))
		assert.are.equal(#mark[4].virt_lines - editor.total_height, editor.geometry.row_offset)
		assert.is_true(editor.geometry.row_offset > 0)
	end)

	it("does not change buffer contents or line count", function()
		local buf = vim.api.nvim_create_buf(false, true)
		local lines = { "line 1", "line 2" }
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		local session = {
			ui = { left_buffer = vim.api.nvim_create_buf(false, true), right_buffer = buf },
			threads = {
				{
					state = "open",
					target = { path = "a.lua", side = "right", line = 1 },
					comments = { { body = "rendered as virtual lines only" } },
				},
			},
		}

		inline.place(session)

		assert.are.equal(2, vim.api.nvim_buf_line_count(buf))
		assert.are.same(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
	end)

	it("does not render threads from other files", function()
		local right_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, { "line 1", "line 2" })
		local session = {
			ui = {
				left_buffer = vim.api.nvim_create_buf(false, true),
				right_buffer = right_buf,
			},
			files = { { path = "a.lua", hunks = {} }, { path = "b.lua", hunks = {} } },
			selection = { file_index = 1 },
			threads = {
				{
					state = "open",
					target = { path = "a.lua", side = "right", line = 1 },
					comments = { { body = "here" } },
				},
				{
					state = "open",
					target = { path = "b.lua", side = "right", line = 2 },
					comments = { { body = "other" } },
				},
			},
		}

		inline.place(session)

		local marks = extmarks(right_buf)
		assert.are.equal(1, #marks)
		assert.are.equal(0, marks[1][2])
		assert.matches("here", flatten_virt_lines(marks[1]))
		assert.not_matches("other", flatten_virt_lines(marks[1]))
	end)

	it("clears all inline virtual lines", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line" })
		local session = {
			ui = { left_buffer = vim.api.nvim_create_buf(false, true), right_buffer = buf },
			threads = {
				{ state = "open", target = { path = "a.lua", side = "right", line = 1 }, comments = {} },
			},
		}

		inline.place(session)
		assert.are.equal(1, #extmarks(buf))

		inline.clear(session)
		assert.are.equal(0, #extmarks(buf))
	end)

	it("navigates between inline marks", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "l1", "l2", "l3", "l4" })
		local session = {
			ui = { left_buffer = vim.api.nvim_create_buf(false, true), right_buffer = buf },
			threads = {
				{
					state = "open",
					target = { path = "a.lua", side = "right", line = 2 },
					comments = { { body = "a" } },
				},
				{
					state = "open",
					target = { path = "a.lua", side = "right", line = 3 },
					comments = { { body = "b" } },
				},
			},
		}
		inline.place(session)

		-- From row 0 (before line 1), next should be row 2 (line 2, 0-indexed 1)
		assert.are.equal(2, inline.next_inline(buf, 0))
		-- From row 2, next should wrap to first
		assert.are.equal(3, inline.next_inline(buf, 1))
		-- Previous from row 2 should go to row 0
		assert.are.equal(2, inline.previous_inline(buf, 2))
		-- Previous from row 0 should wrap to last
		assert.are.equal(3, inline.previous_inline(buf, 0))
	end)

	it("does not render stale thread blocks in diff buffers", function()
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })
		local session = {
			ui = { left_buffer = vim.api.nvim_create_buf(false, true), right_buffer = buf },
			threads = {
				{
					state = "stale",
					target = { path = "a.lua", side = "right", line = 1 },
					comments = { { body = "gone" } },
				},
				{
					state = "open",
					is_outdated = true,
					target = { path = "a.lua", side = "right", line = 2 },
					comments = { { body = "outdated" } },
				},
			},
		}

		inline.place(session)
		assert.are.equal(0, #extmarks(buf))
	end)
end)
