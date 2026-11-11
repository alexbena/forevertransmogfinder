# Forever Transmog Finder

See every transmog appearance on WoW Forever, which ones you are still missing, and where to get them.

On Forever the Collections journal only shows the appearances you already have. This add-on brings its own list of about 10,000 items and asks the game about each one.

## What it does

- **Here:** what you are missing in the zone or dungeon you are in right now. Inside a dungeon or raid the list goes boss by boss, in the order you meet the bosses. In a zone the nearest items come first, with their distance.
- **Zones and Dungeons:** every zone and every dungeon and raid, with "collected / total", a progress bar and how many you are missing. Click one to see its items.
- **All:** every item in one list. Search item names, bosses, NPCs, quests, vendors and professions. "vancleef" finds his loot.
- **Wishlist:** star any item. Starred items get their own tab, an "On your wishlist" line on their tooltip, and one chat line when you enter a zone or dungeon that has one you still miss. The wishlist is shared by all the characters of your account.
- **Stats:** how many appearances you have collected, by slot and by armor type.
- **Where it comes from:** each item shows its best source: "Boss: Edwin VanCleef · Deadmines", "Quest: … · Westfall 56,47", "Vendor: … · 2s 50c", "Crafted: Leatherworking". Click "+N more" to see all its sources.
- **Both factions:** a quest or vendor for one faction only is marked "(Alliance)" or "(Horde)". The other faction's are dimmed and your own faction's come first. The "missing" counts only count what you can get. Sorted by source, items a place has only for the other faction are listed last, under "Alliance only" or "Horde only".
- **3D preview:** your own character tries on the item you hover or click, over your gear or alone ("Undress"). Drag to rotate, use the mouse wheel to zoom. Ctrl-click opens the dressing room.
- **List or grid:** rows with the status and the best source, or a grid of icons with a check mark on the collected ones.
- **Tooltips:** every item tooltip gets one line: missing, collected, or collected from another item. For a missing item, the best source is shown under it.
- **Dungeon notice:** when you enter a dungeon or raid, one chat line tells you how many appearances you are missing there. Never in combat.
- **Map pins:** right-click an item, then "Map pin to source". The pin goes on the world map.
- **Filters:** slot, quality, required level, "Only my armor type" and "Show collected". Sort by source, slot, name or level. Missing items come first.

## How to open it

- **Minimap button:**
  - Left-click: open or close the window.
  - Shift+left-click: the Here tab.
  - Right-click: the options.
  - Drag it along the edge of the minimap. It works on round and square minimaps.
  - Its tooltip shows how many appearances you are missing where you are.
  - Minimap-button collector add-ons can gather it (ForeverTransmogFinderMinimapButton).
- **Keys:** Options > Keybindings > AddOns > Forever Transmog Finder. There are two keys: open or close the window, and the Here tab. They are not bound by default.
- **AddOns menu** on the minimap (left-click: window, right-click: options).
- **Options:** Options > AddOns > Forever Transmog Finder.

The window can be resized from its bottom-right corner. Ctrl+F puts the cursor in the search box, and Esc closes the window.

## Commands

| Command | What it does |
|---|---|
| `/ftf` | Open or close the window (`/transmogfinder` does the same) |
| `/ftf here` | What you are missing where you are |
| `/ftf zone <name>` | One zone, e.g. `/ftf zone westfall` |
| `/ftf dungeon <name>` | One dungeon, boss by boss, e.g. `/ftf dungeon deadmines`. Short names work: `dm`, `wc`, `sfk`, `rfc`, `bfd`, `stocks`, `gnomer`, `sm`, `zf`, `brd`, `lbrs`, `strat`, `scholo`, `mc`, `bwl`, `zg`, `naxx` and more |
| `/ftf search <text>` | Search every item |
| `/ftf wishlist` | Your wishlist |
| `/ftf grid` / `/ftf list` | Icon grid or list |
| `/ftf scan` | Is transmog on, is the item list loaded, and how far the collection check is |
| `/ftf rules` | What your account has collected per armor type, and what the game says about 4 test items |
| `/ftf minimap on` / `off` / `reset` | Show, hide or reset the minimap button |
| `/ftf reset` | Put the window back in the middle of the screen, at its first size |
| `/ftf options` | The options panel |
| `/ftf help` | The version, the licence and the list of commands |

## Clicks on an item

- Hover or click: try it on in the 3D preview.
- Shift-click: link it in chat (open the chat box first).
- Ctrl-click: the dressing room.
- The star: add it to your wishlist, or remove it.
- Right-click: a menu with map pin, all sources, wishlist, dressing room, link in chat and copy name.

## What Forever allows, and what the add-on does

- **Transmog is part of the Enhanced experience preset.** On a character with the Classic preset there is no transmog collection. The add-on then still shows where every item comes from, but with no "missing" marks, no tooltip line and no notices. You can switch in Options > Preset. The add-on never changes it for you.
- **The game decides what you can collect.** The add-on asks the game about each item. On Forever any character collects the look of anything it can loot, so cloth, mail and plate are listed for every class. "Only my armor type" hides the armor your class does not wear.
- **There are no maps inside dungeons on Forever.** A map pin for a dungeon drop goes to the dungeon entrance.
- **In combat** the game blocks some things for add-ons. The dressing room and map pins wait until combat ends. The window itself works in combat. The background check and the 3D model wait until combat ends.

## What it does not do

- It never changes your game settings, your preset or the Collections journal's filters.
- It never casts, targets, moves or loots for you.
- It does not read the combat log. It sends nothing to other players.
- It asks the server for item data slowly: at most 20 items a second.

## Performance

- The item list loads at login, behind the loading screen. Measured outside the game, that takes about 0.2 seconds and about 9 MB of memory. On a character with transmog off it is not loaded at login. Turn off "Load the item list at login" to load it the first time you open the window instead.
- The collection check runs in small steps in the background, a few seconds after login. It pauses in combat.

## Limits (Beta)

- Made for Forever 1.60.1. Items added by later patches are not in the list until an update; one chat line tells you when the list is older than your game. The tooltip line still works for them.
- Item, boss, NPC, quest and dungeon names are in English, and search uses the English names. Zone names follow your game language. Only the English client was tested.
- About 2,800 items show only the kind of source ("World drop", "Vendor", "Quest reward") with no place. Most of them are Forever's new items.
- Forever's new dungeons have no loot table yet. Their items show as world drops.
- There are no drop chances.
- Bind-on-equip items: the game decides when they count as collected.

## Works with

- **ForeverPath** (optional): when it is installed, the right-click menu and the preview can point ForeverPath's arrow to a source your faction can use.

## Feedback and source

Report bugs and ideas on the GitHub Issues page: https://github.com/alexbena/forevertransmogfinder/issues

Drop, quest and vendor data derived from QuestieDB (GPL-3.0), modified.

Forever Transmog Finder is free software under the GNU GPL version 3 or later. It comes with no warranty. Source code and data tools: https://github.com/alexbena/forevertransmogfinder.

## Install

- **CurseForge app:** search for "Forever Transmog Finder" (game: WoW Forever).
- **By hand:** download the zip from the CurseForge page and unzip it into the `Interface/AddOns` folder inside your WoW Forever game folder (`_forever_`). You get two folders, `ForeverTransmogFinder` and `ForeverTransmogFinder_Data`; both are needed.

## Repository layout

- `ForeverTransmogFinder/`, `ForeverTransmogFinder_Data/`: the add-on exactly as released.
- `generator/`: the tool that builds the item data from the game's client tables and QuestieDB. See `generator/README.md`.
- `logo/`: the logo and the in-game icon (SVG sources and PNG exports).

## License

GNU General Public License version 3 or later. See `LICENSE` and `NOTICE.txt`.

