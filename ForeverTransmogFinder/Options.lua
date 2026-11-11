local ADDON_NAME, ns = ...

local settingsByKey = {}

local function VariableName(key)
	return ADDON_NAME .. "_" .. key
end

local function OnSettingChanged()
	ns.ApplySettings()
end

local CHECKBOXES = {
	{ "Item tooltips", nil },
	{ "tooltip", "Transmog line on item tooltips",
		"Adds \"Transmog: missing\", \"collected\" or \"collected (other item)\" to item tooltips, and \"On your wishlist\" for starred items. Off by itself on a character without transmog." },
	{ "tooltipSource", "...with where to get missing ones",
		"Adds the best source (boss, quest, vendor, drop) under \"Transmog: missing\" once the item list is loaded." },
	{ "Window", nil },
	{ "filters.armorOnly", "Only my armor type",
		"Off (default): every item, cloth to plate, is listed: on Forever any character collects the look of anything it loots. On: only your class's armor type, plus everything without an armor type (weapons, cloaks, shirts...). Also in the window's filter bar." },
	{ "armorTag", "Mark armor I don't wear",
		"A small grey \"not for your armor type\" next to cloth, mail and plate on a Rogue (and the same for other classes). Information only: they still count as missing." },
	{ "previewHover", "Preview on hover",
		"The 3D preview tries on the row or icon under the mouse. Off: only the item you click." },
	{ "grid", "Grid view",
		"Icons (40 px) with a check mark on collected ones, instead of the list. Also the List / Grid buttons in the window, and /ftf grid or /ftf list." },
	{ "Chat notices", nil },
	{ "noticeDungeon", "When I enter a dungeon or raid",
		"One chat line: how many appearances you are missing there (/ftf here for the list). Never in combat." },
	{ "noticeZone", "When I enter a new zone",
		"The same line for zones. Off by default." },
	{ "noticeWish", "When I enter a place with a wishlist item",
		"One chat line, once per visit, when a zone or dungeon you enter holds an item you starred and still miss. Never in combat." },
	{ "Loading", nil },
	{ "preload", "Load the item list at login",
		"Loads the list (1.3 MB of data, about 10 MB of memory) while the login loading screen is up, then checks your collection in small steps. Never on a character with transmog off (Classic preset). Off: it loads the first time you open the window or enter a dungeon, built in small steps." },
	{ "Minimap", nil },
	{ "minimap.show", "Minimap button",
		"A round button on the minimap edge. Left-click: the window. Shift+left-click: the HERE tab. Right-click: these options. Drag it along the edge. Also /ftf minimap on, off or reset. Keys: Options > Keybindings > AddOns." },
}

local ABOUT_TIP = "Free software under the GNU General Public License, version 3 or later (LICENSE.txt in the addon folder). "
	.. "It comes with no warranty."

function ns.RegisterOptions()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
		and Settings.RegisterAddOnCategory and Settings.CreateCheckbox) then
		ns.Debug("Settings API not found; no options panel.")
		return
	end
	local db, defaults = ns.db, ns.DEFAULTS
	local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)
	for _, c in ipairs(CHECKBOXES) do
		local key, label, tip = c[1], c[2], c[3]
		if label == nil then
			if CreateSettingsListSectionHeaderInitializer and Settings.RegisterInitializer then
				Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(key))
			end
		else
			local group, field = string.match(key, "^(%w+)%.(%w+)$")
			local tbl, tblKey, default = db, key, defaults[key]
			if group then
				tbl, tblKey, default = db[group], field, defaults[group][field]
			end
			local setting = Settings.RegisterAddOnSetting(category, VariableName(group and (group .. "_" .. field) or key),
				tblKey, tbl, Settings.VarType.Boolean, label, default)
			setting:SetValueChangedCallback(OnSettingChanged)
			settingsByKey[key] = setting
			Settings.CreateCheckbox(category, setting, tip)
		end
	end
	if CreateSettingsListSectionHeaderInitializer and Settings.RegisterInitializer then
		Settings.RegisterInitializer(category, CreateSettingsListSectionHeaderInitializer(ns.About(),
			ABOUT_TIP))
	end
	Settings.RegisterAddOnCategory(category)
	ns.optionsCategory = category
end

function ns.SetOption(key, value)
	local setting = settingsByKey[key]
	if setting then
		setting:SetValue(value)
	else
		ns.SetOptionValue(key, value)
	end
end

function ns.RefreshOptions()
	for _, setting in pairs(settingsByKey) do
		setting:NotifyUpdate()
	end
end

function ns.OpenOptions()
	local category = ns.optionsCategory
	if not (category and Settings and Settings.OpenToCategory) then
		ns.Print("The options panel is not available.")
		return
	end
	local openedNow = ns.RunOutOfCombat("openOptions", function()
		local id = category.GetID and category:GetID()
		if type(id) == "number" and not ns.IsSecret(id) then
			Settings.OpenToCategory(id)
		end
	end)
	if not openedNow then
		ns.Print("Options will open when combat ends.")
	end
end
