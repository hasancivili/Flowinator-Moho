local Paths = require("paths")
local Metadata = require("metadata")

local Project = {}

Project.structure = {
	"00_Pipeline",
	"00_Pipeline/Metadata",
	"00_Pipeline/Users",
	"00_Pipeline/Config",
	"01_Assets",
	"01_Assets/Characters",
	"01_Assets/Props",
	"01_Assets/Environments",
	"02_Scenes",
	"03_Renders",
	"04_Resources",
	"05_Publish",
	"99_Flowinator_Recycle"
}

function Project.metadata_path(root)
	return Paths.join(root, "00_Pipeline", "Metadata", "project.json")
end

function Project.create(location, name, code, notes)
	local safe_code = Paths.safe_name(code ~= "" and code or name)
	local root = Paths.join(location, safe_code)
	Paths.ensure_tree(root, Project.structure)
	local data = {
		name = name,
		code = code,
		notes = notes,
		root = root,
		use_episodes = false,
		created = os.date("%Y-%m-%d %H:%M:%S")
	}
	Metadata.write(Project.metadata_path(root), data)
	return data
end

function Project.open(root)
	return Metadata.read(Project.metadata_path(root), nil)
end

function Project.update(root, updated)
	if not root or root == "" or not updated then
		return false
	end
	local current = Project.open(root) or {}
	current.name = updated.name or current.name or "Untitled"
	current.code = current.code or updated.code or ""
	current.notes = updated.notes or current.notes or ""
	if updated.use_episodes ~= nil then
		current.use_episodes = updated.use_episodes and true or false
	elseif current.use_episodes == nil then
		current.use_episodes = false
	end
	current.root = root
	current.updated = os.date("%Y-%m-%d %H:%M:%S")
	return Metadata.write(Project.metadata_path(root), current), current
end

local function local_state_path()
	local base = os.getenv("APPDATA") or os.getenv("HOME") or "."
	return Paths.join(base, "Flowinator", "flowinator_state.json")
end

function Project.remember(root)
	if not root or root == "" then
		return false
	end
	local state = Metadata.read(local_state_path(), {recent_projects = {}})
	state.recent_projects = state.recent_projects or {}
	local recent = {root}
	for _, item in ipairs(state.recent_projects) do
		if item ~= root then
			table.insert(recent, item)
		end
		if #recent >= 12 then
			break
		end
	end
	state.last_project = root
	state.recent_projects = recent
	state.updated = os.date("%Y-%m-%d %H:%M:%S")
	return Metadata.write(local_state_path(), state)
end

function Project.local_state()
	return Metadata.read(local_state_path(), {recent_projects = {}})
end

function Project.open_last()
	local state = Project.local_state()
	local candidates = {}
	if state.last_project then
		table.insert(candidates, state.last_project)
	end
	for _, root in ipairs(state.recent_projects or {}) do
		table.insert(candidates, root)
	end
	for _, root in ipairs(candidates) do
		local project = Project.open(root)
		if project then
			project.root = root
			return project
		end
	end
	return nil
end

return Project
