local ADDON_NAME, ns = ...

local type, ipairs, pcall, floor, max, min, format = type, ipairs, pcall, math.floor, math.max, math.min, string.format
local Read, IsSecret, Print = ns.Read, ns.IsSecret, ns.Print
local Data, Mog = ns.Data, ns.Mog
local S = ns.STYLE
local W = ns.W

local P = { tryOns = 0, applies = 0, units = 0 }
ns.Preview = P

local MODEL_MIN, MODEL_MAX = 200, 340
local SRC_TOP, SRC_H, MAX_SRC = 92, 36, 10
local DEFAULT_FACING = 0.35
local ROTATE_EVERY, ROTATE_PER_PX = 0.02, 0.012
local ZOOM_STEP, ZOOM_MAX = 0.1, 0.8
P.DEFAULT_FACING, P.ZOOM_MAX = DEFAULT_FACING, ZOOM_MAX

local pane, model, ticker
local st = { id = nil, undress = false, zoom = 0, facing = DEFAULT_FACING, unitSet = false, w = 300, h = 488,
	modelH = 260, nSrc = 4 }
P.state = st
local srcLines = {}

local function M(name, ...)
	local fn = model and model[name]
	if type(fn) ~= "function" then
		return false
	end
	local ok, r = pcall(fn, model, ...)
	return ok, r
end

function P.Apply()
	if not model or not (ns.UI and ns.UI.IsShown()) then
		return false
	end
	if ns.InCombat() then
		P.waiting = true
		ns.RunOutOfCombat("previewModel", P.Apply)
		return false
	end
	P.waiting = false
	if not st.unitSet then
		M("SetUnit", "player", false)
		st.unitSet = true
		P.units = P.units + 1
		M("SetFacing", st.facing)
		M("SetPortraitZoom", st.zoom)
	end
	if st.undress then
		M("Undress")
	elseif not M("Dress") then
		M("SetUnit", "player", false)
	end
	local id = st.id
	if id then
		local row = Data.Item(id)
		local sourceID = row and row[8]
		local target = (type(sourceID) == "number" and sourceID) or Data.Link(id) or ("item:" .. id)
		M("TryOn", target)
		P.tryOns = P.tryOns + 1
	end
	P.applies = P.applies + 1
	return true
end

local function Num(v)
	if type(v) == "number" and not IsSecret(v) and v == v then
		return v
	end
	return nil
end

local function CursorX()
	local x = Read(GetCursorPosition)
	return Num(x)
end

function P.StopRotate()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

function P.RotateTick()
	if not model or Read(IsMouseButtonDown, "LeftButton") == false or ns.InCombat() then
		P.StopRotate()
		return
	end
	local x = CursorX()
	if not x or not st.rotX then
		return
	end
	local scale = Num(Read(model.GetEffectiveScale, model)) or 1
	if scale <= 0 then
		scale = 1
	end
	st.facing = st.rotFacing + (x - st.rotX) / scale * ROTATE_PER_PX
	M("SetFacing", st.facing)
end

function P.StartRotate(_, button)
	if button ~= "LeftButton" or not model or ns.InCombat() then
		return
	end
	P.StopRotate()
	local x = CursorX()
	if not x then
		return
	end
	st.rotX, st.rotFacing = x, st.facing
	if C_Timer and C_Timer.NewTicker then
		ticker = C_Timer.NewTicker(ROTATE_EVERY, function()
			if not ns.SafeCall(P.RotateTick) then
				P.StopRotate()
			end
		end)
	end
end

function P.Rotating()
	return ticker ~= nil
end

function P.Zoom(_, delta)
	if not model or ns.InCombat() or type(delta) ~= "number" or IsSecret(delta) then
		return
	end
	st.zoom = max(0, min(ZOOM_MAX, st.zoom + delta * ZOOM_STEP))
	M("SetPortraitZoom", st.zoom)
end

function P.Reset()
	st.facing, st.zoom = DEFAULT_FACING, 0
	st.unitSet = false
	if ns.InCombat() then
		Print("The preview resets after combat.")
	end
	P.Apply()
end

function P.SetUndress(on)
	st.undress = on == true
	if P.undressBtn then
		P.undressBtn.Sync(true)
	end
	P.Apply()
end

local function SourceLine(i)
	local l = CreateFrame("Frame", nil, pane)
	l:SetSize(st.w - 16, SRC_H)
	l.badge = W.Badge(l, 58, 15)
	l.badge:SetPoint("TOPLEFT", l, "TOPLEFT", 0, -2)
	l.label = W.Label(l, S.small, "LEFT", S.text, 64, -2, st.w - 16 - 64 - 62, "TOPLEFT")
	l.place = W.Label(l, S.small, "LEFT", S.teal, 64, -19, st.w - 16 - 64 - 62, "TOPLEFT")
	l.pin = W.FlatButton(l, 56, 15, "Map pin", function(self)
		local p = self:GetParent()
		if p.id and p.si then
			ns.UI.Pin(p.id, p.si)
		end
	end)
	l.pin:SetPoint("TOPRIGHT", l, "TOPRIGHT", 0, -1)
	l.arrow = W.FlatButton(l, 56, 15, "Arrow", function(self)
		local fn = self:GetParent().arrowFn
		if fn then
			fn()
		end
	end)
	l.arrow:SetPoint("TOPRIGHT", l, "TOPRIGHT", 0, -19)
	srcLines[i] = l
	return l
end

local function PlaceLine(e)
	local where, x, y, extra = e[2], e[4], e[5], e[6]
	local parts = {}
	local place = Data.PlaceText(where, x, y)
	if place then
		parts[#parts + 1] = place
	elseif where == 0 then
		parts[#parts + 1] = (e[1] == 5 and "a profession") or (e[1] == 7 and "anywhere") or "place unknown"
	end
	if e[1] == 4 and type(extra) == "string" then
		parts[#parts + 1] = extra
	end
	local pos = ns.UI.view.pos
	if pos and where == pos.zone then
		local d = Data.SourceYards(e, pos.zone, pos.px, pos.py, pos.w, pos.h)
		if d then
			parts[#parts + 1] = Data.YardsText(d)
		end
	end
	return table.concat(parts, ns.DOT)
end

local function RenderInfo()
	if not pane then
		return
	end
	local id = st.id
	if not id or not Data.Item(id) then
		pane.name:SetText("")
		pane.kind:SetText("")
		pane.status:SetText("")
		pane.srcHead:SetText("")
		pane.starBtn:Hide()
		pane.more:Hide()
		for _, l in ipairs(srcLines) do
			l:Hide()
		end
		pane.empty:SetText(Data.Ready() and "Hover or click an item to try it on." or "")
		pane.empty:Show()
		return
	end
	pane.empty:Hide()
	pane.name:SetText(Data.Name(id))
	pane.name:SetTextColor(Data.QualityColor(Data.Quality(id)))
	pane.starBtn:Show()
	W.SetStar(pane.starBtn.star, ns.Wish.Has(id))
	local row = Data.Item(id)
	local lvl = row[6]
	pane.kind:SetText(Data.TypeText(id) .. ((type(lvl) == "number" and lvl > 1) and (ns.DOT .. "level " .. lvl) or ""))
	local mark = Mog.On() and ns.UI.MARK[Mog.StatusOf(id)]
	local status = mark and mark[1] or ""
	local tags = ns.UI.Tags(id)
	pane.status:SetText(status)
	W.Color(pane.status, mark and mark[2] or S.dim)
	local sw = W.Num(Read(pane.status.GetStringWidth, pane.status))
	local tx = 180
	if sw and (sw > 0 or status == "") then
		tx = 10 + min(168, floor(sw + 0.5)) + (status == "" and 0 or 10)
	end
	pane.tags:ClearAllPoints()
	pane.tags:SetPoint("TOPLEFT", pane, "TOPLEFT", tx, -(st.modelH + 48))
	pane.tags:SetWidth(max(40, st.w - tx - 10))
	pane.tags:SetText(table.concat(tags, ns.DOT))
	local list = Data.Sources(id)
	pane.srcHead:SetText(#list == 1 and "Source" or ("Sources (" .. #list .. ")"))
	local order = Data.SourceOrder(id)
	local n = min(#order, st.nSrc)
	for i = 1, n do
		local l = srcLines[i] or SourceLine(i)
		local si = order[i]
		local e = list[si]
		l.id, l.si = id, si
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -(st.modelH + SRC_TOP + (i - 1) * SRC_H))
		l:SetWidth(st.w - 16)
		W.SetBadge(l.badge, type(e) == "table" and e[1] or 7)
		if type(e) == "table" then
			l.label:SetText(Data.SourceLabel(e))
			W.Color(l.label, Data.OtherSource(e) and S.dim or S.text)
			l.place:SetText(PlaceLine(e))
		else
			l.label:SetText("Source unknown")
			l.place:SetText("")
		end
		local pinOK = Data.PinTarget(e) ~= nil
		W.Color(l.pin.label, pinOK and S.text or S.dim)
		l.arrowFn = ns.UI.ArrowFor(id, si)
		W.Shown(l.arrow, l.arrowFn ~= nil)
		l:Show()
	end
	for i = n + 1, #srcLines do
		srcLines[i]:Hide()
	end
	if #list > n then
		pane.more.label:SetText("All " .. #list .. " sources")
		pane.more:Show()
	else
		pane.more:Hide()
	end
end
P.RenderInfo = RenderInfo

function P.Show(id)
	if type(id) ~= "number" or IsSecret(id) then
		id = nil
	end
	st.id = id
	P.shown = id
	RenderInfo()
	P.Apply()
end

function P.Refresh()
	RenderInfo()
end

function P.OnShow()
	st.unitSet = false
	RenderInfo()
	P.Apply()
end

function P.OnHide()
	P.StopRotate()
end

function P.Layout(w, h)
	if not pane then
		return
	end
	st.w, st.h = w, h
	pane:SetSize(w, h)
	st.modelH = max(MODEL_MIN, min(MODEL_MAX, floor(h * 0.5)))
	model:SetHeight(st.modelH)
	pane.modelBg:SetHeight(st.modelH)
	local top = st.modelH
	pane.name:ClearAllPoints()
	pane.name:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -(top + 10))
	pane.name:SetWidth(w - 44)
	pane.starBtn:ClearAllPoints()
	pane.starBtn:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -8, -(top + 8))
	pane.kind:ClearAllPoints()
	pane.kind:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -(top + 30))
	pane.kind:SetWidth(w - 20)
	pane.status:ClearAllPoints()
	pane.status:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -(top + 48))
	pane.tags:ClearAllPoints()
	pane.tags:SetPoint("TOPLEFT", pane, "TOPLEFT", 10 + 170, -(top + 48))
	pane.tags:SetWidth(w - 190)
	pane.srcHead:ClearAllPoints()
	pane.srcHead:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -(top + 70))
	pane.empty:ClearAllPoints()
	pane.empty:SetPoint("TOPLEFT", pane, "TOPLEFT", 10, -(top + 14))
	pane.empty:SetWidth(w - 20)
	st.nSrc = max(1, min(MAX_SRC, floor((h - top - SRC_TOP - 26) / SRC_H)))
	RenderInfo()
end

function P.Build(parent)
	if pane then
		return pane
	end
	pane = CreateFrame("Frame", nil, parent)
	pane:SetSize(st.w, st.h)
	W.Fill(pane, S.panel, 1)
	W.Edge(pane)
	pane.modelBg = pane:CreateTexture(nil, "BORDER")
	pane.modelBg:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
	pane.modelBg:SetPoint("TOPRIGHT", pane, "TOPRIGHT", 0, 0)
	pane.modelBg:SetHeight(st.modelH)
	pane.modelBg:SetColorTexture(0.05, 0.055, 0.07, 1)

	model = CreateFrame("DressUpModel", nil, pane)
	model:SetPoint("TOPLEFT", pane, "TOPLEFT", 1, -1)
	model:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -1, -1)
	model:SetHeight(st.modelH)
	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	model:SetScript("OnMouseDown", P.StartRotate)
	model:SetScript("OnMouseUp", P.StopRotate)
	model:SetScript("OnMouseWheel", P.Zoom)
	model:SetScript("OnHide", P.StopRotate)
	P.model = model
	local level = (W.Num(Read(model.GetFrameLevel, model)) or 1) + 5

	local reset = W.FlatButton(pane, 50, 18, "Reset", P.Reset)
	reset:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -6)
	reset:SetFrameLevel(level)
	reset:SetScript("OnEnter", function(self)
		W.ShowTip(self, { "Reset", "The first view, and your gear as it is now." })
	end)
	reset:SetScript("OnLeave", W.HideTip)
	P.resetBtn = reset
	local undress = W.Toggle(pane, 80, "Undress", "Only the item, on your character without its gear. Off: the item over what you wear.",
		function()
			return st.undress
		end, function(v)
			P.SetUndress(v)
		end)
	undress:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -6)
	undress:SetFrameLevel(level)
	undress.Sync(true)
	P.undressBtn = undress
	local hint = W.Label(model, S.small, "CENTER", S.dim, 0, 6, st.w - 20, "BOTTOM", model, "BOTTOM")
	hint:SetText("Drag: rotate" .. ns.DOT .. "Wheel: zoom")
	pane.hint = hint

	pane.name = W.Label(pane, S.title, "LEFT", S.text, 10, -(st.modelH + 10), st.w - 44, "TOPLEFT")
	pane.starBtn = W.StarButton(pane, 18, function()
		return st.id
	end)
	pane.kind = W.Label(pane, S.small, "LEFT", S.muted, 10, -(st.modelH + 30), st.w - 20, "TOPLEFT")
	pane.status = W.Label(pane, S.small, "LEFT", S.gold, 10, -(st.modelH + 48), 168, "TOPLEFT")
	pane.tags = W.Label(pane, S.small, "LEFT", S.dim, 180, -(st.modelH + 48), st.w - 190, "TOPLEFT")
	pane.srcHead = W.Label(pane, S.small, "LEFT", S.gold, 10, -(st.modelH + 70), st.w - 20, "TOPLEFT")
	pane.empty = W.Label(pane, S.body, "LEFT", S.muted, 10, -(st.modelH + 14), st.w - 20, "TOPLEFT")
	pane.more = W.FlatButton(pane, 140, 18, "", function(self)
		if st.id then
			ns.UI.ShowSources(self, st.id)
		end
	end)
	pane.more:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 8, 6)
	pane.more:Hide()
	RenderInfo()
	return pane
end

function P.Model()
	return model
end

function P.SourceLines()
	return srcLines
end
