local Paths = require("paths")
local Metadata = require("metadata")
local Recycle = require("recycle")

local Assets = {}

local type_dirs = {
	Character = "Characters",
	Prop = "Props",
	Environment = "Environments"
}

local default_types = {"Character", "Prop", "Environment"}
local default_work_types = {"Draw", "Rig"}

local function assets_path(root)
	return Paths.join(root, "00_Pipeline", "Metadata", "assets.json")
end

local function asset_types_path(root)
	return Paths.join(root, "00_Pipeline", "Metadata", "asset_types.json")
end

function Assets.type_dir(asset_type)
	return type_dirs[asset_type] or Paths.safe_name(asset_type or "Assets")
end

function Assets.asset_folder(root, asset)
	if asset.variant and asset.work_type and asset.work_item then
		return Paths.join(
			root,
			"01_Assets",
			Assets.type_dir(asset.type),
			asset.safe_name or Paths.safe_name(asset.name),
			Paths.safe_name(asset.variant),
			Paths.safe_name(asset.work_type),
			Paths.safe_name(asset.work_item)
		)
	end
	return Paths.join(root, "01_Assets", Assets.type_dir(asset.type), asset.safe_name or Paths.safe_name(asset.name))
end

local function asset_base_folder(root, asset)
	return Paths.join(root, "01_Assets", Assets.type_dir(asset.type), asset.safe_name or Paths.safe_name(asset.name))
end

local function variant_folder(root, asset, variant)
	return Paths.join(asset_base_folder(root, asset), Paths.safe_name(variant.name or "Default"))
end

local function new_branch(work_type, work_item)
	return {
		id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		work_type = work_type or "Draw",
		work_item = work_item or "Default",
		latest_version = 0,
		version_counter = 0,
		workfiles = {},
		publishes = {},
		preview_path = ""
	}
end

local function ensure_hierarchy(asset)
	asset.variants = asset.variants or {}
	if #asset.variants == 0 then
		local old_workfiles = asset.workfiles or {}
		local old_publishes = asset.publishes or {}
		local latest = asset.latest_version or 0
		table.insert(asset.variants, {
			id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
			name = "Default",
			work_branches = {
				{
					id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
					work_type = "Draw",
					work_item = "Default",
					latest_version = latest,
					version_counter = latest,
					workfiles = old_workfiles,
					publishes = old_publishes,
					preview_path = asset.preview_path or ""
				}
			}
		})
	end
	return asset
end

function Assets.ensure_hierarchy(asset)
	return ensure_hierarchy(asset)
end

function Assets.default_work_types()
	return default_work_types
end

function Assets.load(root)
	return Metadata.read(assets_path(root), {assets = {}})
end

function Assets.save(root, data)
	return Metadata.write(assets_path(root), data)
end

function Assets.list(root)
	local data = Assets.load(root)
	local changed = false
	for _, asset in ipairs(data.assets or {}) do
		if not asset.variants or #asset.variants == 0 then
			ensure_hierarchy(asset)
			changed = true
		end
	end
	if changed then
		Assets.save(root, data)
	end
	return data.assets
end

function Assets.load_custom_types(root)
	return Metadata.read(asset_types_path(root), {types = {}})
end

function Assets.save_custom_types(root, data)
	return Metadata.write(asset_types_path(root), data)
end

function Assets.add_type(root, type_name)
	if not type_name or type_name == "" then
		return false, "Type Name is required."
	end
	local data = Assets.load_custom_types(root)
	data.types = data.types or {}
	data.deleted_defaults = data.deleted_defaults or {}
	local restored_default = false
	local kept_deleted = {}
	for _, deleted in ipairs(data.deleted_defaults) do
		if deleted == type_name then
			restored_default = true
		else
			table.insert(kept_deleted, deleted)
		end
	end
	data.deleted_defaults = kept_deleted
	for _, existing in ipairs(data.types) do
		if existing == type_name then
			return false, "Type already exists."
		end
	end
	if not restored_default then
		table.insert(data.types, type_name)
	end
	Assets.save_custom_types(root, data)
	return true
end

function Assets.delete_type(root, type_name, session)
	if not type_name or type_name == "" then
		return false, "Select an asset type first."
	end
	local data = Assets.load(root)
	local kept_assets = {}
	local deleted_count = 0
	for _, asset in ipairs(data.assets or {}) do
		if asset.type == type_name then
			deleted_count = deleted_count + 1
		else
			table.insert(kept_assets, asset)
		end
	end
	if deleted_count > 0 then
		Recycle.move(root, Paths.join(root, "01_Assets", Assets.type_dir(type_name)), session)
	end
	data.assets = kept_assets
	Assets.save(root, data)

	local custom = Assets.load_custom_types(root)
	local kept_types = {}
	for _, existing in ipairs(custom.types or {}) do
		if existing ~= type_name then
			table.insert(kept_types, existing)
		end
	end
	custom.types = kept_types
	custom.deleted_defaults = custom.deleted_defaults or {}
	if type_dirs[type_name] then
		local found = false
		for _, deleted in ipairs(custom.deleted_defaults) do
			if deleted == type_name then
				found = true
				break
			end
		end
		if not found then
			table.insert(custom.deleted_defaults, type_name)
		end
	end
	Assets.save_custom_types(root, custom)
	return true, deleted_count
end

function Assets.types(root)
	local custom = Assets.load_custom_types(root)
	local deleted_defaults = {}
	for _, type_name in ipairs(custom.deleted_defaults or {}) do
		deleted_defaults[type_name] = true
	end
	local seen = {}
	local out = {}
	for _, type_name in ipairs(default_types) do
		if not deleted_defaults[type_name] then
			seen[type_name] = true
			table.insert(out, type_name)
		end
	end
	for _, type_name in ipairs(custom.types or {}) do
		if type_name and type_name ~= "" and not seen[type_name] then
			seen[type_name] = true
			table.insert(out, type_name)
		end
	end
	for _, asset in ipairs(Assets.list(root)) do
		if asset.type and asset.type ~= "" and not seen[asset.type] then
			seen[asset.type] = true
			table.insert(out, asset.type)
		end
	end
	return out
end

function Assets.find(root, id)
	for _, asset in ipairs(Assets.list(root)) do
		if asset.id == id then
			return asset
		end
	end
	return nil
end

local function build_asset(name, asset_type, owner, description, work_types)
	local safe = Paths.safe_name(name)
	work_types = work_types or default_work_types
	local branches = {}
	for _, work_type in ipairs(work_types) do
		if work_type and work_type ~= "" then
			table.insert(branches, new_branch(work_type, "Default"))
		end
	end
	if #branches == 0 then
		table.insert(branches, new_branch("Draw", "Default"))
	end
	local asset = {
		id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		name = name,
		safe_name = safe,
		type = asset_type,
		owner = owner or "",
		created = os.date("%Y-%m-%d %H:%M:%S"),
		description = description or "",
		preview_path = "",
		latest_version = 0,
		workfiles = {},
		publishes = {},
		variants = {
			{
				id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
				name = "Default",
				work_branches = branches
			}
		}
	}
	return asset
end

function Assets.create(root, name, asset_type, owner, description, work_types)
	local data = Assets.load(root)
	local asset = build_asset(name, asset_type, owner, description, work_types)
	table.insert(data.assets, asset)
	Assets.save(root, data)
	return asset
end

function Assets.create_cached(root, assets, name, asset_type, owner, description, work_types)
	assets = assets or {}
	local asset = build_asset(name, asset_type, owner, description, work_types)
	table.insert(assets, asset)
	Assets.save(root, {assets = assets})
	return asset
end

local function stored_asset(root, id)
	local data = Assets.load(root)
	for index, asset in ipairs(data.assets or {}) do
		if asset.id == id then return data, asset, index end
	end
	return data, nil, nil
end

function Assets.delete(root, id, session)
	local data, asset, index = stored_asset(root, id)
	if not asset then return false, "Asset was not found." end
	Recycle.move(root, asset_base_folder(root, asset), session)
	table.remove(data.assets, index)
	return Assets.save(root, data)
end

function Assets.delete_variant(root, id, variant_id, session)
	local data, asset = stored_asset(root, id)
	if not asset then return false, "Asset was not found." end
	ensure_hierarchy(asset)
	for index, variant in ipairs(asset.variants or {}) do
		if variant.id == variant_id then
			Recycle.move(root, variant_folder(root, asset, variant), session)
			table.remove(asset.variants, index)
			return Assets.save(root, data)
		end
	end
	return false, "Variant was not found."
end

function Assets.delete_work_type(root, id, variant_id, work_type, session)
	local data, asset = stored_asset(root, id)
	if not asset then return false, "Asset was not found." end
	ensure_hierarchy(asset)
	for _, variant in ipairs(asset.variants or {}) do
		if variant.id == variant_id then
			local kept, removed = {}, false
			for _, branch in ipairs(variant.work_branches or {}) do
				if branch.work_type == work_type then removed = true else table.insert(kept, branch) end
			end
			if not removed then return false, "Work Type was not found." end
			Recycle.move(root, Paths.join(variant_folder(root, asset, variant), Paths.safe_name(work_type)), session)
			variant.work_branches = kept
			return Assets.save(root, data)
		end
	end
	return false, "Variant was not found."
end

function Assets.delete_work_item(root, id, variant_id, branch_id, session)
	local data, asset = stored_asset(root, id)
	if not asset then return false, "Asset was not found." end
	ensure_hierarchy(asset)
	for _, variant in ipairs(asset.variants or {}) do
		if variant.id == variant_id then
			for index, branch in ipairs(variant.work_branches or {}) do
				if branch.id == branch_id then
					Recycle.move(root, Paths.join(variant_folder(root, asset, variant), Paths.safe_name(branch.work_type), Paths.safe_name(branch.work_item or "Default")), session)
					table.remove(variant.work_branches, index)
					return Assets.save(root, data)
				end
			end
		end
	end
	return false, "Work Item was not found."
end

function Assets.variant(asset, variant_id)
	ensure_hierarchy(asset)
	if variant_id then
		for _, variant in ipairs(asset.variants or {}) do
			if variant.id == variant_id then return variant end
		end
	end
	return asset.variants and asset.variants[1] or nil
end

function Assets.branch(variant, branch_id)
	if not variant then return nil end
	if branch_id then
		for _, branch in ipairs(variant.work_branches or {}) do
			if branch.id == branch_id then return branch end
		end
	end
	return variant.work_branches and variant.work_branches[1] or nil
end

function Assets.branch_item(asset, variant, branch)
	if not asset or not variant or not branch then return nil end
	return {
		id = asset.id,
		kind = "asset",
		name = asset.name,
		safe_name = asset.safe_name,
		type = asset.type,
		owner = asset.owner,
		created = asset.created,
		description = asset.description,
		variant = variant.name,
		work_type = branch.work_type,
		work_item = branch.work_item,
		latest_version = branch.latest_version or 0,
		version_counter = branch.version_counter or branch.latest_version or 0,
		workfiles = branch.workfiles or {},
		publishes = branch.publishes or {},
		live_publish = branch.live_publish,
		preview_path = branch.preview_path or asset.preview_path or "",
		_source_asset = asset,
		_source_variant = variant,
		_source_branch = branch
	}
end

function Assets.sync_branch_item(item)
	local branch = item and item._source_branch
	local asset = item and item._source_asset
	if not branch then return item end
	branch.latest_version = item.latest_version or 0
	branch.version_counter = item.version_counter or branch.version_counter or branch.latest_version or 0
	branch.workfiles = item.workfiles or {}
	branch.publishes = item.publishes or {}
	branch.live_publish = item.live_publish
	branch.preview_path = item.preview_path or ""
	if asset then
		asset.preview_path = item.preview_path or asset.preview_path or ""
		asset.latest_version = item.latest_version or asset.latest_version or 0
		asset.version_counter = item.version_counter or asset.version_counter or asset.latest_version or 0
		asset.workfiles = item.workfiles or asset.workfiles or {}
		asset.publishes = item.publishes or asset.publishes or {}
		asset.live_publish = item.live_publish or asset.live_publish
	end
	return asset
end

function Assets.add_variant(root, asset, name)
	if not asset or not name or name == "" then return false, "Variant Name is required." end
	ensure_hierarchy(asset)
	for _, variant in ipairs(asset.variants or {}) do
		if variant.name == name then return false, "Variant already exists." end
	end
	-- New variants inherit the Default variant's complete empty work structure.
	local source_variant = nil
	for _, candidate in ipairs(asset.variants or {}) do
		if candidate.name == "Default" then
			source_variant = candidate
			break
		end
	end
	source_variant = source_variant or asset.variants[1]
	local branches = {}
	for _, branch in ipairs((source_variant and source_variant.work_branches) or {}) do
		table.insert(branches, new_branch(branch.work_type, branch.work_item or "Default"))
	end
	if #branches == 0 then
		for _, work_type in ipairs(default_work_types) do
			table.insert(branches, new_branch(work_type, "Default"))
		end
	end
	local variant = {
		id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		name = name,
		work_branches = branches
	}
	table.insert(asset.variants, variant)
	return Assets.update(root, asset), variant
end

function Assets.add_work_type(root, asset, variant, work_type)
	if not asset or not variant or not work_type or work_type == "" then return false, "Work Type is required." end
	variant.work_branches = variant.work_branches or {}
	for _, branch in ipairs(variant.work_branches) do
		if branch.work_type == work_type and branch.work_item == "Default" then
			return false, "Work Type already exists."
		end
	end
	local branch = new_branch(work_type, "Default")
	table.insert(variant.work_branches, branch)
	return Assets.update(root, asset), branch
end

function Assets.add_work_item(root, asset, variant, work_type, work_item)
	if not asset or not variant or not work_type or not work_item or work_item == "" then return false, "Work Item is required." end
	variant.work_branches = variant.work_branches or {}
	for _, branch in ipairs(variant.work_branches) do
		if branch.work_type == work_type and branch.work_item == work_item then
			return false, "Work Item already exists."
		end
	end
	local branch = new_branch(work_type, work_item)
	table.insert(variant.work_branches, branch)
	return Assets.update(root, asset), branch
end

function Assets.update(root, updated)
	updated = Assets.sync_branch_item(updated) or updated
	local data = Assets.load(root)
	for i, asset in ipairs(data.assets) do
		if asset.id == updated.id then
			data.assets[i] = updated
			Assets.save(root, data)
			return true
		end
	end
	return false
end

return Assets
