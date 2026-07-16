local Paths = require("paths")
local Assets = require("assets")
local Shots = require("shots")
local Recycle = require("recycle")

local Versions = {}
local AUTO_PREVIEW_ON_SAVE = false

local function is_default(value)
	return not value or value == "" or value == "Default" or value == "Default Variant" or value == "Default Work Item"
end

local function branch_name_parts(item)
	local parts = {item.safe_name or Paths.safe_name(item.name)}
	if item.variant and not is_default(item.variant) then
		table.insert(parts, Paths.safe_name(item.variant))
	end
	if item.work_type and item.work_type ~= "" then
		table.insert(parts, Paths.safe_name(item.work_type))
	end
	if item.work_item and not is_default(item.work_item) then
		table.insert(parts, Paths.safe_name(item.work_item))
	end
	return table.concat(parts, "_")
end

local function version_name(asset, version)
	if asset and asset.kind == "shot" and asset.work_type then
		return string.format("%s_V%04d.moho", branch_name_parts(asset), version)
	end
	if asset and asset.work_type and asset.work_item then
		return string.format("%s_V%04d.moho", branch_name_parts(asset), version)
	end
	return string.format("%s_Work_V%03d.moho", asset.safe_name or Paths.safe_name(asset.name), version)
end

local function publish_name(asset, version)
	if asset and asset.kind == "shot" and asset.work_type then
		return string.format("%s_P%03d.moho", branch_name_parts(asset), version)
	end
	if asset and asset.work_type and asset.work_item then
		return string.format("%s_P%03d.moho", branch_name_parts(asset), version)
	end
	return string.format("%s_Publish_V%03d.moho", asset.safe_name or Paths.safe_name(asset.name), version)
end

local function live_publish_name(asset)
	if asset and (asset.work_type or asset.kind == "shot") then
		return string.format("%s_Live.moho", branch_name_parts(asset))
	end
	return string.format("%s_Live.moho", asset.safe_name or Paths.safe_name(asset.name))
end

local function item_folder(root, item)
	if item and item.kind == "shot" then
		return Shots.shot_folder(root, item)
	end
	return Assets.asset_folder(root, item)
end

local function publish_folder(root, item)
	if item and item.kind == "shot" then
		if item.work_type then
			if item.episode and item.episode ~= "" then
				return Paths.join(root, "05_Publish", "Shots", Paths.safe_name(item.episode), Paths.safe_name(item.sequence or "Sequence"), item.safe_name or Paths.safe_name(item.name), Paths.safe_name(item.work_type), Paths.safe_name(item.work_item or "Default"))
			end
			return Paths.join(root, "05_Publish", "Shots", Paths.safe_name(item.sequence or "Sequence"), item.safe_name or Paths.safe_name(item.name), Paths.safe_name(item.work_type), Paths.safe_name(item.work_item or "Default"))
		end
		return Paths.join(root, "05_Publish", "Shots", item.safe_name or Paths.safe_name(item.name))
	end
	if item and item.variant and item.work_type and item.work_item then
		return Paths.join(root, "05_Publish", Assets.type_dir(item.type), item.safe_name or Paths.safe_name(item.name), Paths.safe_name(item.variant), Paths.safe_name(item.work_type), Paths.safe_name(item.work_item))
	end
	return Paths.join(root, "05_Publish", Assets.type_dir(item.type), item.safe_name or Paths.safe_name(item.name))
end

local function update_item(root, item)
	if item and item.kind == "shot" then
		return Shots.update(root, item)
	end
	return Assets.update(root, item)
end

local function preview_name(asset, kind, version)
	if asset and asset.kind == "shot" and asset.work_type then
		return string.format("%s_%s_V%03d_preview.png", branch_name_parts(asset), kind, version)
	end
	if asset and asset.work_type and asset.work_item then
		return string.format("%s_%s_V%03d_preview.png", branch_name_parts(asset), kind, version)
	end
	return string.format("%s_%s_V%03d_preview.png", asset.safe_name or Paths.safe_name(asset.name), kind, version)
end

local function ps_quote(value)
	return "'" .. tostring(value or ""):gsub("'", "''") .. "'"
end

local function shell_quote(value)
	return "'" .. tostring(value or ""):gsub("'", "'\"'\"'") .. "'"
end

local function resize_preview(src, dst)
	if package.config:sub(1, 1) == "\\" then
		local script = table.concat({
			"Add-Type -AssemblyName System.Drawing",
			"$src=" .. ps_quote(src),
			"$dst=" .. ps_quote(dst),
			"$img=[System.Drawing.Image]::FromFile($src)",
			"$maxW=160",
			"$maxH=90",
			"$scale=[Math]::Min($maxW/$img.Width,$maxH/$img.Height)",
			"if($scale -gt 1){$scale=1}",
			"$w=[Math]::Max(1,[int]($img.Width*$scale))",
			"$h=[Math]::Max(1,[int]($img.Height*$scale))",
			"$bmp=New-Object System.Drawing.Bitmap($w,$h)",
			"$g=[System.Drawing.Graphics]::FromImage($bmp)",
			"$g.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic",
			"$g.DrawImage($img,0,0,$w,$h)",
			"$img.Dispose()",
			"$g.Dispose()",
			"$bmp.Save($dst,[System.Drawing.Imaging.ImageFormat]::Png)",
			"$bmp.Dispose()"
		}, "; ")
		os.execute('powershell -NoProfile -ExecutionPolicy Bypass -Command "' .. script .. '" >nul 2>nul')
	elseif package.config:sub(1, 1) == "/" then
		-- sips is included with macOS and preserves the PNG output format.
		os.execute("sips -Z 160 " .. shell_quote(src) .. " --out " .. shell_quote(dst) .. " >/dev/null 2>/dev/null")
	else
		return false
	end
	return Paths.exists(dst) and Paths.file_size(dst) > 0
end

local function current_document_path(moho)
	if moho and moho.document and moho.document.Path then
		local ok, result = pcall(function() return moho.document:Path() end)
		if ok then
			return result
		end
		ok, result = pcall(function() return moho.document:Path(false) end)
		if ok then
			return result
		end
	end
	return nil
end

local function save_current_document_as(moho, path)
	if moho and moho.FileSaveAs then
		local ok = pcall(function() moho:FileSaveAs(path) end)
		if ok and Paths.exists(path) and Paths.file_size(path) > 0 then
			return true
		end
	end
	return false
end

local function meta_path(root, path)
	return Paths.relative(root, path)
end

local function disk_path(root, path)
	return Paths.resolve(root, path)
end

local function render_preview(root, asset, moho, kind, version)
	if not moho or not moho.FileRender then
		return nil
	end
	local folder = Paths.join(root, "00_Pipeline", "Metadata", "Previews")
	Paths.mkdir(folder)
	local path = Paths.join(folder, preview_name(asset, kind or "work", version or 0))
	local temp_path = path:gsub("%.png$", "_full.png")
	os.remove(path)
	os.remove(temp_path)
	local render_path = temp_path:gsub("\\", "/")
	local ok = pcall(function() moho:FileRender(render_path) end)
	if ok and Paths.exists(temp_path) and Paths.file_size(temp_path) > 0 then
		if not resize_preview(temp_path, path) then
			Paths.copy_file(temp_path, path)
		end
		os.remove(temp_path)
	end
	if (not Paths.exists(path) or Paths.file_size(path) == 0) then
		local direct_path = path:gsub("\\", "/")
		pcall(function() moho:FileRender(direct_path) end)
	end
	if Paths.exists(path) and Paths.file_size(path) > 0 then
		asset.preview_path = meta_path(root, path)
		return path
	end
	return nil
end

local function render_preview_for_save(root, asset, moho, kind, version)
	if not AUTO_PREVIEW_ON_SAVE then
		return nil
	end
	return render_preview(root, asset, moho, kind, version)
end

local function next_work_version(asset)
	local highest = asset.version_counter or asset.latest_version or 0
	for _, entry in ipairs(asset.workfiles or {}) do
		highest = math.max(highest, entry.version or 0)
	end
	return highest + 1
end

function Versions.create_workfile(root, asset, moho, user, comment)
	if #(asset.workfiles or {}) > 0 then
		return nil, "This asset already has a workfile. Use Save Version."
	end
	local folder = item_folder(root, asset)
	Paths.mkdir(folder)
	local version = next_work_version(asset)
	local path = Paths.join(folder, version_name(asset, version))
	return Versions.save_path(root, asset, user, comment, path, version, moho)
end

function Versions.save_path(root, asset, user, comment, path, version, moho)
	local ok = true
	if moho then
		ok = save_current_document_as(moho, path)
	end
	if not ok then
		return nil, "Moho could not save the current document to the version path."
	end
	local preview_path = render_preview_for_save(root, asset, moho, "work", version)
	asset.latest_version = version
	asset.version_counter = version
	asset.workfiles = asset.workfiles or {}
	table.insert(asset.workfiles, {
		version = version,
		path = meta_path(root, path),
		author = user or "",
		created = os.date("%Y-%m-%d %H:%M:%S"),
		comment = comment or "",
		preview_path = preview_path and meta_path(root, preview_path) or ""
	})
	update_item(root, asset)
	return path
end

function Versions.save_new(root, asset, moho, user, comment)
	if #(asset.workfiles or {}) == 0 then
		return nil, "Create the first workfile before saving a new version."
	end
	local folder = item_folder(root, asset)
	Paths.mkdir(folder)
	local version = next_work_version(asset)
	local path = Paths.join(folder, version_name(asset, version))
	local ok = save_current_document_as(moho, path)
	local src = nil
	if not ok then
		src = current_document_path(moho)
	end
	if src and src ~= "" and Paths.exists(src) then
		ok = Paths.copy_file(src, path)
	end
	if not ok then
		return nil, "Moho could not save the current document. Save the scene once in Moho, then try again."
	end
	local preview_path = render_preview_for_save(root, asset, moho, "work", version)
	asset.latest_version = version
	asset.version_counter = version
	asset.workfiles = asset.workfiles or {}
	table.insert(asset.workfiles, {
		version = version,
		path = meta_path(root, path),
		author = user or "",
		created = os.date("%Y-%m-%d %H:%M:%S"),
		comment = comment or "",
		preview_path = preview_path and meta_path(root, preview_path) or ""
	})
	update_item(root, asset)
	return path
end

function Versions.publish(root, asset, moho, user, comment)
	if (asset.latest_version or 0) == 0 then
		return nil, "Create a workfile before publishing."
	end
	local publishes = asset.publishes or {}
	local version = #publishes + 1
	local folder = publish_folder(root, asset)
	Paths.mkdir(folder)
	local path = Paths.join(folder, publish_name(asset, version))
	local live_path = Paths.join(folder, live_publish_name(asset))
	local ok = save_current_document_as(moho, path)
	if not ok then
		local latest = Versions.latest(asset)
		local latest_path = latest and latest.path and disk_path(root, latest.path) or ""
		if latest_path ~= "" and Paths.exists(latest_path) then
			ok = Paths.copy_file(latest_path, path)
		end
	end
	if not ok then
		return nil, "Moho could not publish the current document."
	end
	local live_ok = Paths.copy_file(path, live_path)
	if not live_ok then
		return nil, "Could not update Live Publish."
	end
	local preview_path = render_preview_for_save(root, asset, moho, "publish", version)
	asset.publishes = publishes
	table.insert(asset.publishes, {
		version = version,
		path = meta_path(root, path),
		author = user or "",
		created = os.date("%Y-%m-%d %H:%M:%S"),
		comment = comment or "",
		preview_path = preview_path and meta_path(root, preview_path) or ""
	})
	asset.live_publish = {
		version = version,
		path = meta_path(root, live_path),
		updated = os.date("%Y-%m-%d %H:%M:%S"),
		author = user or "",
		comment = comment or ""
	}
	update_item(root, asset)
	return path
end

function Versions.latest(asset)
	if not asset or not asset.workfiles or #asset.workfiles == 0 then
		return nil
	end
	return asset.workfiles[#asset.workfiles]
end

function Versions.workfile(asset, version)
	if not asset or not asset.workfiles then
		return nil
	end
	if not version then
		return Versions.latest(asset)
	end
	for _, workfile in ipairs(asset.workfiles) do
		if workfile.version == version then
			return workfile
		end
	end
	return nil
end

function Versions.publish_entry(asset, version)
	if not asset or not asset.publishes then
		return nil
	end
	if not version then
		return asset.publishes[#asset.publishes]
	end
	for _, publish in ipairs(asset.publishes) do
		if publish.version == version then
			return publish
		end
	end
	return nil
end

function Versions.latest_publish_version(asset)
	if not asset or not asset.publishes or #asset.publishes == 0 then
		return 0
	end
	return asset.publishes[#asset.publishes].version or #asset.publishes
end

function Versions.set_preview(root, asset, moho, kind, version)
	kind = kind == "publish" and "publish" or "work"
	local entry = nil
	if kind == "publish" then
		entry = Versions.publish_entry(asset, version)
	else
		entry = Versions.workfile(asset, version)
	end
	if not entry then
		return nil, "Select a version before setting a preview."
	end
	local preview_path = render_preview(root, asset, moho, kind, entry.version)
	if not preview_path then
		return nil, "Moho could not render a preview for the selected version."
	end
	entry.preview_path = meta_path(root, preview_path)
	asset.preview_path = meta_path(root, preview_path)
	update_item(root, asset)
	return preview_path
end

function Versions.delete_workfile(root, asset, version, session)
	if not asset or not asset.workfiles then
		return false, "Work version was not found."
	end
	for index, entry in ipairs(asset.workfiles) do
		if entry.version == version then
			Recycle.move(root, disk_path(root, entry.path), session)
			if entry.preview_path and entry.preview_path ~= "" then
				Recycle.move(root, disk_path(root, entry.preview_path), session)
			end
			table.remove(asset.workfiles, index)
			local latest = asset.workfiles[#asset.workfiles]
			asset.latest_version = latest and latest.version or 0
			asset.version_counter = math.max(asset.version_counter or 0, version or 0)
			update_item(root, asset)
			return true
		end
	end
	return false, "Work version was not found."
end

function Versions.live_publish_entry(asset)
	return asset and asset.live_publish or nil
end

function Versions.import_live_publish(asset, moho, root)
	local live = Versions.live_publish_entry(asset)
	if not live or not live.path or live.path == "" then
		return false, "This asset has no Live Publish."
	end
	if moho and moho.FileImport then
		local path = root and disk_path(root, live.path) or live.path
		local ok, err = pcall(function() moho:FileImport(path, 0) end)
		return ok, err
	end
	return false, "Could not import Live Publish."
end

function Versions.reference_live_publish(asset, moho, root)
	local live = Versions.live_publish_entry(asset)
	if not live or not live.path or live.path == "" then
		return false, "This asset has no Live Publish."
	end
	if moho and moho.FileImport then
		local path = root and disk_path(root, live.path) or live.path
		local ok, err = pcall(function() moho:FileImport(path, 1) end)
		return ok, err
	end
	return false, "Could not reference Live Publish."
end

function Versions.import_publish(asset, version, moho, root)
	local publish = Versions.publish_entry(asset, version)
	if not publish then
		return false, "This asset has not been published."
	end
	if publish.path and moho and moho.FileImport then
		local path = root and disk_path(root, publish.path) or publish.path
		local ok, err = pcall(function() moho:FileImport(path, 0) end)
		return ok, err
	end
	return false, "Could not import the selected publish."
end

function Versions.load_workfile(asset, version, root)
	local workfile = Versions.workfile(asset, version)
	if workfile and workfile.path then
		local path = root and disk_path(root, workfile.path) or workfile.path
		if package.config:sub(1, 1) == "\\" then
			os.execute('start "" "' .. path .. '"')
		else
			os.execute('open "' .. path .. '" >/dev/null 2>/dev/null || xdg-open "' .. path .. '" >/dev/null 2>/dev/null')
		end
		return true
	end
	return false
end

function Versions.load_publish(asset, version, root)
	local publish = Versions.publish_entry(asset, version)
	if publish and publish.path then
		local path = root and disk_path(root, publish.path) or publish.path
		if package.config:sub(1, 1) == "\\" then
			os.execute('start "" "' .. path .. '"')
		else
			os.execute('open "' .. path .. '" >/dev/null 2>/dev/null || xdg-open "' .. path .. '" >/dev/null 2>/dev/null')
		end
		return true
	end
	return false
end

function Versions.open_latest(asset)
	return Versions.load_workfile(asset, nil)
end

return Versions
