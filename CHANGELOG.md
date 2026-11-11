# Changelog

## 0.3.1 (2026-11-11)
First public release (Beta).
- Every transmog appearance in the game and where to get it: boss and mob drops, quests, vendors, crafts, containers and world drops.
- Shows the appearances you are missing, per zone and per dungeon. Inside a dungeon or raid the list goes boss by boss, in the order you meet the bosses. In a zone the nearest items come first, with their distance.
- A resizable window with six tabs (Here, Zones, Dungeons, All, Wishlist, Stats), a 3D preview on your own character, a list or grid view, filters, sorting and a search.
- A wishlist: star any item. Starred items get their own tab, a tooltip line and a chat line when you enter a place that has them.
- A transmog line on item tooltips: missing, collected, or collected from another item, with the best source for missing items.
- Minimap button, two key bindings and `/ftf`.

New since 0.3.0 (not released publicly):
- Both factions. A quest or vendor for one faction only is marked "(Alliance)" or "(Horde)", and the other faction's are dimmed. Your own faction's sources come first, in the lists, the preview and the list of all sources. Only items you can get at a place count in its "missing" numbers: the Zones and Dungeons lists, the chat lines and the minimap button. Sorted by source, items a place has only for the other faction are listed last, under "Alliance only" or "Horde only". The ForeverPath arrow points only to your own faction's sources.
- On a character with transmog off (Classic preset), the item list is no longer loaded at login, and the wishlist chat line is off there too. The list loads when you open the window, or when you turn transmog on.
- The window uses your client's font, so zone names in other alphabets show.
- One chat line per session when the item list is older than your game client. `/ftf scan` says it too.
- The window fits on the screen at any UI scale. On a screen smaller than its smallest size, it is scaled down.
- The minimap button has a name, so minimap-button collector add-ons can gather it.
- The item list add-on is grouped under Forever Transmog Finder in the AddOn list.
- Item data is requested from the server more slowly: at most 20 items a second, and at most 2,000 a session.
- The options panel and the first line of `/ftf help` show the version, the author and the licence.
- The item list has a new format (2) that gives each source's faction. It keeps up to 16 sources an item: the best 8 for each faction.

Known limits: item, boss, NPC, quest and dungeon names are in English, and search uses the English names. About 2,800 items show only the kind of source, with no place. Forever's new dungeons have no loot table yet. There are no drop chances.

## 0.3.0 (2026-11-11, not released publicly)
- A bigger window (980 x 620 at first). Drag its bottom-right corner to resize it; the size is saved.
- A 3D preview on the right: your character tries on the item you hover or click, over your gear or alone ("Undress"). Drag to rotate, wheel to zoom, "Reset" for the first view.
- List or grid view: 40 px icons with a check mark on collected ones. `/ftf list` and `/ftf grid`.
- A sort menu: by source (bosses in the order you meet them, then quests, vendors and the rest), slot, name or level. Missing items come first.
- A wishlist: a star on every item, a Wishlist tab, an "On your wishlist" tooltip line, and one chat line when you enter a place with a wishlist item you still miss. It is kept for the whole account.
- Progress bars: in the title bar, on every zone and dungeon, on every group header, and in Stats by slot and by armor type.
- In a zone, the Here tab puts the nearest items first, with their distance.
- The "can't collect" status is gone: on Forever any character collects the look of anything it can loot. Items show as missing, collected, or collected from another item, as the game reports them. "Usable by me" became "Only my armor type" (off by default), and cloth, mail or plate you don't wear gets a small grey tag.
- `/ftf rules`: what this account has collected per armor type, and what the game says about 4 test items.
- Ctrl+F puts the cursor in the search box.
- Its own icon, for the add-on and the minimap button.

## 0.2.0 (2026-11-11, not released publicly)
- A minimap button. Left-click opens or closes the window. Shift+left-click opens the HERE tab. Right-click opens the options. Drag it along the minimap edge; it follows round and square minimaps. `/ftf minimap on`, `off` or `reset`.
- Two key bindings in Options > Keybindings > AddOns: open or close the window, and the HERE tab.
- One welcome line, once per account.
- The tooltip of the minimap button shows how many appearances you are missing where you are.

## 0.1.0 (2026-11-11, not released publicly)
- First version.
- A window with five tabs: HERE (where you are now), ZONES, DUNGEONS (boss by boss), ALL (searchable) and STATS (collected per slot).
- Filters: slot, quality, required level, show collected, and search over items, bosses, NPCs, quests, vendors and professions.
- Each item shows its best source with the place, the coordinates and the vendor price. Click it for all its sources. Shift-click links it in chat. Ctrl-click opens the dressing room. Right-click opens a menu: map pin, all sources, preview, link, copy name.
- A transmog line on item tooltips: missing, collected, or collected from another item, with the best source for missing items.
- One chat line when you enter a dungeon or raid: how many appearances you are missing there (optional for zones).
- The collection check runs in small steps in the background and pauses in combat.
- On a character with transmog off (Classic preset), the window explains why and still lists where items come from.
- The item list (about 10,000 items) is a separate load-on-demand add-on, ForeverTransmogFinder_Data.
