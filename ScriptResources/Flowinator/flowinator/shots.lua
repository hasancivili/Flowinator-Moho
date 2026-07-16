local Paths = require("paths")
local Metadata = require("metadata")
local Recycle = require("recycle")

local Shots = {}
local default_work_types = {"Layout", "Animation", "FX"}

local function shots_path(root)
	return Paths.join(root, "00_Pipeline", "Metadata", "shots.json")
end

function Shots.shot_folder(root, shot)
	if shot and shot.work_type then
		if shot.episode and shot.episode ~= "" then
			return Paths.join(root, "02_Scenes", Paths.safe_name(shot.episode), Paths.safe_name(shot.sequence or "Sequence"), shot.safe_name or Paths.safe_name(shot.name), Paths.safe_name(shot.work_type), Paths.safe_name(shot.work_item or "Default"))
		end
		return Paths.join(root, "02_Scenes", Paths.safe_name(shot.sequence or "Sequence"), shot.safe_name or Paths.safe_name(shot.name), Paths.safe_name(shot.work_type), Paths.safe_name(shot.work_item or "Default"))
	end
	return Paths.join(root, "02_Scenes", shot.safe_name or Paths.safe_name(shot.name))
end

local function shot_base_folder(root, shot)
	if shot.episode and shot.episode ~= "" then
		return Paths.join(root, "02_Scenes", Paths.safe_name(shot.episode), Paths.safe_name(shot.sequence or "Sequence"), shot.safe_name or Paths.safe_name(shot.name))
	end
	return Paths.join(root, "02_Scenes", Paths.safe_name(shot.sequence or "Sequence"), shot.safe_name or Paths.safe_name(shot.name))
end

local function new_branch(work_type, work_item)
	return {
		id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		work_type = work_type or "Animation",
		work_item = work_item or "Default",
		latest_version = 0,
		version_counter = 0,
		workfiles = {},
		publishes = {},
		preview_path = ""
	}
end

local function ensure_hierarchy(shot)
	shot.work_branches = shot.work_branches or {}
	if #shot.work_branches == 0 then
		table.insert(shot.work_branches, {
			id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
			work_type = "Animation",
			work_item = "Default",
			latest_version = shot.latest_version or 0,
			version_counter = shot.latest_version or 0,
			workfiles = shot.workfiles or {},
			publishes = shot.publishes or {},
			preview_path = shot.preview_path or ""
		})
	end
	return shot
end

function Shots.default_work_types()
	return default_work_types
end

function Shots.load(root)
	return Metadata.read(shots_path(root), {shots = {}})
end

function Shots.save(root, data)
	return Metadata.write(shots_path(root), data)
end

function Shots.list(root)
	local data = Shots.load(root)
	local changed = false
	for _, shot in ipairs(data.shots or {}) do
		if not shot.work_branches or #shot.work_branches == 0 then
			ensure_hierarchy(shot)
			changed = true
		end
	end
	if changed then
		Shots.save(root, data)
	end
	return data.shots
end

function Shots.sequences(root, use_episodes)
	local data = Shots.load(root)
	local out = {}
	local seen = {}
	if use_episodes then
		for _, episode in ipairs(data.episodes or {}) do
			local name = episode.name or ""
			if name ~= "" and not seen[name .. "|"] then
				seen[name .. "|"] = true
				table.insert(out, {episode = name, sequence = ""})
			end
		end
	end
	for _, seq in ipairs(data.sequences or {}) do
		local key = (use_episodes and (seq.episode or "") or "") .. "|" .. (seq.sequence or "")
		if seq.sequence and seq.sequence ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, {episode = seq.episode or "", sequence = seq.sequence})
		end
	end
	for _, shot in ipairs(data.shots or {}) do
		local key = (use_episodes and (shot.episode or "") or "") .. "|" .. (shot.sequence or "")
		if shot.sequence and shot.sequence ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, {episode = shot.episode or "", sequence = shot.sequence})
		end
	end
	return out
end

function Shots.add_episode(root, name)
	if not name or name == "" then return false, "Episode is required." end
	local data = Shots.load(root)
	data.episodes = data.episodes or {}
	for _, episode in ipairs(data.episodes) do
		if episode.name == name then return false, "Episode already exists." end
	end
	table.insert(data.episodes, {name = name, created = os.date("%Y-%m-%d %H:%M:%S")})
	return Shots.save(root, data)
end

function Shots.add_sequence(root, episode, sequence)
	if not sequence or sequence == "" then return false, "Sequence is required." end
	local data = Shots.load(root)
	data.sequences = data.sequences or {}
	for _, seq in ipairs(data.sequences) do
		if (seq.episode or "") == (episode or "") and seq.sequence == sequence then
			return false, "Sequence already exists."
		end
	end
	table.insert(data.sequences, {episode = episode or "", sequence = sequence, created = os.date("%Y-%m-%d %H:%M:%S")})
	Shots.save(root, data)
	return true
end

local function build_shot(name, owner, description, work_types, episode, sequence)
	local safe = Paths.safe_name(name)
	work_types = work_types or default_work_types
	local branches = {}
	for _, work_type in ipairs(work_types) do
		if work_type and work_type ~= "" then
			table.insert(branches, new_branch(work_type, "Default"))
		end
	end
	if #branches == 0 then
		table.insert(branches, new_branch("Animation", "Default"))
	end
	local shot = {
		id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
		kind = "shot",
		name = name,
		safe_name = safe,
		type = "Shot",
		episode = episode or "",
		sequence = sequence or "",
		owner = owner or "",
		created = os.date("%Y-%m-%d %H:%M:%S"),
		description = description or "",
		preview_path = "",
		latest_version = 0,
		workfiles = {},
		publishes = {},
		work_branches = branches
	}
	return shot
end

function Shots.create(root, name, owner, description, work_types, episode, sequence)
	local data = Shots.load(root)
	local shot = build_shot(name, owner, description, work_types, episode, sequence)
	table.insert(data.shots, shot)
	Shots.save(root, data)
	return shot
end

function Shots.create_cached(root, shots, name, owner, description, work_types, episode, sequence)
	local data = Shots.load(root)
	data.shots = shots or data.shots or {}
	local shot = build_shot(name, owner, description, work_types, episode, sequence)
	table.insert(data.shots, shot)
	Shots.save(root, data)
	return shot
end

function Shots.add_sequence_with_shots(root, episode, sequence, shot_count, work_types, owner)
	if not sequence or sequence == "" then return false, "Sequence is required." end
	shot_count = math.floor(tonumber(shot_count) or 0)
	if shot_count < 1 then return false, "Shot Count must be at least 1." end
	local data = Shots.load(root)
	data.sequences = data.sequences or {}
	for _, entry in ipairs(data.sequences) do
		if (entry.episode or "") == (episode or "") and entry.sequence == sequence then
			return false, "Sequence already exists."
		end
	end
	table.insert(data.sequences, {episode = episode or "", sequence = sequence, created = os.date("%Y-%m-%d %H:%M:%S")})
	local created = {}
	for index = 1, shot_count do
		local name = "SH0" .. tostring(index * 10)
		local shot = build_shot(name, owner, "", work_types or {"Layout"}, episode, sequence)
		shot.variant = "Default"
		table.insert(data.shots, shot)
		table.insert(created, shot)
	end
	Shots.save(root, data)
	return true, created
end

local function stored_shot(root, id)
	local data = Shots.load(root)
	for index, shot in ipairs(data.shots or {}) do
		if shot.id == id then return data, shot, index end
	end
	return data, nil, nil
end

function Shots.delete(root, id, session)
	local data, shot, index = stored_shot(root, id)
	if not shot then return false, "Shot was not found." end
	Recycle.move(root, shot_base_folder(root, shot), session)
	table.remove(data.shots, index)
	return Shots.save(root, data)
end

function Shots.delete_sequence(root, episode, sequence, session)
	if not sequence or sequence == "" then return false, "Sequence was not found." end
	local data = Shots.load(root)
	local kept, removed = {}, 0
	for _, shot in ipairs(data.shots or {}) do
		if (shot.episode or "") == (episode or "") and (shot.sequence or "") == sequence then
			removed = removed + 1
		else
			table.insert(kept, shot)
		end
	end
	local sequence_kept = {}
	for _, entry in ipairs(data.sequences or {}) do
		if (entry.episode or "") ~= (episode or "") or (entry.sequence or "") ~= sequence then
			table.insert(sequence_kept, entry)
		end
	end
	local folder = episode and episode ~= "" and Paths.join(root, "02_Scenes", Paths.safe_name(episode), Paths.safe_name(sequence)) or Paths.join(root, "02_Scenes", Paths.safe_name(sequence))
	Recycle.move(root, folder, session)
	data.shots = kept
	data.sequences = sequence_kept
	return Shots.save(root, data), removed
end

function Shots.delete_episode(root, episode, session)
	if not episode or episode == "" then return false, "Episode was not found." end
	local data = Shots.load(root)
	local kept_shots, kept_sequences, kept_episodes = {}, {}, {}
	local removed = 0
	for _, shot in ipairs(data.shots or {}) do
		if (shot.episode or "") == episode then
			removed = removed + 1
		else
			table.insert(kept_shots, shot)
		end
	end
	for _, entry in ipairs(data.sequences or {}) do
		if (entry.episode or "") ~= episode then
			table.insert(kept_sequences, entry)
		end
	end
	for _, entry in ipairs(data.episodes or {}) do
		if entry.name ~= episode then
			table.insert(kept_episodes, entry)
		end
	end
	Recycle.move(root, Paths.join(root, "02_Scenes", Paths.safe_name(episode)), session)
	data.shots = kept_shots
	data.sequences = kept_sequences
	data.episodes = kept_episodes
	return Shots.save(root, data), removed
end

function Shots.delete_work_type(root, id, work_type, session)
	local data, shot = stored_shot(root, id)
	if not shot then return false, "Shot was not found." end
	ensure_hierarchy(shot)
	local kept, removed = {}, false
	for _, branch in ipairs(shot.work_branches or {}) do
		if branch.work_type == work_type then removed = true else table.insert(kept, branch) end
	end
	if not removed then return false, "Work Type was not found." end
	Recycle.move(root, Paths.join(shot_base_folder(root, shot), Paths.safe_name(work_type)), session)
	shot.work_branches = kept
	return Shots.save(root, data)
end

function Shots.delete_work_item(root, id, branch_id, session)
	local data, shot = stored_shot(root, id)
	if not shot then return false, "Shot was not found." end
	ensure_hierarchy(shot)
	for index, branch in ipairs(shot.work_branches or {}) do
		if branch.id == branch_id then
			Recycle.move(root, Paths.join(shot_base_folder(root, shot), Paths.safe_name(branch.work_type), Paths.safe_name(branch.work_item or "Default")), session)
			table.remove(shot.work_branches, index)
			return Shots.save(root, data)
		end
	end
	return false, "Work Item was not found."
end

function Shots.branch(shot, branch_id)
	ensure_hierarchy(shot)
	if branch_id then
		for _, branch in ipairs(shot.work_branches or {}) do
			if branch.id == branch_id then return branch end
		end
	end
	return shot.work_branches and shot.work_branches[1] or nil
end

function Shots.branch_item(shot, branch)
	if not shot or not branch then return nil end
	return {
		id = shot.id,
		kind = "shot",
		name = shot.name,
		safe_name = shot.safe_name,
		type = "Shot",
		episode = shot.episode or "",
		sequence = shot.sequence or "",
		owner = shot.owner,
		created = shot.created,
		description = shot.description,
		work_type = branch.work_type,
		work_item = branch.work_item or "Default",
		latest_version = branch.latest_version or 0,
		version_counter = branch.version_counter or branch.latest_version or 0,
		workfiles = branch.workfiles or {},
		publishes = branch.publishes or {},
		live_publish = branch.live_publish,
		preview_path = branch.preview_path or shot.preview_path or "",
		_source_shot = shot,
		_source_branch = branch
	}
end

function Shots.sync_branch_item(item)
	local branch = item and item._source_branch
	local shot = item and item._source_shot
	if not branch then return item end
	branch.latest_version = item.latest_version or 0
	branch.version_counter = item.version_counter or branch.version_counter or branch.latest_version or 0
	branch.workfiles = item.workfiles or {}
	branch.publishes = item.publishes or {}
	branch.live_publish = item.live_publish
	branch.preview_path = item.preview_path or ""
	if shot then
		shot.preview_path = item.preview_path or shot.preview_path or ""
		shot.latest_version = item.latest_version or shot.latest_version or 0
		shot.version_counter = item.version_counter or shot.version_counter or shot.latest_version or 0
		shot.workfiles = item.workfiles or shot.workfiles or {}
		shot.publishes = item.publishes or shot.publishes or {}
		shot.live_publish = item.live_publish or shot.live_publish
	end
	return shot
end

function Shots.add_work_type(root, shot, work_type)
	if not shot or not work_type or work_type == "" then return false, "Work Type is required." end
	ensure_hierarchy(shot)
	for _, branch in ipairs(shot.work_branches or {}) do
		if branch.work_type == work_type and (branch.work_item or "Default") == "Default" then return false, "Work Type already exists." end
	end
	local branch = new_branch(work_type, "Default")
	table.insert(shot.work_branches, branch)
	return Shots.update(root, shot), branch
end

function Shots.add_work_item(root, shot, work_type, work_item)
	if not shot or not work_type or not work_item or work_item == "" then return false, "Work Item is required." end
	ensure_hierarchy(shot)
	for _, branch in ipairs(shot.work_branches or {}) do
		if branch.work_type == work_type and (branch.work_item or "Default") == work_item then
			return false, "Work Item already exists."
		end
	end
	local branch = new_branch(work_type, work_item)
	table.insert(shot.work_branches, branch)
	return Shots.update(root, shot), branch
end

function Shots.update(root, updated)
	updated = Shots.sync_branch_item(updated) or updated
	local data = Shots.load(root)
	for i, shot in ipairs(data.shots) do
		if shot.id == updated.id then
			data.shots[i] = updated
			Shots.save(root, data)
			return true
		end
	end
	return false
end

return Shots
