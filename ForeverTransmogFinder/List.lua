local ADDON_NAME, ns = ...

local type, ipairs, pairs, sort, lower, find, floor = type, ipairs, pairs, table.sort, string.lower, string.find, math.floor
local Data, Mog = ns.Data, ns.Mog
local ST = Mog.ST

local List = {}
ns.List = List

local SMALL_LIST = 400

local ORDER = { [ST.MISSING] = 1, [ST.PENDING] = 2, [ST.UNKNOWN] = 2, [ST.KNOWN] = 3, [ST.EXACT] = 3, [ST.CANT] = 4 }
List.ORDER = ORDER

local SLOT_INV, SLOT_POS = {}, {}
for i, s in ipairs(ns.SLOTS) do
	SLOT_POS[s.key] = i
	if s.inv then
		local set = {}
		for _, inv in ipairs(s.inv) do
			set[inv] = true
		end
		SLOT_INV[s.key] = set
	end
end

local function Query(text)
	if type(text) ~= "string" then
		return nil
	end
	text = lower(text)
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then
		return nil
	end
	return text
end
List.Query = Query

local function Context(f, search)
	local on = Mog.On()
	local c = {
		on = on,
		slotInv = SLOT_INV[f.slot],
		armorOnly = f.armorOnly == true,
		myArmor = Data.armor,
		showCollected = f.showCollected == true,
		minQ = f.minQuality or 0,
		lmin = f.levelMin or 1,
		lmax = f.levelMax or ns.MAX_LEVEL,
		q = Query(search),
		sort = ns.SORT_LABEL[f.sort] and f.sort or "source",
	}
	c.statusFirst = on and not c.showCollected
	return c
end
List.Context = Context

local function PassBase(id, c, now)
	local row = Data.Item(id)
	if not row then
		return false
	end
	if c.slotInv and not c.slotInv[row[2]] then
		return false
	end
	local lvl = row[6]
	if type(lvl) == "number" then
		if lvl < 1 then
			lvl = 1
		end
		if lvl < c.lmin or lvl > c.lmax then
			return false
		end
	end
	if c.minQ > 0 then
		local q = Data.Quality(id)
		if q and q < c.minQ then
			return false
		end
	end
	if c.armorOnly and c.myArmor then
		local sub = Data.ArmorSub(id)
		if sub and sub ~= c.myArmor then
			return false
		end
	end
	if not c.on then
		return true, ST.UNKNOWN
	end
	local st = Mog.StatusOf(id, now)
	if st == ST.CANT and c.armorOnly then
		return false, st
	end
	return true, st
end
List.PassBase = PassBase

local function PassView(id, c, now)
	local ok, st = PassBase(id, c, now)
	if not ok then
		return false, st
	end
	if c.on and not c.showCollected and Mog.IsCollected(st) then
		return false, st
	end
	if c.q and not Data.Matches(id, c.q) then
		return false, st
	end
	return true, st
end
List.PassView = PassView

local function StableBy(ids, keyOf)
	local buckets, keys = {}, {}
	for i = 1, #ids do
		local id = ids[i]
		local k = keyOf(id)
		local b = buckets[k]
		if not b then
			b = {}
			buckets[k] = b
			keys[#keys + 1] = k
		end
		b[#b + 1] = id
	end
	if #keys <= 1 then
		return ids
	end
	sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		local b = buckets[k]
		for i = 1, #b do
			out[#out + 1] = b[i]
		end
	end
	return out
end
List.StableBy = StableBy

local function KeyFn(c, stOf, dist)
	local s = c.sort
	return function(id)
		local k = 0
		if c.statusFirst then
			k = (ORDER[stOf[id]] or 2) * 1000000
		end
		if dist then
			local d = dist[id]
			k = k + (d and math.min(999998, floor(d)) or 999999)
		elseif s == "level" then
			local row = Data.Item(id)
			local l = row and row[6]
			k = k + ((type(l) == "number" and l > 0) and l or 0)
		elseif s == "chance" then
			local ch = Data.BestChance(id)
			k = k + (ch and (100000 - floor(ch * 100)) or 100001)
		end
		return k
	end
end

local function ByRank(a, b)
	return Data.Rank(a) < Data.Rank(b)
end

local INST_GROUP = {
	[2] = { "Trash and other mobs", 1000 }, [3] = { "Quests", 1001 }, [4] = { "Vendors", 1002 },
	[6] = { "Chests and objects", 1003 }, [5] = { "Crafted", 1004 }, [7] = { "Other", 1005 },
}
local ZONE_GROUP = {
	[3] = { "Quest rewards", 1 }, [4] = { "Vendors", 2 }, [2] = { "Mob drops", 3 }, [1] = { "Bosses and rare elites", 4 },
	[6] = { "Chests and objects", 5 }, [5] = { "Crafted", 6 }, [7] = { "World drops", 7 },
}
local ALL_GROUP = {
	[1] = { "Boss drops", 1 }, [3] = { "Quest rewards", 2 }, [4] = { "Vendors", 3 }, [2] = { "Mob drops", 4 },
	[6] = { "Chests and objects", 5 }, [5] = { "Crafted", 6 }, [7] = { "World drops", 7 },
}
local KIND_KEY = {}
for k = 1, 7 do
	KIND_KEY[k] = "k:" .. k
end
local OTHER = { "Other", 1005 }

local function BestEntry(id, where)
	local si = Data.BestIndex(id, where)
	return si and Data.Sources(id)[si]
end

local function KindOf(e)
	local k = type(e) == "table" and e[1]
	if type(k) ~= "number" or not KIND_KEY[k] then
		return 7
	end
	return k
end

local function PlaceGroup(kind, key)
	local groups = kind == "inst" and INST_GROUP or ZONE_GROUP
	return function(id)
		local e = BestEntry(id, key)
		local k = KindOf(e)
		if kind == "inst" and k == 1 then
			local name = type(e[3]) == "string" and e[3] or "Boss"
			return "b:" .. name, name, nil
		end
		local g = groups[k] or OTHER
		return KIND_KEY[k], g[1], g[2]
	end
end

local allKind = {}
local function AllGroup(id)
	local k = allKind[id]
	if not k then
		k = KindOf(BestEntry(id))
		allKind[id] = k
	end
	local g = ALL_GROUP[k]
	return KIND_KEY[k], g[1], g[2]
end

local function WishGroup(id)
	local e = BestEntry(id)
	local w = type(e) == "table" and e[2]
	if type(w) == "string" then
		return "p:" .. w, Data.InstName(w), 10
	elseif type(w) == "number" and w ~= 0 then
		return "z:" .. w, Data.ZoneName(w), 10
	end
	local k = KindOf(e)
	local g = ALL_GROUP[k]
	return KIND_KEY[k], g[1], 1000 + g[2]
end

local function SlotGroup(id)
	local s = Data.SlotKey(id) or "OTHER"
	return "s:" .. s, ns.SLOT_LABEL[s] or "Other", SLOT_POS[s] or 99
end

local function Build(c, ids, groupFn, now, opts)
	opts = opts or {}
	local where = opts.where
	local groups, glist, flat, stOf = {}, {}, {}, {}
	local shown, missing, passed = 0, 0, 0
	for i = 1, #ids do
		local id = ids[i]
		local ok, st = PassBase(id, c, now)
		if ok then
			passed = passed + 1
			local collected = c.on and Mog.IsCollected(st)
			local show = (not c.on or c.showCollected or not collected) and (not c.q or Data.Matches(id, c.q))
			local counted = where == nil or Data.OwnAt(id, where)
			if groupFn then
				local gk, gname, gorder, gplain = groupFn(id)
				local g = groups[gk]
				if not g then
					g = { key = gk, name = gname, order = gorder, plain = gplain, ids = {}, have = 0, total = 0, missing = 0,
						levels = 0, n = 0 }
					groups[gk] = g
					glist[#glist + 1] = g
				end
				g.n = g.n + 1
				if counted then
					g.total = g.total + 1
					if collected then
						g.have = g.have + 1
					end
					if st == ST.MISSING then
						g.missing = g.missing + 1
					end
				end
				local lvl = Data.Item(id)[6]
				g.levels = g.levels + (type(lvl) == "number" and lvl or 0)
				if show then
					g.ids[#g.ids + 1] = id
				end
			elseif show then
				flat[#flat + 1] = id
			end
			if show then
				stOf[id] = st
				shown = shown + 1
				if st == ST.MISSING and counted then
					missing = missing + 1
				end
			end
		end
	end
	local lines
	if groupFn then
		local enc = opts.enc
		for _, g in ipairs(glist) do
			if not g.order then
				local pos = enc and enc[g.name]
				g.order = pos or (100 + g.levels / g.n)
			end
		end
		sort(glist, function(a, b)
			if a.order ~= b.order then
				return a.order < b.order
			end
			return a.name < b.name
		end)
		lines = {}
		local key = KeyFn(c, stOf)
		for _, g in ipairs(glist) do
			if #g.ids > 0 then
				lines[#lines + 1] = { t = "head", text = g.name, have = g.have, total = g.total, missing = g.missing, on = c.on,
					plain = g.plain or (where ~= nil and g.total == 0) }
				local ordered = StableBy(g.ids, g.key == "near" and KeyFn(c, stOf, opts.dist) or key)
				for i = 1, #ordered do
					lines[#lines + 1] = ordered[i]
				end
			end
		end
	else
		lines = StableBy(flat, KeyFn(c, stOf))
	end
	return { lines = lines, shown = shown, missing = missing, hasItems = shown > 0, passed = passed }
end

local function GroupFor(c, sourceFn)
	if c.sort == "source" then
		return sourceFn
	elseif c.sort == "slot" then
		return SlotGroup
	end
	return nil
end

function List.All(f, search)
	local c = Context(f, search)
	return Build(c, Data.IDs(), GroupFor(c, AllGroup), false)
end

function List.PlaceItems(kind, key)
	if kind == "inst" then
		return Data.InstItems(key)
	end
	return Data.ZoneItems(key)
end

local sortedPlace = {}
local function SortedPlace(kind, key)
	local s = sortedPlace[key]
	if s then
		return s
	end
	local ids = List.PlaceItems(kind, key)
	s = {}
	for i = 1, #ids do
		s[i] = ids[i]
	end
	sort(s, ByRank)
	if Data.Ready() then
		sortedPlace[key] = s
	end
	return s
end

List.FAC_ORDER = 3000
function List.Place(kind, key, f, search, dist)
	local c = Context(f, search)
	local ids = SortedPlace(kind, key)
	local groupFn = GroupFor(c, PlaceGroup(kind, key))
	if c.sort == "source" then
		local base = groupFn
		local other = Data.OtherFactionName()
		local facName = other and (other .. " only")
		groupFn = function(id)
			if facName and not Data.OwnAt(id, key) then
				return "fac", facName, List.FAC_ORDER, true
			end
			if dist and dist[id] then
				return "near", "Nearest first", 0
			end
			return base(id)
		end
	end
	local res = Build(c, ids, groupFn, #ids <= SMALL_LIST,
		{ enc = kind == "inst" and Data.EncounterIndex(key) or nil, dist = dist, where = key })
	res.where = key
	return res
end

function List.Distances(ui, px, py)
	local w, h = Data.MapYards(ui)
	if not w then
		return nil
	end
	local out, n = {}, 0
	local ids = Data.ZoneItems(ui)
	for i = 1, #ids do
		local d = Data.NearestYards(ids[i], ui, px, py, w, h)
		if d then
			out[ids[i]] = d
			n = n + 1
		end
	end
	return n > 0 and out or nil
end

local WISH_FILTERS = { slot = "ALL", armorOnly = false, minQuality = 0, showCollected = true, levelMin = 1,
	levelMax = 60 }

function List.Wish(f, search)
	WISH_FILTERS.sort = f.sort
	WISH_FILTERS.levelMax = ns.MAX_LEVEL
	local c = Context(WISH_FILTERS, search)
	c.statusFirst = c.on
	local ids = {}
	for _, id in ipairs(ns.Wish.IDs()) do
		if Data.Item(id) then
			ids[#ids + 1] = id
		end
	end
	sort(ids, ByRank)
	local res = Build(c, ids, GroupFor(c, WishGroup), true)
	res.wishCount = #ids
	return res
end

function List.WishAt(kind, key)
	local out = {}
	for _, id in ipairs(ns.Wish.IDs()) do
		if Data.Item(id) and not Mog.IsCollected(Mog.StatusOf(id, true)) and Data.OwnAt(id, key) then
			out[#out + 1] = id
		end
	end
	sort(out, ByRank)
	return out
end

function List.Places(kind, f)
	local c = Context(f)
	local keys = kind == "inst" and Data.InstKeys() or Data.ZoneKeys()
	local lines = {}
	for _, key in ipairs(keys) do
		local ids = List.PlaceItems(kind, key)
		local total, missing, have = 0, 0, 0
		for i = 1, #ids do
			local ok, st = PassBase(ids[i], c, false)
			if ok and Data.OwnAt(ids[i], key) then
				total = total + 1
				if st == ST.MISSING then
					missing = missing + 1
				elseif c.on and Mog.IsCollected(st) then
					have = have + 1
				end
			end
		end
		if total > 0 then
			local line = { t = "place", kind = kind, key = key, name = Data.PlaceName(key), missing = missing, have = have,
				total = total, on = c.on }
			if kind == "inst" then
				local info = Data.InstInfo(key)
				if info then
					line.minLevel, line.maxLevel, line.itype = info[3], info[4], info[2]
				end
			end
			lines[#lines + 1] = line
		end
	end
	if kind == "inst" then
		sort(lines, function(a, b)
			local la, lb = a.minLevel or 99, b.minLevel or 99
			if la ~= lb then
				return la < lb
			end
			return a.name < b.name
		end)
	else
		sort(lines, function(a, b)
			return a.name < b.name
		end)
	end
	return { lines = lines, shown = #lines, missing = 0 }
end

local statsCache, statsVersion = nil, -1

function List.Stats()
	if statsCache and statsVersion == Mog.version then
		return statsCache
	end
	local can, have, slotOf, armorOf = {}, {}, {}, {}
	local ids = Data.IDs()
	for i = 1, #ids do
		local id = ids[i]
		local st = Mog.StatusOf(id)
		local row = Data.Item(id)
		local app = row and row[7]
		if app ~= nil and st ~= ST.CANT and st ~= ST.UNKNOWN then
			can[app] = true
			if not slotOf[app] then
				slotOf[app] = ns.SLOT_OF_INV[row[2]] or "OTHER"
				armorOf[app] = Data.ArmorSub(id)
			end
			if st == ST.EXACT or st == ST.KNOWN then
				have[app] = true
			end
		end
	end
	local bySlot, byArmor, total, got = {}, {}, 0, 0
	for app in pairs(can) do
		local s = slotOf[app]
		local b = bySlot[s]
		if not b then
			b = { have = 0, total = 0 }
			bySlot[s] = b
		end
		b.total = b.total + 1
		total = total + 1
		local sub = armorOf[app]
		local a = sub and byArmor[sub]
		if sub and not a then
			a = { have = 0, total = 0 }
			byArmor[sub] = a
		end
		if a then
			a.total = a.total + 1
		end
		if have[app] then
			b.have = b.have + 1
			got = got + 1
			if a then
				a.have = a.have + 1
			end
		end
	end
	local lines = {}
	for _, s in ipairs(ns.SLOTS) do
		local b = bySlot[s.key]
		if b then
			lines[#lines + 1] = { t = "stat", key = s.key, text = s.label, have = b.have, total = b.total }
		end
	end
	if next(byArmor) then
		lines[#lines + 1] = { t = "head", text = "By armor type (any character collects every type)", plain = true }
		for sub = 1, 4 do
			local a = byArmor[sub]
			if a then
				lines[#lines + 1] = { t = "stat", key = "ARMOR" .. sub, text = Data.ARMOR_NAME[sub], have = a.have, total = a.total }
			end
		end
	end
	statsCache = { lines = lines, have = got, total = total, shown = #lines, missing = total - got }
	statsVersion = Mog.version
	return statsCache
end

local progCache, progVersion, progSig
function List.Progress(f, cachedOnly)
	local sig = table.concat({ tostring(f.slot), tostring(f.armorOnly), tostring(f.minQuality), tostring(f.levelMin),
		tostring(f.levelMax), tostring(ns.db and ns.db.classRules), tostring(Mog.On()), tostring(Data.armor) }, "|")
	if progCache and progVersion == Mog.version and progSig == sig then
		return progCache, false
	end
	if progCache and cachedOnly then
		return progCache, true
	end
	local c = Context(f)
	local seen, have = {}, {}
	local total, got = 0, 0
	local ids = Data.IDs()
	for i = 1, #ids do
		local id = ids[i]
		local ok, st = PassBase(id, c, false)
		if ok then
			local app = Data.Item(id)[7] or -id
			if not seen[app] then
				seen[app] = true
				total = total + 1
			end
			if Mog.IsCollected(st) and not have[app] then
				have[app] = true
				got = got + 1
			end
		end
	end
	progCache, progVersion, progSig = { have = got, total = total }, Mog.version, sig
	return progCache, false
end

function List.MissingAppearances(kind, key, f)
	local ids = List.PlaceItems(kind, key)
	local minQ = (f and f.minQuality) or 0
	local armorOnly = f and f.armorOnly
	local seen, n = {}, 0
	for i = 1, #ids do
		local id = ids[i]
		local q = minQ > 0 and Data.Quality(id)
		if not (q and q < minQ) and not (armorOnly and Data.NotMyArmor(id)) and Data.OwnAt(id, key)
			and Mog.StatusOf(id, true) == ST.MISSING then
			local row = Data.Item(id)
			local app = (row and row[7]) or ("item" .. id)
			if not seen[app] then
				seen[app] = true
				n = n + 1
			end
		end
	end
	return n
end

local ALIASES = {
	rfc = "i389", wc = "i43", dm = "i36", vc = "i36", deadmines = "i36", sfk = "i33", stocks = "i34", stockade = "i34",
	bfd = "i48", gnomer = "i90", rfk = "i47", sm = "i189", rfd = "i129", ulda = "i70", zf = "i209", mara = "i349",
	st = "i109", brd = "i230", lbrs = "i229", ubrs = "i229", brs = "i229", strat = "i329", scholo = "i289",
	diremaul = "i429", mc = "i409", ony = "i249", bwl = "i469", zg = "i309", aq20 = "i509", aq40 = "i531", naxx = "i533",
}

function List.FindPlace(kind, text)
	local q = Query(text)
	if not q then
		return nil
	end
	local keys = kind == "inst" and Data.InstKeys() or Data.ZoneKeys()
	if kind == "inst" then
		local alias = ALIASES[string.gsub(q, "[%s'%-]", "")]
		if alias and Data.InstInfo(alias) and #Data.InstItems(alias) > 0 then
			return alias, Data.InstName(alias)
		end
	end
	local best, bestScore, bestName
	for _, key in ipairs(keys) do
		local name = Data.PlaceName(key)
		local ln = lower(name)
		local score
		if ln == q or ln == "the " .. q then
			score = 3
		elseif find(ln, q, 1, true) == 1 or find(ln, "the " .. q, 1, true) == 1 then
			score = 2
		elseif find(ln, q, 1, true) then
			score = 1
		end
		if score and (not best or score > bestScore or (score == bestScore and name < bestName)) then
			best, bestScore, bestName = key, score, name
		end
	end
	return best, bestName
end
