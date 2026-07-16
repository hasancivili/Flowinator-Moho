local Paths = {}

local sep = package.config:sub(1, 1)
local known_directories = {}

function Paths.join(...)
	local parts = {...}
	local out = {}
	for _, part in ipairs(parts) do
		if part and tostring(part) ~= "" then
			local s = tostring(part):gsub("[/\\]+", sep)
			s = s:gsub(sep .. "+$", "")
			if #out > 0 then
				s = s:gsub("^" .. sep .. "+", "")
			end
			table.insert(out, s)
		end
	end
	return table.concat(out, sep)
end

function Paths.exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

function Paths.file_size(path)
	local f = io.open(path, "rb")
	if not f then
		return 0
	end
	local size = f:seek("end") or 0
	f:close()
	return size
end

function Paths.mkdir(path)
	if not path or path == "" then
		return false
	end
	local key = Paths.normalize(path)
	if sep == "\\" then
		key = key:lower()
	end
	if known_directories[key] then
		return true
	end
	if sep == "\\" then
		os.execute('mkdir "' .. path .. '" >nul 2>nul')
	else
		os.execute('mkdir -p "' .. path .. '" >/dev/null 2>/dev/null')
	end
	known_directories[key] = true
	return true
end

function Paths.ensure_tree(root, tree)
	Paths.mkdir(root)
	for _, rel in ipairs(tree) do
		Paths.mkdir(Paths.join(root, rel))
	end
end

function Paths.safe_name(value)
	value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
	value = value:gsub("[^%w%s_%-]", "")
	value = value:gsub("%s+", "_")
	if value == "" then
		value = "Untitled"
	end
	return value
end

function Paths.is_absolute(path)
	path = tostring(path or "")
	if path == "" then return false end
	if path:match("^%a:[/\\]") then return true end
	if path:match("^[/\\][/\\]") then return true end
	if path:sub(1, 1) == "/" then return true end
	return false
end

function Paths.normalize(path)
	return tostring(path or ""):gsub("[/\\]+", sep)
end

function Paths.relative(root, path)
	if not root or root == "" or not path or path == "" then
		return path or ""
	end
	local norm_root = Paths.normalize(root):gsub(sep .. "+$", "")
	local norm_path = Paths.normalize(path)
	local compare_root = norm_root
	local compare_path = norm_path
	if sep == "\\" then
		compare_root = compare_root:lower()
		compare_path = compare_path:lower()
	end
	if compare_path == compare_root then
		return ""
	end
	if compare_path:sub(1, #compare_root + 1) == compare_root .. sep then
		return norm_path:sub(#norm_root + 2)
	end
	return path
end

function Paths.resolve(root, path)
	if not path or path == "" then
		return ""
	end
	if Paths.is_absolute(path) then
		return path
	end
	return Paths.join(root, path)
end

function Paths.copy_file(src, dst)
	local input = io.open(src, "rb")
	if not input then
		return false, "Could not open source file."
	end
	local data = input:read("*a")
	input:close()
	local output = io.open(dst, "wb")
	if not output then
		return false, "Could not write destination file."
	end
	output:write(data)
	output:close()
	return true
end

function Paths.move(src, dst)
	if not src or src == "" or not dst or dst == "" then
		return false
	end
	local parent = dst:match("^(.*)[/\\][^/\\]+$")
	if parent then Paths.mkdir(parent) end
	local ok = os.rename(src, dst)
	if ok then return true end
	return false
end

function Paths.write_empty_file(path)
	local f = io.open(path, "wb")
	if not f then
		return false
	end
	f:write("")
	f:close()
	return true
end

function Paths.remove_dir(path)
	if not path or path == "" then
		return false
	end
	if sep == "\\" then
		os.execute('rmdir /s /q "' .. path .. '" >nul 2>nul')
	else
		os.execute('rm -rf "' .. path .. '" >/dev/null 2>/dev/null')
	end
	return true
end

function Paths.open_folder(path)
	if sep == "\\" then
		os.execute('start "" "' .. path .. '"')
	elseif sep == "/" then
		os.execute('open "' .. path .. '" >/dev/null 2>/dev/null || xdg-open "' .. path .. '" >/dev/null 2>/dev/null')
	end
end

return Paths
