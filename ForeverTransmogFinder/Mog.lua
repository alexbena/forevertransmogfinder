local ADDON_NAME, ns = ...

local type, pairs, ipairs, next, min, tostring = type, pairs, ipairs, next, math.min, tostring
local format = string.format
local Read, IsSecret = ns.Read, ns.IsSecret
local Data = ns.Data

local Mog = {}
ns.Mog = Mog

local ST = { UNKNOWN = 0, EXACT = 1, KNOWN = 2, MISSING = 3, CANT = 4, PENDING = 5 }
Mog.ST = ST

local status = {}
local counts = { [0] = 0, 0, 0, 0, 0, 0 }
local pending, pendingCount = {}, 0
local requested = {}
local apiNo, apiNoCount = {}, 0
local changed = false

Mog.version = 0
Mog.available = nil
Mog.availableHow = "not checked yet"
Mog.preset = nil
Mog.scanDone = false

local function Bool(fn, ...)
	local v = Read(fn, ...)
	if type(v) == "boolean" then
		return v
	end
	return nil
end

function Mog.CheckAvailable()
	local was = Mog.available
	local v, how
	local rules = C_GameRules
	Mog.preset = nil
	if rules and rules.GetForeverExperiencePreset then
		local p = Read(rules.GetForeverExperiencePreset)
		if type(p) == "number" then
			local E = Enum and Enum.ForeverExperiencePreset
			local classic = (E and E.Classic) or 0
			local enhanced = (E and E.Enhanced) or 1
			if p == classic then
				Mog.preset = "Classic"
			elseif p == enhanced then
				Mog.preset = "Enhanced"
			end
		end
	end
	if not (C_TransmogCollection and C_TransmogCollection.GetAppearanceInfoBySource) then
		v, how = false, "this client has no transmog collection API"
	else
		local outfit = C_TransmogOutfitInfo
		if outfit and outfit.IsTransmogEnabled then
			v = Bool(outfit.IsTransmogEnabled)
			how = "C_TransmogOutfitInfo.IsTransmogEnabled"
		end
		if v == nil and rules and rules.IsGameRuleActive then
			local rule = Enum and Enum.GameRule and Enum.GameRule.TransmogEnabled
			if type(rule) == "number" then
				v = Bool(rules.IsGameRuleActive, rule)
				how = "game rule TransmogEnabled"
			end
		end
		if v == nil and Mog.preset then
			v = Mog.preset ~= "Classic"
			how = Mog.preset .. " experience preset"
		end
		if v == nil then
			how = "no transmog availability API answered"
		end
	end
	Mog.available, Mog.availableHow = v, how
	if was ~= v then
		ns.Fire("AVAILABILITY_CHANGED", v)
	end
	return v
end

function Mog.On()
	return Mog.available ~= false
end

local function Query(sourceID, classRules)
	local T = C_TransmogCollection
	if type(sourceID) ~= "number" or IsSecret(sourceID) or not T then
		return ST.UNKNOWN
	end
	local answered = false
	local info = Read(T.GetAppearanceInfoBySource, sourceID)
	if type(info) == "table" then
		local srcC, appC = info.sourceIsCollected, info.appearanceIsCollected
		if not IsSecret(srcC) and srcC == true then
			return ST.EXACT
		end
		if not IsSecret(appC) and appC == true then
			return ST.KNOWN
		end
		answered = (not IsSecret(srcC) and srcC == false) or (not IsSecret(appC) and appC == false)
	end
	local has = Bool(T.PlayerHasTransmogItemModifiedAppearance, sourceID)
	if has == true then
		return ST.EXACT
	end
	local hasData, canCollect = Read(T.PlayerCanCollectSource, sourceID)
	if type(canCollect) ~= "boolean" then
		canCollect = nil
	end
	if hasData == false then
		return ST.PENDING, nil
	end
	if canCollect == false and classRules then
		return ST.CANT, false
	end
	if answered or has == false or canCollect ~= nil then
		return ST.MISSING, canCollect
	end
	return ST.UNKNOWN, canCollect
end
Mog.Query = Query

local function ClassRules()
	return ns.db ~= nil and ns.db.classRules == true
end

local function SetApiNo(id, no)
	if no then
		if not apiNo[id] then
			apiNo[id] = true
			apiNoCount = apiNoCount + 1
		end
	elseif apiNo[id] then
		apiNo[id] = nil
		apiNoCount = apiNoCount - 1
	end
end

local function SetStatus(id, code)
	local old = status[id] or ST.UNKNOWN
	if old == code then
		return false
	end
	status[id] = code
	counts[old] = counts[old] - 1
	counts[code] = counts[code] + 1
	if code == ST.PENDING then
		pending[id] = true
		pendingCount = pendingCount + 1
	elseif old == ST.PENDING then
		pending[id] = nil
		pendingCount = pendingCount - 1
	end
	Mog.version = Mog.version + 1
	changed = true
	return true
end

local function NotifyChanged()
	if changed then
		changed = false
		ns.Fire("STATUS_CHANGED")
	end
end
Mog.NotifyChanged = NotifyChanged

function Mog.Refresh(id)
	if not Mog.On() then
		return ST.UNKNOWN
	end
	local row = Data.Item(id)
	if not row then
		return ST.UNKNOWN
	end
	local code, can = Query(row[8], ClassRules())
	SetStatus(id, code)
	SetApiNo(id, can == false)
	return code
end

function Mog.StatusOf(id, now)
	if not Mog.On() then
		return ST.UNKNOWN
	end
	local s = status[id]
	if s == nil and now then
		s = Mog.Refresh(id)
	end
	return s or ST.UNKNOWN
end

function Mog.IsCollected(code)
	return code == ST.EXACT or code == ST.KNOWN
end

function Mog.ForTooltip(itemID, link)
	local T = C_TransmogCollection
	if not T or not Mog.On() then
		return nil
	end
	local row = Data.Item(itemID)
	local sourceID
	if type(link) == "string" and T.GetItemInfo then
		local _, s = Read(T.GetItemInfo, link)
		sourceID = s
	end
	if type(sourceID) ~= "number" then
		if row then
			sourceID = row[8]
		elseif T.GetItemInfo then
			local _, s = Read(T.GetItemInfo, itemID)
			sourceID = s
		end
	end
	if type(sourceID) ~= "number" or IsSecret(sourceID) then
		return nil
	end
	local code, can = Query(sourceID, ClassRules())
	if row and sourceID == row[8] and Data.Ready() then
		SetStatus(itemID, code)
		SetApiNo(itemID, can == false)
		NotifyChanged()
	end
	return code
end

local function Wipe()
	for k in pairs(status) do
		status[k] = nil
	end
	for k in pairs(pending) do
		pending[k] = nil
	end
	pendingCount = 0
	for k in pairs(apiNo) do
		apiNo[k] = nil
	end
	apiNoCount = 0
	for k = 1, 5 do
		counts[k] = 0
	end
	counts[0] = Data.Count()
	Mog.version = Mog.version + 1
	changed = true
end

local SCAN_PER_STEP, SCAN_INTERVAL, SCAN_BUDGET_MS = 200, 0.1, 8
local scanPos = 0
local scanJob, loadJob, recheckJob

local function ScanStep()
	local list = Data.IDs()
	local n = #list
	local t0 = Data.Now()
	local stop = min(scanPos + SCAN_PER_STEP, n)
	while scanPos < stop do
		scanPos = scanPos + 1
		Mog.Refresh(list[scanPos])
		if scanPos % 50 == 0 and Data.Now() - t0 > SCAN_BUDGET_MS then
			break
		end
	end
	NotifyChanged()
	return scanPos >= n
end

scanJob = ns.NewJob("scan", ScanStep, SCAN_INTERVAL, true)

function Mog.StartScan(delay)
	if not Mog.On() or not Data.Ready() then
		return false
	end
	scanPos = 0
	Mog.scanDone = false
	scanJob.Start(delay or 0.5)
	return true
end

local LOAD_PER_STEP, LOAD_INTERVAL, LOAD_SESSION_MAX = 10, 0.5, 2000
Mog.LOAD_PER_STEP, Mog.LOAD_INTERVAL, Mog.LOAD_SESSION_MAX = LOAD_PER_STEP, LOAD_INTERVAL, LOAD_SESSION_MAX
local loadQueue, loadPos = {}, 0
local loadsSent = 0

local function LoadStep()
	local sent = 0
	while loadPos < #loadQueue and sent < LOAD_PER_STEP and loadsSent < LOAD_SESSION_MAX do
		loadPos = loadPos + 1
		local id = loadQueue[loadPos]
		if pending[id] and not requested[id] then
			requested[id] = true
			sent = sent + 1
			loadsSent = loadsSent + 1
			Read(C_Item.RequestLoadItemDataByID, id)
		end
	end
	return loadPos >= #loadQueue or loadsSent >= LOAD_SESSION_MAX
end
loadJob = ns.NewJob("itemLoads", LoadStep, LOAD_INTERVAL, true)

function Mog.RequestsSent()
	return loadsSent
end

local function StartPendingLoads()
	if pendingCount == 0 or loadsSent >= LOAD_SESSION_MAX or not (C_Item and C_Item.RequestLoadItemDataByID) then
		return
	end
	loadQueue, loadPos = {}, 0
	for id in pairs(pending) do
		if not requested[id] then
			loadQueue[#loadQueue + 1] = id
		end
	end
	if #loadQueue > 0 then
		loadJob.Start(1)
	end
end

local recheckQueue, recheckPos = {}, 0
local function RecheckStep()
	local stop = min(recheckPos + SCAN_PER_STEP, #recheckQueue)
	while recheckPos < stop do
		recheckPos = recheckPos + 1
		Mog.Refresh(recheckQueue[recheckPos])
	end
	NotifyChanged()
	return recheckPos >= #recheckQueue
end
recheckJob = ns.NewJob("recheck", RecheckStep, SCAN_INTERVAL, true)

local function RecheckPending()
	if pendingCount == 0 or not Data.Ready() then
		return
	end
	recheckQueue, recheckPos = {}, 0
	for id in pairs(pending) do
		recheckQueue[#recheckQueue + 1] = id
	end
	recheckJob.Start(0)
end

scanJob.onDone = function()
	Mog.scanDone = true
	ns.Debug("Collection check done: missing " .. counts[ST.MISSING] .. ", collected " .. (counts[ST.EXACT] + counts[ST.KNOWN])
		.. ", can't " .. counts[ST.CANT] .. ", pending " .. pendingCount .. ".")
	ns.Fire("SCAN_DONE")
	StartPendingLoads()
end

function Mog.ScanInfo()
	return {
		done = Mog.scanDone, running = scanJob.running, paused = scanJob.paused, pos = scanPos, total = Data.Count(),
		missing = counts[ST.MISSING], exact = counts[ST.EXACT], known = counts[ST.KNOWN], cant = counts[ST.CANT],
		pending = pendingCount, unknown = counts[ST.UNKNOWN], apiNo = apiNoCount,
	}
end

function Mog.ApiSaidNo(id)
	return apiNo[id] == true
end

function Mog.Progress()
	local n = Data.Count()
	if n == 0 then
		return 0
	end
	return scanPos / n
end

local function RefreshSource(sourceID)
	if type(sourceID) ~= "number" or IsSecret(sourceID) or not Data.Ready() then
		return
	end
	local id = Data.ItemBySource(sourceID)
	local app
	if id then
		local row = Data.Item(id)
		app = row and row[7]
		Mog.Refresh(id)
	else
		local T = C_TransmogCollection
		local info = T and Read(T.GetSourceInfo, sourceID)
		if type(info) == "table" and type(info.visualID) == "number" and not IsSecret(info.visualID) then
			app = info.visualID
		end
	end
	if type(app) == "number" then
		Data.ForAppearance(app, Mog.Refresh)
	end
	NotifyChanged()
end
Mog.RefreshSource = RefreshSource

local fullRefresh = ns.Debounce(3, function()
	if Data.Ready() and Mog.On() then
		Mog.StartScan(0)
	end
end)
local pendingRefresh = ns.Debounce(1, RecheckPending)

ns.Listen("LOGIN", function()
	Mog.CheckAvailable()
end)

ns.Listen("DATA_READY", function()
	for k = 1, 5 do
		counts[k] = 0
	end
	counts[ST.UNKNOWN] = Data.Count()
	for _, n in pairs(status) do
		counts[ST.UNKNOWN] = counts[ST.UNKNOWN] - 1
		counts[n] = counts[n] + 1
	end
	Mog.StartScan(0.5)
end)

ns.Listen("AVAILABILITY_CHANGED", function(_, on)
	Wipe()
	scanJob.Stop()
	if on ~= false then
		Mog.StartScan(0.5)
	else
		Mog.scanDone = false
	end
	NotifyChanged()
end)

ns.TryOn("TRANSMOG_COLLECTION_SOURCE_ADDED", function(_, sourceID)
	RefreshSource(sourceID)
end)
ns.TryOn("TRANSMOG_COLLECTION_SOURCE_REMOVED", function(_, sourceID)
	RefreshSource(sourceID)
end)
ns.TryOn("TRANSMOG_COLLECTION_UPDATED", function()
	fullRefresh()
end)
ns.TryOn("TRANSMOG_COLLECTION_ITEM_UPDATE", function()
	pendingRefresh()
end)
ns.TryOn("TRANSMOG_SOURCE_COLLECTABILITY_UPDATE", function(_, sourceID)
	if type(sourceID) ~= "number" or IsSecret(sourceID) or not Data.Ready() then
		return
	end
	local id = Data.ItemBySource(sourceID)
	if id then
		Mog.Refresh(id)
		NotifyChanged()
	end
end)
ns.TryOn("ITEM_DATA_LOAD_RESULT", function(_, itemID, success)
	if type(itemID) ~= "number" or IsSecret(itemID) or not pending[itemID] then
		return
	end
	if not IsSecret(success) and success == true then
		Mog.Refresh(itemID)
		NotifyChanged()
	end
end)
ns.TryOn("GAME_RULES_CHANGED", function()
	Mog.CheckAvailable()
end)

ns.Listen("RULES_CHANGED", function()
	Wipe()
	scanJob.Stop()
	Mog.scanDone = false
	if Mog.On() then
		Mog.StartScan(0)
	end
	NotifyChanged()
end)

Mog.RULE_ITEMS = {
	{ 7919, "Heavy Mithril Gauntlet", "plate, green" },
	{ 153, "Primitive Kilt", "leather, grey" },
	{ 193, "Tattered Cloth Vest", "cloth, white" },
	{ 6070, "Wolfskin Bracers", "leather, white" },
}

local function YesNo(v)
	if v == true then
		return "yes"
	elseif v == false then
		return "NO"
	end
	return "?"
end

local STATUS_WORD = { [ST.EXACT] = "collected", [ST.KNOWN] = "collected (other item)", [ST.MISSING] = "missing",
	[ST.PENDING] = "waiting for item data", [ST.CANT] = "can't (class rules)", [ST.UNKNOWN] = "no answer" }

function Mog.ArmorCounts()
	local seenAll, seenHave = { {}, {}, {}, {} }, { {}, {}, {}, {} }
	local out = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
	local ids = Data.IDs()
	for i = 1, #ids do
		local id = ids[i]
		local sub = Data.ArmorSub(id)
		if sub then
			local row = Data.Item(id)
			local app = row[7] or -id
			if not seenAll[sub][app] then
				seenAll[sub][app] = true
				out[sub][2] = out[sub][2] + 1
			end
			if Mog.IsCollected(status[id]) and not seenHave[sub][app] then
				seenHave[sub][app] = true
				out[sub][1] = out[sub][1] + 1
			end
		end
	end
	return out
end

function Mog.PrintRules()
	local P = ns.Print
	if not Mog.On() then
		P("Transmog is off on this character (" .. tostring(Mog.availableHow) .. "); nothing to check.")
		return
	end
	if Data.Ready() then
		local c = Mog.ArmorCounts()
		local parts = {}
		for sub = 1, 4 do
			parts[sub] = format("%s %s / %s", Data.ARMOR_NAME[sub], ns.Comma(c[sub][1]), ns.Comma(c[sub][2]))
		end
		local s = Mog.ScanInfo()
		P(format("Collected appearances on this account, by armor type (item list, collection check %s):",
			s.done and "done" or format("%d%%", math.floor(100 * Mog.Progress()))))
		print("  " .. table.concat(parts, ns.DOT))
		local mine = Data.armor and Data.ARMOR_NAME[Data.armor]
		if mine then
			print("  This class wears " .. string.lower(mine) .. ". Other armor types above were collected by this account (this or another character).")
		end
		print(format("  At the last check the game's PlayerCanCollectSource said \"can't\" for %s of %s items in the list (not used as a verdict).",
			ns.Comma(s.apiNo), ns.Comma(s.total)))
	else
		P("The item list is not loaded yet (open /ftf once); the armor-type counts need it.")
	end
	P("PlayerCanCollectSource for this character, on 4 test items (run it twice: the first run may lack item data):")
	local T = C_TransmogCollection
	for _, t in ipairs(Mog.RULE_ITEMS) do
		local id, name, what = t[1], t[2], t[3]
		local _, sourceID = Read(T and T.GetItemInfo, id)
		if type(sourceID) ~= "number" then
			local row = Data.Item(id)
			sourceID = row and row[8]
		end
		local head = format("  %d %s (%s): ", id, name, what)
		if type(sourceID) ~= "number" then
			Read(C_Item and C_Item.RequestLoadItemDataByID, id)
			print(head .. "no item data yet (asked the client; run /ftf rules again in a few seconds)")
		else
			local hasData, can = Read(T.PlayerCanCollectSource, sourceID)
			local accHas, accCan = Read(T.AccountCanCollectSource, sourceID)
			local code = Query(sourceID, false)
			if hasData == false then
				Read(C_Item and C_Item.RequestLoadItemDataByID, id)
			end
			print(head .. format("source %d%sthis character can collect: %s%saccount: %s%s%s", sourceID, ns.DOT,
				hasData == false and "? (no item data yet)" or YesNo(can), ns.DOT, accHas == false and "?" or YesNo(accCan),
				ns.DOT, STATUS_WORD[code] or "?"))
		end
	end
	if ns.db.classRules then
		print("  Class rules are ON: \"NO\" items show as CAN'T in the window. /ftf classrules off for the default.")
	else
		print("  If the plate gauntlet says \"yes\" for a Rogue, Forever lets every class collect every armor type. Either way the window shows every item as missing or collected (/ftf classrules on trusts the game's \"NO\" again).")
	end
end
