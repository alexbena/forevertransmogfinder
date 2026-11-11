local ADDON_NAME, ns = ...

local type, pairs, ipairs, pcall, select, tostring, tonumber = type, pairs, ipairs, pcall, select, tostring, tonumber
local floor, format = math.floor, string.format

local function GetMetadata(key)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local ok, v = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, key)
		if ok and type(v) == "string" then
			return v
		end
	end
	return nil
end

ns.VERSION = GetMetadata("Version") or "dev"
ns.TITLE = GetMetadata("Title") or "Forever Transmog Finder"
ns.AUTHOR = GetMetadata("Author")
ns.LICENSE = GetMetadata("X-License") or "GPL-3.0-or-later"
ns.DATA_ADDON = "ForeverTransmogFinder_Data"

local IsSecret
if type(issecretvalue) == "function" then
	IsSecret = issecretvalue
else
	IsSecret = function()
		return false
	end
end
ns.IsSecret = IsSecret

local function Clean(v)
	if IsSecret(v) then
		return nil
	end
	return v
end

function ns.Read(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Clean(a), Clean(b), Clean(c), Clean(d), Clean(e), Clean(f), Clean(g), Clean(h)
end
local Read = ns.Read

local CHAT_PREFIX = "|cffF2C14ETransmog Finder|r:"

local function JoinForChat(...)
	local count = select("#", ...)
	local parts = {}
	for i = 1, count do
		local value = select(i, ...)
		if IsSecret(value) then
			parts[i] = "<secret>"
		else
			parts[i] = tostring(value)
		end
	end
	return table.concat(parts, " ", 1, count)
end

function ns.Print(...)
	print(CHAT_PREFIX, JoinForChat(...))
end

function ns.Debug(...)
	if ns.db and ns.db.debug then
		print(CHAT_PREFIX .. " |cff888888debug|r", JoinForChat(...))
	end
end

local function ReportError(err)
	local handler = geterrorhandler and geterrorhandler()
	if handler then
		handler(err)
	else
		print(CHAT_PREFIX, tostring(err))
	end
	return err
end
ns.ReportError = ReportError

local function Call(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		ReportError(err)
	end
	return ok
end
ns.SafeCall = Call

function ns.Comma(n)
	if type(n) ~= "number" then
		return "?"
	end
	local s = tostring(floor(n + 0.5))
	local out, k = s, 0
	repeat
		out, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return out
end

local function Hex(h)
	return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
local function ClientFont()
	local fo = GameFontHighlightSmall
	if type(fo) == "table" and type(fo.GetFont) == "function" then
		local ok, path = pcall(fo.GetFont, fo)
		if ok and type(path) == "string" and not IsSecret(path) and path ~= "" then
			return path
		end
	end
	local std = STANDARD_TEXT_FONT
	if type(std) == "string" and not IsSecret(std) and std ~= "" then
		return std
	end
	return FALLBACK_FONT
end
ns.ClientFont = ClientFont

ns.STYLE = {
	bg = Hex("14161A"), bgAlpha = 0.95, panel = Hex("1B1E24"), border = Hex("2A2F38"),
	gold = Hex("F2C14E"), teal = Hex("3BC9DB"), green = Hex("51CF66"), orange = Hex("FF922B"),
	red = Hex("FF6B6B"), muted = Hex("9AA3AE"), text = Hex("E6E9EE"), dim = Hex("6B7380"),
	font = ClientFont(), title = 14, body = 13, small = 12,
	flat = "Interface\\Buttons\\WHITE8X8",
}
ns.DOT = " \194\183 "

function ns.About()
	local text = ns.TITLE .. " " .. ns.VERSION
	if ns.AUTHOR and ns.AUTHOR ~= "" then
		text = text .. " by " .. ns.AUTHOR
	end
	return text .. ns.DOT .. ns.LICENSE .. ns.DOT .. "no warranty"
end

local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if list then
		for i = 1, #list do
			Call(list[i], event, ...)
		end
	end
end)

local function AddHandler(event, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
	end
	list[#list + 1] = fn
end

function ns.On(event, fn)
	AddHandler(event, fn)
	eventFrame:RegisterEvent(event)
end

function ns.TryOn(event, fn)
	if C_EventUtils and C_EventUtils.IsEventValid then
		local ok, valid = pcall(C_EventUtils.IsEventValid, event)
		if ok and valid == false then
			return false
		end
	end
	local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
	if ok then
		AddHandler(event, fn)
	end
	return ok
end

local messages = {}
function ns.Listen(msg, fn)
	local list = messages[msg]
	if not list then
		list = {}
		messages[msg] = list
	end
	list[#list + 1] = fn
end
function ns.Fire(msg, ...)
	local list = messages[msg]
	if list then
		for i = 1, #list do
			Call(list[i], msg, ...)
		end
	end
end

function ns.After(delay, fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(delay, function()
			Call(fn)
		end)
		return true
	end
	return false
end

function ns.Debounce(delay, fn)
	local waiting = false
	return function()
		if waiting then
			return
		end
		waiting = true
		ns.After(delay, function()
			waiting = false
			fn()
		end)
	end
end

ns.inCombat = false

function ns.InCombat()
	if ns.inCombat then
		return true
	end
	return Read(InCombatLockdown) == true
end

local combatQueue, combatQueueOrder = {}, {}

function ns.RunOutOfCombat(key, fn)
	if not ns.InCombat() then
		fn()
		return true
	end
	if combatQueue[key] == nil then
		combatQueueOrder[#combatQueueOrder + 1] = key
	end
	combatQueue[key] = fn
	return false
end

local function FlushCombatQueue()
	if Read(InCombatLockdown) == true then
		return
	end
	local order = combatQueueOrder
	combatQueueOrder = {}
	for i = 1, #order do
		local key = order[i]
		local fn = combatQueue[key]
		combatQueue[key] = nil
		if fn then
			Call(fn)
		end
	end
end

function ns.PendingCombatActions()
	return #combatQueueOrder
end

local jobs = {}

function ns.NewJob(name, step, interval, pauseInCombat)
	local job = { name = name, running = false, paused = false, done = false, gen = 0, ticks = 0 }
	local Schedule
	local function Tick(gen)
		if gen ~= job.gen or not job.running then
			return
		end
		if pauseInCombat and ns.InCombat() then
			job.paused = true
			return
		end
		job.paused = false
		job.ticks = job.ticks + 1
		local ok, finished = pcall(step, job)
		if not ok then
			job.running, job.failed = false, true
			ReportError(finished)
			return
		end
		if finished then
			job.running, job.done = false, true
			if job.onDone then
				Call(job.onDone, job)
			end
			return
		end
		Schedule(gen, interval)
	end
	Schedule = function(gen, delay)
		if not ns.After(delay, function()
			Tick(gen)
		end) then
			Tick(gen)
		end
	end
	function job.Start(delay)
		job.gen = job.gen + 1
		job.running, job.done, job.paused, job.failed = true, false, false, false
		Schedule(job.gen, delay or 0)
	end
	function job.Stop()
		job.gen = job.gen + 1
		job.running, job.paused = false, false
	end
	function job.Resume()
		if job.running and job.paused then
			job.paused = false
			job.gen = job.gen + 1
			Schedule(job.gen, 1)
		end
	end
	if pauseInCombat then
		jobs[#jobs + 1] = job
	end
	return job
end

ns.Listen("COMBAT", function(_, inCombat)
	if not inCombat then
		for i = 1, #jobs do
			jobs[i].Resume()
		end
	end
end)

ns.TABS = { "HERE", "ZONES", "DUNGEONS", "ALL", "WISHLIST", "STATS" }
local VALID_TAB = {}
for _, t in ipairs(ns.TABS) do
	VALID_TAB[t] = true
end

ns.SORTS = {
	{ key = "source", label = "Source" },
	{ key = "slot", label = "Slot" },
	{ key = "name", label = "Name" },
	{ key = "level", label = "Level" },
	{ key = "chance", label = "Drop chance" },
}
ns.SORT_LABEL = {}
for _, s in ipairs(ns.SORTS) do
	ns.SORT_LABEL[s.key] = s.label
end

ns.WIN = { W = 980, H = 620, MIN_W = 820, MIN_H = 520, MAX_W = 1600, MAX_H = 1100 }

ns.SLOTS = {
	{ key = "ALL", label = "All slots" },
	{ key = "HEAD", label = "Head", inv = { 1 } },
	{ key = "SHOULDER", label = "Shoulder", inv = { 3 } },
	{ key = "BACK", label = "Back", inv = { 16 } },
	{ key = "CHEST", label = "Chest", inv = { 5, 20 } },
	{ key = "SHIRT", label = "Shirt", inv = { 4 } },
	{ key = "TABARD", label = "Tabard", inv = { 19 } },
	{ key = "WRIST", label = "Wrist", inv = { 9 } },
	{ key = "HANDS", label = "Hands", inv = { 10 } },
	{ key = "WAIST", label = "Waist", inv = { 6 } },
	{ key = "LEGS", label = "Legs", inv = { 7 } },
	{ key = "FEET", label = "Feet", inv = { 8 } },
	{ key = "MAIN", label = "One-hand / main hand", inv = { 13, 21 } },
	{ key = "OFF", label = "Off hand (weapon)", inv = { 22 } },
	{ key = "TWO", label = "Two-hand", inv = { 17 } },
	{ key = "RANGED", label = "Ranged", inv = { 15, 25, 26 } },
	{ key = "SHIELD", label = "Shield", inv = { 14 } },
	{ key = "HELD", label = "Held in off hand", inv = { 23 } },
}
ns.SLOT_OF_INV = {}
ns.SLOT_LABEL = {}
for _, s in ipairs(ns.SLOTS) do
	ns.SLOT_LABEL[s.key] = s.label
	for _, inv in ipairs(s.inv or {}) do
		ns.SLOT_OF_INV[inv] = s.key
	end
end

ns.QUALITIES = {
	{ value = 0, label = "Any quality" },
	{ value = 1, label = "Common+" },
	{ value = 2, label = "Uncommon+" },
	{ value = 3, label = "Rare+" },
	{ value = 4, label = "Epic+" },
}

ns.MAX_LEVEL = 60

local DEFAULTS = {
	tooltip = true,
	tooltipSource = true,
	noticeDungeon = true,
	noticeZone = false,
	noticeWish = true,
	preload = true,
	debug = false,
	welcomed = false,
	previewHover = true,
	grid = false,
	armorTag = true,
	classRules = false,
	minimap = { show = true, angle = 200 },
	filters = { slot = "ALL", armorOnly = false, minQuality = 2, showCollected = false, levelMin = 1, levelMax = 60,
		sort = "source" },
	win = { set = false, x = 0, y = 0, w = 980, h = 620, tab = "HERE", zone = 0, dungeon = "" },
	wish = {},
}
ns.DEFAULTS = DEFAULTS

local SCHEMA_VERSION = 2
local MIGRATIONS = {}
MIGRATIONS[2] = function(db)
	if type(db.filters) == "table" then
		db.filters.usable = nil
	end
end

local function Migrate(tbl, migrations, target)
	local from = tbl.schemaVersion
	if from == nil then
		from = (next(tbl) == nil) and target or 1
	elseif type(from) ~= "number" then
		from = 1
	end
	if from > target then
		ns.Debug("Saved settings come from a newer version (" .. from .. "); left unchanged.")
		return
	end
	for version = from + 1, target do
		local step = migrations[version]
		if step and not Call(step, tbl) then
			ns.Print("Could not upgrade the saved settings to version " .. version .. ".")
			return
		end
		tbl.schemaVersion = version
	end
	tbl.schemaVersion = target
end

local function MergeDefaults(dst, defaults)
	for key, value in pairs(defaults) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then
				dst[key] = {}
			end
			MergeDefaults(dst[key], value)
		elseif type(dst[key]) ~= type(value) then
			dst[key] = value
		end
	end
	return dst
end
ns.MergeDefaults = MergeDefaults

local function Clamp(v, lo, hi)
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end
ns.Clamp = Clamp

function ns.SanitizeDB()
	local db = ns.db
	local f, w = db.filters, db.win
	if not ns.SLOT_LABEL[f.slot] then
		f.slot = "ALL"
	end
	f.minQuality = Clamp(floor(f.minQuality), 0, 5)
	f.levelMin = Clamp(floor(f.levelMin), 1, ns.MAX_LEVEL)
	f.levelMax = Clamp(floor(f.levelMax), f.levelMin, ns.MAX_LEVEL)
	if not VALID_TAB[w.tab] then
		w.tab = "HERE"
	end
	if not ns.SORT_LABEL[f.sort] then
		f.sort = "source"
	end
	local S = ns.WIN
	if w.w ~= w.w or w.h ~= w.h then
		w.w, w.h = S.W, S.H
	end
	w.w = Clamp(floor(w.w), S.MIN_W, S.MAX_W)
	w.h = Clamp(floor(w.h), S.MIN_H, S.MAX_H)
	local m, a = db.minimap, db.minimap.angle
	if a ~= a or a == math.huge or a == -math.huge then
		a = DEFAULTS.minimap.angle
	end
	m.angle = a % 360
	for k, v in pairs(db.wish) do
		if type(k) ~= "number" or k <= 0 or k ~= floor(k) or v ~= true then
			db.wish[k] = nil
		end
	end
end

local Wish = {}
ns.Wish = Wish

function Wish.Has(id)
	return ns.db ~= nil and type(id) == "number" and not IsSecret(id) and ns.db.wish[id] == true
end

function Wish.Toggle(id)
	if not ns.db or type(id) ~= "number" or IsSecret(id) then
		return false
	end
	local now = not Wish.Has(id)
	ns.db.wish[id] = now or nil
	ns.Fire("WISH_CHANGED", id, now)
	return now
end

function Wish.IDs()
	local out = {}
	if ns.db then
		for id in pairs(ns.db.wish) do
			out[#out + 1] = id
		end
	end
	return out
end

function Wish.Count()
	return #Wish.IDs()
end

function ns.ApplySettings()
	ns.Fire("SETTINGS_CHANGED")
end

function ns.SetOptionValue(key, value)
	local group, field = string.match(key, "^(%w+)%.(%w+)$")
	if group then
		ns.db[group][field] = value
	else
		ns.db[key] = value
	end
	ns.ApplySettings()
end
ns.SetOption = ns.SetOptionValue

function ns.RefreshOptions()
end

function ns.OpenOptions()
	ns.Print("The options panel is not available.")
end

SLASH_FOREVERTRANSMOGFINDER1 = "/ftf"
SLASH_FOREVERTRANSMOGFINDER2 = "/transmogfinder"
local CMD = "/ftf"

local function PrintHelp()
	print("|cffF2C14E" .. ns.About() .. "|r")
	print("Commands:")
	print("  " .. CMD .. " - open or close the window")
	print("  " .. CMD .. " here - what you are missing where you are now")
	print("  " .. CMD .. " zone <name> - one zone's list (e.g. " .. CMD .. " zone westfall)")
	print("  " .. CMD .. " dungeon <name> - one dungeon's boss-by-boss list (e.g. " .. CMD .. " dungeon deadmines)")
	print("  " .. CMD .. " search <text> - search every item, boss, quest and vendor")
	print("  " .. CMD .. " wishlist - the items you starred")
	print("  " .. CMD .. " grid / " .. CMD .. " list - icon grid or list view")
	print("  " .. CMD .. " scan - state of the item list and the collection check")
	print("  " .. CMD .. " rules - what this account collected per armor type, and what the game says for 4 test items")
	print("  " .. CMD .. " reset - put the window back in the middle of the screen, at its first size")
	print("  " .. CMD .. " minimap on|off|reset - the minimap button (drag it along the edge)")
	print("  " .. CMD .. " options - the options panel (also: right-click the minimap button)")
	print("  Window: click an item to try it on (right pane: drag to rotate, wheel to zoom), the star adds it to")
	print("  your wishlist, drag the bottom-right corner to resize, Ctrl+F to search, Esc to close.")
	print("  Minimap button: left-click the window, shift+left-click the HERE tab, right-click the options.")
	print("  Keys: Options > Keybindings > AddOns > Forever Transmog Finder (toggle, and here).")
end

local function Words(rest)
	local s = string.gsub(rest or "", "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

local COMMANDS = {
	help = PrintHelp,
	here = function()
		ns.UI.Open("HERE")
	end,
	zone = function(rest)
		ns.UI.OpenPlace("zone", Words(rest))
	end,
	dungeon = function(rest)
		ns.UI.OpenPlace("dungeon", Words(rest))
	end,
	search = function(rest)
		ns.UI.Search(Words(rest))
	end,
	scan = function()
		ns.PrintScanStatus()
	end,
	reset = function()
		ns.UI.ResetPosition()
	end,
	options = function()
		ns.OpenOptions()
	end,
	minimap = function(rest)
		ns.Minimap.Command(Words(rest))
	end,
	debug = function()
		ns.db.debug = not ns.db.debug
		ns.Print("Debug output " .. (ns.db.debug and "on" or "off") .. ".")
	end,
	wishlist = function()
		ns.UI.Open("WISHLIST")
	end,
	grid = function()
		ns.SetOption("grid", true)
		ns.RefreshOptions()
		ns.UI.Open()
	end,
	list = function()
		ns.SetOption("grid", false)
		ns.RefreshOptions()
		ns.UI.Open()
	end,
	rules = function()
		if not ns.RunOutOfCombat("rules", ns.Mog.PrintRules) then
			ns.Print("The rules report comes when combat ends.")
		end
	end,
	classrules = function(rest)
		local arg = string.lower(Words(rest))
		local v
		if arg == "on" then
			v = true
		elseif arg == "off" then
			v = false
		elseif arg == "" then
			v = not ns.db.classRules
		else
			ns.Print("Usage: " .. CMD .. " classrules on | off")
			return
		end
		ns.db.classRules = v
		ns.Print(v and "Class rules on: items the game says this character can't collect show as CAN'T again, and \"Only my armor type\" hides them."
			or "Class rules off (the default): every item shows as missing or collected; the game's \"can't collect\" answer is only kept for /ftf rules.")
		ns.Fire("RULES_CHANGED")
	end,
}
COMMANDS.raid = COMMANDS.dungeon
COMMANDS.instance = COMMANDS.dungeon
COMMANDS.config = COMMANDS.options
COMMANDS.status = COMMANDS.scan
COMMANDS.find = COMMANDS.search
COMMANDS.button = COMMANDS.minimap
COMMANDS.wish = COMMANDS.wishlist

SlashCmdList.FOREVERTRANSMOGFINDER = function(message)
	if not ns.db then
		ns.Print("Not loaded yet.")
		return
	end
	if IsSecret(message) then
		return
	end
	local command, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
	command = string.lower(command or "")
	if command == "" then
		ns.UI.Toggle()
		return
	end
	local handler = COMMANDS[command]
	if not handler then
		ns.Print("Unknown command '" .. command .. "'.")
		PrintHelp()
		return
	end
	handler(rest or "")
end

function ForeverTransmogFinder_OnAddonCompartmentClick(_, buttonName)
	if not ns.db then
		return
	end
	if buttonName == "RightButton" then
		ns.OpenOptions()
	else
		ns.UI.Toggle()
	end
end

BINDING_HEADER_FOREVERTRANSMOGFINDER = "Forever Transmog Finder"
BINDING_NAME_FOREVERTRANSMOGFINDER_TOGGLE = "Toggle Forever Transmog Finder"
BINDING_NAME_FOREVERTRANSMOGFINDER_HERE = "Forever Transmog Finder: here"

function ForeverTransmogFinder_ToggleWindow()
	if ns.db and ns.UI then
		ns.UI.Toggle()
	end
end

function ForeverTransmogFinder_OpenHere()
	if ns.db and ns.UI then
		ns.UI.ToggleHere()
	end
end

function ns.PrintScanStatus()
	local Data, Mog = ns.Data, ns.Mog
	local avail, how = Mog.available, Mog.availableHow
	if avail == false then
		ns.Print("Transmog is off on this character (" .. tostring(how) .. "). Lists still show where items come from.")
	elseif avail == nil then
		ns.Print("Transmog: could not tell whether it is on (" .. tostring(how) .. "); assuming it is.")
	else
		ns.Print("Transmog is on (" .. tostring(how) .. ").")
	end
	local st = Data.state
	if st == "ready" then
		local d = Data.Raw()
		ns.Print(format("Item list: %s items, %s zones, %s dungeons and raids (data v%s, %s, built %s).",
			ns.Comma(Data.Count()), ns.Comma(Data.ZoneCount()), ns.Comma(Data.InstCount()), tostring(d.version),
			tostring(d.build), tostring(d.generated)))
		local outdated = Data.OutdatedText()
		if outdated then
			ns.Print(outdated)
		end
	elseif st == "error" then
		ns.Print("Item list: not loaded. " .. tostring(Data.error))
	elseif st == "idle" then
		ns.Print("Item list: not loaded yet (it loads when you open the window" ..
			((ns.db.preload and Mog.On()) and ", or at login" or "") .. ").")
	else
		ns.Print("Item list: " .. st .. (Data.waitingForCombat and " (waits for the end of combat)" or "") .. ".")
	end
	if avail ~= false and st == "ready" then
		local s = Mog.ScanInfo()
		local line
		if s.done then
			line = "Collection check: done"
		elseif s.paused then
			line = format("Collection check: paused in combat at %s / %s", ns.Comma(s.pos), ns.Comma(s.total))
		elseif s.running then
			line = format("Collection check: %s / %s", ns.Comma(s.pos), ns.Comma(s.total))
		else
			line = "Collection check: not started"
		end
		ns.Print(format("%s. Missing %s, collected %s (%s from this exact item), waiting for item data %s.",
			line, ns.Comma(s.missing), ns.Comma(s.exact + s.known), ns.Comma(s.exact), ns.Comma(s.pending)))
		if ns.db.classRules then
			ns.Print(format("Class rules on (/ftf classrules off): %s items the game says this character can't collect.",
				ns.Comma(s.cant)))
		else
			ns.Print(format("The game's PlayerCanCollectSource said \"can't\" for %s of them; not used (any character collects what it loots). /ftf rules for details.",
				ns.Comma(s.apiNo)))
		end
	end
end

local loggedIn = false

local function OnLogin()
	if loggedIn then
		return
	end
	loggedIn = true
	ns.inCombat = Read(InCombatLockdown) == true
	ns.Fire("LOGIN")
	ns.Fire("LOGIN_DONE")
end

local function OnAddonLoaded(_, loadedName)
	if loadedName ~= ADDON_NAME or ns.db then
		return
	end
	if type(ForeverTransmogFinderDB) ~= "table" then
		ForeverTransmogFinderDB = {}
	end
	ns.db = ForeverTransmogFinderDB
	Migrate(ns.db, MIGRATIONS, SCHEMA_VERSION)
	MergeDefaults(ns.db, DEFAULTS)
	ns.SanitizeDB()
	if ns.RegisterOptions then
		Call(ns.RegisterOptions)
	end
	if IsLoggedIn and Read(IsLoggedIn) == true then
		OnLogin()
	end
end

ns.On("ADDON_LOADED", OnAddonLoaded)
ns.On("PLAYER_LOGIN", OnLogin)
ns.On("PLAYER_REGEN_DISABLED", function()
	ns.inCombat = true
	ns.Fire("COMBAT", true)
end)
ns.On("PLAYER_REGEN_ENABLED", function()
	ns.inCombat = false
	FlushCombatQueue()
	ns.Fire("COMBAT", false)
end)
