local Json = require("json")
local Paths = require("paths")

local Metadata = {}

function Metadata.read(path, fallback)
	local f = io.open(path, "rb")
	if not f then
		return fallback
	end
	local text = f:read("*a")
	f:close()
	local ok, data = pcall(Json.decode, text)
	if ok and data ~= nil then
		return data
	end
	return fallback
end

function Metadata.write(path, data)
	local parent = path:match("^(.*)[/\\][^/\\]+$")
	if parent then
		Paths.mkdir(parent)
	end
	local f = io.open(path, "wb")
	if not f then
		return false
	end
	-- Metadata is intentionally human-readable. Files stay small because
	-- version histories are stored per work item, not in a project-wide blob.
	f:write(Json.encode(data, 0))
	f:write("\n")
	f:close()
	return true
end

return Metadata
