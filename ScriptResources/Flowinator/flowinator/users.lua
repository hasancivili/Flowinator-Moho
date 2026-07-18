local Paths = require("paths")
local Metadata = require("metadata")

local Users = {}

local current_user = nil
local current_root = nil

Users.ROLE_ADMIN = "project_admin"
Users.ROLE_ARTIST = "artist"

function Users.role_label(role)
	return role == Users.ROLE_ADMIN and "Project Admin" or "Artist"
end

local function normalize_role(role)
	return role == Users.ROLE_ADMIN and Users.ROLE_ADMIN or Users.ROLE_ARTIST
end

local function users_path(root)
	return Paths.join(root, "00_Pipeline", "Metadata", "users.json")
end

local function local_sessions_path()
	local base = os.getenv("APPDATA") or os.getenv("HOME") or "."
	return Paths.join(base, "Flowinator", "flowinator_sessions.json")
end

local function same_root(a, b)
	local left = Paths.normalize(a or "")
	local right = Paths.normalize(b or "")
	if package.config:sub(1, 1) == "\\" then
		left = left:lower()
		right = right:lower()
	end
	return left == right
end

local function local_session(root)
	local data = Metadata.read(local_sessions_path(), {projects = {}})
	data.projects = data.projects or {}
	for _, entry in ipairs(data.projects) do
		if same_root(entry.root, root) then
			return data, entry
		end
	end
	return data, nil
end

local function save_local_session(root, username)
	if not root or root == "" then return false end
	local data, entry = local_session(root)
	if not entry then
		entry = {root = root}
		table.insert(data.projects, entry)
	end
	entry.current_user = username or ""
	entry.logged_in = username and username ~= "" and os.date("%Y-%m-%d %H:%M:%S") or ""
	return Metadata.write(local_sessions_path(), data)
end

function Users.load(root)
	local data = Metadata.read(users_path(root), {users = {}})
	data.users = data.users or {}
	-- Existing projects predate roles. Keep their current users fully functional.
	for _, user in ipairs(data.users) do
		if not user.role then
			user.role = Users.ROLE_ADMIN
		end
	end
	return data
end

function Users.save(root, data)
	return Metadata.write(users_path(root), data)
end

function Users.add(root, username, password, role)
	if not username or username == "" or not password or password == "" then
		return false, "Username and Password are required."
	end
	local data = Users.load(root)
	for _, user in ipairs(data.users) do
		if user.username == username then
			return false, "User already exists."
		end
	end
	if #(data.users or {}) == 0 then
		role = Users.ROLE_ADMIN
	else
		role = normalize_role(role)
	end
	table.insert(data.users, {
		username = username,
		password = password,
		role = role,
		created = os.date("%Y-%m-%d %H:%M:%S")
	})
	Users.save(root, data)
	return true
end

function Users.find(root, username)
	if not username or username == "" then return nil end
	local data = Users.load(root)
	for _, user in ipairs(data.users or {}) do
		if user.username == username then
			return user
		end
	end
	return nil
end

function Users.role(root, username)
	local user = Users.find(root, username)
	return user and normalize_role(user.role) or nil
end

function Users.can_manage_project(root, username)
	return Users.role(root, username) == Users.ROLE_ADMIN
end

function Users.can_delete_item(root, username, item)
	if Users.can_manage_project(root, username) then return true end
	return item and item.owner and item.owner == username
end

function Users.set_role(root, username, role)
	if not username or username == "" then
		return false, "Select a user first."
	end
	local data = Users.load(root)
	for _, user in ipairs(data.users or {}) do
		if user.username == username then
			if user.role == Users.ROLE_ADMIN and normalize_role(role) ~= Users.ROLE_ADMIN then
				local admin_count = 0
				for _, other in ipairs(data.users) do
					if normalize_role(other.role) == Users.ROLE_ADMIN then admin_count = admin_count + 1 end
				end
				if admin_count <= 1 then
					return false, "A project must keep at least one Project Admin."
				end
			end
			user.role = normalize_role(role)
			return Users.save(root, data)
		end
	end
	return false, "User was not found."
end

function Users.delete(root, username, actor)
	if not username or username == "" then
		return false, "Select a user first."
	end
	if actor and not Users.can_manage_project(root, actor) then
		return false, "Only Project Admins can manage users."
	end
	local data = Users.load(root)
	local removed_user = nil
	for _, user in ipairs(data.users or {}) do
		if user.username == username then removed_user = user break end
	end
	if removed_user and normalize_role(removed_user.role) == Users.ROLE_ADMIN then
		local admin_count = 0
		for _, user in ipairs(data.users or {}) do
			if normalize_role(user.role) == Users.ROLE_ADMIN then admin_count = admin_count + 1 end
		end
		if admin_count <= 1 then
			return false, "A project must keep at least one Project Admin."
		end
	end
	local kept = {}
	local removed = false
	for _, user in ipairs(data.users or {}) do
		if user.username == username then
			removed = true
		else
			table.insert(kept, user)
		end
	end
	if not removed then
		return false, "User was not found."
	end
	data.users = kept
	Users.save(root, data)
	if current_user == username and current_root == root then
		current_user = nil
		current_root = nil
		save_local_session(root, "")
	end
	return true
end

function Users.clear_current(root)
	current_user = nil
	current_root = nil
	if root then
		save_local_session(root, "")
	end
end

function Users.login(root, username, password)
	if not username or username == "" or not password or password == "" then
		return false, "Username and Password are required."
	end
	local data = Users.load(root)
	for _, user in ipairs(data.users) do
		if user.username == username and user.password == password then
			current_user = username
			current_root = root
			save_local_session(root, username)
			return true
		end
	end
	return false, "Invalid username or password."
end

function Users.current(root)
	if current_user and current_root == root then
		if Users.find(root, current_user) then
			return current_user
		end
		current_user = nil
		current_root = nil
	end
	local _, session = local_session(root)
	local username = session and session.current_user or ""
	if username ~= "" and Users.find(root, username) then
		current_user = username
		current_root = root
	else
		current_user = nil
		current_root = nil
		if username ~= "" then
			save_local_session(root, "")
		end
	end
	return current_user
end

return Users
