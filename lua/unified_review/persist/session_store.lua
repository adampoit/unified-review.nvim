local migration = require("unified_review.persist.migration")
local repo_store = require("unified_review.persist.repo_store")

local M = {}

local function session_path(root, session_id, opts)
	local dir = repo_store.ensure_repo_dir(root, opts)
	return dir .. "/" .. session_id:gsub("[^%w._-]", "_") .. ".json"
end

local function encode(data)
	return vim.json.encode(data)
end

local function decode(text)
	return vim.json.decode(text, { luanil = { object = true, array = true } })
end

function M.snapshot(session)
	return {
		version = migration.current_version,
		session = {
			id = session.id,
			kind = session.kind,
			provider = session.provider,
			target = session.target,
			metadata = session.metadata,
			created_at = session.created_at,
			updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		},
		threads = session.threads or {},
		anchors = session.anchors or {},
	}
end

function M.write(session, opts)
	local root = assert(session.target and session.target.root, "session target root is required")
	local path = session_path(root, assert(session.id, "session id is required"), opts)
	vim.fn.writefile(vim.split(encode(M.snapshot(session)), "\n", { plain = true }), path)
	return path
end

function M.read(root, session_id, opts)
	local path = session_path(root, session_id, opts)
	if vim.fn.filereadable(path) == 0 then
		return nil, { message = "session store not found", path = path }
	end
	local ok, data = pcall(decode, table.concat(vim.fn.readfile(path), "\n"))
	if not ok then
		return nil, { message = "failed to decode session store", error = data, path = path }
	end
	return migration.migrate(data)
end

function M.restore(session, opts)
	local data, err = M.read(session.target.root, session.id, opts)
	if not data then
		return nil, err
	end
	session.threads = data.threads or {}
	session.anchors = data.anchors or {}
	session.persisted = data.session or {}
	session.metadata =
		vim.tbl_deep_extend("force", session.metadata or {}, data.session and data.session.metadata or {})
	return session, nil
end

return M
