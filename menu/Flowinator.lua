-- Flowinator MVP
-- Select the Flowinator folder with Moho's Install Script command, then run:
-- Scripts > Flowinator > Flowinator

ScriptName = "Flowinator"

Flowinator = {}

local function script_dir()
	local source = debug.getinfo(1, "S").source
	source = source:gsub("^@", "")
	return source:match("^(.*[\\/])") or ""
end

local MENU_DIR = script_dir()
local RESOURCE_DIR = MENU_DIR:gsub("([/\\])Menu[/\\]$", "%1ScriptResources%1Flowinator%1")
if RESOURCE_DIR == MENU_DIR then
	RESOURCE_DIR = MENU_DIR .. "ScriptResources/Flowinator/"
end
package.path = RESOURCE_DIR .. "?.lua;" .. RESOURCE_DIR .. "flowinator/?.lua;" .. package.path

local function reload_flowinator_modules()
	-- Keep the modeless UI module loaded so the Scripts menu cannot open a
	-- second Flowinator window while one is already active.
	local modules = {"project", "users", "assets", "shots", "versions", "metadata", "json", "paths"}
	for _, name in ipairs(modules) do
		package.loaded[name] = nil
	end
	return require("ui")
end

function Flowinator:Name()
	return "Flowinator"
end

function Flowinator:Version()
	return "0.9.2"
end

function Flowinator:Description()
	return "Local-first production management MVP for Moho Pro."
end

function Flowinator:Creator()
	return "Flowinator MVP"
end

function Flowinator:UILabel()
	return "Flowinator"
end

function Flowinator:Run(moho)
	local UI = reload_flowinator_modules()
	UI.show(moho)
end
