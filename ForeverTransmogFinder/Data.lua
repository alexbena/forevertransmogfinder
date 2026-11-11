local ADDON_NAME, ns = ...

local type, pairs, ipairs, next, tostring = type, pairs, ipairs, next, tostring
local floor, min, format, lower, find = math.floor, math.min, string.format, string.lower, string.find
local Read, IsSecret = ns.Read, ns.IsSecret

local Data = {}
ns.Data = Data

Data.state = "idle"
Data.error = nil
Data.faction = nil
Data.facCode = nil
Data.armor = nil
Data.CONTRACT = 2

local FAC_CODE = { Alliance = "A", Horde = "H" }
local FAC_NAME = { A = "Alliance", H = "Horde" }
Data.FAC_NAME = FAC_NAME

function Data.SetFaction(faction)
	if type(faction) == "string" and not IsSecret(faction) then
		Data.faction = faction
		Data.facCode = FAC_CODE[faction]
	else
		Data.faction, Data.facCode = nil, nil
	end
end

function Data.OtherFactionName()
	if Data.facCode == "A" then
		return "Horde"
	elseif Data.facCode == "H" then
		return "Alliance"
	end
	return nil
end

local EMPTY = {}
local D, items, src, zones, insts, encs
local ids, rank, byZone, byInst, byApp, bySrc = {}, {}, {}, {}, {}, {}
local zoneKeys, instKeys = {}, {}
local badRows = 0
local stats = { loadMs = 0, indexMs = 0, steps = 0 }
Data.stats = stats

local function Now()
	if type(debugprofilestop) == "function" then
		local ok, t = pcall(debugprofilestop)
		if ok and type(t) == "number" and not IsSecret(t) then
			return t
		end
	end
	return 0
end
Data.Now = Now

local function Str(v)
	if type(v) == "string" and not IsSecret(v) and v ~= "" then
		return v
	end
	return nil
end

local REASONS = {
	MISSING = "The item list (ForeverTransmogFinder_Data) is not installed. Put the ForeverTransmogFinder_Data folder next to ForeverTransmogFinder in Interface\\AddOns, then /reload.",
	DISABLED = "The item list (ForeverTransmogFinder_Data) is turned off in the AddOn list. Tick it there, then /reload.",
	INTERFACE_VERSION = "The item list (ForeverTransmogFinder_Data) is marked out of date for this client. Install the version that came with this addon.",
	CORRUPT = "The item list (ForeverTransmogFinder_Data) is damaged. Install it again.",
}

local function ReasonText(why)
	if type(why) == "string" and not IsSecret(why) then
		if REASONS[why] then
			return REASONS[why]
		end
		local g = _G["ADDON_" .. why]
		if type(g) == "string" and not IsSecret(g) then
			return "The item list (ForeverTransmogFinder_Data) could not load: " .. g .. "."
		end
		return "The item list (ForeverTransmogFinder_Data) could not load (" .. why .. ")."
	end
	return "The item list (ForeverTransmogFinder_Data) could not load."
end

local function Fail(msg)
	Data.state, Data.error = "error", msg
	ns.Debug("Data:", msg)
	ns.Fire("DATA_FAILED", msg)
	return false
end

local indexJob, RunIndexNow

function Data.Load(why, now)
	local st = Data.state
	if st == "ready" or st == "indexing" then
		return true
	end
	if st == "error" then
		return false
	end
	if ns.InCombat() then
		Data.waitingForCombat = true
		ns.RunOutOfCombat("dataLoad", function()
			Data.waitingForCombat = false
			Data.Load(why)
		end)
		ns.Fire("DATA_WAITING")
		return false
	end
	Data.state = "loading"
	local t0 = Now()
	local t = ForeverTransmogFinderData
	if type(t) ~= "table" then
		if not (C_AddOns and type(C_AddOns.LoadAddOn) == "function") then
			return Fail("This client has no C_AddOns.LoadAddOn, so the item list cannot load.")
		end
		local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, ns.DATA_ADDON)
		if not ok then
			return Fail("The item list (ForeverTransmogFinder_Data) raised an error while loading: " .. tostring(loaded))
		end
		if IsSecret(loaded) or not loaded then
			return Fail(ReasonText(reason))
		end
		t = ForeverTransmogFinderData
	end
	stats.loadMs = Now() - t0
	if type(t) ~= "table" or type(t.items) ~= "table" or type(t.src) ~= "table" then
		return Fail("The item list (ForeverTransmogFinder_Data) loaded but holds no items. Install the version that came with this addon.")
	end
	if type(t.version) ~= "number" or t.version < Data.CONTRACT then
		return Fail("The item list (ForeverTransmogFinder_Data) has an unknown format (version " .. tostring(t.version)
			.. "; this addon needs " .. Data.CONTRACT .. "). Install the version that came with this addon.")
	end
	if t.version > Data.CONTRACT then
		ns.Print("The item list is newer (format " .. t.version .. ") than this addon expects (" .. Data.CONTRACT .. "); update Forever Transmog Finder if something looks wrong.")
	end
	D, items, src = t, t.items, t.src
	zones = type(t.zones) == "table" and t.zones or {}
	insts = type(t.instances) == "table" and t.instances or {}
	encs = type(t.encounters) == "table" and t.encounters or {}
	Data.state = "indexing"
	ns.Debug(format("Data loaded in %.0f ms (%s).", stats.loadMs, tostring(why)))
	ns.Fire("DATA_LOADING")
	if now then
		RunIndexNow()
	else
		indexJob.Start(0)
	end
	return true
end

local WALK_PER_STEP, RUN, MERGE_BUDGET = 800, 1000, 5000
local phase, walkKey = "walk", nil
local runPos, width, mergeSrc, mergeDst, mergePos = 0, 0, nil, nil, 1
stats.maxStepMs = 0

local function AddTo(index, key, id)
	local list = index[key]
	if not list then
		list = {}
		index[key] = list
	end
	if list[#list] ~= id then
		list[#list + 1] = id
	end
end

local function IndexItem(id, row)
	if type(id) ~= "number" or type(row) ~= "table" or type(row[1]) ~= "string" then
		badRows = badRows + 1
		return
	end
	ids[#ids + 1] = id
	local s, a = row[8], row[7]
	if type(s) == "number" then
		bySrc[s] = id
	end
	if type(a) == "number" then
		local cur = byApp[a]
		if cur == nil then
			byApp[a] = id
		elseif type(cur) == "number" then
			byApp[a] = { cur, id }
		else
			cur[#cur + 1] = id
		end
	end
	local list = src[id]
	if type(list) == "table" then
		for i = 1, #list do
			local e = list[i]
			if type(e) == "table" then
				local w = e[2]
				if type(w) == "number" then
					if w ~= 0 then
						AddTo(byZone, w, id)
					end
				elseif type(w) == "string" then
					AddTo(byInst, w, id)
				end
			end
		end
	end
end

local function ByName(a, b)
	local na, nb = items[a][1], items[b][1]
	if na == nb then
		return a < b
	end
	return na < nb
end
Data.ByName = ByName

local function SortRun(lo, hi)
	local tmp = {}
	for i = lo, hi do
		tmp[#tmp + 1] = ids[i]
	end
	table.sort(tmp, ByName)
	for i = 1, #tmp do
		ids[lo + i - 1] = tmp[i]
	end
end

local function MergePair(from, to, lo, mid, hi)
	local i, j, k = lo, mid, lo
	while i < mid and j < hi do
		local a, b = from[i], from[j]
		if ByName(b, a) then
			to[k] = b
			j = j + 1
		else
			to[k] = a
			i = i + 1
		end
		k = k + 1
	end
	while i < mid do
		to[k] = from[i]
		i, k = i + 1, k + 1
	end
	while j < hi do
		to[k] = from[j]
		j, k = j + 1, k + 1
	end
end

local function IndexStep()
	local t0 = Now()
	stats.steps = stats.steps + 1
	local n = #ids
	if phase == "walk" then
		local key = walkKey
		for _ = 1, WALK_PER_STEP do
			local row
			key, row = next(items, key)
			if key == nil then
				phase, runPos = "runs", 0
				break
			end
			IndexItem(key, row)
		end
		walkKey = key
	elseif phase == "runs" then
		if runPos < n then
			local hi = min(runPos + RUN, n)
			SortRun(runPos + 1, hi)
			runPos = hi
		end
		if runPos >= n then
			phase, width, mergeSrc, mergeDst, mergePos = "merge", RUN, ids, {}, 1
			if width >= n then
				phase = "finish"
			end
		end
	elseif phase == "merge" then
		local moved = 0
		while moved < MERGE_BUDGET do
			if mergePos > n then
				mergeSrc, mergeDst = mergeDst, mergeSrc
				width, mergePos = width * 2, 1
				if width >= n then
					phase = "finish"
					break
				end
			end
			local lo = mergePos
			local mid = min(lo + width, n + 1)
			local hi = min(lo + 2 * width, n + 1)
			MergePair(mergeSrc, mergeDst, lo, mid, hi)
			moved = moved + (hi - lo)
			mergePos = hi
		end
	else
		if mergeSrc and mergeSrc ~= ids then
			for i = 1, n do
				ids[i] = mergeSrc[i]
			end
		end
		mergeSrc, mergeDst = nil, nil
		for i = 1, n do
			rank[ids[i]] = i
		end
		for k in pairs(byZone) do
			zoneKeys[#zoneKeys + 1] = k
		end
		for k in pairs(byInst) do
			instKeys[#instKeys + 1] = k
		end
		stats.indexMs = stats.indexMs + (Now() - t0)
		return true
	end
	local d = Now() - t0
	stats.indexMs = stats.indexMs + d
	if d > stats.maxStepMs then
		stats.maxStepMs = d
	end
	return false
end

local function IndexDone()
	Data.state = "ready"
	if badRows > 0 then
		ns.Debug("Data: skipped " .. badRows .. " malformed item rows.")
	end
	ns.Debug(format("Indexes built: %d items, %d zones, %d instances, %.0f ms over %d steps.", #ids, #zoneKeys,
		#instKeys, stats.indexMs, stats.steps))
	ns.Fire("DATA_READY")
end

indexJob = ns.NewJob("index", IndexStep, 0.05, true)
indexJob.onDone = IndexDone
Data.indexJob = indexJob

RunIndexNow = function()
	for _ = 1, 100000 do
		if IndexStep() then
			break
		end
	end
	IndexDone()
end

function Data.Ready()
	return Data.state == "ready"
end

function Data.Raw()
	return D
end

function Data.Count()
	return #ids
end

function Data.BadRows()
	return badRows
end

function Data.IDs()
	return ids
end

function Data.Rank(id)
	return rank[id] or 0
end

function Data.Item(id)
	return items and items[id]
end

function Data.Sources(id)
	return (src and src[id]) or EMPTY
end

function Data.ZoneKeys()
	return zoneKeys
end

function Data.InstKeys()
	return instKeys
end

function Data.ZoneCount()
	return #zoneKeys
end

function Data.InstCount()
	return #instKeys
end

function Data.ZoneItems(ui)
	return byZone[ui] or EMPTY
end

function Data.InstItems(key)
	return byInst[key] or EMPTY
end

function Data.InstInfo(key)
	return insts and insts[key]
end

local encIndex = {}
function Data.EncounterIndex(key)
	local idx = encIndex[key]
	if idx ~= nil then
		return idx or nil
	end
	local list = encs and encs[key]
	if type(list) == "table" then
		idx = {}
		for i = 1, #list do
			local name = list[i]
			if type(name) == "string" and idx[name] == nil then
				idx[name] = i
			end
		end
	end
	encIndex[key] = idx or false
	return idx
end

function Data.ItemBySource(sourceID)
	return bySrc[sourceID]
end

function Data.ForAppearance(app, fn)
	local v = byApp[app]
	if type(v) == "number" then
		fn(v)
	elseif type(v) == "table" then
		for i = 1, #v do
			fn(v[i])
		end
	end
end

local zoneNames = {}

function Data.ZoneName(ui)
	local n = zoneNames[ui]
	if n then
		return n
	end
	local info = C_Map and Read(C_Map.GetMapInfo, ui)
	n = type(info) == "table" and Str(info.name) or (zones and Str(zones[ui])) or ("map " .. tostring(ui))
	zoneNames[ui] = n
	return n
end

function Data.InstName(key)
	local info = insts and insts[key]
	return (info and Str(info[1])) or tostring(key)
end

function Data.PlaceName(where)
	if type(where) == "number" then
		return Data.ZoneName(where)
	end
	return Data.InstName(where)
end

local function Coord(v)
	return floor(v + 0.5)
end

function Data.PlaceText(where, x, y)
	if type(where) == "number" then
		if where == 0 then
			return nil
		end
		local name = Data.ZoneName(where)
		if type(x) == "number" and type(y) == "number" then
			return format("%s %d,%d", name, Coord(x), Coord(y))
		end
		return name
	elseif type(where) == "string" then
		return Data.InstName(where)
	end
	return nil
end

local UIMAP_ZONE = 3

function Data.CurrentPlace()
	local inInstance, instanceType = Read(IsInInstance)
	if inInstance == true and (instanceType == "party" or instanceType == "raid") then
		local name, _, _, _, _, _, _, mapID = Read(GetInstanceInfo)
		if type(mapID) == "number" then
			local key = "i" .. mapID
			local info = insts and insts[key]
			return { kind = "inst", key = key, name = (info and Str(info[1])) or Str(name) or key, listed = byInst[key] ~= nil }
		end
	end
	if not (C_Map and C_Map.GetBestMapForUnit) then
		return nil
	end
	local ui = Read(C_Map.GetBestMapForUnit, "player")
	local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or UIMAP_ZONE
	for _ = 1, 6 do
		if type(ui) ~= "number" or ui == 0 then
			break
		end
		if byZone[ui] or (zones and zones[ui]) then
			break
		end
		local info = Read(C_Map.GetMapInfo, ui)
		if type(info) ~= "table" or type(info.mapType) ~= "number" or IsSecret(info.mapType) or info.mapType <= zoneType then
			break
		end
		local parent = info.parentMapID
		if type(parent) ~= "number" or IsSecret(parent) or parent == 0 then
			break
		end
		ui = parent
	end
	if type(ui) == "number" and ui ~= 0 then
		return { kind = "zone", key = ui, name = Data.ZoneName(ui), listed = byZone[ui] ~= nil }
	end
	return nil
end

Data.KIND_WORD = { "Boss", "Drop", "Quest", "Vendor", "Crafted", "Container", "World drop" }
local KIND_WORD = Data.KIND_WORD

local GENERIC = { ["World drop"] = true, ["Vendor"] = true, ["Quest reward"] = true, ["Boss drop"] = true,
	["Profession"] = true, ["Achievement"] = true }

local function OtherSource(e)
	if Data.facCode == nil or type(e) ~= "table" then
		return false
	end
	local f = e[7]
	return (f == "A" or f == "H") and f ~= Data.facCode
end
Data.OtherSource = OtherSource

local function FacSuffix(e)
	local f = type(e) == "table" and e[7]
	local name = (f == "A" or f == "H") and FAC_NAME[f]
	return name and (" (" .. name .. ")") or ""
end
Data.FacSuffix = FacSuffix

function Data.Chance(e)
	if type(e) == "table" and (e[1] == 1 or e[1] == 2) and type(e[6]) == "number" and e[6] > 0 then
		return e[6]
	end
	return nil
end

function Data.BestChance(id)
	local list = src and src[id]
	local best
	if type(list) == "table" then
		for i = 1, #list do
			local c = Data.Chance(list[i])
			if c and (not best or c > best) then
				best = c
			end
		end
	end
	return best
end

local function ChanceText(c)
	if c >= 10 then
		return format("%d%%", floor(c + 0.5))
	end
	return format("%.1f%%", c)
end
Data.ChanceText = ChanceText

function Data.SourceText(e, here, short)
	if type(e) ~= "table" then
		return "Source unknown"
	end
	local kind, where, label, x, y, extra = e[1], e[2], e[3], e[4], e[5], e[6]
	label = Str(label) or "?"
	if where == 0 and GENERIC[label] then
		local text = label
		if kind == 4 and Str(extra) then
			text = text .. ns.DOT .. extra
		end
		if kind ~= 7 then
			text = text .. " (place unknown)"
		end
		return text
	end
	label = label .. FacSuffix(e)
	local text
	local chance = Data.Chance(e)
	if short then
		text = label
		if chance then
			text = text .. " (" .. ChanceText(chance) .. ")"
		elseif kind == 5 and type(extra) == "number" and extra > 1 then
			text = text .. format(" (yellow at %d)", extra)
		end
	elseif kind == 7 then
		text = label
	elseif kind == 2 and chance then
		text = format("Drop %s: %s", ChanceText(chance), label)
	elseif kind == 5 then
		text = "Crafted: " .. label
		if type(extra) == "number" and extra > 1 then
			text = text .. format(" (yellow at %d)", extra)
		end
	else
		text = (KIND_WORD[kind] or "Source") .. ": " .. label
		if chance then
			text = text .. " (" .. ChanceText(chance) .. ")"
		end
	end
	local place
	if here ~= nil and where == here then
		if type(x) == "number" and type(y) == "number" then
			place = format("%d,%d", Coord(x), Coord(y))
		end
	else
		place = Data.PlaceText(where, x, y)
	end
	if place then
		text = text .. ns.DOT .. place
	end
	if kind == 4 and Str(extra) then
		text = text .. ns.DOT .. extra
	end
	return text
end

function Data.SourceLabel(e)
	if type(e) ~= "table" then
		return "Source unknown"
	end
	local label = (Str(e[3]) or "?") .. FacSuffix(e)
	local chance = Data.Chance(e)
	if chance then
		return label .. " (" .. ChanceText(chance) .. ")"
	end
	if e[1] == 5 and type(e[6]) == "number" and e[6] > 1 then
		return label .. format(" (yellow at %d)", e[6])
	end
	return label
end

function Data.BestIndex(id, where)
	local list = src and src[id]
	if type(list) ~= "table" then
		return nil
	end
	local first
	for i = 1, #list do
		local e = list[i]
		if type(e) == "table" and (where == nil or e[2] == where) then
			first = first or i
			if not OtherSource(e) then
				return i
			end
		end
	end
	return first
end

function Data.OwnAt(id, where)
	local list = src and src[id]
	if type(list) ~= "table" then
		return false
	end
	for i = 1, #list do
		local e = list[i]
		if type(e) == "table" and e[2] == where and not OtherSource(e) then
			return true
		end
	end
	return false
end

function Data.SourceOrder(id)
	local list = src and src[id]
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	local later
	for i = 1, #list do
		if OtherSource(list[i]) then
			later = later or {}
			later[#later + 1] = i
		else
			out[#out + 1] = i
		end
	end
	if later then
		for i = 1, #later do
			out[#out + 1] = later[i]
		end
	end
	return out
end

function Data.BestText(id)
	local i = Data.BestIndex(id)
	if not i then
		return nil
	end
	return Data.SourceText(src[id][i])
end

function Data.PinTarget(e)
	if type(e) ~= "table" then
		return nil, "no source"
	end
	local where, x, y = e[2], e[4], e[5]
	if type(where) == "number" and where ~= 0 then
		if type(x) == "number" and type(y) == "number" then
			return where, x, y, Data.PlaceText(where, x, y)
		end
		return nil, "somewhere in " .. Data.ZoneName(where) .. " (no exact spot known)"
	elseif type(where) == "string" then
		local info = insts and insts[where]
		if info and type(info[5]) == "number" and info[5] ~= 0 and type(info[6]) == "number" and type(info[7]) == "number" then
			return info[5], info[6], info[7], Data.InstName(where) .. " entrance, " .. Data.PlaceText(info[5], info[6], info[7])
		end
		return nil, Data.InstName(where) .. " (its entrance is not in the item list)"
	end
	return nil, "no place known for this source"
end

function Data.PinIndex(id, ownOnly)
	local list = src and src[id]
	if type(list) ~= "table" then
		return nil
	end
	local first
	for i = 1, #list do
		if Data.PinTarget(list[i]) then
			first = first or i
			if not OtherSource(list[i]) then
				return i
			end
		end
	end
	if ownOnly then
		return nil
	end
	return first
end

function Data.OtherFaction(id)
	if Data.facCode == nil then
		return false
	end
	local list = src and src[id]
	if type(list) ~= "table" or #list == 0 then
		return false
	end
	for i = 1, #list do
		if not OtherSource(list[i]) then
			return false
		end
	end
	return true
end

local function PlainNum(v)
	if type(v) == "number" and not IsSecret(v) and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return nil
end

function Data.PlayerPos(ui)
	if type(ui) ~= "number" or not (C_Map and C_Map.GetPlayerMapPosition) then
		return nil
	end
	local ok, v = pcall(C_Map.GetPlayerMapPosition, ui, "player")
	if not ok or IsSecret(v) or type(v) ~= "table" then
		return nil
	end
	local getXY = v.GetXY
	if type(getXY) ~= "function" then
		return nil
	end
	local ok2, x, y = pcall(getXY, v)
	x, y = PlainNum(x), PlainNum(y)
	if not (ok2 and x and y) or (x == 0 and y == 0) then
		return nil
	end
	return x, y
end

local mapYards = {}
function Data.MapYards(ui)
	local c = mapYards[ui]
	if c then
		return c[1], c[2]
	end
	if type(ui) ~= "number" or not (C_Map and C_Map.GetMapWorldSize) then
		return nil
	end
	local w, h = Read(C_Map.GetMapWorldSize, ui)
	w, h = PlainNum(w), PlainNum(h)
	if not (w and h and w > 0 and h > 0) then
		return nil
	end
	mapYards[ui] = { w, h }
	return w, h
end

function Data.SourceYards(e, ui, px, py, w, h)
	if type(e) ~= "table" or e[2] ~= ui or type(e[4]) ~= "number" or type(e[5]) ~= "number" then
		return nil
	end
	local dx, dy = (e[4] / 100 - px) * w, (e[5] / 100 - py) * h
	return math.sqrt(dx * dx + dy * dy)
end

function Data.NearestYards(id, ui, px, py, w, h)
	local list = src and src[id]
	if type(list) ~= "table" then
		return nil
	end
	local best, bestI, anyBest, anyI
	for i = 1, #list do
		local d = Data.SourceYards(list[i], ui, px, py, w, h)
		if d then
			if not anyBest or d < anyBest then
				anyBest, anyI = d, i
			end
			if not OtherSource(list[i]) and (not best or d < best) then
				best, bestI = d, i
			end
		end
	end
	if best then
		return best, bestI
	end
	return anyBest, anyI
end

function Data.YardsText(d)
	if type(d) ~= "number" then
		return ""
	end
	return format("~%d yd", math.max(10, floor(d / 10 + 0.5) * 10))
end

local qualityCache = {}

function Data.Name(id)
	local row = items and items[id]
	return (row and row[1]) or ("item " .. tostring(id))
end

function Data.Quality(id)
	local row = items and items[id]
	local q = row and row[5]
	if type(q) == "number" and q >= 0 then
		return q
	end
	q = qualityCache[id]
	if q then
		return q
	end
	q = C_Item and Read(C_Item.GetItemQualityByID, id)
	if type(q) == "number" then
		qualityCache[id] = q
		return q
	end
	return nil
end

local QUALITY_RGB = {
	[0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

function Data.QualityColor(q)
	local c = type(q) == "number" and QUALITY_RGB[q]
	if c then
		return c[1], c[2], c[3]
	end
	return 1, 1, 1
end

function Data.Icon(id)
	if not (C_Item and C_Item.GetItemInfoInstant) then
		return nil
	end
	local _, _, _, _, icon = Read(C_Item.GetItemInfoInstant, id)
	return icon
end

function Data.Link(id)
	if C_Item and C_Item.GetItemInfo then
		local _, link = Read(C_Item.GetItemInfo, id)
		if Str(link) then
			return link
		end
		if C_Item.RequestLoadItemDataByID then
			Read(C_Item.RequestLoadItemDataByID, id)
		end
	end
	return nil
end

local INV_NAME = { [1] = "Head", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
	[9] = "Wrist", [10] = "Hands", [13] = "One-hand", [14] = "Shield", [15] = "Ranged", [16] = "Back", [17] = "Two-hand",
	[19] = "Tabard", [20] = "Chest", [21] = "Main hand", [22] = "Off hand", [23] = "Held in off hand", [25] = "Thrown",
	[26] = "Ranged" }
local ARMOR_SUB = { [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate" }
local WEAPON_SUB = { [0] = "Axe", [1] = "Axe", [2] = "Bow", [3] = "Gun", [4] = "Mace", [5] = "Mace", [6] = "Polearm",
	[7] = "Sword", [8] = "Sword", [10] = "Staff", [13] = "Fist weapon", [15] = "Dagger", [16] = "Thrown",
	[18] = "Crossbow", [19] = "Wand", [20] = "Fishing pole" }
local subNames = {}

local function SubName(classID, subID)
	if type(classID) ~= "number" or type(subID) ~= "number" then
		return nil
	end
	local key = classID * 1000 + subID
	local n = subNames[key]
	if n ~= nil then
		return n or nil
	end
	if classID == 2 then
		n = WEAPON_SUB[subID]
	elseif classID == 4 then
		n = ARMOR_SUB[subID]
	end
	if n == nil and C_Item and C_Item.GetItemSubClassInfo and classID == 2 then
		n = Str((Read(C_Item.GetItemSubClassInfo, classID, subID)))
	end
	subNames[key] = n or false
	return n
end

function Data.TypeText(id)
	local row = items and items[id]
	if not row then
		return ""
	end
	local slot = INV_NAME[row[2]] or "Other"
	local sub = SubName(row[3], row[4])
	if sub and sub ~= slot then
		return slot .. ns.DOT .. sub
	end
	return slot
end

function Data.SlotKey(id)
	local row = items and items[id]
	return row and ns.SLOT_OF_INV[row[2]] or nil
end

local INV_BACK = 16
function Data.ArmorSub(id)
	local row = items and items[id]
	if row and row[3] == 4 and row[2] ~= INV_BACK and type(row[4]) == "number" and row[4] >= 1 and row[4] <= 4 then
		return row[4]
	end
	return nil
end

Data.ARMOR_NAME = { "Cloth", "Leather", "Mail", "Plate" }

function Data.NotMyArmor(id)
	local sub = Data.ArmorSub(id)
	return sub ~= nil and Data.armor ~= nil and sub ~= Data.armor
end

local lowerNames = {}
function Data.Matches(id, q)
	local ln = lowerNames[id]
	if not ln then
		ln = lower(Data.Name(id))
		lowerNames[id] = ln
	end
	if find(ln, q, 1, true) then
		return true
	end
	local list = src and src[id]
	if type(list) == "table" then
		for i = 1, #list do
			local e = list[i]
			local l = type(e) == "table" and e[3]
			if type(l) == "string" and find(lower(l), q, 1, true) then
				return true
			end
		end
	end
	return false
end

local CLASS_ARMOR = { WARRIOR = 4, PALADIN = 4, DEATHKNIGHT = 4, HUNTER = 3, SHAMAN = 3, EVOKER = 3, ROGUE = 2,
	DRUID = 2, MONK = 2, DEMONHUNTER = 2, MAGE = 1, PRIEST = 1, WARLOCK = 1 }
Data.CLASS_ARMOR = CLASS_ARMOR

ns.Listen("LOGIN", function()
	Data.SetFaction((Read(UnitFactionGroup, "player")))
	local _, classFile = Read(UnitClass, "player")
	if type(classFile) == "string" then
		Data.armor = CLASS_ARMOR[classFile]
	end
end)

local loginDone = false
ns.Listen("LOGIN_DONE", function()
	loginDone = true
	if ns.db and ns.db.preload and ns.Mog.On() and Data.state == "idle" then
		Data.Load("login", true)
	end
end)

ns.Listen("AVAILABILITY_CHANGED", function(_, on)
	if loginDone and on ~= false and ns.db and ns.db.preload and Data.state == "idle" then
		Data.Load("transmog on")
	end
end)

function Data.Builds()
	local dataBuild
	if D and type(D.build) == "string" then
		dataBuild = tonumber(string.match(D.build, "(%d+)$"))
	end
	local v, b = Read(GetBuildInfo)
	local clientBuild
	if type(b) == "string" or type(b) == "number" then
		clientBuild = tonumber(b)
	end
	local clientText = clientBuild and ((type(v) == "string" and v ~= "" and (v .. ".") or "") .. clientBuild) or nil
	return dataBuild, clientBuild, clientText
end

function Data.OutdatedText()
	local dataBuild, clientBuild, clientText = Data.Builds()
	if not (dataBuild and clientBuild) or clientBuild <= dataBuild then
		return nil
	end
	return "The item list was made for " .. tostring(D.build) .. "; this client is " .. tostring(clientText)
		.. ". Items from later patches are missing; item tooltips still work."
end

local outdatedSaid = false
ns.Listen("DATA_READY", function()
	local text = Data.OutdatedText()
	if text and not outdatedSaid then
		outdatedSaid = true
		ns.Print(text)
	end
end)
