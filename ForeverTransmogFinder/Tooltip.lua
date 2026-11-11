local ADDON_NAME, ns = ...

local type, pcall = type, pcall
local IsSecret = ns.IsSecret
local Data, Mog = ns.Data, ns.Mog
local ST = Mog.ST
local S = ns.STYLE

local Tip = {}
ns.Tip = Tip
Tip.lines = 0

local TEXT = {
	[ST.MISSING] = { "Transmog: missing", S.gold },
	[ST.EXACT] = { "Transmog: collected", S.muted },
	[ST.KNOWN] = { "Transmog: collected (other item)", S.muted },
	[ST.CANT] = { "Transmog: can't collect (class rules)", S.red },
}
Tip.TEXT = TEXT
Tip.WISH = "On your wishlist"

local function Wanted(tooltip)
	if tooltip == GameTooltip then
		return true
	end
	return ItemRefTooltip ~= nil and tooltip == ItemRefTooltip
end

function Tip.OnItem(tooltip, data)
	if not (ns.db and ns.db.tooltip) or not Mog.On() then
		return
	end
	if not Wanted(tooltip) then
		return
	end
	if type(tooltip.IsForbidden) == "function" then
		local ok, forbidden = pcall(tooltip.IsForbidden, tooltip)
		if not ok or IsSecret(forbidden) or forbidden then
			return
		end
	end
	local link, itemID
	if TooltipUtil and type(TooltipUtil.GetDisplayedItem) == "function" then
		local ok, _, l, id = pcall(TooltipUtil.GetDisplayedItem, tooltip)
		if ok then
			link, itemID = l, id
		end
	end
	if IsSecret(link) or IsSecret(itemID) then
		return
	end
	if type(itemID) ~= "number" and type(data) == "table" then
		local id = data.id
		if not IsSecret(id) then
			itemID = id
		end
	end
	if type(itemID) ~= "number" then
		return
	end
	if type(link) ~= "string" then
		link = nil
	end
	local code = Mog.ForTooltip(itemID, link)
	local t = code and TEXT[code]
	if t and (code ~= ST.CANT or ns.db.classRules) then
		tooltip:AddLine(t[1], t[2][1], t[2][2], t[2][3])
		Tip.lines = Tip.lines + 1
		if code == ST.MISSING and ns.db.tooltipSource and Data.Ready() then
			local best = Data.BestText(itemID)
			if best then
				tooltip:AddLine("  " .. best, S.text[1], S.text[2], S.text[3], true)
			end
		end
	end
	if ns.Wish.Has(itemID) then
		tooltip:AddLine(Tip.WISH, S.gold[1], S.gold[2], S.gold[3])
	end
end

function Tip.Init()
	if Tip.registered then
		return
	end
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType
		and Enum.TooltipDataType.Item ~= nil) then
		ns.Debug("TooltipDataProcessor not found: no tooltip line.")
		return
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		local ok, err = pcall(Tip.OnItem, tooltip, data)
		if not ok then
			Tip.errors = (Tip.errors or 0) + 1
			ns.Debug("Tooltip line failed:", err)
		end
	end)
	Tip.registered = true
end

ns.Listen("LOGIN", Tip.Init)
