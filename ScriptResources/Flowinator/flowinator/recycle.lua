local Paths = require("paths")

local Recycle = {}

Recycle.folder_name = "99_Flowinator_Recycle"

function Recycle.root(project_root)
	return Paths.join(project_root, Recycle.folder_name)
end

function Recycle.begin(project_root)
	local session = Paths.join(Recycle.root(project_root), os.date("%Y%m%d_%H%M%S") .. "_" .. tostring(math.random(1000, 9999)))
	Paths.mkdir(session)
	return session
end

function Recycle.move(project_root, source, session)
	if not source or source == "" then return true end
	session = session or Recycle.begin(project_root)
	local relative = Paths.relative(project_root, source)
	if relative == "" or relative == source then return false end
	return Paths.move(source, Paths.join(session, relative))
end

function Recycle.clear(project_root)
	local folder = Recycle.root(project_root)
	Paths.remove_dir(folder)
	Paths.mkdir(folder)
	return true
end

return Recycle
