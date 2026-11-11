local ADDON_NAME, ns = ...

local type, tostring = type, tostring
local floor, abs, max, cos, sin, rad, deg, atan2 = math.floor, math.abs, math.max, math.cos, math.sin, math.rad,
	math.deg, math.atan2
local format = string.format
local Read, IsSecret, Print = ns.Read, ns.IsSecret, ns.Print
local Data, Mog, List = ns.Data, ns.Mog, ns.List
local S = ns.STYLE

local MM = {}
ns.Minimap = MM

local SIZE = 31
local ICON = "Interface\\AddOns\\ForeverTransmogFinder\\Media\\icon-64"
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local EDGE_OUT = 5
local DEFAULT_SIZE = 198
local LEVEL_ABOVE = 10
local DRAG_INTERVAL = 0.01
local WELCOME_DELAY = 8
MM.DEFAULT_ANGLE = 200
MM.SIZE = SIZE
MM.BUTTON_NAME = "ForeverTransmogFinderMinimapButton"

local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button, ticker
local dragging = false

local function Num(v)
	if type(v) == "number" and not IsSecret(v) and v == v then
		return v
	end
	return nil
end

local function NormAngle(a)
	a = Num(a)
	if not a or a == math.huge or a == -math.huge then
		return nil
	end
	return a % 360
end
MM.NormAngle = NormAngle

function MM.Shape()
	if type(GetMinimapShape) ~= "function" then
		return "ROUND"
	end
	local shape = Read(GetMinimapShape)
	if type(shape) == "string" and SHAPES[shape] then
		return shape
	end
	return "ROUND"
end

function MM.Offset(angle, w, h, shape)
	local a = rad(NormAngle(angle) or MM.DEFAULT_ANGLE)
	local x, y = cos(a), sin(a)
	local q = 1
	if x < 0 then
		q = q + 1
	end
	if y > 0 then
		q = q + 2
	end
	local rw, rh = w / 2 + EDGE_OUT, h / 2 + EDGE_OUT
	if (SHAPES[shape] or SHAPES.ROUND)[q] then
		return x * rw, y * rh
	end
	local m = max(abs(x), abs(y))
	return x / m * rw, y / m * rh
end

local function MapSize()
	local w = Num(Read(Minimap.GetWidth, Minimap))
	local h = Num(Read(Minimap.GetHeight, Minimap))
	if not w or w <= 0 then
		w = DEFAULT_SIZE
	end
	if not h or h <= 0 then
		h = w
	end
	return w, h
end

function MM.Place()
	if not button then
		return
	end
	local w, h = MapSize()
	local shape = MM.Shape()
	local x, y = MM.Offset(ns.db.minimap.angle, w, h, shape)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
	MM.shape, MM.x, MM.y = shape, x, y
end

function MM.CursorAngle()
	local mx, my = Read(Minimap.GetCenter, Minimap)
	local scale = Num(Read(Minimap.GetEffectiveScale, Minimap))
	local cx, cy = Read(GetCursorPosition)
	mx, my, cx, cy = Num(mx), Num(my), Num(cx), Num(cy)
	if not (mx and my and cx and cy and scale) or scale <= 0 then
		return nil
	end
	local dx, dy = cx / scale - mx, cy / scale - my
	if dx == 0 and dy == 0 then
		return nil
	end
	return floor(deg(atan2(dy, dx)) + 0.5) % 360
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function FollowCursor()
	local a = MM.CursorAngle()
	if a then
		ns.db.minimap.angle = a
		MM.Place()
	end
end

function MM.StopDrag()
	StopTicker()
	if not dragging then
		return
	end
	dragging = false
	if button then
		button.icon:SetSize(19, 19)
	end
	FollowCursor()
end

local function DragTick()
	if Read(IsMouseButtonDown, "LeftButton") == false then
		MM.StopDrag()
		return
	end
	FollowCursor()
end

function MM.StartDrag()
	StopTicker()
	dragging = true
	if GameTooltip then
		GameTooltip:Hide()
	end
	if C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(DRAG_INTERVAL, function()
			if not ns.SafeCall(DragTick) then
				StopTicker()
			end
		end)
	end
end

function MM.Dragging()
	return dragging, ticker ~= nil
end

function MM.HereLine()
	if not Mog.On() then
		return "Transmog is off on this character", S.orange
	end
	if not Data.Ready() then
		if Data.state == "error" then
			return "The item list did not load (/ftf scan)", S.red
		end
		return "Click to open", S.muted
	end
	if ns.InCombat() then
		return "Missing here: shown after combat", S.muted
	end
	local place = Data.CurrentPlace()
	if not place then
		return "Click to open", S.muted
	end
	if not place.listed then
		return "Nothing in the list here (" .. tostring(place.name) .. ")", S.muted
	end
	local n = List.MissingAppearances(place.kind, place.key, ns.db.filters)
	return format("Missing here: %d  (%s)", n, tostring(place.name)), n > 0 and S.gold or S.muted
end

MM.HINTS = {
	"Left-click: open or close the window",
	"Shift+left-click: the HERE tab",
	"Right-click: options",
	"Drag: move it along the minimap edge",
}

local function ShowTooltip(self)
	if dragging or not GameTooltip then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.TITLE, S.gold[1], S.gold[2], S.gold[3])
	local text, c = MM.HereLine()
	GameTooltip:AddLine(text, c[1], c[2], c[3], true)
	GameTooltip:AddLine(" ")
	for i = 1, #MM.HINTS do
		GameTooltip:AddLine(MM.HINTS[i], S.dim[1], S.dim[2], S.dim[3], true)
	end
	GameTooltip:Show()
end

local function HideTooltip()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

function MM.Click(which)
	if not ns.db then
		return
	end
	HideTooltip()
	if which == "RightButton" then
		ns.OpenOptions()
	elseif Read(IsShiftKeyDown) == true then
		ns.UI.ToggleHere()
	else
		ns.UI.Toggle()
	end
end

local function Disc(b, layer, sub, size, c, a)
	local t = b:CreateTexture(nil, layer, nil, sub)
	t:SetTexture(DISC)
	t:SetSize(size, size)
	t:SetPoint("CENTER", b, "CENTER", 0, 0)
	t:SetVertexColor(c[1], c[2], c[3], a)
	return t
end

local function Build()
	if button then
		return button
	end
	if type(Minimap) ~= "table" or type(Minimap.GetWidth) ~= "function" then
		ns.Debug("No Minimap frame; no minimap button (the compartment entry and /ftf still work).")
		return nil
	end
	local b = CreateFrame("Button", MM.BUTTON_NAME, Minimap)
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	if b.SetFixedFrameStrata then
		b:SetFixedFrameStrata(true)
	end
	local level = Num(Read(Minimap.GetFrameLevel, Minimap)) or 0
	b:SetFrameLevel(level + LEVEL_ABOVE)
	if b.SetFixedFrameLevel then
		b:SetFixedFrameLevel(true)
	end
	b:SetClampedToScreen(true)
	b:EnableMouse(true)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")

	b.edge = Disc(b, "BACKGROUND", 0, SIZE, S.gold, 0.55)
	b.ring = Disc(b, "BACKGROUND", 1, SIZE - 2, S.bg, 1)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(19, 19)
	icon:SetPoint("CENTER", b, "CENTER", 0, 0)
	icon:SetTexCoord(0, 1, 0, 1)
	if b.CreateMaskTexture and icon.AddMaskTexture then
		local mask = b:CreateMaskTexture()
		mask:SetTexture(DISC, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(icon)
		icon:AddMaskTexture(mask)
		b.mask = mask
	end
	b.icon = icon
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(HIGHLIGHT)
	hl:SetSize(SIZE + 2, SIZE + 2)
	hl:SetPoint("CENTER", b, "CENTER", 0, 0)
	if hl.SetBlendMode then
		hl:SetBlendMode("ADD")
	end
	b.hl = hl

	b:SetScript("OnClick", function(_, which)
		MM.Click(which)
	end)
	b:SetScript("OnEnter", function(self)
		self.edge:SetVertexColor(S.gold[1], S.gold[2], S.gold[3], 1)
		ShowTooltip(self)
	end)
	b:SetScript("OnLeave", function(self)
		self.edge:SetVertexColor(S.gold[1], S.gold[2], S.gold[3], 0.55)
		HideTooltip()
	end)
	b:SetScript("OnMouseDown", function(self)
		self.icon:SetSize(17, 17)
	end)
	b:SetScript("OnMouseUp", function(self)
		self.icon:SetSize(19, 19)
	end)
	b:SetScript("OnDragStart", MM.StartDrag)
	b:SetScript("OnDragStop", MM.StopDrag)
	b:SetScript("OnHide", function(self)
		self.icon:SetSize(19, 19)
		MM.StopDrag()
	end)
	button = b
	MM.button = b
	return b
end

function MM.Update()
	if not ns.db then
		return
	end
	if ns.db.minimap.show then
		if Build() then
			MM.Place()
			button:Show()
		end
	elseif button then
		button:Hide()
	end
end

function MM.Command(arg)
	arg = string.lower(arg or "")
	local m = ns.db.minimap
	if arg == "" then
		arg = m.show and "off" or "on"
	end
	if arg == "on" or arg == "show" then
		ns.SetOption("minimap.show", true)
		Print("Minimap button on. Drag it along the edge; /ftf minimap reset puts it back.")
	elseif arg == "off" or arg == "hide" then
		ns.SetOption("minimap.show", false)
		Print("Minimap button off. /ftf minimap on brings it back; /ftf and the AddOns menu still work.")
	elseif arg == "reset" then
		m.angle = MM.DEFAULT_ANGLE
		ns.SetOption("minimap.show", true)
		MM.Place()
		Print("Minimap button back at its first place, on the left edge of the minimap.")
	else
		Print("Usage: /ftf minimap on | off | reset")
	end
	ns.RefreshOptions()
end

MM.WELCOME = "|cffF2C14EForever Transmog Finder|r: click the minimap button or type /ftf."

local function Welcome()
	if ns.db.welcomed then
		return
	end
	ns.RunOutOfCombat("welcome", function()
		if not ns.db.welcomed then
			ns.db.welcomed = true
			print(MM.WELCOME)
		end
	end)
end

ns.Listen("LOGIN", function()
	MM.Update()
	if not ns.db.welcomed then
		ns.After(WELCOME_DELAY, Welcome)
	end
end)
ns.Listen("SETTINGS_CHANGED", MM.Update)
ns.On("PLAYER_ENTERING_WORLD", function()
	if button and ns.db and ns.db.minimap.show and not dragging then
		MM.Place()
	end
end)
