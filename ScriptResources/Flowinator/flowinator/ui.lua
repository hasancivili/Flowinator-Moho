local Project = require("project")
local Users = require("users")
local Assets = require("assets")
local Shots = require("shots")
local Versions = require("versions")
local Paths = require("paths")
local Recycle = require("recycle")

local UI = {}

local MSG_NEW_PROJECT = 50001
local MSG_OPEN_PROJECT = 50002
local MSG_ADD_USER = 50003
local MSG_LOGIN = 50004
local MSG_PROJECT_SETTINGS = 50005
local MSG_LOGOUT = 50006
local MSG_PROJECT_DIALOG_RECENT_SELECTED = 50007
local MSG_TYPE_SELECTED = 50010
local MSG_ADD_TYPE = 50011
local MSG_MODE_ASSETS = 50012
local MSG_MODE_SHOTS = 50013
local MSG_DELETE_TYPE = 50014
local MSG_REFRESH = 50020
local MSG_ASSET_SELECTED = 50021
local MSG_WORK_VERSION_SELECTED = 50022
local MSG_PUBLISH_VERSION_SELECTED = 50023
local MSG_VARIANT_SELECTED = 50024
local MSG_WORK_TYPE_SELECTED = 50025
local MSG_WORK_ITEM_SELECTED = 50026
local MSG_CREATE_ASSET = 50030
local MSG_ADD_VARIANT = 50031
local MSG_SHOW_PREVIEW = 50032
local MSG_ADD_WORK_TYPE = 50033
local MSG_ADD_WORK_ITEM = 50034
local MSG_DELETE_ITEM = 50035
local MSG_DELETE_VARIANT = 50036
local MSG_DELETE_WORK_TYPE = 50037
local MSG_DELETE_WORK_ITEM = 50038
local MSG_CREATE_WORKFILE = 50040
local MSG_SAVE_VERSION = 50042
local MSG_OPEN_FOLDER = 50043
local MSG_PUBLISH_VERSION = 50044
local MSG_REFERENCE_LIVE = 50045
local MSG_LOAD_VERSION = 50046
local MSG_IMPORT_LIVE = 50047
local MSG_DELETE_WORK_VERSION = 50048
local MSG_ASSET_TYPE_CHARACTER = 50101
local MSG_ASSET_TYPE_PROP = 50102
local MSG_ASSET_TYPE_ENVIRONMENT = 50103
local MSG_PROJECT_DIALOG_BROWSE_LOCATION = 50201
local MSG_PROJECT_DIALOG_BROWSE_ROOT = 50202
local MSG_SETTINGS_ADD_USER = 50301
local MSG_SETTINGS_TOGGLE_EPISODES = 50302
local MSG_SETTINGS_DELETE_USER = 50303
local MSG_SETTINGS_ROLE_ADMIN = 50304
local MSG_SETTINGS_ROLE_ARTIST = 50305
local MSG_SETTINGS_SET_USER_ROLE = 50306
local MSG_SETTINGS_USER_SELECTED = 50307
local MSG_SETTINGS_EMPTY_RECYCLE = 50308
local MSG_PREVIEW_SET_NEW = 50401
local MSG_SHOT_LAYOUT_TOGGLE = 50501
local MSG_SHOT_ANIMATION_TOGGLE = 50502
local MSG_SHOT_FX_TOGGLE = 50503
local MSG_ASSET_DRAW_TOGGLE = 50511
local MSG_ASSET_RIG_TOGGLE = 50512
local MSG_ASSET_FX_TOGGLE = 50513
local MSG_SEQUENCE_LAYOUT = 50521
local MSG_SEQUENCE_ANIMATION = 50522
local MSG_SEQUENCE_FX = 50523
local MSG_DYNAMIC_TYPE_BASE = 51000

-- Keep the fixed native Moho dialog compact while leaving a small gutter after actions.
local BROWSER_LIST_WIDTH = 110
local CURRENT_PROJECT_TEXT_WIDTH = 240
local VERSION_LIST_WIDTH = 390

local state = {
	project = nil,
	current_user = nil,
	browser_mode = "assets",
	selected_type = nil,
	selected_asset_id = nil,
	selected_variant_id = nil,
	selected_work_branch_id = nil,
	selected_work_type = nil,
	selected_shot_id = nil,
	selected_episode = nil,
	selected_sequence = nil,
	selected_work_version = nil,
	selected_publish_version = nil,
	selected_version_kind = "work",
	assets = {},
	assets_by_id = {},
	shots = {},
	shots_by_id = {},
	type_rows = {},
	asset_rows = {},
	variant_rows = {},
	work_type_rows = {},
	work_item_rows = {},
	work_version_rows = {},
	publish_version_rows = {},
	preview_cache_token = 0,
	refreshing_lists = false
}

local function module_dir()
	local source = debug.getinfo(1, "S").source:gsub("^@", "")
	return source:match("^(.*[\\/])") or ""
end

local MODULE_DIR = module_dir()
local RESOURCE_DIR = MODULE_DIR:gsub("flowinator[/\\]?$", "")
local PREVIEW_CACHE_DIR = Paths.join(RESOURCE_DIR, "preview_cache")
local PREVIEW_RESOURCE_PREFIX = "ScriptResources/Flowinator/preview_cache/"
local EMPTY_PREVIEW_RESOURCE = PREVIEW_RESOURCE_PREFIX .. "empty"
local text_cache = {}
local preview_cache_ready = false
local preview_resource_cache = {}

local function alert(text)
	if LM and LM.GUI and type(LM.GUI.Alert) == "function" then
		LM.GUI.Alert(LM.GUI.ALERT_INFO, text or "")
	else
		print(text or "")
	end
end

local function confirm_warning(title, line2, line3, action)
	if LM and LM.GUI and type(LM.GUI.Alert) == "function" then
		local result = LM.GUI.Alert(LM.GUI.ALERT_WARNING, title or "", line2, line3, action or "Delete", "Cancel", nil)
		return result == 0
	end
	return false
end

local function text_value(control)
	if not control then return "" end
	if type(control.Value) == "function" then
		local ok, value = pcall(function() return control:Value() end)
		if ok then return value or "" end
	end
	if type(control.Text) == "function" then
		local ok, value = pcall(function() return control:Text() end)
		if ok then return value or "" end
	end
	return ""
end

local function set_text(control, value)
	if not control then return end
	value = value or ""
	if text_cache[control] == value then
		return
	end
	text_cache[control] = value
	if type(control.SetValue) == "function" then
		pcall(function() control:SetValue(value) end)
	elseif type(control.SetText) == "function" then
		pcall(function() control:SetText(value) end)
	end
	if type(control.Redraw) == "function" then
		pcall(function() control:Redraw() end)
	end
end

local function set_button_label(button, value)
	if not button then return end
	value = value or ""
	if type(button.SetLabel) == "function" then
		pcall(function() button:SetLabel(value) end)
	elseif type(button.SetText) == "function" then
		pcall(function() button:SetText(value) end)
	elseif type(button.SetValue) == "function" then
		pcall(function() button:SetValue(value) end)
	end
end

local function add_label(layout, text)
	layout:AddChild(LM.GUI.StaticText(text), LM.GUI.ALIGN_LEFT)
end

local function add_dynamic(layout, text, width)
	local label = LM.GUI.DynamicText(text, width or 0)
	layout:AddChild(label, LM.GUI.ALIGN_LEFT)
	return label
end

local function add_button(layout, label, msg)
	local button = LM.GUI.Button(label, msg)
	layout:AddChild(button, LM.GUI.ALIGN_LEFT)
	return button
end

local function add_small_button(layout, label, msg)
	return add_button(layout, " " .. (label or "") .. " ", msg)
end

local function call_method(obj, name, ...)
	if obj and type(obj[name]) == "function" then
		local args = {...}
		local unpack_args = unpack or table.unpack
		local ok, result = pcall(function()
			return obj[name](obj, unpack_args(args))
		end)
		if ok then return result end
	end
	return nil
end

local function select_list_item(list, index)
	if not list or type(list.SetSelItem) ~= "function" then return end
	local ok = pcall(function() list:SetSelItem(index, true) end)
	if not ok then
		ok = pcall(function() list:SetSelItem(index, false) end)
	end
	if not ok then
		pcall(function() list:SetSelItem(index) end)
	end
end

local function add_image_button(layout, path, tooltip, msg)
	if LM and LM.GUI and type(LM.GUI.ImageButton) == "function" then
		local ok, button = pcall(function()
			return LM.GUI.ImageButton(path, tooltip or "", true, msg or 0, true)
		end)
		if not ok or not button then
			ok, button = pcall(function()
				return LM.GUI.ImageButton(path, tooltip or "", false, msg or 0, false)
			end)
		end
		if ok and button then
			layout:AddChild(button, LM.GUI.ALIGN_LEFT)
			return button
		end
	end
	local button = LM.GUI.Button("Preview", msg or 0)
	if type(button.SetTooltip) == "function" then
		pcall(function() button:SetTooltip(tooltip or "") end)
	end
	layout:AddChild(button, LM.GUI.ALIGN_LEFT)
	return button
end

local function add_edit(layout, label, default, width)
	layout:AddChild(LM.GUI.StaticText(label), LM.GUI.ALIGN_LEFT)
	local edit = LM.GUI.TextControl(width or 220, default or "", 0, LM.GUI.FIELD_TEXT)
	layout:AddChild(edit, LM.GUI.ALIGN_FILL)
	return edit
end

local function add_checkbox(layout, label, checked, msg)
	local edit = LM.GUI.TextControl(60, checked and "yes" or "no", 0, LM.GUI.FIELD_TEXT)
	layout:AddChild(LM.GUI.StaticText(label .. " (yes/no)"), LM.GUI.ALIGN_LEFT)
	layout:AddChild(edit, LM.GUI.ALIGN_LEFT)
	return edit
end

local function bool_value(control)
	if not control then return false end
	if type(control.Value) == "function" then
		local ok, value = pcall(function() return control:Value() end)
		if ok then
			if type(value) == "boolean" then return value end
			return tostring(value):lower() == "true" or tostring(value):lower() == "yes" or tostring(value) == "1"
		end
	end
	local text = text_value(control):lower()
	return text == "true" or text == "yes" or text == "1" or text == "on"
end

local function split_csv(text)
	local out = {}
	for part in tostring(text or ""):gmatch("[^,]+") do
		local clean = part:gsub("^%s+", ""):gsub("%s+$", "")
		if clean ~= "" then table.insert(out, clean) end
	end
	return out
end

local function clear_text_list(list)
	if not list or type(list.CountItems) ~= "function" then return end
	while list:CountItems() > 0 do
		call_method(list, "RemoveItem", 0, false)
	end
end

local function bind_methods(dialog, methods)
	for name, fn in pairs(methods) do
		if type(fn) == "function" then
			dialog[name] = fn
		end
	end
end

local function select_folder(caption)
	if LM and LM.GUI and type(LM.GUI.SelectFolder) == "function" then
		local ok, folder = pcall(function() return LM.GUI.SelectFolder(caption) end)
		if ok and folder and folder ~= "" then return folder end
	end
	return nil
end

local function with_live_moho(fallback, fn)
	if MOHO and MOHO.ScriptInterfaceHelper then
		local ok, helper = pcall(function() return MOHO.ScriptInterfaceHelper:new_local() end)
		if ok and helper and type(helper.MohoObject) == "function" then
			local ok2, moho = pcall(function() return helper:MohoObject() end)
			if ok2 and moho then
				local ok3, result, err = pcall(fn, moho)
				if type(helper.delete) == "function" then pcall(function() helper:delete() end) end
				if ok3 then return result, err end
				return nil, result
			end
			if type(helper.delete) == "function" then pcall(function() helper:delete() end) end
		end
	end
	return fn(fallback)
end

local function clip(value, size)
	local text = tostring(value or "")
	if #text <= size then
		return text
	end
	return text:sub(1, size - 1) .. "."
end

local function work_label(version)
	if not version or version == 0 then
		return "-"
	end
	return string.format("V%04d", version)
end

local function publish_label(version)
	if not version or version == 0 then
		return "-"
	end
	return string.format("P%03d", version)
end

local function version_row(entry, prefix, live_entry)
	local version = entry and entry.version or 0
	local author = entry and entry.author or ""
	local comment = entry and entry.comment or ""
	local width = prefix == "V" and "%s%04d" or "%s%03d"
	local live = live_entry and live_entry.version == version and "Live" or "-"
	if prefix == "P" then
		return string.format("%-12s     %-20s     %-28s     %s", string.format(width, prefix, version), clip(author, 20), clip(comment, 28), live)
	end
	return string.format("%-12s     %-20s     %s", string.format(width, prefix, version), clip(author, 20), clip(comment, 28))
end

local function add_banner(layout)
	if LM and LM.GUI and type(LM.GUI.ImageButton) == "function" then
		local ok, banner = pcall(function()
			return LM.GUI.ImageButton("ScriptResources/Ikon/Banner", "Flowinator", false, 0, false)
		end)
		if ok and banner then
			layout:AddChild(banner, LM.GUI.ALIGN_LEFT)
			return
		end
	end
end

local function episode_label(episode)
	return episode and episode ~= "" and episode or "Default"
end

local function selected_episode_value()
	return state.selected_episode == "Default" and "" or (state.selected_episode or "")
end

local function asset_table_row(name)
	return name:upper()
end

local function work_item_label(item, branch)
	if not item or not branch then return "" end
	local latest = branch.workfiles and branch.workfiles[#branch.workfiles] or nil
	local path = latest and latest.path or ""
	local file = path:match("[^/\\]+$") or ""
	if file ~= "" then
		file = file:gsub("%.moho$", "")
		file = file:gsub("_V%d%d%d%d$", ""):gsub("_V%d%d%d$", "")
		return file
	end
	local parts = {item.safe_name or Paths.safe_name(item.name)}
	if item.variant and item.variant ~= "Default" and item.variant ~= "Default Variant" then
		table.insert(parts, Paths.safe_name(item.variant))
	end
	table.insert(parts, Paths.safe_name(branch.work_type or "Work"))
	if branch.work_item and branch.work_item ~= "Default" and branch.work_item ~= "Default Work Item" then
		table.insert(parts, Paths.safe_name(branch.work_item))
	end
	return table.concat(parts, "_")
end

local function resolve_preview_path(preview_path)
	if not preview_path or preview_path == "" then
		return ""
	end
	if Paths.exists(preview_path) then
		return preview_path
	end
	if state.project and state.project.root then
		local root_rel = Paths.join(state.project.root, preview_path)
		if Paths.exists(root_rel) then
			return root_rel
		end
		local filename = preview_path:match("[^/\\]+$") or preview_path
		local previews_rel = Paths.join(state.project.root, "00_Pipeline", "Metadata", "Previews", filename)
		if Paths.exists(previews_rel) then
			return previews_rel
		end
	end
	return preview_path
end

local function preview_cache_path(asset, entry, kind, force, token)
	if not asset or not entry or not entry.preview_path or entry.preview_path == "" then
		return nil
	end
	if not entry.preview_path:lower():match("%.png$") then
		return nil
	end
	local src = resolve_preview_path(entry.preview_path)
	if not Paths.exists(src) then
		return nil
	end
	if not preview_cache_ready then
		Paths.mkdir(PREVIEW_CACHE_DIR)
		preview_cache_ready = true
	end
	local version = entry.version or 0
	local suffix = tostring(Paths.file_size(src))
	local cache_key = tostring(src) .. "|" .. suffix .. "|" .. tostring(force and token or "")
	if not force and preview_resource_cache[cache_key] then
		return preview_resource_cache[cache_key]
	end
	if force and token then
		suffix = suffix .. "_" .. tostring(token)
	end
	local file_name = Paths.safe_name((asset.safe_name or asset.name or "asset") .. "_" .. (kind or "work") .. "_V" .. string.format("%03d", version) .. "_" .. suffix) .. ".png"
	local dst = Paths.join(PREVIEW_CACHE_DIR, file_name)
	if force or not Paths.exists(dst) or Paths.file_size(dst) == 0 then
		Paths.copy_file(src, dst)
	end
	local resource = PREVIEW_RESOURCE_PREFIX .. file_name:gsub("%.png$", "")
	preview_resource_cache[cache_key] = resource
	return resource
end

local ProjectDialog = {}

function ProjectDialog:new(mode)
	local d = LM.GUI.SimpleDialog(mode == "create" and "Create Project" or "Open Project", ProjectDialog)
	bind_methods(d, ProjectDialog)
	ProjectDialog.dialog = d
	ProjectDialog.result = nil
	local l = d:GetLayout()
	d.mode = mode
	if mode == "create" then
		add_label(l, "PROJECT LOCATION")
		d.location = add_edit(l, "Folder", "", 380)
		add_button(l, "Browse Location...", MSG_PROJECT_DIALOG_BROWSE_LOCATION)
		l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)
		add_label(l, "PROJECT INFO")
		d.name = add_edit(l, "Name", "", 260)
		d.code = add_edit(l, "Code", "", 140)
		d.notes = add_edit(l, "Description / Notes", "", 380)
	else
		add_label(l, "PROJECT ROOT")
		d.root = add_edit(l, "Folder", "", 380)
		add_button(l, "Browse Project Root...", MSG_PROJECT_DIALOG_BROWSE_ROOT)
		l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)
		add_label(l, "RECENT PROJECTS")
		d.recentProjectList = LM.GUI.TextList(380, 120, MSG_PROJECT_DIALOG_RECENT_SELECTED)
		l:AddChild(d.recentProjectList, LM.GUI.ALIGN_FILL)
		add_label(l, "Select the folder that contains 00_Pipeline.")
		d:refresh_recent_projects()
	end
	return d
end

function ProjectDialog:refresh_recent_projects()
	if not self.recentProjectList then return end
	clear_text_list(self.recentProjectList)
	ProjectDialog.recent_rows = {}
	local seen = {}
	for _, root in ipairs(Project.local_state().recent_projects or {}) do
		if root and root ~= "" and not seen[root] then
			seen[root] = true
			local project = Project.open(root)
			if project then
				local label = project.name or "Untitled"
				if project.code and project.code ~= "" then
					label = label .. " [" .. project.code .. "]"
				end
				table.insert(ProjectDialog.recent_rows, {root = root, label = label})
				call_method(self.recentProjectList, "AddItem", label, false)
			end
		end
	end
	call_method(self.recentProjectList, "Redraw")
end

function ProjectDialog:HandleMessage(msg)
	local d = ProjectDialog.dialog or self
	if msg == MSG_PROJECT_DIALOG_BROWSE_LOCATION then
		local folder = select_folder("Select Project Location")
		if folder then set_text(d.location, folder) end
	elseif msg == MSG_PROJECT_DIALOG_BROWSE_ROOT then
		local folder = select_folder("Select Project Root")
		if folder then set_text(d.root, folder) end
	elseif msg == MSG_PROJECT_DIALOG_RECENT_SELECTED then
		local index = call_method(d.recentProjectList, "SelItem") or -1
		local row = (ProjectDialog.recent_rows or {})[index + 1]
		if row then set_text(d.root, row.root) end
	end
end

function ProjectDialog:OnOK()
	local d = ProjectDialog.dialog or self
	if d.mode == "create" then
		ProjectDialog.result = {
			location = text_value(d.location),
			name = text_value(d.name),
			code = text_value(d.code),
			notes = text_value(d.notes)
		}
	else
		ProjectDialog.result = {root = text_value(d.root)}
	end
end

local UserDialog = {}

function UserDialog:new(title)
	local d = LM.GUI.SimpleDialog(title, UserDialog)
	bind_methods(d, UserDialog)
	UserDialog.dialog = d
	UserDialog.result = nil
	local l = d:GetLayout()
	d.username = add_edit(l, "Username", "", 220)
	d.password = add_edit(l, "Password", "", 220)
	return d
end

function UserDialog:OnOK()
	local d = UserDialog.dialog or self
	UserDialog.result = {
		username = text_value(d.username),
		password = text_value(d.password)
	}
end

local ProjectSettingsDialog = {}

local function settings_episode_status()
	return ProjectSettingsDialog.use_episodes and "Use Episodes: On" or "Use Episodes: Off"
end

local function refresh_settings_users(d)
	clear_text_list(d.usersList)
	if not state.project or not state.project.root then
		return
	end
	local data = Users.load(state.project.root)
	ProjectSettingsDialog.user_rows = {}
	for _, user in ipairs(data.users or {}) do
		local role = Users.role_label(user.role)
		table.insert(ProjectSettingsDialog.user_rows, {username = user.username or "", role = user.role})
		call_method(d.usersList, "AddItem", string.format("%-24s %-16s %s", user.username or "", role, user.created or ""), false)
	end
	call_method(d.usersList, "Redraw")
end

local function settings_role_status()
	return "Role: " .. Users.role_label(ProjectSettingsDialog.selected_role)
end

function ProjectSettingsDialog:new()
	local d = LM.GUI.SimpleDialog("Project Settings", ProjectSettingsDialog)
	bind_methods(d, ProjectSettingsDialog)
	ProjectSettingsDialog.dialog = d
	ProjectSettingsDialog.result = nil
	local project = state.project or {}
	ProjectSettingsDialog.initial_name = project.name or ""
	ProjectSettingsDialog.initial_use_episodes = project.use_episodes and true or false
	local l = d:GetLayout()
	l:PushH()
	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "PROJECT")
	d.name = add_edit(l, "Project Name", project.name or "", 300)
	add_label(l, "Project Code")
	add_dynamic(l, project.code or "", 300)
	add_label(l, "Project Location")
	add_dynamic(l, project.root or "", 340)
	ProjectSettingsDialog.use_episodes = project.use_episodes and true or false
	-- SimpleDialog supplies the lower-right buttons. These calls are harmless on
	-- older Moho builds that do not expose label setters.
	call_method(d, "SetOKLabel", "Save")
	call_method(d, "SetCancelLabel", "Cancel")
	call_method(d, "SetOKButtonLabel", "Save")
	call_method(d, "SetCancelButtonLabel", "Cancel")
	l:PushH()
	add_button(l, "Use Episodes", MSG_SETTINGS_TOGGLE_EPISODES)
	d.useEpisodesStatus = add_dynamic(l, settings_episode_status(), 160)
	l:Pop()
	l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)
	add_label(l, "USERS")
	d.usersList = LM.GUI.TextList(420, 120, MSG_SETTINGS_USER_SELECTED)
	l:AddChild(d.usersList, LM.GUI.ALIGN_FILL)
	l:PushH()
	d.username = add_edit(l, "Username", "", 150)
	d.password = add_edit(l, "Password", "", 150)
	l:Pop()
	ProjectSettingsDialog.selected_role = Users.ROLE_ARTIST
	l:PushH()
	add_button(l, "Project Admin", MSG_SETTINGS_ROLE_ADMIN)
	add_button(l, "Artist", MSG_SETTINGS_ROLE_ARTIST)
	d.roleStatus = add_dynamic(l, settings_role_status(), 150)
	l:Pop()
	l:PushH()
	add_button(l, "Add User", MSG_SETTINGS_ADD_USER)
	add_button(l, "Set Role", MSG_SETTINGS_SET_USER_ROLE)
	add_button(l, "Delete User", MSG_SETTINGS_DELETE_USER)
	l:Pop()
	add_button(l, "Empty Flowinator Recycle", MSG_SETTINGS_EMPTY_RECYCLE)
	l:Pop()
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)
	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "CURRENT PROJECT")
	add_dynamic(l, project.name or "Untitled", 260)
	add_dynamic(l, project.code or "", 260)
	add_dynamic(l, project.root or "", 360)
	l:Pop()
	l:Pop()
	refresh_settings_users(d)
	return d
end

function ProjectSettingsDialog:HandleMessage(msg)
	local d = ProjectSettingsDialog.dialog or self
	if msg == MSG_SETTINGS_ADD_USER then
		local ok, err = Users.add(state.project.root, text_value(d.username), text_value(d.password), ProjectSettingsDialog.selected_role)
		alert(ok and "User added." or err)
		if ok then
			set_text(d.username, "")
			set_text(d.password, "")
			refresh_settings_users(d)
		end
	elseif msg == MSG_SETTINGS_DELETE_USER then
		local index = call_method(d.usersList, "SelItem") or 0
		local row = ProjectSettingsDialog.user_rows and ProjectSettingsDialog.user_rows[index + 1]
		if not row or not row.username or row.username == "" then
			alert("Select a user first.")
			return
		end
		local confirmed = confirm_warning(
			"Delete user: " .. row.username .. "?",
			"This only removes the local Flowinator user.",
			"Project files will not be deleted."
		)
		if not confirmed then return end
		local ok, err = Users.delete(state.project.root, row.username, state.current_user)
		alert(ok and "User deleted." or err)
		if ok then
			if state.current_user == row.username then
				state.current_user = nil
			end
			refresh_settings_users(d)
		end
	elseif msg == MSG_SETTINGS_TOGGLE_EPISODES then
		ProjectSettingsDialog.use_episodes = not ProjectSettingsDialog.use_episodes
		set_text(d.useEpisodesStatus, settings_episode_status())
	elseif msg == MSG_SETTINGS_ROLE_ADMIN then
		ProjectSettingsDialog.selected_role = Users.ROLE_ADMIN
		set_text(d.roleStatus, settings_role_status())
	elseif msg == MSG_SETTINGS_ROLE_ARTIST then
		ProjectSettingsDialog.selected_role = Users.ROLE_ARTIST
		set_text(d.roleStatus, settings_role_status())
	elseif msg == MSG_SETTINGS_USER_SELECTED then
		local index = call_method(d.usersList, "SelItem") or 0
		local row = ProjectSettingsDialog.user_rows and ProjectSettingsDialog.user_rows[index + 1]
		if row then
			ProjectSettingsDialog.selected_role = row.role or Users.ROLE_ARTIST
			set_text(d.roleStatus, settings_role_status())
		end
	elseif msg == MSG_SETTINGS_SET_USER_ROLE then
		local index = call_method(d.usersList, "SelItem") or 0
		local row = ProjectSettingsDialog.user_rows and ProjectSettingsDialog.user_rows[index + 1]
		if not row or not row.username or row.username == "" then
			alert("Select a user first.")
			return
		end
		local ok, err = Users.set_role(state.project.root, row.username, ProjectSettingsDialog.selected_role)
		alert(ok and "User role updated." or err)
		if ok then refresh_settings_users(d) end
	elseif msg == MSG_SETTINGS_EMPTY_RECYCLE then
		local confirmed = confirm_warning(
			"Empty Flowinator Recycle?",
			"All recycled project files will be permanently deleted.",
			"This action cannot be undone."
		)
		if confirmed then
			Recycle.clear(state.project.root)
			alert("Flowinator Recycle emptied.")
		end
	end
end

function ProjectSettingsDialog:OnOK()
	local d = ProjectSettingsDialog.dialog or self
	ProjectSettingsDialog.result = {
		name = text_value(d.name),
		use_episodes = ProjectSettingsDialog.use_episodes and true or false
	}
end

function ProjectSettingsDialog:OnCancel()
	local d = ProjectSettingsDialog.dialog or self
	local changed = text_value(d.name) ~= (ProjectSettingsDialog.initial_name or "")
		or (ProjectSettingsDialog.use_episodes and true or false) ~= (ProjectSettingsDialog.initial_use_episodes and true or false)
	if changed and confirm_warning("Save project setting changes?", "Your changes will be discarded if you cancel.", "", "OK") then
		ProjectSettingsDialog.result = {
			name = text_value(d.name),
			use_episodes = ProjectSettingsDialog.use_episodes and true or false
		}
	end
end

local TypeDialog = {}

function TypeDialog:new(title, label)
	local d = LM.GUI.SimpleDialog(title or "Add Type", TypeDialog)
	bind_methods(d, TypeDialog)
	TypeDialog.dialog = d
	TypeDialog.result = nil
	local l = d:GetLayout()
	d.name = add_edit(l, label or "Type Name", "", 220)
	return d
end

function TypeDialog:OnOK()
	local d = TypeDialog.dialog or self
	TypeDialog.result = text_value(d.name)
end

local WorkItemDialog = {}

function WorkItemDialog:new(prefix)
	local d = LM.GUI.SimpleDialog("Add Work Item", WorkItemDialog)
	bind_methods(d, WorkItemDialog)
	WorkItemDialog.dialog = d
	WorkItemDialog.result = nil
	local l = d:GetLayout()
	add_label(l, "Scene Name")
	add_dynamic(l, prefix or "", 300)
	d.name = add_edit(l, "Suffix", "", 180)
	return d
end

function WorkItemDialog:OnOK()
	local d = WorkItemDialog.dialog or self
	WorkItemDialog.result = text_value(d.name)
end

local SequenceDialog = {}

local function sequence_work_type_status()
	local selected = {}
	if SequenceDialog.layout_selected then table.insert(selected, "Layout") end
	if SequenceDialog.animation_selected then table.insert(selected, "Animation") end
	if SequenceDialog.fx_selected then table.insert(selected, "FX") end
	return #selected > 0 and ("Selected: " .. table.concat(selected, ", ")) or "Selected: none"
end

function SequenceDialog:new()
	local d = LM.GUI.SimpleDialog("Add Sequence", SequenceDialog)
	bind_methods(d, SequenceDialog)
	SequenceDialog.dialog = d
	SequenceDialog.result = nil
	SequenceDialog.layout_selected = true
	SequenceDialog.animation_selected = false
	SequenceDialog.fx_selected = false
	local l = d:GetLayout()
	d.sequence = add_edit(l, "Sequence", state.selected_sequence or "SQ01", 120)
	d.shot_count = add_edit(l, "Shot Count", "1", 100)
	add_label(l, "Work Type")
	l:PushH()
	add_button(l, "Layout", MSG_SEQUENCE_LAYOUT)
	add_button(l, "Animation", MSG_SEQUENCE_ANIMATION)
	add_button(l, "FX", MSG_SEQUENCE_FX)
	l:Pop()
	d.workTypeStatus = add_dynamic(l, sequence_work_type_status(), 260)
	return d
end

function SequenceDialog:HandleMessage(msg)
	if msg == MSG_SEQUENCE_LAYOUT then SequenceDialog.layout_selected = not SequenceDialog.layout_selected end
	if msg == MSG_SEQUENCE_ANIMATION then SequenceDialog.animation_selected = not SequenceDialog.animation_selected end
	if msg == MSG_SEQUENCE_FX then SequenceDialog.fx_selected = not SequenceDialog.fx_selected end
	set_text((SequenceDialog.dialog or self).workTypeStatus, sequence_work_type_status())
end

function SequenceDialog:OnOK()
	local d = SequenceDialog.dialog or self
	SequenceDialog.result = {
		sequence = text_value(d.sequence),
		shot_count = tonumber(text_value(d.shot_count)) or 0,
		work_types = {}
	}
	if SequenceDialog.layout_selected then table.insert(SequenceDialog.result.work_types, "Layout") end
	if SequenceDialog.animation_selected then table.insert(SequenceDialog.result.work_types, "Animation") end
	if SequenceDialog.fx_selected then table.insert(SequenceDialog.result.work_types, "FX") end
end

local ShotDialog = {}

local function shot_work_type_status()
	local selected = {}
	if ShotDialog.layout_selected then table.insert(selected, "Layout") end
	if ShotDialog.animation_selected then table.insert(selected, "Animation") end
	if ShotDialog.fx_selected then table.insert(selected, "FX") end
	if #selected == 0 then return "Selected: none" end
	return "Selected: " .. table.concat(selected, ", ")
end

function ShotDialog:new()
	local d = LM.GUI.SimpleDialog("Create Shot", ShotDialog)
	bind_methods(d, ShotDialog)
	ShotDialog.dialog = d
	ShotDialog.result = nil
	ShotDialog.layout_selected = true
	ShotDialog.animation_selected = true
	ShotDialog.fx_selected = false
	local l = d:GetLayout()
	add_label(l, "Episode: " .. episode_label(selected_episode_value()))
	add_label(l, "Sequence: " .. (state.selected_sequence or ""))
	d.name = add_edit(l, "Shot Name", "", 220)
	add_label(l, "Work Types")
	l:PushH()
	add_button(l, "Layout", MSG_SHOT_LAYOUT_TOGGLE)
	add_button(l, "Animation", MSG_SHOT_ANIMATION_TOGGLE)
	add_button(l, "FX", MSG_SHOT_FX_TOGGLE)
	l:Pop()
	d.workTypeStatus = add_dynamic(l, shot_work_type_status(), 260)
	d.custom_work_type = add_edit(l, "Custom Work Type", "", 180)
	d.commit = add_edit(l, "Description / Notes", "", 300)
	return d
end

function ShotDialog:HandleMessage(msg)
	local d = ShotDialog.dialog or self
	if msg == MSG_SHOT_LAYOUT_TOGGLE then
		ShotDialog.layout_selected = not ShotDialog.layout_selected
	elseif msg == MSG_SHOT_ANIMATION_TOGGLE then
		ShotDialog.animation_selected = not ShotDialog.animation_selected
	elseif msg == MSG_SHOT_FX_TOGGLE then
		ShotDialog.fx_selected = not ShotDialog.fx_selected
	else
		return
	end
	set_text(d.workTypeStatus, shot_work_type_status())
end

function ShotDialog:OnOK()
	local d = ShotDialog.dialog or self
	ShotDialog.result = {
		episode = selected_episode_value(),
		sequence = state.selected_sequence or "",
		name = text_value(d.name),
		commit = text_value(d.commit),
		work_types = {}
	}
	if ShotDialog.layout_selected then table.insert(ShotDialog.result.work_types, "Layout") end
	if ShotDialog.animation_selected then table.insert(ShotDialog.result.work_types, "Animation") end
	if ShotDialog.fx_selected then table.insert(ShotDialog.result.work_types, "FX") end
	for _, custom in ipairs(split_csv(text_value(d.custom_work_type))) do
		table.insert(ShotDialog.result.work_types, custom)
	end
end

local PreviewDialog = {}

function PreviewDialog:new(resource_path, info_text)
	local d = LM.GUI.SimpleDialog("Preview Image", PreviewDialog)
	bind_methods(d, PreviewDialog)
	PreviewDialog.dialog = d
	local l = d:GetLayout()
	add_label(l, "PREVIEW IMAGE")
	d.previewImage = add_image_button(l, resource_path or EMPTY_PREVIEW_RESOURCE, "Preview", 0)
	add_button(l, "Set New Preview", MSG_PREVIEW_SET_NEW)
	d.info = add_dynamic(l, "", 220)
	return d
end

function PreviewDialog:HandleMessage(msg)
	if msg == MSG_PREVIEW_SET_NEW then
		local d = PreviewDialog.dialog or self
		local flowinator = UI.dialog
		if flowinator and type(flowinator.set_preview) == "function" then
			flowinator:set_preview()
			set_text(d.info, "Preview updated.")
		end
	end
end

local AssetDialog = {}

local function asset_work_type_status()
	local selected = {}
	if AssetDialog.draw_selected then table.insert(selected, "Draw") end
	if AssetDialog.rig_selected then table.insert(selected, "Rig") end
	if AssetDialog.fx_selected then table.insert(selected, "FX") end
	if #selected == 0 then return "Selected: none" end
	return "Selected: " .. table.concat(selected, ", ")
end

function AssetDialog:new()
	local d = LM.GUI.SimpleDialog("Create Asset", AssetDialog)
	bind_methods(d, AssetDialog)
	AssetDialog.dialog = d
	AssetDialog.result = nil

	local types = {"Character", "Prop", "Environment"}
	if state.project and state.project.root then
		local seen = {Character = true, Prop = true, Environment = true}
		local custom = Assets.load_custom_types(state.project.root)
		for _, type_name in ipairs(custom.types or {}) do
			if type_name and type_name ~= "" and not seen[type_name] then
				seen[type_name] = true
				table.insert(types, type_name)
			end
		end
		for _, asset in ipairs(state.assets or {}) do
			if asset.type and asset.type ~= "" and not seen[asset.type] then
				seen[asset.type] = true
				table.insert(types, asset.type)
			end
		end
	end
	AssetDialog.available_types = types
	AssetDialog.asset_type = types[1] or "Character"
	AssetDialog.draw_selected = true
	AssetDialog.rig_selected = true
	AssetDialog.fx_selected = false

	local l = d:GetLayout()
	d.name = add_edit(l, "Asset Name", "", 260)
	add_label(l, "Type")
	l:PushH()
	for i, type_name in ipairs(types) do
		add_button(l, type_name, MSG_DYNAMIC_TYPE_BASE + i)
	end
	l:Pop()
	d.type_label = add_dynamic(l, "Selected Type: " .. AssetDialog.asset_type, 260)
	add_label(l, "Work Types")
	l:PushH()
	add_button(l, "Draw", MSG_ASSET_DRAW_TOGGLE)
	add_button(l, "Rig", MSG_ASSET_RIG_TOGGLE)
	add_button(l, "FX", MSG_ASSET_FX_TOGGLE)
	l:Pop()
	d.workTypeStatus = add_dynamic(l, asset_work_type_status(), 260)
	d.commit = add_edit(l, "Commit / Details", "", 300)
	return d
end

function AssetDialog:HandleMessage(msg)
	local d = AssetDialog.dialog or self
	if msg >= MSG_DYNAMIC_TYPE_BASE and msg < MSG_DYNAMIC_TYPE_BASE + 100 then
		local index = msg - MSG_DYNAMIC_TYPE_BASE
		local selected = AssetDialog.available_types[index]
		if selected then
			AssetDialog.asset_type = selected
			if d.type_label then
				set_text(d.type_label, "Selected Type: " .. selected)
			end
		end
	elseif msg == MSG_ASSET_DRAW_TOGGLE then
		AssetDialog.draw_selected = not AssetDialog.draw_selected
		set_text(d.workTypeStatus, asset_work_type_status())
	elseif msg == MSG_ASSET_RIG_TOGGLE then
		AssetDialog.rig_selected = not AssetDialog.rig_selected
		set_text(d.workTypeStatus, asset_work_type_status())
	elseif msg == MSG_ASSET_FX_TOGGLE then
		AssetDialog.fx_selected = not AssetDialog.fx_selected
		set_text(d.workTypeStatus, asset_work_type_status())
	end
end

function AssetDialog:OnOK()
	local d = AssetDialog.dialog or self
	AssetDialog.result = {
		name = text_value(d.name),
		asset_type = AssetDialog.asset_type or "Character",
		commit = text_value(d.commit),
		work_types = {}
	}
	if AssetDialog.draw_selected then table.insert(AssetDialog.result.work_types, "Draw") end
	if AssetDialog.rig_selected then table.insert(AssetDialog.result.work_types, "Rig") end
	if AssetDialog.fx_selected then table.insert(AssetDialog.result.work_types, "FX") end
end

local CommitDialog = {}

function CommitDialog:new(title)
	local d = LM.GUI.SimpleDialog(title or "Commit", CommitDialog)
	bind_methods(d, CommitDialog)
	CommitDialog.dialog = d
	CommitDialog.result = nil
	local l = d:GetLayout()
	d.commit = add_edit(l, "Commit / Details", "", 360)
	return d
end

function CommitDialog:OnOK()
	local d = CommitDialog.dialog or self
	CommitDialog.result = text_value(d.commit)
end

local function ask_commit(title)
	local d = CommitDialog:new(title)
	CommitDialog.result = nil
	d:DoModal()
	if CommitDialog.result ~= nil then
		return CommitDialog.result
	end
	return text_value(d.commit)
end

local FlowinatorDialog = {}

function FlowinatorDialog:new(moho)
	local d = LM.GUI.SimpleDialog("Flowinator v0.9.2", FlowinatorDialog)
	bind_methods(d, FlowinatorDialog)
	FlowinatorDialog.dialog = d
	d.moho = moho
	d:load_last_project()
	local l = d:GetLayout()

	l:PushH()
	l:PushV(LM.GUI.ALIGN_TOP)
	add_banner(l)
	l:Pop()
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "PROJECT")
	l:PushH()
	add_button(l, "New Project", MSG_NEW_PROJECT)
	add_button(l, "Select Project", MSG_OPEN_PROJECT)
	l:Pop()
	l:Pop()

	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "CURRENT PROJECT")
	l:PushH()
	l:PushV(LM.GUI.ALIGN_TOP)
	d.projectStatus = add_dynamic(l, "No project selected", CURRENT_PROJECT_TEXT_WIDTH)
	d.projectNotesStatus = add_dynamic(l, "", CURRENT_PROJECT_TEXT_WIDTH)
	d.projectPathStatus = add_dynamic(l, "", CURRENT_PROJECT_TEXT_WIDTH)
	l:Pop()
	l:PushV(LM.GUI.ALIGN_TOP)
	local settingsBtn = LM.GUI.Button("Project Settings", MSG_PROJECT_SETTINGS)
	l:AddChild(settingsBtn, LM.GUI.ALIGN_RIGHT)
	add_button(l, "Refresh", MSG_REFRESH)
	l:Pop()
	l:Pop()
	l:Pop()

	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "USER")
	d.userStatus = add_dynamic(l, "User: not logged in", 180)
	l:PushH()
	add_button(l, "Login", MSG_LOGIN)
	add_button(l, "Log Out", MSG_LOGOUT)
	l:Pop()
	l:Pop()
	l:Pop()

	l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)

	l:PushH()

	l:PushV(LM.GUI.ALIGN_TOP)
	d.typeTitle = add_dynamic(l, "TYPE", BROWSER_LIST_WIDTH)
	l:PushH()
	d.assetsModeButton = add_button(l, "Assets", MSG_MODE_ASSETS)
	d.shotsModeButton = add_button(l, "Shots", MSG_MODE_SHOTS)
	l:Pop()
	d.modeStatus = add_dynamic(l, "Mode: Assets", BROWSER_LIST_WIDTH)
	d.typeList = LM.GUI.TextList(BROWSER_LIST_WIDTH, 300, MSG_TYPE_SELECTED)
	l:AddChild(d.typeList, LM.GUI.ALIGN_FILL)
	l:PushH()
	d.addTypeButton = add_small_button(l, "Add", MSG_ADD_TYPE)
	add_button(l, "Delete", MSG_DELETE_TYPE)
	l:Pop()
	l:Pop()

	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	d.nameTitle = add_dynamic(l, "NAME", BROWSER_LIST_WIDTH)
	l:PushH()
	d.createItemButton = add_small_button(l, "Add", MSG_CREATE_ASSET)
	add_small_button(l, "Delete", MSG_DELETE_ITEM)
	l:Pop()
	d.assetList = LM.GUI.TextList(BROWSER_LIST_WIDTH, 300, MSG_ASSET_SELECTED)
	l:AddChild(d.assetList, LM.GUI.ALIGN_FILL)
	l:Pop()

	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	d.variantTitle = add_dynamic(l, "VARIANT", BROWSER_LIST_WIDTH)
	l:PushH()
	add_small_button(l, "Add", MSG_ADD_VARIANT)
	add_small_button(l, "Delete", MSG_DELETE_VARIANT)
	l:Pop()
	d.variantList = LM.GUI.TextList(BROWSER_LIST_WIDTH, 300, MSG_VARIANT_SELECTED)
	l:AddChild(d.variantList, LM.GUI.ALIGN_FILL)
	l:Pop()

	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "WORK TYPE")
	l:PushH()
	add_small_button(l, "Add", MSG_ADD_WORK_TYPE)
	add_small_button(l, "Delete", MSG_DELETE_WORK_TYPE)
	l:Pop()
	d.workTypeList = LM.GUI.TextList(BROWSER_LIST_WIDTH, 300, MSG_WORK_TYPE_SELECTED)
	l:AddChild(d.workTypeList, LM.GUI.ALIGN_FILL)
	l:Pop()
	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)
	l:PushV(LM.GUI.ALIGN_TOP)
	add_label(l, "WORK ITEM")
	l:PushH()
	add_small_button(l, "Add", MSG_ADD_WORK_ITEM)
	add_small_button(l, "Delete", MSG_DELETE_WORK_ITEM)
	l:Pop()
	d.workItemList = LM.GUI.TextList(BROWSER_LIST_WIDTH, 300, MSG_WORK_ITEM_SELECTED)
	l:AddChild(d.workItemList, LM.GUI.ALIGN_FILL)
	l:Pop()

	l:AddChild(LM.GUI.Divider(true), LM.GUI.ALIGN_FILL)

	l:PushV(LM.GUI.ALIGN_TOP)
	d.detailsTitle = add_dynamic(l, "Asset Details", 250)
	d.assetName = add_dynamic(l, "No asset selected", 250)
	d.assetMeta = add_dynamic(l, "", 250)
	d.versionInfo = add_dynamic(l, "Selected: none", 250)
	d.previewInfo = add_dynamic(l, "Preview: none", 240)
	l:PushH()
	add_button(l, "Show Preview", MSG_SHOW_PREVIEW)
	add_button(l, "Open Folder", MSG_OPEN_FOLDER)
	l:Pop()
	l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)
	add_label(l, "WORK VERSIONS")
	d.workVersionHeader = add_dynamic(l, "Version          Author                  Commit", VERSION_LIST_WIDTH)
	d.workVersionList = LM.GUI.TextList(VERSION_LIST_WIDTH, 95, MSG_WORK_VERSION_SELECTED)
	l:AddChild(d.workVersionList, LM.GUI.ALIGN_FILL)
	l:PushH()
	add_button(l, "Load", MSG_LOAD_VERSION)
	add_button(l, "Delete", MSG_DELETE_WORK_VERSION)
	l:Pop()
	add_label(l, "PUBLISH VERSIONS")
	d.publishVersionHeader = add_dynamic(l, "Version          Author                  Commit                            Live", VERSION_LIST_WIDTH)
	d.publishVersionList = LM.GUI.TextList(VERSION_LIST_WIDTH, 75, MSG_PUBLISH_VERSION_SELECTED)
	l:AddChild(d.publishVersionList, LM.GUI.ALIGN_FILL)
	l:PushH()
	add_button(l, "Import Live", MSG_IMPORT_LIVE)
	add_button(l, "Reference Live", MSG_REFERENCE_LIVE)
	l:Pop()
	-- Keep the versioning actions visually separate from browsing controls.
	l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)
	l:PushH()
	add_button(l, "Create Workfile", MSG_CREATE_WORKFILE)
	add_button(l, "Save New Version", MSG_SAVE_VERSION)
	add_button(l, "Publish", MSG_PUBLISH_VERSION)
	l:Pop()
	l:AddChild(LM.GUI.Divider(false), LM.GUI.ALIGN_FILL)
	l:Pop()

	l:Pop()
	d:refresh()
	return d
end

function FlowinatorDialog:HandleMessage(msg)
	local d = FlowinatorDialog.dialog or self
	if msg == MSG_NEW_PROJECT then
		d:new_project()
	elseif msg == MSG_OPEN_PROJECT then
		d:open_project()
	elseif msg == MSG_ADD_USER then
		d:add_user()
	elseif msg == MSG_LOGIN then
		d:login()
	elseif msg == MSG_LOGOUT then
		d:logout()
	elseif msg == MSG_PROJECT_SETTINGS then
		d:project_settings()
	elseif msg == MSG_TYPE_SELECTED then
		if state.refreshing_lists then return end
		d:select_type_from_list()
	elseif msg == MSG_ADD_TYPE then
		d:add_type()
	elseif msg == MSG_DELETE_TYPE then
		d:delete_type()
	elseif msg == MSG_MODE_ASSETS then
		d:set_browser_mode("assets")
	elseif msg == MSG_MODE_SHOTS then
		d:set_browser_mode("shots")
	elseif msg == MSG_REFRESH then
		d:reload_assets()
		d:refresh()
	elseif msg == MSG_ASSET_SELECTED then
		if state.refreshing_lists then return end
		d:select_asset_from_list()
	elseif msg == MSG_VARIANT_SELECTED then
		if state.refreshing_lists then return end
		d:select_variant_from_list()
	elseif msg == MSG_WORK_TYPE_SELECTED then
		if state.refreshing_lists then return end
		d:select_work_type_from_list()
	elseif msg == MSG_WORK_ITEM_SELECTED then
		if state.refreshing_lists then return end
		d:select_work_item_from_list()
	elseif msg == MSG_WORK_VERSION_SELECTED then
		if state.refreshing_lists then return end
		d:select_work_version_from_list()
	elseif msg == MSG_PUBLISH_VERSION_SELECTED then
		if state.refreshing_lists then return end
		d:select_publish_version_from_list()
	elseif msg == MSG_CREATE_ASSET then
		d:create_asset()
	elseif msg == MSG_ADD_VARIANT then
		d:add_variant()
	elseif msg == MSG_ADD_WORK_TYPE then
		d:add_work_type()
	elseif msg == MSG_ADD_WORK_ITEM then
		d:add_work_item()
	elseif msg == MSG_DELETE_ITEM then
		d:delete_item()
	elseif msg == MSG_DELETE_VARIANT then
		d:delete_variant()
	elseif msg == MSG_DELETE_WORK_TYPE then
		d:delete_work_type()
	elseif msg == MSG_DELETE_WORK_ITEM then
		d:delete_work_item()
	elseif msg == MSG_SHOW_PREVIEW then
		d:show_preview()
	elseif msg == MSG_REFERENCE_LIVE then
		d:reference_live_publish()
	elseif msg == MSG_IMPORT_LIVE then
		d:import_live_publish()
	elseif msg == MSG_LOAD_VERSION then
		d:load_version()
	elseif msg == MSG_DELETE_WORK_VERSION then
		d:delete_work_version()
	elseif msg == MSG_CREATE_WORKFILE then
		d:create_workfile()
	elseif msg == MSG_SAVE_VERSION then
		d:save_version()
	elseif msg == MSG_PUBLISH_VERSION then
		d:publish_version()
	elseif msg == MSG_OPEN_FOLDER then
		d:open_folder()
	end
end

function FlowinatorDialog:UpdateWidgets()
	-- Keep modeless UI responsive; refresh only after explicit Flowinator actions.
end

function FlowinatorDialog:OnClose()
	UI.dialog = nil
end

function FlowinatorDialog:OnOK()
	-- Moho routes the modeless window's X button through OnOK.
	UI.dialog = nil
end

function FlowinatorDialog:OnCancel()
	UI.dialog = nil
end

function FlowinatorDialog:require_project()
	if not state.project or not state.project.root then
		alert("Open or create a project first.")
		return false
	end
	return true
end

function FlowinatorDialog:current_user()
	if not self:require_project() then return nil end
	local user = state.current_user
	if not user or user == "" then
		user = Users.current(state.project.root)
		state.current_user = user
	end
	if not user or user == "" then
		alert("Login with a project user first.")
		return nil
	end
	return user
end

function FlowinatorDialog:require_project_admin()
	if not self:require_project() then return nil end
	-- A new project has no session yet; its first account is always an admin.
	local user_data = Users.load(state.project.root)
	if #(user_data.users or {}) == 0 then
		return "__first_admin__"
	end
	local user = self:current_user()
	if not user then return nil end
	if not Users.can_manage_project(state.project.root, user) then
		alert("Project Admin access is required.")
		return nil
	end
	return user
end

function FlowinatorDialog:reload_assets()
	state.assets = {}
	state.assets_by_id = {}
	state.shots = {}
	state.shots_by_id = {}
	if not state.project or not state.project.root then
		return
	end
	state.assets = Assets.list(state.project.root) or {}
	for _, asset in ipairs(state.assets) do
		if asset.id then
			state.assets_by_id[asset.id] = asset
		end
	end
	state.shots = Shots.list(state.project.root) or {}
	for _, shot in ipairs(state.shots) do
		if shot.id then
			shot.kind = "shot"
			shot.type = "Shot"
			state.shots_by_id[shot.id] = shot
		end
	end
end

function FlowinatorDialog:load_last_project()
	if state.project then
		return
	end
	local project = Project.open_last()
	if project then
		state.project = project
		state.current_user = Users.current(project.root)
		state.selected_type = nil
		self:reset_selection()
		self:reload_assets()
	end
end

function FlowinatorDialog:activate_project(root, project)
	project = project or Project.open(root)
	if not project then
		alert("Project metadata was not found.")
		return false
	end
	project.root = root
	state.project = project
	Project.remember(root)
	state.current_user = Users.current(root)
	state.selected_type = nil
	self:reset_selection()
	self:reload_assets()
	self:refresh()
	return true
end

function FlowinatorDialog:ensure_default_selection()
	if not state.project then
		return
	end
	if state.browser_mode == "shots" then
		if (not state.selected_shot_id or not state.shots_by_id[state.selected_shot_id]) and #state.shots > 0 then
			state.selected_shot_id = state.shots[1].id
			state.selected_work_branch_id = nil
			state.selected_work_version = nil
			state.selected_publish_version = nil
			state.selected_version_kind = "work"
		end
	else
		if (not state.selected_asset_id or not state.assets_by_id[state.selected_asset_id]) and #state.assets > 0 then
			state.selected_asset_id = state.assets[1].id
			state.selected_variant_id = nil
			state.selected_work_branch_id = nil
			state.selected_work_version = nil
			state.selected_publish_version = nil
			state.selected_version_kind = "work"
		end
	end
	local asset = self:selected_asset()
	if asset then
		local workfiles = asset.workfiles or {}
		if #workfiles > 0 and not state.selected_work_version then
			state.selected_work_version = workfiles[#workfiles].version
		end
		local publishes = asset.publishes or {}
		if #publishes > 0 and not state.selected_publish_version then
			state.selected_publish_version = publishes[#publishes].version
		end
	end
end

function FlowinatorDialog:reset_version_selection()
	state.selected_work_version = nil
	state.selected_publish_version = nil
	state.selected_version_kind = "work"
end

function FlowinatorDialog:reset_selection()
	state.selected_asset_id = nil
	state.selected_shot_id = nil
	state.selected_variant_id = nil
	state.selected_work_branch_id = nil
	state.selected_work_type = nil
	state.selected_episode = nil
	state.selected_sequence = nil
	self:reset_version_selection()
end

function FlowinatorDialog:replace_asset_in_state(asset)
	if not asset or not asset.id then return end
	for i, item in ipairs(state.assets or {}) do
		if item.id == asset.id then
			state.assets[i] = asset
			break
		end
	end
	state.assets_by_id[asset.id] = asset
end

function FlowinatorDialog:replace_shot_in_state(shot)
	if not shot or not shot.id then return end
	shot.kind = "shot"
	shot.type = "Shot"
	for i, item in ipairs(state.shots or {}) do
		if item.id == shot.id then
			state.shots[i] = shot
			break
		end
	end
	state.shots_by_id[shot.id] = shot
end

function FlowinatorDialog:replace_current_base_item()
	local item = self:selected_asset()
	if not item then return end
	if item.kind == "shot" then
		local shot = Shots.sync_branch_item(item)
		self:replace_shot_in_state(shot)
	else
		local asset = Assets.sync_branch_item(item)
		self:replace_asset_in_state(asset)
	end
end

function FlowinatorDialog:set_browser_mode(mode)
	if mode ~= "shots" then
		mode = "assets"
	end
	if state.browser_mode == mode then
		return
	end
	state.browser_mode = mode
	self:reset_selection()
	self:refresh()
end

function FlowinatorDialog:refresh_mode_buttons()
	set_text(self.modeStatus, state.browser_mode == "shots" and "Mode: Shots" or "Mode: Assets")
	set_text(self.typeTitle, state.browser_mode == "shots" and "EPISODE" or "TYPE")
	set_text(self.nameTitle, state.browser_mode == "shots" and "SEQUENCE" or "NAME")
	set_text(self.variantTitle, state.browser_mode == "shots" and "SHOT" or "VARIANT")
end

function FlowinatorDialog:current_item_label()
	return state.browser_mode == "shots" and "shot" or "asset"
end

function FlowinatorDialog:current_item()
	if state.browser_mode == "shots" then
		if not state.project or not state.selected_shot_id then return nil end
		local shot = state.shots_by_id[state.selected_shot_id]
		if not state.selected_work_branch_id then return nil end
		local branch = shot and Shots.branch(shot, state.selected_work_branch_id)
		return branch and Shots.branch_item(shot, branch) or nil
	end
	if not state.project or not state.selected_asset_id then return nil end
	local asset = state.assets_by_id[state.selected_asset_id]
	local variant = asset and Assets.variant(asset, state.selected_variant_id)
	if not state.selected_work_branch_id then return nil end
	local branch = variant and Assets.branch(variant, state.selected_work_branch_id)
	return branch and Assets.branch_item(asset, variant, branch) or nil
end

function FlowinatorDialog:base_asset()
	if not state.project or not state.selected_asset_id then return nil end
	return state.assets_by_id[state.selected_asset_id]
end

function FlowinatorDialog:base_shot()
	if not state.project or not state.selected_shot_id then return nil end
	return state.shots_by_id[state.selected_shot_id]
end

function FlowinatorDialog:selected_variant()
	local asset = self:base_asset()
	if not asset then return nil end
	return Assets.variant(asset, state.selected_variant_id)
end

function FlowinatorDialog:selected_branch()
	if state.browser_mode == "shots" then
		local shot = self:base_shot()
		if not state.selected_work_branch_id then return nil end
		return shot and Shots.branch(shot, state.selected_work_branch_id) or nil
	end
	local variant = self:selected_variant()
	if not state.selected_work_branch_id then return nil end
	return variant and Assets.branch(variant, state.selected_work_branch_id) or nil
end

function FlowinatorDialog:current_item_folder(item)
	if state.browser_mode == "shots" then
		return Shots.shot_folder(state.project.root, item)
	end
	return Assets.asset_folder(state.project.root, item)
end

function FlowinatorDialog:current_detail_title()
	return state.browser_mode == "shots" and "Shot Details" or "Asset Details"
end

function FlowinatorDialog:current_empty_title()
	return state.browser_mode == "shots" and "No shot selected" or "No asset selected"
end

function FlowinatorDialog:current_select_message()
	return state.browser_mode == "shots" and "Select a shot first." or "Select an asset first."
end

function FlowinatorDialog:preferred_asset_type(types)
	if state.selected_type then
		for _, type_name in ipairs(types) do
			if type_name == state.selected_type then
				return state.selected_type
			end
		end
	end
	for _, asset in ipairs(state.assets or {}) do
		for _, type_name in ipairs(types) do
			if asset.type == type_name then
				return type_name
			end
		end
	end
	return types[1]
end

-- compatibility name used by the existing workflow methods
function FlowinatorDialog:selected_asset()
	return self:current_item()
end

function FlowinatorDialog:current_preview_path()
	local asset = self:selected_asset()
	if not asset then
		return nil, nil, nil
	end
	local entry, kind = self:selected_version_entry()
	local preview_path = entry and entry.preview_path or ""
	if preview_path == "" then
		preview_path = asset.preview_path or ""
	end
	local resolved_path = resolve_preview_path(preview_path)
	if entry and entry.preview_path and entry.preview_path ~= "" then
		return resolved_path, entry, kind
	end
	return resolved_path, {version = 0, preview_path = resolved_path}, kind
end

function FlowinatorDialog:new_project()
	local d = ProjectDialog:new("create")
	ProjectDialog.result = nil
	d:DoModal()
	local result = ProjectDialog.result or {
		location = text_value(d.location),
		name = text_value(d.name),
		code = text_value(d.code),
		notes = text_value(d.notes)
	}
	local location = result.location
	if location == "" then location = select_folder("Select Project Location") or "" end
	if location == "" or result.name == "" then
		alert("Location and Project Name are required.")
		return
	end
	local project = Project.create(location, result.name, result.code, result.notes)
	self:activate_project(project.root, project)
end

function FlowinatorDialog:open_project()
	local d = ProjectDialog:new("open")
	ProjectDialog.result = nil
	d:DoModal()
	local result = ProjectDialog.result or {root = text_value(d.root)}
	local root = result.root
	if root == "" then root = select_folder("Select Project Root") or "" end
	if root == "" then return end
	self:activate_project(root)
end

function FlowinatorDialog:add_user()
	if not self:require_project_admin() then return end
	local d = UserDialog:new("Add User")
	UserDialog.result = nil
	d:DoModal()
	local result = UserDialog.result or {username = text_value(d.username), password = text_value(d.password)}
	local ok, err = Users.add(state.project.root, result.username, result.password, Users.ROLE_ARTIST)
	alert(ok and "User added." or err)
	self:refresh_status()
end

function FlowinatorDialog:login()
	if not self:require_project() then return end
	local d = UserDialog:new("Login")
	UserDialog.result = nil
	d:DoModal()
	local result = UserDialog.result or {username = text_value(d.username), password = text_value(d.password)}
	local ok, err = Users.login(state.project.root, result.username, result.password)
	if ok then
		state.current_user = result.username
	end
	alert(ok and "Logged in." or err)
	self:refresh_status()
end

function FlowinatorDialog:logout()
	if not self:require_project() then return end
	Users.clear_current(state.project.root)
	state.current_user = nil
	self:refresh_status()
	alert("Logged out.")
end

function FlowinatorDialog:project_settings()
	if not self:require_project_admin() then return end
	local d = ProjectSettingsDialog:new()
	ProjectSettingsDialog.result = nil
	d:DoModal()
	local result = ProjectSettingsDialog.result
	if not result then
		return
	end
	if result.name and result.name ~= "" then
		local ok, updated = Project.update(state.project.root, {name = result.name, use_episodes = result.use_episodes})
		if ok and updated then
			state.project = updated
			self:refresh_status()
			alert("Project settings saved.")
		else
			alert("Could not save project settings.")
		end
	else
		self:refresh_status()
	end
end

function FlowinatorDialog:add_type()
	if not self:require_project_admin() then return end
	if state.browser_mode == "shots" then
		self:create_episode()
		return
	end
	local d = TypeDialog:new()
	TypeDialog.result = nil
	d:DoModal()
	local type_name = TypeDialog.result or text_value(d.name)
	if not type_name or type_name == "" then return end
	local ok, err = Assets.add_type(state.project.root, type_name)
	if not ok then
		alert(err)
		return
	end
	state.selected_type = type_name
	self:refresh_types()
	self:refresh_assets()
end

function FlowinatorDialog:create_episode()
	if not state.project.use_episodes then
		local proceed = confirm_warning(
			"Episode mode is disabled.",
			"You can still add an Episode, but enabling Episode mode is recommended.",
		"Continue adding the Episode?",
		"Add"
		)
		if not proceed then return end
	end
	local d = TypeDialog:new("Add Episode", "Episode Name")
	TypeDialog.result = nil
	d:DoModal()
	local name = TypeDialog.result or text_value(d.name)
	if not name or name == "" then return end
	local ok, err = Shots.add_episode(state.project.root, name)
	if not ok then alert(err) return end
	state.selected_episode = name
	state.selected_sequence = nil
	state.selected_shot_id = nil
	state.selected_work_branch_id = nil
	state.selected_work_type = nil
	self:reset_version_selection()
	self:refresh_types()
	self:refresh_assets()
end

function FlowinatorDialog:create_sequence()
	local user = self:current_user()
	if not user then return end
	if not state.selected_episode or state.selected_episode == "" then
		alert("Select an Episode first.")
		return
	end
	local d = SequenceDialog:new()
	SequenceDialog.result = nil
	d:DoModal()
	local result = SequenceDialog.result
	if not result then return end
	if not result.sequence or result.sequence == "" then
		alert("Sequence is required.")
		return
	end
	local episode = selected_episode_value()
	if not result.work_types or #result.work_types == 0 then
		alert("Select at least one Work Type.")
		return
	end
	local ok, created_or_err = Shots.add_sequence_with_shots(
		state.project.root,
		episode,
		result.sequence,
		result.shot_count,
		result.work_types,
		user
	)
	if not ok then alert(created_or_err) return end
	state.selected_episode = episode_label(episode)
	state.selected_sequence = result.sequence
	state.selected_shot_id = created_or_err[1] and created_or_err[1].id or nil
	state.selected_work_branch_id = nil
	state.selected_work_type = nil
	self:reset_version_selection()
	self:reload_assets()
	self:refresh_types()
	self:refresh_assets()
	self:refresh_variants()
end

function FlowinatorDialog:delete_type()
	if not self:require_project_admin() then return end
	if state.browser_mode == "shots" then
		if not state.selected_episode or state.selected_episode == "" then
			alert("Select an Episode first.")
			return
		end
		if state.selected_episode == "Default" then
			alert("Default is the built-in non-episode group and cannot be deleted.")
			return
		end
		if not self:confirm_recycle("Episode " .. state.selected_episode) then return end
		local ok, removed = Shots.delete_episode(state.project.root, state.selected_episode, Recycle.begin(state.project.root))
		if not ok then
			alert(removed or "Could not move the Episode to Flowinator Recycle.")
			return
		end
		self:reset_selection()
		self:reload_assets()
		self:refresh()
		return
	end
	if not state.selected_type or state.selected_type == "" then
		alert("Select an asset type first.")
		return
	end
	local confirmed = confirm_warning(
		"Delete asset type: " .. state.selected_type .. "?",
		"All assets inside this type will be moved to Flowinator Recycle.",
		"You can permanently clear it later from Project Settings.",
		"Move"
	)
	if not confirmed then return end
	local ok, deleted_count = Assets.delete_type(state.project.root, state.selected_type, Recycle.begin(state.project.root))
	if not ok then
		alert(deleted_count or "Could not delete type.")
		return
	end
	state.selected_type = nil
	state.selected_asset_id = nil
	self:reset_version_selection()
	self:reload_assets()
	self:refresh()
	alert("Moved type assets to Flowinator Recycle: " .. tostring(deleted_count or 0))
end

function FlowinatorDialog:can_delete(owner)
	local user = self:current_user()
	if not user then return false end
	if not Users.can_delete_item(state.project.root, user, {owner = owner or ""}) then
		alert("Artists can only delete their own work.")
		return false
	end
	return true
end

function FlowinatorDialog:confirm_recycle(label)
	return confirm_warning(
		"Move " .. label .. " to Flowinator Recycle?",
		"The project files will be removed from the active pipeline.",
		"You can permanently clear the recycle folder later from Project Settings.",
		"Move"
	)
end

function FlowinatorDialog:delete_item()
	if not self:require_project() then return end
	local session = Recycle.begin(state.project.root)
	local ok, err
	if state.browser_mode == "shots" then
		if not state.selected_shot_id then
			if not state.selected_sequence or not self:require_project_admin() then return end
			if not self:confirm_recycle("Sequence " .. state.selected_sequence) then return end
			ok, err = Shots.delete_sequence(state.project.root, selected_episode_value(), state.selected_sequence, session)
		else
			local shot = self:base_shot()
			if not shot then alert("Select a shot first.") return end
			if not self:can_delete(shot.owner) or not self:confirm_recycle("Shot " .. shot.name) then return end
			ok, err = Shots.delete(state.project.root, shot.id, session)
		end
	else
		local asset = self:base_asset()
		if not asset then alert("Select an asset first.") return end
		if not self:can_delete(asset.owner) or not self:confirm_recycle("Asset " .. asset.name) then return end
		ok, err = Assets.delete(state.project.root, asset.id, session)
	end
	if not ok then alert(err or "Could not move the item to Flowinator Recycle.") return end
	self:reset_selection()
	self:reload_assets()
	self:refresh()
end

function FlowinatorDialog:delete_variant()
	if not self:require_project() then return end
	local session = Recycle.begin(state.project.root)
	local ok, err
	if state.browser_mode == "shots" then
		local shot = self:base_shot()
		if not shot then alert("Select a shot first.") return end
		if not self:can_delete(shot.owner) or not self:confirm_recycle("Shot " .. shot.name) then return end
		ok, err = Shots.delete(state.project.root, shot.id, session)
	else
		local asset, variant = self:base_asset(), self:selected_variant()
		if not asset or not variant then alert("Select a variant first.") return end
		if not self:can_delete(asset.owner) or not self:confirm_recycle("Variant " .. variant.name) then return end
		ok, err = Assets.delete_variant(state.project.root, asset.id, variant.id, session)
	end
	if not ok then alert(err or "Could not move the variant to Flowinator Recycle.") return end
	self:reset_selection()
	self:reload_assets()
	self:refresh()
end

function FlowinatorDialog:delete_work_type()
	if not self:require_project() then return end
	if not state.selected_work_type then alert("Select a Work Type first.") return end
	local item = state.browser_mode == "shots" and self:base_shot() or self:base_asset()
	if not item then alert(self:current_select_message()) return end
	if not self:can_delete(item.owner) or not self:confirm_recycle("Work Type " .. state.selected_work_type) then return end
	local session = Recycle.begin(state.project.root)
	local ok, err
	if state.browser_mode == "shots" then
		ok, err = Shots.delete_work_type(state.project.root, item.id, state.selected_work_type, session)
	else
		local variant = self:selected_variant()
		if not variant then alert("Select a variant first.") return end
		ok, err = Assets.delete_work_type(state.project.root, item.id, variant.id, state.selected_work_type, session)
	end
	if not ok then alert(err or "Could not move the Work Type to Flowinator Recycle.") return end
	state.selected_work_branch_id = nil
	state.selected_work_type = nil
	self:reset_version_selection()
	self:reload_assets()
	self:refresh()
end

function FlowinatorDialog:delete_work_item()
	if not self:require_project() then return end
	local item = state.browser_mode == "shots" and self:base_shot() or self:base_asset()
	local branch = self:selected_branch()
	if not item or not branch then alert("Select a Work Item first.") return end
	if not self:can_delete(item.owner) or not self:confirm_recycle("Work Item " .. (branch.work_item or "Default")) then return end
	local session = Recycle.begin(state.project.root)
	local ok, err
	if state.browser_mode == "shots" then
		ok, err = Shots.delete_work_item(state.project.root, item.id, branch.id, session)
	else
		local variant = self:selected_variant()
		if not variant then alert("Select a variant first.") return end
		ok, err = Assets.delete_work_item(state.project.root, item.id, variant.id, branch.id, session)
	end
	if not ok then alert(err or "Could not move the Work Item to Flowinator Recycle.") return end
	state.selected_work_branch_id = nil
	self:reset_version_selection()
	self:reload_assets()
	self:refresh()
end

function FlowinatorDialog:delete_work_version()
	local asset = self:selected_asset()
	local entry = self:selected_workfile()
	if not asset or not entry then alert("Select a Work Version first.") return end
	if not self:can_delete(entry.author) then return end
	if not self:confirm_recycle("Work Version V" .. string.format("%04d", entry.version or 0)) then return end
	local ok, err = Versions.delete_workfile(state.project.root, asset, entry.version, Recycle.begin(state.project.root))
	if not ok then alert(err or "Could not move the Work Version to Flowinator Recycle.") return end
	state.selected_work_version = nil
	self:replace_current_base_item()
	self:refresh_versions()
end

local function ask_name(title)
	local d = TypeDialog:new(title or "Add", "Name")
	TypeDialog.result = nil
	d:DoModal()
	return TypeDialog.result or text_value(d.name)
end

function FlowinatorDialog:add_variant()
	if not self:require_project() then return end
	if state.browser_mode == "shots" then
		self:create_shot()
		return
	end
	local asset = self:base_asset()
	if not asset then alert("Select an asset first.") return end
	local name = ask_name("Add Variant")
	if not name or name == "" then return end
	local ok, result = Assets.add_variant(state.project.root, asset, name)
	if not ok then alert(result) return end
	state.selected_variant_id = result.id
	state.selected_work_branch_id = nil
	self:replace_asset_in_state(asset)
	self:reset_version_selection()
	self:refresh_variants()
end

function FlowinatorDialog:add_work_type()
	if not self:require_project() then return end
	local name = ask_name("Add Work Type")
	if not name or name == "" then return end
	if state.browser_mode == "shots" then
		local shot = self:base_shot()
		if not shot then alert("Select a shot first.") return end
		local ok, result = Shots.add_work_type(state.project.root, shot, name)
		if not ok then alert(result) return end
		state.selected_work_branch_id = result.id
		self:replace_shot_in_state(shot)
	else
		local asset = self:base_asset()
		local variant = self:selected_variant()
		if not asset or not variant then alert("Select a variant first.") return end
		local ok, result = Assets.add_work_type(state.project.root, asset, variant, name)
		if not ok then alert(result) return end
		state.selected_work_branch_id = result.id
		self:replace_asset_in_state(asset)
	end
	self:reset_version_selection()
	self:refresh_workfiles()
end

function FlowinatorDialog:add_work_item()
	if not self:require_project() then return end
	if state.browser_mode == "shots" then
		local shot = self:base_shot()
		if not shot or not state.selected_work_type then alert("Select a Work Type first.") return end
		local prefix = table.concat({
			shot.safe_name or Paths.safe_name(shot.name),
			Paths.safe_name(state.selected_work_type)
		}, "_") .. "_"
		local d = WorkItemDialog:new(prefix)
		WorkItemDialog.result = nil
		d:DoModal()
		local name = WorkItemDialog.result or text_value(d.name)
		if not name or name == "" then return end
		local ok, result = Shots.add_work_item(state.project.root, shot, state.selected_work_type, name)
		if not ok then alert(result) return end
		state.selected_work_branch_id = result.id
		self:reset_version_selection()
		self:replace_shot_in_state(shot)
		self:refresh_workfiles()
		return
	end
	local asset = self:base_asset()
	local variant = self:selected_variant()
	local branch = self:selected_branch()
	if not asset or not variant or not branch then alert("Select a Work Type first.") return end
	local prefix_parts = {asset.safe_name or Paths.safe_name(asset.name)}
	if variant.name and variant.name ~= "Default" then
		table.insert(prefix_parts, Paths.safe_name(variant.name))
	end
	table.insert(prefix_parts, Paths.safe_name(branch.work_type or "Work"))
	local prefix = table.concat(prefix_parts, "_") .. "_"
	local d = WorkItemDialog:new(prefix)
	WorkItemDialog.result = nil
	d:DoModal()
	local name = WorkItemDialog.result or text_value(d.name)
	if not name or name == "" then return end
	local ok, result = Assets.add_work_item(state.project.root, asset, variant, branch.work_type, name)
	if not ok then alert(result) return end
	state.selected_work_branch_id = result.id
	self:reset_version_selection()
	self:replace_asset_in_state(asset)
	self:refresh_workfiles()
end

function FlowinatorDialog:create_shot()
	local user = self:current_user()
	if not user then return end
	local d = ShotDialog:new()
	ShotDialog.result = nil
	d:DoModal()
	local result = ShotDialog.result
	if not result then return end
	if result.name == "" then
		alert("Shot Name is required.")
		return
	end
	if result.sequence == "" then
		alert("Sequence is required.")
		return
	end
	local shot = Shots.create_cached(state.project.root, state.shots, result.name, user, result.commit, result.work_types, result.episode, result.sequence)
	self:replace_shot_in_state(shot)
	state.selected_shot_id = shot.id
	state.selected_episode = episode_label(result.episode)
	state.selected_sequence = result.sequence
	state.selected_work_branch_id = nil
	self:reset_version_selection()
	self:refresh_assets()
end

function FlowinatorDialog:create_asset()
	if state.browser_mode == "shots" then
		self:create_sequence()
		return
	end
	local user = self:current_user()
	if not user then return end
	local d = AssetDialog:new()
	AssetDialog.result = nil
	d:DoModal()
	local result = AssetDialog.result or {
		name = text_value(d.name),
		asset_type = AssetDialog.asset_type or "Character",
		commit = text_value(d.commit),
		work_types = {"Draw", "Rig"}
	}
	if result.name == "" then
		alert("Asset Name is required.")
		return
	end
	local type_changed = state.selected_type ~= result.asset_type
	local asset = Assets.create_cached(state.project.root, state.assets, result.name, result.asset_type, user, result.commit, result.work_types)
	self:replace_asset_in_state(asset)
	state.selected_type = result.asset_type
	state.selected_asset_id = asset.id
	local default_variant = asset.variants and asset.variants[1] or nil
	local default_branch = default_variant and default_variant.work_branches and default_variant.work_branches[1] or nil
	state.selected_variant_id = default_variant and default_variant.id or nil
	state.selected_work_branch_id = default_branch and default_branch.id or nil
	state.selected_work_type = default_branch and default_branch.work_type or nil
	state.selected_work_version = nil
	state.selected_publish_version = nil
	state.selected_version_kind = "work"
	if type_changed then
		self:refresh_types()
		self:refresh_assets()
		return
	end
	-- The visible Type did not change: append the new asset instead of rebuilding
	-- every browser list, then refresh only its dependent hierarchy.
	table.insert(state.asset_rows, {id = asset.id})
	call_method(self.assetList, "AddItem", asset_table_row(asset.name), false)
	call_method(self.assetList, "SetSelItem", #state.asset_rows - 1, false)
	call_method(self.assetList, "Redraw")
	self:refresh_variants()
end

function FlowinatorDialog:selected_workfile()
	local asset = self:selected_asset()
	if not asset then return nil end
	return Versions.workfile(asset, state.selected_work_version)
end

function FlowinatorDialog:selected_publish()
	local asset = self:selected_asset()
	if not asset then return nil end
	return Versions.publish_entry(asset, state.selected_publish_version)
end

function FlowinatorDialog:selected_version_entry()
	if state.selected_version_kind == "publish" then
		local publish = self:selected_publish()
		if publish then return publish, "publish" end
	end
	return self:selected_workfile(), "work"
end

function FlowinatorDialog:select_type_from_list()
	if not self.typeList or type(self.typeList.SelItem) ~= "function" then return end
	local sel_idx = call_method(self.typeList, "SelItem") or 0
	local row = state.type_rows[sel_idx + 1]
	if row then
		if state.browser_mode == "shots" then
			if row.key ~= state.selected_episode then
				state.selected_episode = row.key
				state.selected_sequence = nil
				state.selected_shot_id = nil
				state.selected_work_branch_id = nil
				state.selected_work_type = nil
				self:reset_version_selection()
			end
			self:refresh_assets()
		else
			if row.type ~= state.selected_type then
				state.selected_type = row.type
				state.selected_asset_id = nil
				state.selected_variant_id = nil
				state.selected_work_branch_id = nil
				state.selected_work_type = nil
				self:reset_version_selection()
			end
			self:refresh_assets()
		end
	end
end

function FlowinatorDialog:select_asset_from_list()
	if not self.assetList or type(self.assetList.SelItem) ~= "function" then return end
	local index = call_method(self.assetList, "SelItem") or 0
	local row = state.asset_rows[index + 1]
	if row then
		if state.browser_mode == "shots" then
			if row.sequence ~= state.selected_sequence then
				state.selected_sequence = row.sequence
				state.selected_shot_id = nil
				state.selected_work_branch_id = nil
				state.selected_work_type = nil
				self:reset_version_selection()
			end
		else
			if row.id ~= state.selected_asset_id then
				state.selected_asset_id = row.id
				state.selected_variant_id = nil
				state.selected_work_branch_id = nil
				state.selected_work_type = nil
				self:reset_version_selection()
			end
		end
		self:refresh_variants()
	end
end

function FlowinatorDialog:select_variant_from_list()
	if not self.variantList or type(self.variantList.SelItem) ~= "function" then return end
	local index = call_method(self.variantList, "SelItem") or 0
	local row = state.variant_rows[index + 1]
	if not row then return end
	if row.info then return end
	if state.browser_mode == "shots" then
		if row.id ~= state.selected_shot_id then
			state.selected_shot_id = row.id
			state.selected_work_branch_id = nil
			state.selected_work_type = nil
			self:reset_version_selection()
		end
	else
		if row.id ~= state.selected_variant_id then
			state.selected_variant_id = row.id
			state.selected_work_branch_id = nil
			state.selected_work_type = nil
			self:reset_version_selection()
		end
	end
	self:refresh_workfiles()
end

function FlowinatorDialog:select_work_type_from_list()
	if not self.workTypeList or type(self.workTypeList.SelItem) ~= "function" then return end
	local index = call_method(self.workTypeList, "SelItem") or 0
	local row = state.work_type_rows[index + 1]
	if not row then return end
	state.selected_work_type = row.work_type
	state.selected_work_branch_id = nil
	self:reset_version_selection()
	self:refresh_work_items()
end

function FlowinatorDialog:select_work_item_from_list()
	if not self.workItemList or type(self.workItemList.SelItem) ~= "function" then return end
	local index = call_method(self.workItemList, "SelItem") or 0
	local row = state.work_item_rows[index + 1]
	if not row or row.id == state.selected_work_branch_id then return end
	state.selected_work_branch_id = row.id
	self:reset_version_selection()
	self:refresh_versions()
end

function FlowinatorDialog:select_work_version_from_list()
	if not self.workVersionList or type(self.workVersionList.SelItem) ~= "function" then return end
	local index = call_method(self.workVersionList, "SelItem") or 0
	local row = state.work_version_rows[index + 1]
	if row then
		if row.virtual then
			state.selected_work_version = nil
			state.selected_version_kind = "work"
			self:refresh_details()
			return
		end
		if row.version == state.selected_work_version and state.selected_version_kind == "work" then return end
		state.selected_work_version = row.version
		state.selected_version_kind = "work"
		self:refresh_details()
	end
end

function FlowinatorDialog:select_publish_version_from_list()
	if not self.publishVersionList or type(self.publishVersionList.SelItem) ~= "function" then return end
	local index = call_method(self.publishVersionList, "SelItem") or 0
	local row = state.publish_version_rows[index + 1]
	if row then
		if row.version == state.selected_publish_version and state.selected_version_kind == "publish" then return end
		state.selected_publish_version = row.version
		state.selected_version_kind = "publish"
		self:refresh_details()
	end
end

function FlowinatorDialog:set_preview()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	local entry, kind = self:selected_version_entry()
	if not entry then
		alert("Create or select a version before setting a preview.")
		return
	end
	local path, err = with_live_moho(self.moho, function(moho)
		return Versions.set_preview(state.project.root, asset, moho, kind, entry.version)
	end)
	if not path then alert(err or "Could not render preview.") return end
	state.preview_cache_token = state.preview_cache_token + 1
	self:replace_current_base_item()
	alert("Preview updated.")
	self:refresh_versions()
end

function FlowinatorDialog:show_preview()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	local preview_path, entry, kind = self:current_preview_path()
	if not preview_path or preview_path == "" then
		local d = PreviewDialog:new(EMPTY_PREVIEW_RESOURCE, "")
		d:DoModal()
		return
	end
	local preview_entry = entry or {version = 0, preview_path = preview_path}
	local resource_path = preview_cache_path(asset, preview_entry, kind or "work", false, state.preview_cache_token)
	local d = PreviewDialog:new(resource_path or EMPTY_PREVIEW_RESOURCE, "")
	d:DoModal()
end

function FlowinatorDialog:import_publish()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	if Versions.latest_publish_version(asset) == 0 then
		alert("This asset has not been published.")
		return
	end
	local ok, err = with_live_moho(self.moho, function(moho)
		return Versions.import_publish(asset, state.selected_publish_version, moho, state.project.root)
	end)
	if not ok then
		alert(err or "Could not import the selected publish.")
	end
end

function FlowinatorDialog:import_live_publish()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	local live = Versions.live_publish_entry(asset)
	if not live or not live.path or live.path == "" then
		alert("This asset has no Live Publish.")
		return
	end
	local ok, err = with_live_moho(self.moho, function(moho)
		return Versions.import_live_publish(asset, moho, state.project.root)
	end)
	if not ok then
		alert(err or "Could not import Live Publish.")
	end
end

function FlowinatorDialog:reference_live_publish()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	local live = Versions.live_publish_entry(asset)
	if not live or not live.path or live.path == "" then
		alert("This asset has no Live Publish.")
		return
	end
	local ok, err = with_live_moho(self.moho, function(moho)
		return Versions.reference_live_publish(asset, moho, state.project.root)
	end)
	if not ok then
		alert(err or "Could not reference Live Publish.")
	end
end

function FlowinatorDialog:load_version()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	local ok = Versions.load_workfile(asset, state.selected_work_version, state.project.root)
	if not ok then
		alert("Could not load the selected version.")
	end
end

function FlowinatorDialog:create_workfile()
	local user = self:current_user()
	local asset = self:selected_asset()
	if not user or not asset then alert("Select an asset first.") return end
	if #(asset.workfiles or {}) > 0 then
		local previous_branch_id = state.selected_work_branch_id
		self:add_work_item()
		if state.selected_work_branch_id == previous_branch_id then
			return
		end
		asset = self:selected_asset()
		if not asset then return end
	end
	local commit = ask_commit("Create Workfile")
	local path, err = with_live_moho(self.moho, function(moho)
		return Versions.create_workfile(state.project.root, asset, moho, user, commit)
	end)
	if not path then alert(err) return end
	state.selected_version_kind = "work"
	state.selected_work_version = nil
	self:replace_current_base_item()
	self:refresh_versions()
end

function FlowinatorDialog:save_version()
	local user = self:current_user()
	local asset = self:selected_asset()
	if not user or not asset then alert("Select an asset first.") return end
	local commit = ask_commit("Save New Version")
	local path, err = with_live_moho(self.moho, function(moho)
		return Versions.save_new(state.project.root, asset, moho, user, commit)
	end)
	if not path then alert(err) return end
	state.selected_version_kind = "work"
	state.selected_work_version = nil
	self:replace_current_base_item()
	self:refresh_versions()
end

function FlowinatorDialog:publish_version()
	local user = self:current_user()
	local asset = self:selected_asset()
	if not user or not asset then alert("Select an asset first.") return end
	local commit = ask_commit("Publish")
	local path, err = with_live_moho(self.moho, function(moho)
		return Versions.publish(state.project.root, asset, moho, user, commit)
	end)
	if not path then alert(err) return end
	state.selected_version_kind = "publish"
	state.selected_publish_version = nil
	self:replace_current_base_item()
	self:refresh_versions()
end

function FlowinatorDialog:open_folder()
	local asset = self:selected_asset()
	if not asset then alert("Select an asset first.") return end
	Paths.open_folder(self:current_item_folder(asset))
end

function FlowinatorDialog:refresh_status()
	if state.project then
		local code = state.project.code or ""
		local name = state.project.name or "Untitled"
		set_text(self.projectStatus, code ~= "" and (name .. " [" .. code .. "]") or name)
		set_text(self.projectNotesStatus, state.project.notes and state.project.notes ~= "" and ("Notes: " .. state.project.notes) or "")
		set_text(self.projectPathStatus, state.project.root or "")
		local user = state.current_user or Users.current(state.project.root)
		if user and user ~= "" then
			local role = Users.role(state.project.root, user)
			set_text(self.userStatus, "User: " .. user .. " (" .. Users.role_label(role) .. ")")
		else
			set_text(self.userStatus, "User: not logged in")
		end
	else
		set_text(self.projectStatus, "No project selected")
		set_text(self.projectNotesStatus, "")
		set_text(self.projectPathStatus, "")
		set_text(self.userStatus, "User: not logged in")
	end
end

function FlowinatorDialog:refresh_types()
	local was_refreshing = state.refreshing_lists
	state.refreshing_lists = true
	clear_text_list(self.typeList)
	state.type_rows = {}
	if not state.project then
		call_method(self.typeList, "Redraw")
		state.refreshing_lists = was_refreshing
		return
	end
	local selected_index = 0
	local selected_visible = false
	if state.browser_mode == "shots" then
		local seen = {Default = true}
		table.insert(state.type_rows, {key = "Default"})
		call_method(self.typeList, "AddItem", "Default", false)
		if state.selected_episode == "Default" then
			selected_index = 0
			selected_visible = true
		end
		for _, seq in ipairs(Shots.sequences(state.project.root, true)) do
			local key = episode_label(seq.episode)
			if key ~= "" and not seen[key] then
				seen[key] = true
				table.insert(state.type_rows, {key = key})
				call_method(self.typeList, "AddItem", key, false)
				if key == state.selected_episode then
					selected_index = #state.type_rows - 1
					selected_visible = true
				end
			end
		end
	else
		local types = Assets.types(state.project.root)
		for _, type_name in ipairs(types) do
			table.insert(state.type_rows, {type = type_name})
			call_method(self.typeList, "AddItem", type_name, false)
			if type_name == state.selected_type then
				selected_index = #state.type_rows - 1
				selected_visible = true
			end
		end
	end
	if #state.type_rows > 0 and selected_visible then
		call_method(self.typeList, "SetSelItem", selected_index, false)
	end
	call_method(self.typeList, "Redraw")
	state.refreshing_lists = was_refreshing
end

function FlowinatorDialog:refresh_assets()
	local was_refreshing = state.refreshing_lists
	state.refreshing_lists = true
	clear_text_list(self.assetList)
	state.asset_rows = {}
	clear_text_list(self.variantList)
	state.variant_rows = {}
	clear_text_list(self.workTypeList)
	state.work_type_rows = {}
	clear_text_list(self.workItemList)
	state.work_item_rows = {}
	if not state.project then
		call_method(self.assetList, "Redraw")
		call_method(self.variantList, "Redraw")
		call_method(self.workTypeList, "Redraw")
		call_method(self.workItemList, "Redraw")
		self:refresh_versions()
		state.refreshing_lists = was_refreshing
		return
	end
	if state.browser_mode ~= "shots" and (not state.selected_type or state.selected_type == "") then
		call_method(self.assetList, "Redraw")
		call_method(self.variantList, "Redraw")
		call_method(self.workTypeList, "Redraw")
		call_method(self.workItemList, "Redraw")
		self:refresh_versions()
		state.refreshing_lists = was_refreshing
		return
	end
	if state.browser_mode == "shots" and (not state.selected_episode or state.selected_episode == "") then
		call_method(self.assetList, "Redraw")
		call_method(self.variantList, "Redraw")
		call_method(self.workTypeList, "Redraw")
		call_method(self.workItemList, "Redraw")
		self:refresh_versions()
		state.refreshing_lists = was_refreshing
		return
	end
	local selected_visible = false
	local selected_index = 0
	if state.browser_mode == "shots" then
		local seen = {}
		for _, seq in ipairs(Shots.sequences(state.project.root, true)) do
			if episode_label(seq.episode) == state.selected_episode and seq.sequence and seq.sequence ~= "" and not seen[seq.sequence] then
				seen[seq.sequence] = true
				table.insert(state.asset_rows, {sequence = seq.sequence})
				call_method(self.assetList, "AddItem", seq.sequence, false)
				if seq.sequence == state.selected_sequence then
					selected_visible = true
					selected_index = #state.asset_rows - 1
				end
			end
		end
		if #state.asset_rows > 0 and selected_visible then
			call_method(self.assetList, "SetSelItem", selected_index, false)
		else
			state.selected_sequence = nil
			state.selected_shot_id = nil
			state.selected_work_branch_id = nil
			state.selected_work_type = nil
			self:reset_version_selection()
		end
	else
		for _, item in ipairs(state.assets or {}) do
			if not state.selected_type or item.type == state.selected_type then
				table.insert(state.asset_rows, {id = item.id})
				call_method(self.assetList, "AddItem", asset_table_row(item.name), false)
				if item.id == state.selected_asset_id then
					selected_visible = true
					selected_index = #state.asset_rows - 1
				end
			end
		end
		if #state.asset_rows > 0 and selected_visible then
			call_method(self.assetList, "SetSelItem", selected_index, false)
		else
			state.selected_asset_id = nil
			state.selected_variant_id = nil
			state.selected_work_branch_id = nil
			state.selected_work_type = nil
			self:reset_version_selection()
		end
	end
	call_method(self.assetList, "Redraw")
	self:refresh_variants()
	state.refreshing_lists = was_refreshing
end

function FlowinatorDialog:refresh_variants()
	local was_refreshing = state.refreshing_lists
	state.refreshing_lists = true
	clear_text_list(self.variantList)
	state.variant_rows = {}
	if state.browser_mode == "shots" then
		if not state.selected_sequence then
			call_method(self.variantList, "Redraw")
			self:refresh_workfiles()
			state.refreshing_lists = was_refreshing
			return
		end
		local selected_visible = false
		local selected_index = 0
		for _, shot in ipairs(state.shots or {}) do
			if episode_label(shot.episode) == state.selected_episode and shot.sequence == state.selected_sequence then
				table.insert(state.variant_rows, {id = shot.id})
				call_method(self.variantList, "AddItem", asset_table_row(shot.name), false)
				if shot.id == state.selected_shot_id then
					selected_visible = true
					selected_index = #state.variant_rows - 1
				end
			end
		end
		if #state.variant_rows > 0 and selected_visible then
			call_method(self.variantList, "SetSelItem", selected_index, false)
		else
			state.selected_shot_id = nil
			state.selected_work_branch_id = nil
			state.selected_work_type = nil
			self:reset_version_selection()
		end
		call_method(self.variantList, "Redraw")
		self:refresh_workfiles()
		state.refreshing_lists = was_refreshing
		return
	end
	local asset = self:base_asset()
	if not asset then
		call_method(self.variantList, "Redraw")
		self:refresh_workfiles()
		state.refreshing_lists = was_refreshing
		return
	end
	if asset then
		Assets.ensure_hierarchy(asset)
		local selected_visible = false
		local selected_index = 0
		for _, variant in ipairs(asset.variants or {}) do
			table.insert(state.variant_rows, {id = variant.id})
			call_method(self.variantList, "AddItem", variant.name or "Default", false)
			if variant.id == state.selected_variant_id then
				selected_visible = true
				selected_index = #state.variant_rows - 1
			end
		end
		if #state.variant_rows > 0 and selected_visible then
			call_method(self.variantList, "SetSelItem", selected_index, false)
		else
			state.selected_variant_id = nil
			state.selected_work_branch_id = nil
			state.selected_work_type = nil
			self:reset_version_selection()
		end
	end
	call_method(self.variantList, "Redraw")
	self:refresh_workfiles()
	state.refreshing_lists = was_refreshing
end

function FlowinatorDialog:refresh_workfiles()
	local was_refreshing = state.refreshing_lists
	state.refreshing_lists = true
	clear_text_list(self.workTypeList)
	clear_text_list(self.workItemList)
	state.work_type_rows = {}
	state.work_item_rows = {}
	local branches = {}
	if state.browser_mode == "shots" then
		if not state.selected_shot_id then
			call_method(self.workTypeList, "Redraw")
			call_method(self.workItemList, "Redraw")
			self:refresh_versions()
			state.refreshing_lists = was_refreshing
			return
		end
		local shot = self:base_shot()
		if shot then
			branches = shot.work_branches or {}
		end
	else
		if not state.selected_variant_id then
			call_method(self.workTypeList, "Redraw")
			call_method(self.workItemList, "Redraw")
			self:refresh_versions()
			state.refreshing_lists = was_refreshing
			return
		end
		local variant = self:selected_variant()
		if variant then
			branches = variant.work_branches or {}
		end
	end
	local seen = {}
	local selected_type_index = 0
	local selected_type_visible = false
	for _, branch in ipairs(branches) do
		if branch.work_type and not seen[branch.work_type] then
			seen[branch.work_type] = true
			table.insert(state.work_type_rows, {work_type = branch.work_type, id = branch.id})
			local is_selected = branch.id == state.selected_work_branch_id or (state.selected_work_branch_id == nil and branch.work_type == state.selected_work_type)
			local label = branch.work_type
			call_method(self.workTypeList, "AddItem", label, false)
			if is_selected then
				selected_type_index = #state.work_type_rows - 1
				selected_type_visible = true
				state.selected_work_type = branch.work_type
			end
		end
	end
	if state.selected_work_type and not seen[state.selected_work_type] then
		state.selected_work_type = nil
		state.selected_work_branch_id = nil
		self:reset_version_selection()
	end
	if #state.work_type_rows > 0 and selected_type_visible then
		select_list_item(self.workTypeList, selected_type_index)
	end
	local selected_item_index = 0
	local selected_visible = false
	local item_for_label = state.browser_mode == "shots" and self:base_shot() or self:base_asset()
	local selected_variant = state.browser_mode == "assets" and self:selected_variant() or nil
	for _, branch in ipairs(branches) do
		if branch.work_type == state.selected_work_type then
			table.insert(state.work_item_rows, {id = branch.id})
			local label_item = selected_variant and Assets.branch_item(item_for_label, selected_variant, branch) or item_for_label
			local label = work_item_label(label_item, branch)
			call_method(self.workItemList, "AddItem", label, false)
			if branch.id == state.selected_work_branch_id then
				selected_visible = true
				selected_item_index = #state.work_item_rows - 1
			end
		end
	end
	if #state.work_item_rows > 0 and selected_visible then
		call_method(self.workItemList, "SetSelItem", selected_item_index, false)
	elseif #state.work_item_rows > 0 then
		state.selected_work_branch_id = nil
		self:reset_version_selection()
	end
	call_method(self.workTypeList, "Redraw")
	call_method(self.workItemList, "Redraw")
	self:refresh_versions()
	state.refreshing_lists = was_refreshing
end

function FlowinatorDialog:refresh_work_items()
	local was_refreshing = state.refreshing_lists
	state.refreshing_lists = true
	clear_text_list(self.workItemList)
	state.work_item_rows = {}
	local branches = {}
	if state.browser_mode == "shots" then
		local shot = self:base_shot()
		if shot then branches = shot.work_branches or {} end
	else
		local variant = self:selected_variant()
		if variant then branches = variant.work_branches or {} end
	end
	local selected_item_index = 0
	local selected_visible = false
	local item_for_label = state.browser_mode == "shots" and self:base_shot() or self:base_asset()
	local selected_variant = state.browser_mode == "assets" and self:selected_variant() or nil
	for _, branch in ipairs(branches) do
		if branch.work_type == state.selected_work_type then
			table.insert(state.work_item_rows, {id = branch.id})
			local label_item = selected_variant and Assets.branch_item(item_for_label, selected_variant, branch) or item_for_label
			call_method(self.workItemList, "AddItem", work_item_label(label_item, branch), false)
			if branch.id == state.selected_work_branch_id then
				selected_visible = true
				selected_item_index = #state.work_item_rows - 1
			end
		end
	end
	if #state.work_item_rows > 0 and selected_visible then
		call_method(self.workItemList, "SetSelItem", selected_item_index, false)
	elseif #state.work_item_rows > 0 then
		state.selected_work_branch_id = nil
		self:reset_version_selection()
	end
	call_method(self.workItemList, "Redraw")
	self:refresh_versions()
	state.refreshing_lists = was_refreshing
end

function FlowinatorDialog:refresh_versions()
	local was_refreshing = state.refreshing_lists
	state.refreshing_lists = true
	clear_text_list(self.workVersionList)
	clear_text_list(self.publishVersionList)
	state.work_version_rows = {}
	state.publish_version_rows = {}

	if not state.selected_work_branch_id then
		state.selected_work_version = nil
		state.selected_publish_version = nil
		state.selected_version_kind = "work"
		call_method(self.workVersionList, "Redraw")
		call_method(self.publishVersionList, "Redraw")
		self:refresh_details()
		state.refreshing_lists = was_refreshing
		return
	end

	local asset = self:selected_asset()
	if not asset then
		state.selected_work_version = nil
		state.selected_publish_version = nil
		state.selected_version_kind = "work"
		call_method(self.workVersionList, "Redraw")
		call_method(self.publishVersionList, "Redraw")
		self:refresh_details()
		state.refreshing_lists = was_refreshing
		return
	end

	local workfiles = asset.workfiles or {}
	if #workfiles > 0 then
		local selected_index = #workfiles - 1
		local selected_exists = false
		for i, workfile in ipairs(workfiles) do
			table.insert(state.work_version_rows, {version = workfile.version})
			call_method(self.workVersionList, "AddItem", version_row(workfile, "V"), false)
			if workfile.version == state.selected_work_version then
				selected_index = i - 1
				selected_exists = true
			end
		end
		if not selected_exists then
			state.selected_work_version = workfiles[#workfiles].version
			selected_index = #workfiles - 1
		end
		call_method(self.workVersionList, "SetSelItem", selected_index, false)
	else
		state.selected_work_version = nil
		table.insert(state.work_version_rows, {version = 0, virtual = true})
		call_method(self.workVersionList, "AddItem", "V000          -                       UI placeholder", false)
		call_method(self.workVersionList, "SetSelItem", 0, false)
	end
	call_method(self.workVersionList, "Redraw")

	local publishes = asset.publishes or {}
	local live_publish = Versions.live_publish_entry(asset)
	if #publishes > 0 then
		local selected_index = #publishes - 1
		local selected_exists = false
		for i, publish in ipairs(publishes) do
			table.insert(state.publish_version_rows, {version = publish.version})
			call_method(self.publishVersionList, "AddItem", version_row(publish, "P", live_publish), false)
			if publish.version == state.selected_publish_version then
				selected_index = i - 1
				selected_exists = true
			end
		end
		if not selected_exists then
			state.selected_publish_version = publishes[#publishes].version
			selected_index = #publishes - 1
		end
		call_method(self.publishVersionList, "SetSelItem", selected_index, false)
	else
		state.selected_publish_version = nil
		if state.selected_version_kind == "publish" then
			state.selected_version_kind = "work"
		end
	end
	call_method(self.publishVersionList, "Redraw")

	if state.selected_version_kind == "publish" and not state.selected_publish_version then
		state.selected_version_kind = "work"
	end
	self:refresh_details()
	state.refreshing_lists = was_refreshing
end

function FlowinatorDialog:refresh_details()
	set_text(self.detailsTitle, self:current_detail_title())
	local asset = self:selected_asset()
	if not asset then
		set_text(self.assetName, "No item selected")
		set_text(self.assetMeta, "")
		set_text(self.previewInfo, "Preview: none")
		set_text(self.versionInfo, "Selected: none")
		return
	end

	local entry, kind = self:selected_version_entry()
	if state.browser_mode == "shots" then
		set_text(self.assetName, asset.name .. (asset.work_type and (" / " .. asset.work_type) or ""))
	else
		local context = asset.variant and (" / " .. asset.variant .. " / " .. (asset.work_type or "") .. " / " .. (asset.work_item or "")) or ""
		set_text(self.assetName, asset.name .. " (" .. asset.type .. ")" .. context)
	end
	set_text(self.assetMeta, "Owner: " .. (asset.owner or "") .. " | Created: " .. (asset.created or ""))

	local preview_path = entry and entry.preview_path or ""
	if preview_path == "" then
		preview_path = asset.preview_path or ""
	end

	if preview_path ~= "" then
		set_text(self.previewInfo, "Preview: available")
	else
		set_text(self.previewInfo, "Preview: none")
	end

	if kind == "publish" and entry then
		local live = Versions.live_publish_entry(asset)
		set_text(self.versionInfo, string.format("Selected Publish: P%03d | Latest Publish: %s | Live: %s", entry.version or 0, publish_label(Versions.latest_publish_version(asset)), live and publish_label(live.version or 0) or "-"))
	elseif entry then
		set_text(self.versionInfo, string.format("Selected Work: V%04d | Latest Work: %s", entry.version or 0, work_label(asset.latest_version or 0)))
	else
		local live = Versions.live_publish_entry(asset)
		set_text(self.versionInfo, string.format("Latest Work: %s | Latest Publish: %s | Live: %s", work_label(asset.latest_version or 0), publish_label(Versions.latest_publish_version(asset)), live and publish_label(live.version or 0) or "-"))
	end
end

function FlowinatorDialog:refresh()
	self:refresh_status()
	self:refresh_mode_buttons()
	self:refresh_types()
	clear_text_list(self.assetList)
	clear_text_list(self.variantList)
	clear_text_list(self.workTypeList)
	clear_text_list(self.workItemList)
	clear_text_list(self.workVersionList)
	clear_text_list(self.publishVersionList)
	state.asset_rows = {}
	state.variant_rows = {}
	state.work_type_rows = {}
	state.work_item_rows = {}
	state.work_version_rows = {}
	state.publish_version_rows = {}
	self:refresh_details()
end

function UI.show(moho)
	if not LM or not LM.GUI then
		print("Flowinator requires Moho's LM.GUI runtime.")
		return
	end
	if UI.dialog then
		alert("Flowinator is already open.")
		return
	end
	math.randomseed(os.time())
	local dialog = FlowinatorDialog:new(moho)
	UI.dialog = dialog
	dialog:DoModeless()
end

return UI
