local ADDON_NAME, ns = ...

local type, ipairs, pcall, tostring, tonumber = type, ipairs, pcall, tostring, tonumber
local floor, max, min, format, lower, find, sqrt = math.floor, math.max, math.min, string.format, string.lower,
	string.find, math.sqrt
local Read, IsSecret, Print = ns.Read, ns.IsSecret, ns.Print
local Data, Mog, List = ns.Data, ns.Mog, ns.List
local ST = Mog.ST
local S = ns.STYLE
local WS = ns.WIN

local UI = {}
ns.UI = UI

local WINDOW_NAME = "ForeverTransmogFinderFrame"
local PAD = 12
local TITLE_H = 30
local TABS_Y, FILTER_Y, INFO_Y, LIST_TOP = -36, -66, -98, -122
local FOOT_H = 34
local PREVIEW_W, PANE_GAP = 300, 12
local ROW_H = 34
local SCROLL_W = 10
local CELL, CELL_GAP = 40, 6
local GRID_LINE_H, GRID_HEAD_H = CELL + CELL_GAP, 26
local BODY, SMALL = S.body, S.small
local QUESTION_ICON = 134400
local CHECK_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready"
local STAR_ATLAS = "PetJournal-FavoritesIcon"
local STAR_FALLBACK = "Interface\\Common\\ReputationStar"
local GRIP_TEX = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local GRIP_HL = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight"
local REFRESH_THROTTLE = 1.0
local HOVER_DELAY, HOVER_BACK = 0.08, 0.4
local HERE_EVERY, HERE_MOVE = 2, 5
UI.HERE_EVERY = HERE_EVERY
UI.ROW_H, UI.GRID_LINE_H = ROW_H, GRID_LINE_H

local WHITE, DARK = { 1, 1, 1 }, { 0.08, 0.08, 0.1 }
local BADGE = {
	[1] = { "BOSS", { 0.78, 0.24, 0.24 }, WHITE },
	[2] = { "DROP", { 0.40, 0.43, 0.48 }, WHITE },
	[3] = { "QUEST", { 0.95, 0.80, 0.25 }, DARK },
	[4] = { "VENDOR", { 0.22, 0.60, 0.30 }, WHITE },
	[5] = { "CRAFT", { 0.24, 0.45, 0.85 }, WHITE },
	[6] = { "CHEST", { 0.55, 0.37, 0.20 }, WHITE },
	[7] = { "WORLD", { 0.40, 0.43, 0.48 }, WHITE },
}
UI.BADGE = BADGE

local win
local rows, glines = {}, {}
local view = { tab = "HERE", zone = 0, dungeon = "", search = "", offset = 0, dirty = true, list = nil, builds = 0,
	renders = 0, selected = nil, hover = nil, hoverToken = 0, mode = "list", dist = nil, pos = nil, grid = nil,
	gridCols = 0, herePolls = 0 }
UI.view = view
local lay = { w = WS.W, h = WS.H, listW = 0, listH = 0, rowW = 0, nRows = 1, cols = 1 }
UI.layout = lay

local function Num(v)
	if type(v) == "number" and not IsSecret(v) and v == v then
		return v
	end
	return nil
end

local function Fill(frame, c, a, layer, sub)
	local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
	t:SetAllPoints(frame)
	t:SetColorTexture(c[1], c[2], c[3], a or 1)
	return t
end

local function Edge(frame, c, inset)
	c = c or S.border
	inset = inset or 1
	local t = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	t:SetPoint("TOPLEFT", frame, "TOPLEFT", -inset, inset)
	t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", inset, -inset)
	t:SetColorTexture(c[1], c[2], c[3], 1)
	return t
end

local function Label(parent, size, justify, color, x, y, w, point, rel, relPoint)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pcall(fs.SetFont, fs, S.font, size, "")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	local c = color or S.text
	fs:SetTextColor(c[1], c[2], c[3])
	fs:SetPoint(point or "LEFT", rel or parent, relPoint or point or "LEFT", x or 0, y or 0)
	if w then
		fs:SetWidth(w)
	end
	return fs
end

local function Color(fs, c)
	fs:SetTextColor(c[1], c[2], c[3])
end

local function Shown(region, on)
	if on then
		region:Show()
	else
		region:Hide()
	end
end

local function FlatButton(parent, w, h, text, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, h)
	b.bgTex = Fill(b, S.panel, 1)
	Edge(b)
	b.hl = Fill(b, S.gold, 0.15, "HIGHLIGHT")
	b.label = Label(b, SMALL, "CENTER", S.text, 0, 0, w - 4, "CENTER")
	b.label:SetText(text)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", onClick)
	return b
end

local function ShowTip(owner, lines)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	for i, l in ipairs(lines) do
		if i == 1 then
			GameTooltip:SetText(l, S.gold[1], S.gold[2], S.gold[3])
		else
			GameTooltip:AddLine(l, S.text[1], S.text[2], S.text[3], true)
		end
	end
	GameTooltip:Show()
end

local function HideTip()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

local function Badge(parent, w, h)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(w or 58, h or 15)
	b.bg = Fill(b, BADGE[7][2], 1, "ARTWORK")
	b.label = Label(b, SMALL, "CENTER", WHITE, 0, 0, (w or 58) - 2, "CENTER")
	return b
end

local function SetBadge(b, kind)
	local d = BADGE[kind] or BADGE[7]
	b.bg:SetColorTexture(d[2][1], d[2][2], d[2][3], 1)
	b.label:SetText(d[1])
	Color(b.label, d[3])
	b:Show()
end

local starAtlasOK
local function StarAtlasOK()
	if starAtlasOK == nil then
		local info = C_Texture and Read(C_Texture.GetAtlasInfo, STAR_ATLAS)
		starAtlasOK = type(info) == "table"
	end
	return starAtlasOK
end

local function StarTexture(parent, size)
	local t = parent:CreateTexture(nil, "OVERLAY")
	t:SetSize(size, size)
	t:SetPoint("CENTER", parent, "CENTER", 0, 0)
	local ok = StarAtlasOK() and t.SetAtlas and pcall(t.SetAtlas, t, STAR_ATLAS)
	if not ok then
		t:SetTexture(STAR_FALLBACK)
		t:SetTexCoord(0, 0.5, 0, 0.5)
	end
	return t
end

local function SetStar(t, on)
	if t.SetDesaturated then
		pcall(t.SetDesaturated, t, not on)
	end
	t:SetAlpha(on and 1 or 0.3)
	t.on = on
end

local function StarButton(parent, size, getID)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.star = StarTexture(b, size)
	SetStar(b.star, false)
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function(self)
		local id = getID(self)
		if type(id) == "number" then
			ns.Wish.Toggle(id)
		end
	end)
	b:SetScript("OnEnter", function(self)
		local id = getID(self)
		if type(id) == "number" then
			ShowTip(self, { ns.Wish.Has(id) and "On your wishlist" or "Add to your wishlist",
				ns.Wish.Has(id) and "Click to remove it." or "Starred items get their own tab, a tooltip line and a chat line when you enter a place that has them." })
		end
	end)
	b:SetScript("OnLeave", HideTip)
	return b
end

local function Modified(kind)
	if type(IsModifiedClick) == "function" then
		local ok, v = pcall(IsModifiedClick, kind)
		if ok and not IsSecret(v) then
			return v == true
		end
	end
	if kind == "DRESSUP" then
		return Read(IsControlKeyDown) == true
	end
	return Read(IsShiftKeyDown) == true
end

local function Shown_(frame)
	if not frame then
		return false
	end
	local ok, v = pcall(frame.IsShown, frame)
	return ok and not IsSecret(v) and v == true
end

local function Toggle(parent, w, text, tip, get, set)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(w, 20)
	local box = CreateFrame("Frame", nil, b)
	box:SetSize(12, 12)
	box:SetPoint("LEFT", b, "LEFT", 2, 0)
	Fill(box, { 0, 0, 0 }, 0.6)
	Edge(box)
	local dot = box:CreateTexture(nil, "OVERLAY")
	dot:SetSize(8, 8)
	dot:SetPoint("CENTER", box, "CENTER", 0, 0)
	dot:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
	b.dot = dot
	b.label = Label(b, SMALL, "LEFT", S.text, 18, 0, w - 18)
	b.label:SetText(text)
	b.hl = Fill(b, S.gold, 0.08, "HIGHLIGHT")
	b:RegisterForClicks("LeftButtonUp")
	b:SetScript("OnClick", function()
		set(not get())
	end)
	b:SetScript("OnEnter", function(self)
		ShowTip(self, { text, tip })
	end)
	b:SetScript("OnLeave", HideTip)
	function b.Sync(enabled)
		Shown(dot, get())
		Color(b.label, enabled == false and S.dim or S.text)
	end
	return b
end

ns.W = { Fill = Fill, Edge = Edge, Label = Label, Color = Color, Shown = Shown, FlatButton = FlatButton,
	ShowTip = ShowTip, HideTip = HideTip, Badge = Badge, SetBadge = SetBadge, StarButton = StarButton,
	SetStar = SetStar, Toggle = Toggle, Num = Num }

local Menu = {}
UI.Menu = Menu
local MENU_W, ITEM_H = 230, 20
local menu, catcher

local function CloseMenu()
	if menu then
		menu:Hide()
		catcher:Hide()
	end
end
Menu.Close = CloseMenu

local function BuildMenu()
	catcher = CreateFrame("Button", nil, UIParent)
	catcher:SetAllPoints(UIParent)
	catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	catcher:SetFrameLevel(1)
	catcher:RegisterForClicks("AnyUp")
	catcher:SetScript("OnClick", CloseMenu)
	catcher:Hide()
	menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetFrameLevel(20)
	menu:SetClampedToScreen(true)
	menu:SetWidth(MENU_W)
	menu:EnableMouse(true)
	Fill(menu, S.bg, 0.98)
	Edge(menu, S.gold)
	menu.title = Label(menu, SMALL, "LEFT", S.gold, 8, -6, MENU_W - 16, "TOPLEFT")
	menu.items = {}
	menu:Hide()
end

local function MenuItem(i)
	local b = CreateFrame("Button", nil, menu)
	b:SetSize(MENU_W - 4, ITEM_H)
	b.hl = Fill(b, S.gold, 0.15, "HIGHLIGHT")
	b.check = Label(b, SMALL, "LEFT", S.gold, 6, 0, 14)
	b.label = Label(b, SMALL, "LEFT", S.text, 20, 0, MENU_W - 28)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", function(self)
		local e = self.entry
		CloseMenu()
		if e and not e.disabled and e.func then
			ns.SafeCall(e.func)
		end
	end)
	b:SetScript("OnEnter", function(self)
		local e = self.entry
		if e and e.tip then
			ShowTip(self, { e.text, e.tip })
		end
	end)
	b:SetScript("OnLeave", HideTip)
	menu.items[i] = b
	return b
end

function Menu.Open(anchor, entries, title, x, y)
	if not menu then
		BuildMenu()
	end
	local top = 4
	if title then
		menu.title:SetText(title)
		menu.title:Show()
		top = 22
	else
		menu.title:Hide()
	end
	for i, e in ipairs(entries) do
		local b = menu.items[i] or MenuItem(i)
		b.entry = e
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", menu, "TOPLEFT", 2, -top - (i - 1) * ITEM_H)
		b.label:SetText(e.text)
		Color(b.label, e.disabled and S.dim or S.text)
		b.check:SetText(e.checked and "*" or "")
		b:Show()
	end
	for i = #entries + 1, #menu.items do
		menu.items[i].entry = nil
		menu.items[i]:Hide()
	end
	menu:SetHeight(top + #entries * ITEM_H + 4)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -2)
	catcher:Show()
	menu:Show()
	Menu.entries = entries
end

function Menu.IsOpen()
	return menu ~= nil and Shown_(menu)
end

local function MapOpen()
	local map = WorldMapFrame
	if type(map) ~= "table" or type(map.IsShown) ~= "function" then
		return false
	end
	local ok, shown = pcall(map.IsShown, map)
	if not ok or IsSecret(shown) then
		return true
	end
	return shown == true
end

function UI.Pin(id, si)
	local e = Data.Sources(id)[si]
	local ui, x, y, text = Data.PinTarget(e)
	if not ui then
		Print("No spot for a map pin: " .. tostring(x) .. ".")
		return false
	end
	if ns.InCombat() then
		Print("Map pins work after combat.")
		return false
	end
	if MapOpen() then
		Print("Close the world map first, then set the pin.")
		return false
	end
	if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
		Print("Map pins are not available here. Go to " .. text .. ".")
		return false
	end
	if C_Map.CanSetUserWaypointOnMap and Read(C_Map.CanSetUserWaypointOnMap, ui) == false then
		Print("This map takes no pin. Go to " .. text .. ".")
		return false
	end
	local ok, wasSet = pcall(function()
		return C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(ui, x / 100, y / 100))
	end)
	if not ok or IsSecret(wasSet) or wasSet == false then
		Print("Could not set the pin. Go to " .. text .. ".")
		return false
	end
	Print(format("Map pin for %s: %s. Open the map (M) to see it; click the pin there to track it.", Data.Name(id), text))
	return true
end

function UI.ArrowFor(id, si)
	local api = ForeverPathAPI
	if type(api) ~= "table" then
		return nil
	end
	local e = Data.Sources(id)[si]
	if type(e) ~= "table" or Data.OtherSource(e) then
		return nil
	end
	if type(api.ArrowToPoint) == "function" then
		local ui, x, y, text = Data.PinTarget(e)
		if ui then
			return function()
				local ok, done = pcall(api.ArrowToPoint, ui, x, y, Data.Name(id) .. " - " .. text)
				if not (ok and done) then
					Print("ForeverPath could not point its arrow there. Go to " .. text .. ".")
				end
			end
		end
	end
	if type(api.ArrowTo) == "function" and e[1] == 3 and type(e[6]) == "number" then
		local questID, title = e[6], e[3]
		return function()
			local ok, done = pcall(api.ArrowTo, questID)
			if not (ok and done) then
				Print("ForeverPath has no spot for the quest \"" .. tostring(title) .. "\".")
			end
		end
	end
	return nil
end

function UI.ArrowAction(id)
	local api = ForeverPathAPI
	if type(api) ~= "table" then
		return nil
	end
	if type(api.ArrowToPoint) == "function" then
		local pi = Data.PinIndex(id, true)
		if pi then
			return UI.ArrowFor(id, pi), "ForeverPath arrow"
		end
	end
	if type(api.ArrowTo) == "function" then
		for i, e in ipairs(Data.Sources(id)) do
			if type(e) == "table" and e[1] == 3 and type(e[6]) == "number" and not Data.OtherSource(e) then
				local questID, title = e[6], e[3]
				return function()
					local ok, done = pcall(api.ArrowTo, questID)
					if not (ok and done) then
						Print("ForeverPath has no spot for the quest \"" .. tostring(title) .. "\".")
					end
				end, "ForeverPath arrow (quest)"
			end
		end
	end
	return nil
end

function UI.Preview(id)
	if ns.InCombat() then
		Print("The dressing room opens after combat (the game blocks it for addons in combat).")
		return false
	end
	if type(DressUpItemLink) ~= "function" then
		Print("The dressing room is not available.")
		return false
	end
	local link = Data.Link(id) or ("item:" .. id)
	local ok, shown = pcall(DressUpItemLink, link)
	if ok and not IsSecret(shown) and shown == false then
		Print("The dressing room can't show " .. Data.Name(id) .. " yet. Try again in a moment.")
		return false
	end
	return ok
end

local function InsertChatLink(link)
	local util = ChatFrameUtil
	if type(util) == "table" and type(util.InsertLink) == "function" then
		local ok, done = pcall(util.InsertLink, link)
		return ok and not IsSecret(done) and done == true
	end
	if type(HandleModifiedItemClick) == "function" and Modified("CHATLINK") then
		local ok, done = pcall(HandleModifiedItemClick, link)
		return ok and not IsSecret(done) and done == true
	end
	return false
end

function UI.LinkInChat(id)
	local link = Data.Link(id)
	if not link then
		Print("Item data is loading; try again in a moment.")
		return false
	end
	if InsertChatLink(link) then
		return true
	end
	Print("Open the chat box (Enter) first, then link it again: " .. link)
	return false
end

local copy
function UI.CopyName(id)
	if not win then
		return
	end
	if not copy then
		copy = CreateFrame("Frame", nil, win)
		copy:SetSize(380, 64)
		copy:SetPoint("CENTER", win, "CENTER", 0, 40)
		copy:SetFrameStrata("DIALOG")
		copy:EnableMouse(true)
		Fill(copy, S.bg, 1)
		Edge(copy, S.gold)
		local t = Label(copy, SMALL, "LEFT", S.gold, 10, -10, 360, "TOPLEFT")
		t:SetText("Copy: press Ctrl+C, then Esc or Enter.")
		local e = CreateFrame("EditBox", nil, copy)
		e:SetSize(356, 22)
		e:SetPoint("TOPLEFT", copy, "TOPLEFT", 12, -30)
		e:SetAutoFocus(false)
		pcall(e.SetFont, e, S.font, BODY, "")
		e:SetTextInsets(4, 4, 0, 0)
		Fill(e, { 0, 0, 0 }, 0.6)
		Edge(e)
		e:SetScript("OnEscapePressed", function(self)
			self:ClearFocus()
			copy:Hide()
		end)
		e:SetScript("OnEnterPressed", function(self)
			self:ClearFocus()
			copy:Hide()
		end)
		e:SetScript("OnTextChanged", function(self, userInput)
			if userInput and copy.text then
				self:SetText(copy.text)
				self:HighlightText()
			end
		end)
		copy.edit = e
	end
	copy.text = Data.Name(id)
	copy.edit:SetText(copy.text)
	copy:Show()
	copy.edit:SetFocus()
	copy.edit:HighlightText()
end

local srcPop
local POP_W, POP_LINE = 560, 20
function UI.ShowSources(anchor, id)
	if not win then
		return
	end
	if not srcPop then
		srcPop = CreateFrame("Frame", nil, win)
		srcPop:SetWidth(POP_W)
		srcPop:SetFrameStrata("DIALOG")
		srcPop:SetClampedToScreen(true)
		srcPop:EnableMouse(true)
		Fill(srcPop, S.bg, 0.98)
		Edge(srcPop, S.gold)
		srcPop.title = Label(srcPop, BODY, "LEFT", S.gold, 10, -10, POP_W - 50, "TOPLEFT")
		local close = FlatButton(srcPop, 18, 18, "x", function()
			srcPop:Hide()
		end)
		close:SetPoint("TOPRIGHT", srcPop, "TOPRIGHT", -6, -6)
		srcPop.hint = Label(srcPop, SMALL, "LEFT", S.muted, 10, 8, POP_W - 20, "BOTTOMLEFT")
		srcPop.lines = {}
	end
	local list = Data.Sources(id)
	srcPop.title:SetText(Data.Name(id) .. ": " .. #list .. " source" .. (#list == 1 and "" or "s"))
	local order = Data.SourceOrder(id)
	for i, si in ipairs(order) do
		local e = list[si]
		local b = srcPop.lines[i]
		if not b then
			b = CreateFrame("Button", nil, srcPop)
			b:SetSize(POP_W - 20, POP_LINE)
			b:SetPoint("TOPLEFT", srcPop, "TOPLEFT", 10, -32 - (i - 1) * POP_LINE)
			b.hl = Fill(b, S.gold, 0.12, "HIGHLIGHT")
			b.label = Label(b, SMALL, "LEFT", S.text, 4, 0, POP_W - 28)
			b:RegisterForClicks("LeftButtonUp")
			b:SetScript("OnClick", function(self)
				if self.id and self.pin then
					UI.Pin(self.id, self.si)
				end
			end)
			srcPop.lines[i] = b
		end
		b.id, b.si = id, si
		b.pin = Data.PinTarget(e) ~= nil
		b.label:SetText(i .. ". " .. Data.SourceText(e))
		Color(b.label, Data.OtherSource(e) and S.dim or (b.pin and S.teal or S.text))
		b:Show()
	end
	for i = #order + 1, #srcPop.lines do
		srcPop.lines[i]:Hide()
	end
	srcPop.hint:SetText("Blue lines have a spot: click one for a map pin (out of combat, world map closed).")
	srcPop:SetHeight(32 + max(1, #list) * POP_LINE + 28)
	srcPop:ClearAllPoints()
	srcPop:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 40, 0)
	srcPop.id = id
	srcPop:Show()
end

function UI.OpenItemMenu(anchor, id)
	local entries = {}
	local pi = Data.PinIndex(id)
	local pinTip
	if pi then
		local _, _, _, text = Data.PinTarget(Data.Sources(id)[pi])
		pinTip = text
	else
		pinTip = "None of this item's sources has a known spot."
	end
	entries[#entries + 1] = { text = "Map pin to source", disabled = pi == nil, tip = pinTip, func = function()
		UI.Pin(id, pi)
	end }
	local arrow, arrowText = UI.ArrowAction(id)
	if arrow then
		entries[#entries + 1] = { text = arrowText, func = arrow }
	end
	local n = #Data.Sources(id)
	entries[#entries + 1] = { text = "All sources (" .. n .. ")", func = function()
		UI.ShowSources(anchor, id)
	end }
	entries[#entries + 1] = { text = ns.Wish.Has(id) and "Remove from wishlist" or "Add to wishlist", func = function()
		ns.Wish.Toggle(id)
	end }
	entries[#entries + 1] = { text = "Preview (dressing room)", func = function()
		UI.Preview(id)
	end }
	entries[#entries + 1] = { text = "Link in chat", func = function()
		UI.LinkInChat(id)
	end }
	entries[#entries + 1] = { text = "Copy name", func = function()
		UI.CopyName(id)
	end }
	Menu.Open(anchor, entries, Data.Name(id), 40, 2)
end

local function Note(text, color, action)
	return { t = "note", text = text, color = color or S.muted, action = action }
end

local function OffNotes(lines)
	local preset = (type(PRESET_LABEL) == "string" and not IsSecret(PRESET_LABEL)) and PRESET_LABEL or "Preset"
	local why = Mog.preset == "Classic" and "This character is on the Classic preset" or "The game says transmog is off for this character"
	table.insert(lines, 1, Note("Transmog is part of the Enhanced experience on Forever. " .. why
		.. ", so it does not collect appearances.", S.orange))
	table.insert(lines, 2, Note("To turn it on: Options > " .. preset .. " > Enhanced (this addon never changes it). "
		.. "The lists below still show where every item comes from.", S.orange))
end

local function NotReadyList()
	local st = Data.state
	if st == "error" then
		return { lines = { Note(Data.error or "The item list could not load.", S.red),
			Note("Item tooltips still show the transmog status of any item.") }, shown = 0, missing = 0 }
	end
	if Data.waitingForCombat then
		return { lines = { Note("The item list loads when combat ends.") }, shown = 0, missing = 0 }
	end
	return { lines = { Note("Loading the item list...") }, shown = 0, missing = 0 }
end

local function FilterPlaces(res, q)
	if not q then
		return res
	end
	local out = {}
	for _, l in ipairs(res.lines) do
		if find(lower(l.name), q, 1, true) then
			out[#out + 1] = l
		end
	end
	res.lines, res.shown = out, #out
	return res
end

local function TitleOfInst(key)
	local info = Data.InstInfo(key)
	local name = Data.InstName(key)
	if info then
		return format("%s  (%d-%d %s)", name, info[3] or 0, info[4] or 0, info[2] or "dungeon")
	end
	return name
end

local function HereList(place, f, search)
	view.pos, view.dist = nil, nil
	local x, y = Data.PlayerPos(place.key)
	if x then
		local w, h = Data.MapYards(place.key)
		if w then
			view.pos = { zone = place.key, px = x, py = y, w = w, h = h }
			view.dist = List.Distances(place.key, x, y)
		end
	end
	return List.Place("zone", place.key, f, search, view.dist)
end

local function BuildList()
	local f = ns.db.filters
	local tab, search = view.tab, view.search
	local res
	view.back = nil
	view.pos, view.dist = nil, nil
	if not Data.Ready() then
		res = NotReadyList()
		res.title = "Forever Transmog Finder"
		return res
	end
	local placeHasItems = false
	if tab == "HERE" then
		local place = Data.CurrentPlace()
		if not place then
			res = { lines = { Note("Can't tell where you are right now. Try again in a moment.") }, shown = 0, missing = 0 }
			res.title = "Here"
		elseif not place.listed then
			local lines = { Note("Nothing in the item list drops, sells or rewards here (" .. place.name .. ").") }
			if place.kind == "inst" then
				lines[2] = Note("Forever's own new dungeons have no loot data yet; their items show as world drops.")
			end
			res = { lines = lines, shown = 0, missing = 0, title = "Here: " .. place.name }
		else
			if place.kind == "inst" then
				res = List.Place("inst", place.key, f, search)
			else
				res = HereList(place, f, search)
			end
			res.title = "Here: " .. (place.kind == "inst" and TitleOfInst(place.key) or place.name)
			placeHasItems = true
		end
	elseif tab == "ZONES" then
		if view.zone ~= 0 and #Data.ZoneItems(view.zone) > 0 then
			res = List.Place("zone", view.zone, f, search)
			res.title = Data.ZoneName(view.zone)
			view.back = "Zones"
			placeHasItems = true
		else
			view.zone = 0
			res = FilterPlaces(List.Places("zone", f), List.Query(search))
			res.title = "Zones"
		end
	elseif tab == "DUNGEONS" then
		if view.dungeon ~= "" and #Data.InstItems(view.dungeon) > 0 then
			res = List.Place("inst", view.dungeon, f, search)
			res.title = TitleOfInst(view.dungeon)
			view.back = "Dungeons"
			placeHasItems = true
		else
			view.dungeon = ""
			res = FilterPlaces(List.Places("inst", f), List.Query(search))
			res.title = "Dungeons and raids"
		end
	elseif tab == "ALL" then
		res = List.All(f, search)
		res.title = "All items"
	elseif tab == "WISHLIST" then
		res = List.Wish(f, search)
		res.title = "Your wishlist"
	else
		if Mog.On() then
			res = List.Stats()
			local copyRes = { lines = {}, shown = res.shown, missing = res.missing, have = res.have, total = res.total }
			for i, l in ipairs(res.lines) do
				copyRes.lines[i] = l
			end
			res = copyRes
			if #res.lines == 0 then
				res.lines[1] = Note("Nothing checked yet: the collection check is still running.")
			end
		else
			res = { lines = {}, shown = 0, missing = 0 }
		end
		res.title = "Your collection"
	end
	if not Mog.On() then
		OffNotes(res.lines)
	elseif res.shown == 0 and #res.lines == 0 then
		local q = List.Query(search)
		if tab == "ZONES" or tab == "DUNGEONS" then
			res.lines[1] = Note(q and "No place matches: clear the search." or "No place matches the filters.", nil, q and "clear")
		elseif tab == "WISHLIST" and (res.wishCount or 0) == 0 then
			res.lines[1] = Note("Your wishlist is empty. Click the star on any item to add it.")
		elseif q then
			res.lines[1] = Note("No results: clear the search.", nil, "clear")
		elseif placeHasItems and res.passed == 0 then
			res.lines[1] = Note("Nothing here matches the filters (slot, quality, level, armor type).")
		elseif ns.db.filters.showCollected or res.passed == 0 then
			res.lines[1] = Note("Nothing matches the filters.")
		elseif placeHasItems then
			res.lines[1] = Note("Nothing missing here. Tick \"Show collected\" to see the rest.", S.green)
		else
			res.lines[1] = Note("Nothing missing that matches the filters. Tick \"Show collected\" to see the rest.")
		end
	end
	return res
end

local MARK = {
	[ST.MISSING] = { "MISSING", S.gold },
	[ST.EXACT] = { "COLLECTED", S.muted },
	[ST.KNOWN] = { "COLLECTED (OTHER ITEM)", S.muted },
	[ST.CANT] = { "CAN'T", S.red },
	[ST.PENDING] = { "...", S.dim },
	[ST.UNKNOWN] = { "checking", S.dim },
}
UI.MARK = MARK

local DIM_HEX = format("|cff%02x%02x%02x", floor(S.dim[1] * 255 + 0.5), floor(S.dim[2] * 255 + 0.5),
	floor(S.dim[3] * 255 + 0.5))

function UI.Tags(id)
	local tags = {}
	if Data.OtherFaction(id) then
		tags[#tags + 1] = "other faction"
	end
	if ns.db.armorTag and Data.NotMyArmor(id) then
		tags[#tags + 1] = "not for your armor type"
	end
	return tags
end

function UI.KindText(id)
	local row = Data.Item(id)
	local lvl = row and row[6]
	local text = Data.TypeText(id)
	if type(lvl) == "number" and lvl > 1 then
		text = text .. ns.DOT .. "level " .. lvl
	end
	local tags = UI.Tags(id)
	if #tags > 0 then
		text = text .. DIM_HEX .. ns.DOT .. table.concat(tags, ns.DOT) .. "|r"
	end
	return text
end

local Render

local function PreviewShow(id)
	if ns.Preview and ns.Preview.Show then
		ns.Preview.Show(id)
	end
end

function UI.Select(id)
	view.selected = id
	view.hover = nil
	view.hoverToken = view.hoverToken + 1
	PreviewShow(id)
	Render()
end

function UI.HoverItem(id)
	if not (ns.db and ns.db.previewHover) or type(id) ~= "number" then
		return
	end
	view.hoverToken = view.hoverToken + 1
	local token = view.hoverToken
	ns.After(HOVER_DELAY, function()
		if token == view.hoverToken and UI.IsShown() then
			view.hover = id
			PreviewShow(id)
		end
	end)
end

local function OverPreview()
	local pane = win and win.preview
	if not pane or type(pane.IsMouseOver) ~= "function" then
		return false
	end
	return Read(pane.IsMouseOver, pane) == true
end

local function HoverBack(token)
	if token ~= view.hoverToken or view.hover == nil or not UI.IsShown() then
		return
	end
	if OverPreview() then
		ns.After(HOVER_BACK, function()
			HoverBack(token)
		end)
		return
	end
	view.hover = nil
	PreviewShow(view.selected)
end

function UI.HoverEnd()
	if not (ns.db and ns.db.previewHover) then
		return
	end
	view.hoverToken = view.hoverToken + 1
	local token = view.hoverToken
	ns.After(HOVER_BACK, function()
		HoverBack(token)
	end)
end

local function ItemClick(owner, id, button)
	HideTip()
	if button == "RightButton" then
		UI.OpenItemMenu(owner, id)
	elseif Modified("DRESSUP") then
		UI.Preview(id)
	elseif Modified("CHATLINK") then
		UI.LinkInChat(id)
	else
		UI.Select(id)
	end
end

local function ItemTooltip(owner, id)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local ok = pcall(GameTooltip.SetItemByID, GameTooltip, id)
	if not ok then
		pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id)
	end
	local st = Mog.StatusOf(id)
	if st == ST.KNOWN then
		GameTooltip:AddLine("You have this look from another item.", S.muted[1], S.muted[2], S.muted[3], true)
	end
	local d = view.dist and view.dist[id]
	if d then
		GameTooltip:AddLine(Data.YardsText(d) .. " from you", S.teal[1], S.teal[2], S.teal[3])
	end
	local tags = UI.Tags(id)
	if #tags > 0 then
		GameTooltip:AddLine(table.concat(tags, ns.DOT), S.dim[1], S.dim[2], S.dim[3], true)
	end
	GameTooltip:AddLine("Click: try on.  Shift-click: link.  Ctrl-click: dressing room.  Right-click: menu.",
		S.dim[1], S.dim[2], S.dim[3], true)
	GameTooltip:Show()
end

local function RowClick(self, button)
	local line = self.line
	if type(line) == "number" then
		ItemClick(self, line, button)
	elseif type(line) == "table" and line.t == "place" then
		UI.Drill(line.kind, line.key)
	elseif type(line) == "table" and line.t == "note" and line.action == "clear" then
		UI.ClearSearch()
	end
end

local function RowEnter(self)
	local line = self.line
	if type(line) == "number" then
		ItemTooltip(self, line)
		UI.HoverItem(line)
	elseif type(line) == "table" and line.t == "place" then
		ShowTip(self, { line.name, "Click to list its items." })
	end
end

local function RowLeave()
	HideTip()
	UI.HoverEnd()
end

local function NewRow(parent, i)
	local r = CreateFrame("Button", nil, parent)
	r:SetSize(lay.rowW, ROW_H)
	r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.band = Fill(r, S.panel, 1, "BACKGROUND")
	r.hl = Fill(r, S.text, 0.06, "HIGHLIGHT")
	r.sel = Fill(r, S.gold, 0.10, "BORDER")
	r.selEdge = r:CreateTexture(nil, "OVERLAY")
	r.selEdge:SetWidth(2)
	r.selEdge:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
	r.selEdge:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
	r.selEdge:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(26, 26)
	r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
	r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	r.name = Label(r, BODY, "LEFT", S.text, 40, 8, 200)
	r.kind = Label(r, SMALL, "LEFT", S.muted, 248, 8, 200)
	r.mark = Label(r, SMALL, "RIGHT", S.gold, -28, 8, 170, "RIGHT")
	r.starBtn = StarButton(r, 16, function(self)
		return self:GetParent().line
	end)
	r.starBtn:SetPoint("RIGHT", r, "RIGHT", -6, 8)
	r.badge = Badge(r, 58, 15)
	r.badge:SetPoint("LEFT", r, "LEFT", 40, -8)
	r.src = Label(r, SMALL, "LEFT", S.teal, 104, -8, 300)
	r.dist = Label(r, SMALL, "RIGHT", S.teal, -88, -8, 76, "RIGHT")
	r.more = FlatButton(r, 76, 16, "", function(self)
		local id = self:GetParent().line
		if type(id) == "number" then
			UI.ShowSources(self:GetParent(), id)
		end
	end)
	r.more:SetPoint("RIGHT", r, "RIGHT", -6, -8)
	r.barBg = r:CreateTexture(nil, "ARTWORK")
	r.barBg:SetSize(160, 6)
	r.barBg:SetPoint("RIGHT", r, "RIGHT", -28, -8)
	r.barBg:SetColorTexture(S.border[1], S.border[2], S.border[3], 1)
	r.bar = r:CreateTexture(nil, "OVERLAY")
	r.bar:SetHeight(6)
	r.bar:SetPoint("LEFT", r.barBg, "LEFT", 0, 0)
	r.bar:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
	r.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pcall(r.note.SetFont, r.note, S.font, BODY, "")
	r.note:SetJustifyH("LEFT")
	r.note:SetWordWrap(true)
	r.note:SetWidth(lay.rowW - 12)
	r.note:SetPoint("LEFT", r, "LEFT", 6, 0)
	r:SetScript("OnClick", RowClick)
	r:SetScript("OnEnter", RowEnter)
	r:SetScript("OnLeave", RowLeave)
	r:Hide()
	return r
end

local function SizeRow(r)
	local w = lay.rowW
	r:SetWidth(w)
	local nameW = floor((w - 40 - 28 - 170 - 12) * 0.5)
	r.name:SetWidth(nameW)
	r.kindX = 40 + nameW + 8
	r.kindW = max(40, w - 40 - nameW - 8 - 28 - 170 - 4)
	r.kind:ClearAllPoints()
	r.kind:SetPoint("LEFT", r, "LEFT", r.kindX, 8)
	r.kind:SetWidth(r.kindW)
	r.src:SetWidth(max(60, w - 104 - 88 - 80))
	r.note:SetWidth(w - 12)
end

local function FitKind(r)
	local mw = Num(Read(r.mark.GetStringWidth, r.mark))
	if mw and mw > 0 then
		r.kind:SetWidth(max(r.kindW, lay.rowW - 28 - floor(mw + 0.5) - 12 - r.kindX))
	else
		r.kind:SetWidth(r.kindW)
	end
end

local function ShowParts(r, icon, two, bar, note)
	Shown(r.icon, icon)
	Shown(r.name, not note)
	Shown(r.kind, not note)
	Shown(r.mark, not note)
	Shown(r.src, two)
	Shown(r.badge, two)
	Shown(r.dist, two)
	Shown(r.starBtn, icon)
	Shown(r.barBg, bar)
	Shown(r.bar, bar)
	Shown(r.note, note)
	if not two then
		r.more:Hide()
	end
	if not icon then
		r.sel:Hide()
		r.selEdge:Hide()
	end
end

local function SetBar(bar, frac, width)
	frac = max(0, min(1, frac or 0))
	if frac <= 0 then
		bar:Hide()
	else
		bar:SetWidth(floor((width or 160) * frac + 0.5))
		bar:Show()
	end
end

local function CountText(have, total)
	return ns.Comma(have) .. " / " .. ns.Comma(total)
end

local function ConfigureItem(r, id, where)
	ShowParts(r, true, true, false, false)
	r.band:Hide()
	local selected = view.selected == id
	Shown(r.sel, selected)
	Shown(r.selEdge, selected)
	r.icon:SetTexture(Data.Icon(id) or QUESTION_ICON)
	r.name:SetText(Data.Name(id))
	r.name:SetTextColor(Data.QualityColor(Data.Quality(id)))
	r.kind:SetText(UI.KindText(id))
	local st = Mog.StatusOf(id)
	local m = (Mog.On() and MARK[st]) or { "", S.dim }
	r.mark:SetText(m[1])
	Color(r.mark, m[2])
	FitKind(r)
	SetStar(r.starBtn.star, ns.Wish.Has(id))
	local list = Data.Sources(id)
	local si = (where ~= nil and Data.BestIndex(id, where)) or Data.BestIndex(id)
	local e = si and list[si]
	SetBadge(r.badge, type(e) == "table" and e[1] or 7)
	r.src:SetText(e and Data.SourceText(e, where, true) or "Source unknown")
	Color(r.src, Data.OtherSource(e) and S.dim or S.teal)
	local d = view.dist and view.dist[id]
	r.dist:SetText(d and Data.YardsText(d) or "")
	local more = #list - 1
	if more > 0 then
		r.more.label:SetText("+" .. more .. " more")
		r.more:Show()
	else
		r.more:Hide()
	end
end

local function ConfigureRow(r, line, where)
	if type(line) == "number" then
		ConfigureItem(r, line, where)
		return
	end
	local t = line.t
	if t == "head" then
		ShowParts(r, false, false, line.on == true and not line.plain, false)
		r.band:Show()
		r.name:SetText(line.text)
		Color(r.name, S.gold)
		r.kind:SetText("")
		if line.plain then
			r.mark:SetText("")
		elseif line.on then
			r.mark:SetText(CountText(line.have, line.total) .. " collected")
			Color(r.mark, line.have >= line.total and S.green or S.muted)
			SetBar(r.bar, line.total > 0 and line.have / line.total or 0)
		else
			r.mark:SetText(line.total .. " item" .. (line.total == 1 and "" or "s"))
			Color(r.mark, S.muted)
		end
	elseif t == "place" then
		ShowParts(r, false, false, line.on, false)
		r.band:Hide()
		r.name:SetText(line.name)
		Color(r.name, S.text)
		local kind = ""
		if line.minLevel then
			kind = format("level %d-%d%s%s", line.minLevel, line.maxLevel or line.minLevel, ns.DOT, line.itype or "")
		end
		if line.on and line.missing > 0 then
			kind = kind .. (kind ~= "" and ns.DOT or "") .. line.missing .. " missing"
		end
		r.kind:SetText(kind)
		if line.on then
			r.mark:SetText(CountText(line.have or 0, line.total))
			Color(r.mark, (line.have or 0) >= line.total and S.green or S.gold)
			SetBar(r.bar, line.total > 0 and (line.have or 0) / line.total or 0)
		else
			r.mark:SetText(line.total .. " items")
			Color(r.mark, S.muted)
		end
		FitKind(r)
	elseif t == "stat" then
		ShowParts(r, false, false, true, false)
		r.band:Hide()
		r.name:SetText(line.text)
		Color(r.name, S.text)
		r.kind:SetText("")
		local pct = line.total > 0 and floor(100 * line.have / line.total) or 0
		r.mark:SetText(format("%s / %s  (%d%%)", ns.Comma(line.have), ns.Comma(line.total), pct))
		Color(r.mark, S.text)
		SetBar(r.bar, line.total > 0 and line.have / line.total or 0)
	else
		ShowParts(r, false, false, false, true)
		r.band:Hide()
		r.note:SetText(line.text)
		Color(r.note, line.color or S.muted)
	end
end

local function CellEnter(self)
	local id = self.id
	if type(id) == "number" then
		ItemTooltip(self, id)
		UI.HoverItem(id)
	end
end

local function CellClick(self, button)
	if type(self.id) == "number" then
		ItemClick(self, self.id, button)
	end
end

local function NewCell(gl)
	local c = CreateFrame("Button", nil, gl)
	c:SetSize(CELL, CELL)
	c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	c.border = Edge(c, S.border, 2)
	c.icon = c:CreateTexture(nil, "ARTWORK")
	c.icon:SetAllPoints(c)
	c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	c.sel = Fill(c, S.gold, 0.30, "OVERLAY")
	c.hl = Fill(c, S.text, 0.15, "HIGHLIGHT")
	c.check = c:CreateTexture(nil, "OVERLAY", nil, 2)
	c.check:SetSize(16, 16)
	c.check:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 2, -2)
	c.check:SetTexture(CHECK_TEX)
	c.starBtn = StarButton(c, 14, function(self)
		return self:GetParent().id
	end)
	c.starBtn:SetPoint("TOPRIGHT", c, "TOPRIGHT", 3, 3)
	c:SetScript("OnClick", CellClick)
	c:SetScript("OnEnter", CellEnter)
	c:SetScript("OnLeave", RowLeave)
	return c
end

local function NewGridLine(parent)
	local gl = CreateFrame("Frame", nil, parent)
	gl:SetSize(lay.rowW, GRID_LINE_H)
	gl:EnableMouse(false)
	gl.band = Fill(gl, S.panel, 1, "BACKGROUND")
	gl.name = Label(gl, BODY, "LEFT", S.gold, 8, 0, 300)
	gl.mark = Label(gl, SMALL, "RIGHT", S.muted, -8, 0, 170, "RIGHT")
	gl.barBg = gl:CreateTexture(nil, "ARTWORK")
	gl.barBg:SetSize(120, 4)
	gl.barBg:SetPoint("RIGHT", gl, "RIGHT", -186, 0)
	gl.barBg:SetColorTexture(S.border[1], S.border[2], S.border[3], 1)
	gl.bar = gl:CreateTexture(nil, "OVERLAY")
	gl.bar:SetHeight(4)
	gl.bar:SetPoint("LEFT", gl.barBg, "LEFT", 0, 0)
	gl.bar:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
	gl.note = Label(gl, BODY, "LEFT", S.muted, 8, 0, lay.rowW - 16)
	gl.cells = {}
	gl:Hide()
	return gl
end

local function GridLines(lines, cols)
	local out, cur = {}, nil
	for i = 1, #lines do
		local l = lines[i]
		if type(l) == "number" then
			if not cur or #cur.ids >= cols then
				cur = { t = "cells", ids = {} }
				out[#out + 1] = cur
			end
			cur.ids[#cur.ids + 1] = l
		else
			cur = nil
			out[#out + 1] = l
		end
	end
	return out
end

local function LineH(l)
	if view.mode == "grid" then
		return (type(l) == "table" and l.t == "cells") and GRID_LINE_H or GRID_HEAD_H
	end
	return ROW_H
end

local function ConfigureCell(c, id)
	c.id = id
	c.icon:SetTexture(Data.Icon(id) or QUESTION_ICON)
	local r, g, b = Data.QualityColor(Data.Quality(id))
	c.border:SetColorTexture(r, g, b, 1)
	Shown(c.check, Mog.On() and Mog.IsCollected(Mog.StatusOf(id)))
	Shown(c.sel, view.selected == id)
	SetStar(c.starBtn.star, ns.Wish.Has(id))
	c:Show()
end

local function ConfigureGridLine(gl, l)
	gl:SetWidth(lay.rowW)
	if type(l) == "table" and l.t == "cells" then
		gl:SetHeight(GRID_LINE_H)
		gl.band:Hide()
		gl.name:Hide()
		gl.mark:Hide()
		gl.barBg:Hide()
		gl.bar:Hide()
		gl.note:Hide()
		for k = 1, #l.ids do
			local c = gl.cells[k]
			if not c then
				c = NewCell(gl)
				gl.cells[k] = c
			end
			c:ClearAllPoints()
			c:SetPoint("TOPLEFT", gl, "TOPLEFT", 2 + (k - 1) * GRID_LINE_H, -3)
			ConfigureCell(c, l.ids[k])
		end
		for k = #l.ids + 1, #gl.cells do
			gl.cells[k].id = nil
			gl.cells[k]:Hide()
		end
		return
	end
	gl:SetHeight(GRID_HEAD_H)
	for k = 1, #gl.cells do
		gl.cells[k].id = nil
		gl.cells[k]:Hide()
	end
	if l.t == "head" then
		gl.band:Show()
		gl.note:Hide()
		gl.name:SetText(l.text)
		gl.name:SetWidth(max(60, lay.rowW - (l.plain and 16 or (l.on and 322 or 194))))
		gl.name:Show()
		if l.plain then
			gl.mark:Hide()
			gl.barBg:Hide()
			gl.bar:Hide()
		elseif l.on then
			gl.mark:SetText(CountText(l.have, l.total) .. " collected")
			Color(gl.mark, l.have >= l.total and S.green or S.muted)
			gl.mark:Show()
			gl.barBg:Show()
			SetBar(gl.bar, l.total > 0 and l.have / l.total or 0, 120)
		else
			gl.mark:SetText(l.total .. " item" .. (l.total == 1 and "" or "s"))
			gl.mark:Show()
			gl.barBg:Hide()
			gl.bar:Hide()
		end
	else
		gl.band:Hide()
		gl.name:Hide()
		gl.mark:Hide()
		gl.barBg:Hide()
		gl.bar:Hide()
		gl.note:SetWidth(lay.rowW - 16)
		gl.note:SetText(l.text or "")
		Color(gl.note, l.color or S.muted)
		gl.note:Show()
	end
end

local rendering = false

local function DisplayLines()
	local res = view.list
	local lines = res and res.lines or {}
	if view.mode ~= "grid" then
		return lines
	end
	if not view.grid or view.gridCols ~= lay.cols or view.gridOf ~= res then
		view.grid = GridLines(lines, lay.cols)
		view.gridCols, view.gridOf = lay.cols, res
	end
	return view.grid
end
UI.DisplayLines = DisplayLines

local function MaxOffset()
	local lines = DisplayLines()
	local n = #lines
	if view.mode ~= "grid" then
		return max(0, n - lay.nRows)
	end
	local acc, i = 0, n
	while i >= 1 do
		local h = LineH(lines[i])
		if acc + h > lay.listH then
			break
		end
		acc = acc + h
		i = i - 1
	end
	return max(0, i)
end

local function RenderList(res, lines)
	for i = 1, #glines do
		glines[i]:Hide()
	end
	for i = 1, lay.nRows do
		local r = rows[i]
		local line = lines[view.offset + i]
		if line ~= nil then
			r.line = line
			ConfigureRow(r, line, res and res.where)
			r:Show()
		else
			r.line = nil
			r:Hide()
		end
	end
	for i = lay.nRows + 1, #rows do
		rows[i].line = nil
		rows[i]:Hide()
	end
end

local function RenderGrid(lines)
	for i = 1, #rows do
		rows[i].line = nil
		rows[i]:Hide()
	end
	local y, j = 0, 0
	local i = view.offset + 1
	while i <= #lines do
		local l = lines[i]
		local h = LineH(l)
		if y + h > lay.listH then
			break
		end
		j = j + 1
		local gl = glines[j]
		if not gl then
			gl = NewGridLine(win.listPane)
			glines[j] = gl
		end
		gl:ClearAllPoints()
		gl:SetPoint("TOPLEFT", win.listPane, "TOPLEFT", 0, -y)
		gl.line = l
		ConfigureGridLine(gl, l)
		gl:Show()
		y = y + h
		i = i + 1
	end
	for k = j + 1, #glines do
		glines[k].line = nil
		glines[k]:Hide()
	end
	view.gridShown = j
end

function Render()
	if not win then
		return
	end
	local res = view.list
	view.mode = (ns.db.grid and res and res.hasItems) and "grid" or "list"
	local lines = DisplayLines()
	local maxOff = MaxOffset()
	if view.offset > maxOff then
		view.offset = maxOff
	end
	if view.offset < 0 then
		view.offset = 0
	end
	if view.mode == "grid" then
		RenderGrid(lines)
	else
		RenderList(res, lines)
	end
	rendering = true
	win.scroll:SetMinMaxValues(0, maxOff)
	win.scroll:SetValue(view.offset)
	rendering = false
	Shown(win.scroll, maxOff > 0)
	Color(win.viewList.label, ns.db.grid and S.muted or S.gold)
	Color(win.viewGrid.label, ns.db.grid and S.gold or S.muted)
	Shown(win.viewList.on, not ns.db.grid)
	Shown(win.viewGrid.on, ns.db.grid)
	view.renders = (view.renders or 0) + 1
end
UI.Render = Render

local function SetOffset(o)
	o = max(0, min(floor(o + 0.5), MaxOffset()))
	if o ~= view.offset then
		view.offset = o
		Render()
	end
end
UI.SetOffset = SetOffset

local function TopItem()
	local lines = DisplayLines()
	for i = view.offset + 1, min(#lines, view.offset + 40) do
		local l = lines[i]
		if type(l) == "number" then
			return l
		elseif type(l) == "table" and l.t == "cells" then
			return l.ids[1]
		end
	end
	return nil
end

local function LineOfItem(id)
	if not id then
		return nil
	end
	local lines = DisplayLines()
	for i = 1, #lines do
		local l = lines[i]
		if l == id then
			return i
		elseif type(l) == "table" and l.t == "cells" then
			for k = 1, #l.ids do
				if l.ids[k] == id then
					return i
				end
			end
		end
	end
	return nil
end

local function UpdateTabs()
	for _, key in ipairs(ns.TABS) do
		local b = win.tabs[key]
		local on = view.tab == key
		Color(b.label, on and S.gold or S.muted)
		Shown(b.underline, on)
	end
	local n = ns.Wish.Count()
	win.tabs.WISHLIST.label:SetText(n > 0 and ("WISHLIST " .. n) or "WISHLIST")
end

local function UpdateFilters()
	local f = ns.db.filters
	win.slotBtn.label:SetText("Slot: " .. (ns.SLOT_LABEL[f.slot] or "All slots"))
	local ql = "Any quality"
	for _, q in ipairs(ns.QUALITIES) do
		if q.value == f.minQuality then
			ql = q.label
		end
	end
	win.qualBtn.label:SetText("Quality: " .. ql)
	win.sortBtn.label:SetText("Sort: " .. (ns.SORT_LABEL[f.sort] or "Source"))
	local on = Mog.On()
	win.armor.Sync(Data.armor ~= nil)
	win.collected.Sync(on)
	win.lmin:SetText(tostring(f.levelMin))
	win.lmax:SetText(tostring(f.levelMax))
end

local function UpdateHeader()
	local text, frac = "", nil
	if Data.Ready() and Mog.On() then
		local p, stale = List.Progress(ns.db.filters, ns.InCombat())
		if stale then
			view.staleHeader = true
		end
		local pct = p.total > 0 and floor(100 * p.have / p.total) or 0
		text = format("%s / %s appearances (%d%%)", ns.Comma(p.have), ns.Comma(p.total), pct)
		frac = p.total > 0 and p.have / p.total or 0
	elseif not Mog.On() then
		text = "Transmog is off on this character"
	end
	win.summary:SetText(text)
	Shown(win.progBg, frac ~= nil)
	if frac then
		SetBar(win.progBar, frac, 120)
	else
		win.progBar:Hide()
	end
	UI.progress = frac
end

local function UpdateFooter()
	local text, c = "", S.muted
	if Data.Ready() and Mog.On() then
		local s = Mog.ScanInfo()
		if s.done then
			text = "Collection checked" .. (s.pending > 0 and (ns.DOT .. s.pending .. " waiting for item data") or "")
		elseif s.paused or (s.running and ns.InCombat()) then
			text, c = format("Check paused in combat (%d%%)", floor(100 * Mog.Progress())), S.orange
		elseif s.running then
			text = format("Checking your collection %d%%", floor(100 * Mog.Progress()))
		end
	elseif Data.state == "indexing" or Data.state == "loading" then
		text = "Building the lists..."
	end
	win.status:SetText(text)
	Color(win.status, c)
end

local function UpdateInfo(res)
	win.title2:SetText(res.title or "")
	local right = ""
	if Data.Ready() then
		if res.lines[1] and type(res.lines[1]) == "table" and res.lines[1].t == "place" then
			right = res.shown .. (view.tab == "ZONES" and " zones" or " dungeons and raids")
		elseif view.tab == "STATS" then
			if res.total then
				local pct = res.total > 0 and floor(100 * res.have / res.total) or 0
				right = format("%s of %s appearances (%d%%)", ns.Comma(res.have), ns.Comma(res.total), pct)
			end
		elseif view.tab == "WISHLIST" then
			right = format("%s starred%s%s missing", ns.Comma(res.wishCount or 0), ns.DOT, ns.Comma(res.missing or 0))
		elseif Mog.On() then
			right = format("%s missing%s%s shown", ns.Comma(res.missing or 0), ns.DOT, ns.Comma(res.shown or 0))
		else
			right = ns.Comma(res.shown or 0) .. " shown"
		end
		if view.pos and view.tab == "HERE" then
			right = right .. ns.DOT .. "nearest first"
		end
	end
	win.infoRight:SetText(right)
	local titleW = floor(lay.listW * 0.58)
	if view.back then
		win.back.label:SetText("< " .. view.back)
		win.back:Show()
		win.title2:ClearAllPoints()
		win.title2:SetPoint("LEFT", win.back, "RIGHT", 8, 0)
		titleW = titleW - 98
	else
		win.back:Hide()
		win.title2:ClearAllPoints()
		win.title2:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, INFO_Y - 4)
	end
	win.title2:SetWidth(max(80, titleW))
end

local hereGen = 0
local UpdateHereTimer

local function HereTick(gen)
	if gen ~= hereGen then
		return
	end
	if not (UI.IsShown() and view.tab == "HERE" and view.pos and not ns.InCombat()) then
		hereGen = hereGen + 1
		view.hereTimer = false
		return
	end
	view.herePolls = view.herePolls + 1
	local p = view.pos
	local x, y = Data.PlayerPos(p.zone)
	if x then
		local dx, dy = (x - p.px) * p.w, (y - p.py) * p.h
		if sqrt(dx * dx + dy * dy) >= HERE_MOVE then
			UI.Rebuild(true)
			view.moves = (view.moves or 0) + 1
		end
	end
	if gen == hereGen then
		ns.After(HERE_EVERY, function()
			HereTick(gen)
		end)
	end
end

UpdateHereTimer = function()
	local want = UI.IsShown() and view.tab == "HERE" and view.pos ~= nil and not ns.InCombat()
	if want and not view.hereTimer then
		hereGen = hereGen + 1
		view.hereTimer = true
		local gen = hereGen
		ns.After(HERE_EVERY, function()
			HereTick(gen)
		end)
	elseif not want and view.hereTimer then
		hereGen = hereGen + 1
		view.hereTimer = false
	end
end

function UI.IsShown()
	return win ~= nil and Shown_(win)
end

function UI.Rebuild(keep)
	if not UI.IsShown() then
		view.dirty = true
		return
	end
	local top = keep and TopItem() or nil
	view.dirty = false
	view.builtVersion = Mog.version
	if Data.state == "idle" then
		Data.Load("window")
	end
	local res = BuildList()
	view.list = res
	view.grid = nil
	view.builds = view.builds + 1
	view.mode = (ns.db.grid and res.hasItems) and "grid" or "list"
	if keep then
		local at = LineOfItem(top)
		view.offset = at and (at - 1) or view.offset
	end
	UpdateTabs()
	UpdateFilters()
	UpdateHeader()
	UpdateInfo(res)
	UpdateFooter()
	Render()
	UpdateHereTimer()
	if ns.Preview and ns.Preview.Refresh then
		ns.Preview.Refresh()
	end
end

local refreshQueued = false
function UI.MarkDirty()
	view.dirty = true
	if not UI.IsShown() or refreshQueued or ns.InCombat() then
		return
	end
	refreshQueued = true
	ns.After(REFRESH_THROTTLE, function()
		refreshQueued = false
		if view.dirty and UI.IsShown() and not ns.InCombat() then
			UI.Rebuild(true)
		end
	end)
end

local function Restart()
	view.offset = 0
	CloseMenu()
	if srcPop then
		srcPop:Hide()
	end
	UI.Rebuild()
end

local function SavePosition()
	local ok, cx, cy = pcall(win.GetCenter, win)
	if ok and type(cx) == "number" and type(cy) == "number" and not IsSecret(cx) and not IsSecret(cy) then
		local p = ns.db.win
		p.x, p.y, p.set = floor(cx + 0.5), floor(cy + 0.5), true
	end
end

local function ApplyPosition()
	local p = ns.db.win
	win:ClearAllPoints()
	if p.set then
		win:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
end

local Layout

local FIT_MARGIN = 32
UI.FIT_MARGIN = FIT_MARGIN

local function ScreenRoom()
	local pw = Num(Read(UIParent.GetWidth, UIParent))
	local ph = Num(Read(UIParent.GetHeight, UIParent))
	if not (pw and ph and pw > FIT_MARGIN and ph > FIT_MARGIN) then
		return nil
	end
	return pw - FIT_MARGIN, ph - FIT_MARGIN
end
UI.ScreenRoom = ScreenRoom

function UI.FitSize(w, h)
	w = ns.Clamp(floor(w + 0.5), WS.MIN_W, WS.MAX_W)
	h = ns.Clamp(floor(h + 0.5), WS.MIN_H, WS.MAX_H)
	local rw, rh = ScreenRoom()
	if not rw then
		return w, h, 1, WS.MAX_W, WS.MAX_H
	end
	local maxW = max(WS.MIN_W, min(WS.MAX_W, floor(rw)))
	local maxH = max(WS.MIN_H, min(WS.MAX_H, floor(rh)))
	return min(w, maxW), min(h, maxH), min(1, rw / WS.MIN_W, rh / WS.MIN_H), maxW, maxH
end

local function Fit()
	local p = ns.db.win
	local w, h, scale, maxW, maxH = UI.FitSize(p.w, p.h)
	local changed = not UI.fit or UI.fit.w ~= w or UI.fit.h ~= h or UI.fit.scale ~= scale
	UI.fit = { w = w, h = h, scale = scale, maxW = maxW, maxH = maxH }
	if win.SetScale then
		pcall(win.SetScale, win, scale)
	end
	if win.SetResizeBounds then
		pcall(win.SetResizeBounds, win, WS.MIN_W, WS.MIN_H, maxW, maxH)
	end
	win:SetSize(w, h)
	if changed and Layout and win.listPane then
		Layout()
		if view.list then
			Render()
		end
	end
	return changed
end
UI.Fit = function()
	if win then
		return Fit()
	end
	return false
end

local function SaveSize()
	local w = Num(Read(win.GetWidth, win)) or ns.db.win.w
	local h = Num(Read(win.GetHeight, win)) or ns.db.win.h
	local fw, fh = UI.FitSize(w, h)
	ns.db.win.w, ns.db.win.h = fw, fh
	win:SetSize(fw, fh)
	UI.fit = nil
	Fit()
end

local sizing = false
local function EndSizing()
	if not sizing then
		return
	end
	sizing = false
	win:StopMovingOrSizing()
	SaveSize()
	SavePosition()
	ApplyPosition()
	Layout()
	Render()
end

Layout = function()
	local w = Num(Read(win.GetWidth, win)) or ns.db.win.w
	local h = Num(Read(win.GetHeight, win)) or ns.db.win.h
	w, h = max(w, WS.MIN_W), max(h, WS.MIN_H)
	lay.w, lay.h = w, h
	lay.listW = w - 2 * PAD - PREVIEW_W - PANE_GAP
	lay.listH = h + LIST_TOP - FOOT_H
	lay.rowW = lay.listW - SCROLL_W - 6
	lay.nRows = max(1, floor(lay.listH / ROW_H))
	local cols = max(1, floor((lay.rowW + CELL_GAP) / GRID_LINE_H))
	if cols ~= lay.cols then
		lay.cols = cols
		view.grid = nil
	end
	win.listPane:SetSize(lay.rowW, lay.listH)
	win.scroll:SetHeight(lay.listH)
	win.scroll:ClearAllPoints()
	win.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + lay.rowW + 6, LIST_TOP)
	for i = 1, lay.nRows do
		local r = rows[i]
		if not r then
			r = NewRow(win.listPane, i)
			rows[i] = r
		end
		SizeRow(r)
	end
	for i = 1, #glines do
		glines[i]:SetWidth(lay.rowW)
	end
	win.infoRight:ClearAllPoints()
	win.infoRight:SetPoint("TOPRIGHT", win, "TOPLEFT", PAD + lay.listW, INFO_Y - 5)
	win.infoRight:SetWidth(floor(lay.listW * 0.42))
	win.foot:SetWidth(max(200, lay.listW - 10))
	if ns.Preview and ns.Preview.Layout then
		ns.Preview.Layout(PREVIEW_W, h + INFO_Y - FOOT_H)
	end
end

local function LevelBox(parent, key)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(28, 20)
	e:SetAutoFocus(false)
	pcall(e.SetFont, e, S.font, SMALL, "")
	e:SetTextInsets(4, 2, 0, 0)
	e:SetMaxLetters(2)
	pcall(e.SetNumeric, e, true)
	Fill(e, { 0, 0, 0 }, 0.6)
	Edge(e)
	local function Commit(self)
		local f = ns.db.filters
		local v = tonumber(self:GetText() or "")
		if v then
			v = ns.Clamp(floor(v), 1, ns.MAX_LEVEL)
			f[key] = v
			if f.levelMin > f.levelMax then
				if key == "levelMin" then
					f.levelMax = v
				else
					f.levelMin = v
				end
			end
		end
		local before = self.committed
		self:SetText(tostring(f[key]))
		self.committed = f[key]
		if f.levelMin ~= view.lastMin or f.levelMax ~= view.lastMax or before ~= f[key] then
			view.lastMin, view.lastMax = f.levelMin, f.levelMax
			Restart()
		end
	end
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	e:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(ns.db.filters[key]))
		self:ClearFocus()
	end)
	e:SetScript("OnEditFocusLost", Commit)
	return e
end

local function SetFilter(key, value)
	ns.db.filters[key] = value
	Restart()
end

local function SetupKeys()
	if not win or win.keysReady then
		return
	end
	if type(win.SetPropagateKeyboardInput) ~= "function" or type(win.EnableKeyboard) ~= "function" then
		return
	end
	if not pcall(win.SetPropagateKeyboardInput, win, true) then
		return
	end
	if not pcall(win.EnableKeyboard, win, true) then
		return
	end
	win:SetScript("OnKeyDown", function(_, key)
		if not IsSecret(key) and key == "F" and Read(IsControlKeyDown) == true then
			UI.FocusSearch()
		end
	end)
	win.keysReady = true
end

local searchToken = 0

local function Build()
	local db = ns.db
	win = CreateFrame("Frame", WINDOW_NAME, UIParent)
	win:SetFrameStrata("HIGH")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:EnableMouse(true)
	win:SetMovable(true)
	pcall(win.SetResizable, win, true)
	Fit()
	Fill(win, S.bg, S.bgAlpha, "BACKGROUND", -2)
	Edge(win)
	ApplyPosition()

	local bar = CreateFrame("Frame", nil, win)
	bar:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
	bar:SetPoint("TOPRIGHT", win, "TOPRIGHT", -34, 0)
	bar:SetHeight(TITLE_H)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		win:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		win:StopMovingOrSizing()
		SavePosition()
		ApplyPosition()
	end)
	Fill(bar, S.border, 0.35)
	local title = Label(bar, S.title, "LEFT", S.gold, PAD, 0, 300)
	title:SetText("Forever Transmog Finder")
	win.progBg = bar:CreateTexture(nil, "ARTWORK")
	win.progBg:SetSize(120, 6)
	win.progBg:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
	win.progBg:SetColorTexture(S.border[1], S.border[2], S.border[3], 1)
	win.progBar = bar:CreateTexture(nil, "OVERLAY")
	win.progBar:SetHeight(6)
	win.progBar:SetPoint("LEFT", win.progBg, "LEFT", 0, 0)
	win.progBar:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
	win.summary = Label(bar, SMALL, "RIGHT", S.muted, -136, 0, 360, "RIGHT")
	local close = FlatButton(win, 20, 20, "x", function()
		win:Hide()
	end)
	close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -6, -5)

	win.tabs = {}
	local x = PAD
	local TAB_W = { HERE = 56, ZONES = 64, DUNGEONS = 90, ALL = 44, WISHLIST = 100, STATS = 60 }
	for _, key in ipairs(ns.TABS) do
		local w = TAB_W[key] or 72
		local b = CreateFrame("Button", nil, win)
		b:SetSize(w, 24)
		b:SetPoint("TOPLEFT", win, "TOPLEFT", x, TABS_Y)
		b.hl = Fill(b, S.gold, 0.08, "HIGHLIGHT")
		b.label = Label(b, BODY, "CENTER", S.muted, 0, 1, w, "CENTER")
		b.label:SetText(key)
		b.underline = b:CreateTexture(nil, "OVERLAY")
		b.underline:SetHeight(2)
		b.underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, 0)
		b.underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 0)
		b.underline:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
		b:RegisterForClicks("LeftButtonUp")
		b:SetScript("OnClick", function()
			UI.SetTab(key)
		end)
		win.tabs[key] = b
		x = x + w + 4
	end
	local rule = win:CreateTexture(nil, "ARTWORK")
	rule:SetHeight(1)
	rule:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, TABS_Y - 25)
	rule:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, TABS_Y - 25)
	rule:SetColorTexture(S.border[1], S.border[2], S.border[3], 1)

	local search = CreateFrame("EditBox", nil, win)
	search:SetSize(200, 20)
	search:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, TABS_Y - 2)
	search:SetAutoFocus(false)
	pcall(search.SetFont, search, S.font, SMALL, "")
	search:SetTextInsets(6, 4, 0, 0)
	search:SetMaxLetters(40)
	Fill(search, { 0, 0, 0 }, 0.6)
	Edge(search)
	local hint = Label(search, SMALL, "LEFT", S.dim, 6, 0, 186)
	hint:SetText("Search...  (Ctrl+F)")
	search:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		if IsSecret(text) then
			return
		end
		Shown(hint, text == "")
		if text == view.search then
			return
		end
		view.search = text
		searchToken = searchToken + 1
		local token = searchToken
		ns.After(0.25, function()
			if token == searchToken then
				Restart()
			end
		end)
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	search:SetScript("OnEditFocusGained", function()
		hint:Hide()
	end)
	search:SetScript("OnEditFocusLost", function(self)
		Shown(hint, (self:GetText() or "") == "")
	end)
	win.search, win.searchHint = search, hint
	local function ViewButton(text, grid, tip)
		local b = FlatButton(win, 44, 20, text, function()
			UI.SetGrid(grid)
		end)
		b.on = b:CreateTexture(nil, "OVERLAY")
		b.on:SetHeight(2)
		b.on:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 1)
		b.on:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 1)
		b.on:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
		b:SetScript("OnEnter", function(self)
			ShowTip(self, { text, tip })
		end)
		b:SetScript("OnLeave", HideTip)
		return b
	end
	win.viewGrid = ViewButton("Grid", true, "Icons, 40 px: a check mark on collected ones. Hover for the tooltip and the preview.")
	win.viewGrid:SetPoint("TOPRIGHT", search, "TOPLEFT", -8, 0)
	win.viewList = ViewButton("List", false, "Rows with the status, the source and where it is.")
	win.viewList:SetPoint("TOPRIGHT", win.viewGrid, "TOPLEFT", -4, 0)

	local fy = FILTER_Y
	win.slotBtn = FlatButton(win, 124, 20, "", function(self)
		local entries = {}
		for _, s in ipairs(ns.SLOTS) do
			entries[#entries + 1] = { text = s.label, checked = ns.db.filters.slot == s.key, func = function()
				SetFilter("slot", s.key)
			end }
		end
		Menu.Open(self, entries)
	end)
	win.slotBtn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, fy)
	win.armor = Toggle(win, 146, "Only my armor type",
		"Off (default): every item, cloth to plate, since on Forever any character collects the look of anything it loots. On: only your class's armor type (and everything that has no armor type).",
		function()
			return ns.db.filters.armorOnly
		end, function(v)
			ns.SetOption("filters.armorOnly", v)
			ns.RefreshOptions()
		end)
	win.armor:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 130, fy)
	win.qualBtn = FlatButton(win, 128, 20, "", function(self)
		local entries = {}
		for _, q in ipairs(ns.QUALITIES) do
			entries[#entries + 1] = { text = q.label, checked = ns.db.filters.minQuality == q.value, func = function()
				SetFilter("minQuality", q.value)
			end }
		end
		Menu.Open(self, entries)
	end)
	win.qualBtn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 282, fy)
	local lvl = Label(win, SMALL, "LEFT", S.muted, PAD + 416, fy - 10, 34, "TOPLEFT")
	lvl:SetText("Level")
	win.lmin = LevelBox(win, "levelMin")
	win.lmin:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 450, fy)
	local dash = Label(win, SMALL, "CENTER", S.muted, PAD + 479, fy - 10, 10, "TOPLEFT")
	dash:SetText("-")
	win.lmax = LevelBox(win, "levelMax")
	win.lmax:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 490, fy)
	win.collected = Toggle(win, 112, "Show collected", "Off: only what you are missing. On: everything, collected ones marked (and missing ones no longer sort first).",
		function()
			return ns.db.filters.showCollected
		end, function(v)
			SetFilter("showCollected", v)
		end)
	win.collected:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 524, fy)
	win.sortBtn = FlatButton(win, 138, 20, "", function(self)
		local entries = {}
		for _, s in ipairs(ns.SORTS) do
			entries[#entries + 1] = { text = s.label, checked = ns.db.filters.sort == s.key, func = function()
				SetFilter("sort", s.key)
			end }
		end
		Menu.Open(self, entries, "Sort (missing first)")
	end)
	win.sortBtn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 642, fy)

	win.back = FlatButton(win, 90, 20, "", function()
		if view.tab == "ZONES" then
			view.zone = 0
			ns.db.win.zone = 0
		else
			view.dungeon = ""
			ns.db.win.dungeon = ""
		end
		Restart()
	end)
	win.back:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, INFO_Y)
	win.back:Hide()
	win.title2 = Label(win, BODY, "LEFT", S.gold, PAD, INFO_Y - 4, 360, "TOPLEFT")
	win.infoRight = Label(win, SMALL, "RIGHT", S.muted, 0, 0, 300, "TOPRIGHT", win, "TOPLEFT")

	local list = CreateFrame("Frame", nil, win)
	list:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, LIST_TOP)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		if IsSecret(delta) then
			return
		end
		SetOffset(view.offset - delta * (view.mode == "grid" and 2 or 3))
	end)
	win.listPane = list
	win.list = list
	local scroll = CreateFrame("Slider", nil, win)
	scroll:SetOrientation("VERTICAL")
	scroll:SetWidth(SCROLL_W)
	Fill(scroll, S.border, 0.6)
	local thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetSize(SCROLL_W, 40)
	thumb:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 0.8)
	scroll:SetThumbTexture(thumb)
	scroll:SetMinMaxValues(0, 0)
	scroll:SetValueStep(1)
	pcall(scroll.SetObeyStepOnDrag, scroll, true)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		if IsSecret(delta) then
			return
		end
		SetOffset(view.offset - delta * (view.mode == "grid" and 2 or 3))
	end)
	scroll:SetScript("OnValueChanged", function(_, value)
		if rendering or IsSecret(value) then
			return
		end
		SetOffset(value)
	end)
	win.scroll = scroll

	if ns.Preview and ns.Preview.Build then
		local pane = ns.Preview.Build(win)
		pane:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, INFO_Y)
		win.preview = pane
	end

	local foot = Label(win, SMALL, "LEFT", S.dim, PAD, 14, 560, "BOTTOMLEFT")
	foot:SetText("Click: try on" .. ns.DOT .. "Shift: link" .. ns.DOT .. "Ctrl: dressing room" .. ns.DOT
		.. "Right-click: menu" .. ns.DOT .. "Star: wishlist")
	win.foot = foot
	win.status = Label(win, SMALL, "RIGHT", S.muted, -PAD - 14, 14, 290, "BOTTOMRIGHT")
	local grip = CreateFrame("Button", nil, win)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -2, 2)
	grip.tex = grip:CreateTexture(nil, "OVERLAY")
	grip.tex:SetAllPoints(grip)
	grip.tex:SetTexture(GRIP_TEX)
	grip.hl = grip:CreateTexture(nil, "HIGHLIGHT")
	grip.hl:SetAllPoints(grip)
	grip.hl:SetTexture(GRIP_HL)
	grip:SetScript("OnMouseDown", function(_, button)
		if button == "LeftButton" and not sizing then
			sizing = true
			win:StartSizing("BOTTOMRIGHT")
		end
	end)
	grip:SetScript("OnMouseUp", EndSizing)
	grip:SetScript("OnEnter", function(self)
		ShowTip(self, { "Resize", "Drag to resize the window (at least 820 x 520). The size is saved." })
	end)
	grip:SetScript("OnLeave", HideTip)
	win.grip = grip

	win:SetScript("OnSizeChanged", function()
		Layout()
		if view.list then
			Render()
		end
	end)
	win:SetScript("OnShow", function()
		Fit()
		if view.dirty or view.builtVersion ~= Mog.version or view.builds == 0 then
			UI.Rebuild()
		else
			UpdateFooter()
			UpdateHereTimer()
		end
		if ns.Preview and ns.Preview.OnShow then
			ns.Preview.OnShow()
		end
	end)
	win:SetScript("OnHide", function()
		EndSizing()
		CloseMenu()
		HideTip()
		if srcPop then
			srcPop:Hide()
		end
		if copy then
			copy:Hide()
		end
		win.search:ClearFocus()
		win.lmin:ClearFocus()
		win.lmax:ClearFocus()
		view.hoverToken = view.hoverToken + 1
		UpdateHereTimer()
		if ns.Preview and ns.Preview.OnHide then
			ns.Preview.OnHide()
		end
	end)
	win:Hide()

	if type(UISpecialFrames) == "table" then
		local found = false
		for i = 1, #UISpecialFrames do
			if UISpecialFrames[i] == WINDOW_NAME then
				found = true
			end
		end
		if not found then
			table.insert(UISpecialFrames, WINDOW_NAME)
		end
	end
	Layout()
	ns.RunOutOfCombat("keys", SetupKeys)
	view.lastGrid = ns.db.grid
	UI.frame = win
end

local function Ensure()
	if not win then
		Build()
		view.tab = ns.db.win.tab
		view.zone = ns.db.win.zone
		view.dungeon = ns.db.win.dungeon
	end
end

function UI.Show()
	if not ns.db then
		return
	end
	Ensure()
	win:Show()
end

function UI.Toggle()
	if not ns.db then
		return
	end
	Ensure()
	if Shown_(win) then
		win:Hide()
	else
		win:Show()
	end
end

function UI.Hide()
	if win then
		win:Hide()
	end
end

function UI.ToggleHere()
	if not ns.db then
		return
	end
	if Shown_(win) and view.tab == "HERE" then
		win:Hide()
	else
		UI.Open("HERE")
	end
end

function UI.SetTab(key)
	view.tab = key
	ns.db.win.tab = key
	Restart()
end

function UI.Open(tab)
	if not ns.db then
		return
	end
	Ensure()
	view.tab = tab or view.tab
	ns.db.win.tab = view.tab
	if Shown_(win) then
		Restart()
	else
		view.offset = 0
		view.dirty = true
		win:Show()
	end
end

function UI.SetGrid(on)
	ns.SetOption("grid", on == true)
	ns.RefreshOptions()
end

function UI.Drill(kind, key)
	if kind == "inst" then
		view.dungeon = key
		ns.db.win.dungeon = key
		view.tab = "DUNGEONS"
	else
		view.zone = key
		ns.db.win.zone = key
		view.tab = "ZONES"
	end
	ns.db.win.tab = view.tab
	Restart()
end

local pendingPlace

local function ResolvePlace(kind, text)
	Ensure()
	local k = kind == "dungeon" and "inst" or "zone"
	if text == "" then
		if k == "inst" then
			view.dungeon, ns.db.win.dungeon = "", ""
		else
			view.zone, ns.db.win.zone = 0, 0
		end
		UI.Open(k == "inst" and "DUNGEONS" or "ZONES")
		return
	end
	local key, name = List.FindPlace(k, text)
	if not key then
		Print("No " .. (k == "inst" and "dungeon or raid" or "zone") .. " in the item list matches \"" .. text .. "\".")
		UI.Open(k == "inst" and "DUNGEONS" or "ZONES")
		return
	end
	Ensure()
	if not Shown_(win) then
		view.dirty = true
		win:Show()
	end
	UI.Drill(k, key)
	ns.Debug("Opened " .. tostring(name))
end

function UI.OpenPlace(kind, text)
	if not ns.db then
		return
	end
	if Data.Ready() then
		ResolvePlace(kind, text)
		return
	end
	pendingPlace = { kind, text }
	UI.Open(kind == "dungeon" and "DUNGEONS" or "ZONES")
end

function UI.Search(text)
	Ensure()
	view.tab = "ALL"
	ns.db.win.tab = "ALL"
	view.search = text or ""
	win.search:SetText(view.search)
	if Shown_(win) then
		Restart()
	else
		view.offset = 0
		view.dirty = true
		win:Show()
	end
end

function UI.ClearSearch()
	if not win then
		return
	end
	view.search = ""
	win.search:SetText("")
	Restart()
end

function UI.FocusSearch()
	if not ns.db then
		return
	end
	Ensure()
	if not Shown_(win) then
		win:Show()
	end
	win.search:SetFocus()
	win.search:HighlightText()
end

function UI.ResetPosition()
	ns.db.win.set = false
	ns.db.win.w, ns.db.win.h = WS.W, WS.H
	Ensure()
	Fit()
	ApplyPosition()
	Layout()
	if not Shown_(win) then
		win:Show()
	else
		Render()
	end
	Print("Window moved back to the middle of the screen, at its first size.")
end

function UI.Rows()
	return rows
end

function UI.GridLinesFrames()
	return glines
end

function UI.CurrentList()
	return view.list
end

UI.Layout = function()
	if win then
		Layout()
	end
end

ns.Listen("DATA_READY", function()
	if pendingPlace then
		local p = pendingPlace
		pendingPlace = nil
		ResolvePlace(p[1], p[2])
	end
	if UI.IsShown() then
		Restart()
	else
		view.dirty = true
	end
end)
for _, msg in ipairs({ "DATA_LOADING", "DATA_FAILED", "DATA_WAITING", "AVAILABILITY_CHANGED" }) do
	ns.Listen(msg, function()
		if UI.IsShown() then
			UI.Rebuild()
		else
			view.dirty = true
		end
	end)
end
ns.Listen("STATUS_CHANGED", UI.MarkDirty)
ns.Listen("SCAN_DONE", UI.MarkDirty)
ns.Listen("COMBAT", function(_, inCombat)
	if UI.IsShown() then
		UpdateFooter()
		UpdateHereTimer()
		if not inCombat and view.staleHeader then
			view.staleHeader = false
			UpdateHeader()
		end
		if not inCombat and view.dirty then
			UI.MarkDirty()
		end
	end
end)
ns.Listen("SETTINGS_CHANGED", function()
	if not win then
		return
	end
	if UI.IsShown() then
		UI.Rebuild(true)
	else
		view.dirty = true
	end
end)
ns.Listen("WISH_CHANGED", function()
	if not UI.IsShown() then
		view.dirty = true
		return
	end
	if view.tab == "WISHLIST" then
		UI.Rebuild(true)
	else
		UpdateTabs()
		Render()
	end
	if ns.Preview and ns.Preview.Refresh then
		ns.Preview.Refresh()
	end
end)
local HereChanged = ns.Debounce(1, function()
	if view.tab == "HERE" then
		if UI.IsShown() then
			Restart()
		else
			view.dirty = true
		end
	end
end)
ns.On("ZONE_CHANGED_NEW_AREA", HereChanged)
ns.On("PLAYER_ENTERING_WORLD", HereChanged)
local function Refit()
	if win then
		Fit()
	end
end
ns.TryOn("UI_SCALE_CHANGED", Refit)
ns.TryOn("DISPLAY_SIZE_CHANGED", Refit)
