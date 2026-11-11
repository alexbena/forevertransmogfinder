local ADDON_NAME, ns = ...

local format = string.format
local Data, Mog, List = ns.Data, ns.Mog, ns.List

local Notices = {}
ns.Notices = Notices

local lastKey
local waiting = false
Notices.printed = 0
Notices.wishPrinted = 0

local function WantMissing(place)
	if not Mog.On() then
		return false
	end
	if place.kind == "inst" then
		return ns.db.noticeDungeon
	end
	return ns.db.noticeZone
end

local function WantWish()
	return Mog.On() and ns.db.noticeWish and next(ns.db.wish) ~= nil
end

local function WishLine(place)
	local ids = List.WishAt(place.kind, place.key)
	local n = #ids
	if n == 0 then
		return nil
	end
	local names = {}
	for i = 1, math.min(n, 3) do
		names[i] = Data.Name(ids[i])
	end
	local list = table.concat(names, ", ")
	if n > 3 then
		list = list .. format(" and %d more", n - 3)
	end
	return format("Wishlist: %s %s here (%s; /ftf wishlist)", list, n == 1 and "is" or "are", place.name)
end
Notices.WishLine = WishLine

function Notices.Check()
	if not ns.db then
		return
	end
	local place = Data.CurrentPlace()
	if not place or place.key == lastKey then
		return
	end
	local missing, wish = WantMissing(place), WantWish()
	if not missing and not wish then
		lastKey = place.key
		return
	end
	if not Data.Ready() then
		if Data.state == "idle" then
			Data.Load("notice")
		end
		return
	end
	if ns.InCombat() then
		waiting = true
		return
	end
	lastKey = place.key
	waiting = false
	if not place.listed then
		return
	end
	if missing then
		local n = List.MissingAppearances(place.kind, place.key, ns.db.filters)
		if n > 0 then
			Notices.printed = Notices.printed + 1
			ns.Print(format("%s: %d appearance%s you're missing (/ftf here)", place.name, n, n == 1 and "" or "s"))
		end
	end
	if wish then
		local line = WishLine(place)
		if line then
			Notices.wishPrinted = Notices.wishPrinted + 1
			ns.Print(line)
		end
	end
end

local Soon = ns.Debounce(1.5, Notices.Check)

ns.On("PLAYER_ENTERING_WORLD", Soon)
ns.On("ZONE_CHANGED_NEW_AREA", Soon)
ns.Listen("DATA_READY", Soon)
ns.Listen("COMBAT", function(_, inCombat)
	if not inCombat and waiting then
		Soon()
	end
end)
