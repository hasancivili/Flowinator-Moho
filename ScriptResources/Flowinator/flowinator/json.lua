local Json = {}

local function escape_string(s)
	return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t") .. '"'
end

local function is_array(t)
	local max = 0
	local count = 0
	for k, _ in pairs(t) do
		if type(k) ~= "number" then
			return false
		end
		if k > max then
			max = k
		end
		count = count + 1
	end
	return max == count
end

function Json.encode(value, indent)
	indent = indent or 0
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" or kind == "number" then
		return tostring(value)
	elseif kind == "string" then
		return escape_string(value)
	elseif kind ~= "table" then
		return escape_string(tostring(value))
	end

	local pad = string.rep("  ", indent)
	local child_pad = string.rep("  ", indent + 1)
	local chunks = {}

	if is_array(value) then
		for i = 1, #value do
			table.insert(chunks, child_pad .. Json.encode(value[i], indent + 1))
		end
		if #chunks == 0 then
			return "[]"
		end
		return "[\n" .. table.concat(chunks, ",\n") .. "\n" .. pad .. "]"
	end

	local keys = {}
	for k, _ in pairs(value) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		table.insert(chunks, child_pad .. escape_string(k) .. ": " .. Json.encode(value[k], indent + 1))
	end
	if #chunks == 0 then
		return "{}"
	end
	return "{\n" .. table.concat(chunks, ",\n") .. "\n" .. pad .. "}"
end

function Json.encode_compact(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" or kind == "number" then
		return tostring(value)
	elseif kind == "string" then
		return escape_string(value)
	elseif kind ~= "table" then
		return escape_string(tostring(value))
	end
	local chunks = {}
	if is_array(value) then
		for i = 1, #value do
			table.insert(chunks, Json.encode_compact(value[i]))
		end
		return "[" .. table.concat(chunks, ",") .. "]"
	end
	for k, v in pairs(value) do
		table.insert(chunks, escape_string(k) .. ":" .. Json.encode_compact(v))
	end
	return "{" .. table.concat(chunks, ",") .. "}"
end

function Json.decode(text)
	local pos = 1

	local function skip_ws()
		while text:sub(pos, pos):match("%s") do
			pos = pos + 1
		end
	end

	local parse_value

	local function parse_string()
		pos = pos + 1
		local out = {}
		while pos <= #text do
			local c = text:sub(pos, pos)
			if c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local n = text:sub(pos + 1, pos + 1)
				local map = {n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\"}
				table.insert(out, map[n] or n)
				pos = pos + 2
			else
				table.insert(out, c)
				pos = pos + 1
			end
		end
		return table.concat(out)
	end

	local function parse_number()
		local start = pos
		while text:sub(pos, pos):match("[%d%+%-%.eE]") do
			pos = pos + 1
		end
		return tonumber(text:sub(start, pos - 1))
	end

	local function parse_array()
		pos = pos + 1
		local arr = {}
		skip_ws()
		if text:sub(pos, pos) == "]" then
			pos = pos + 1
			return arr
		end
		while true do
			table.insert(arr, parse_value())
			skip_ws()
			local c = text:sub(pos, pos)
			pos = pos + 1
			if c == "]" then
				break
			end
		end
		return arr
	end

	local function parse_object()
		pos = pos + 1
		local obj = {}
		skip_ws()
		if text:sub(pos, pos) == "}" then
			pos = pos + 1
			return obj
		end
		while true do
			skip_ws()
			local key = parse_string()
			skip_ws()
			pos = pos + 1
			obj[key] = parse_value()
			skip_ws()
			local c = text:sub(pos, pos)
			pos = pos + 1
			if c == "}" then
				break
			end
		end
		return obj
	end

	function parse_value()
		skip_ws()
		local c = text:sub(pos, pos)
		if c == '"' then
			return parse_string()
		elseif c == "{" then
			return parse_object()
		elseif c == "[" then
			return parse_array()
		elseif c == "t" then
			pos = pos + 4
			return true
		elseif c == "f" then
			pos = pos + 5
			return false
		elseif c == "n" then
			pos = pos + 4
			return nil
		end
		return parse_number()
	end

	if not text or text == "" then
		return nil
	end
	return parse_value()
end

return Json
