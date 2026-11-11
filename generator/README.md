# Forever Transmog Finder data generator

`build_mog_public.py` builds `ForeverTransmogFinder_Data`, the item list that Forever Transmog Finder loads on demand. Its inputs are the WoW Forever client tables and QuestieDB Forever. It lists every transmog item with its appearance and where to get it: boss and mob drops, quest rewards, vendors, crafts, containers and world drops. These scripts are the source of the generated `Items*.lua`, `Sources*.lua` and `Places.lua`.

## Files

| File | Purpose |
|---|---|
| `build_mog_public.py` | The generator (command line, sources, ranking, writers) |
| `mogdata.py` | Input loaders: config, client tables, hotfixes, quest cache, QuestieDB, zone geometry |
| `hotfix.py` | Reader for the client hotfix cache `DBCache.bin` and its WoWDBDefs row layouts |
| `wdb.py` | Reader for the client quest cache `questcache.wdb` |
| `svlua.py` | Reader for Lua table literals (QuestieDB data files); it never runs Lua code |
| `dungeon_entrances.csv` | Dungeon and raid entrances (committed; see below) |
| `config.example.json` | Example config; copy it to `config.json` (git-ignored) |

## Requirements

- Python 3.8 or later. Standard library only. Run it with `python -I`.
- A full build takes about 15 seconds.

## Inputs

None of the inputs are committed. Put them under `inputs/` (git-ignored) or anywhere else, and point the config at them.

**1. Client tables (CSV), from wago.tools, for client build 1.60.1.70862**

`https://wago.tools/db2/<Table>/csv?build=1.60.1.70862`, saved as `<Table>.csv`, for these 14 tables:

`ItemSparse`, `Item`, `SpellEffect`, `SkillLineAbility`, `AreaTable`, `QuestSort`, `LFGDungeons`, `ContentTuning`, `Map`, `DungeonEncounter`, `UiMap`, `UiMapAssignment`, `ItemModifiedAppearance`, `ItemAppearance`

**2. WoWDBDefs layouts** (only needed with `dbcache`)

`https://raw.githubusercontent.com/wowdev/WoWDBDefs/master/definitions/<Table>.dbd` (repository https://github.com/wowdev/WoWDBDefs), for `ItemSparse`, `Item`, `SpellEffect` and `SkillLineAbility`. They decode the hotfix rows. The layout used must list build 1.60.1.70862.

The generator checks these files before it starts and prints every missing file with its download URL.

**3. `DBCache.bin`** (optional, recommended)

The client's hotfix cache: `Cache/ADB/enUS/DBCache.bin` in the game's `_forever_` folder. Copy it while the game is closed. It holds the item rows that the server patched after the build. In build 70862 it adds 5,039 `ItemSparse` rows (names, levels, quality) and updates about 5,700 `Item` rows. Without it, items that only it names are left out, and the list shrinks from 10,030 to about 8,000 items.

**4. `questcache.wdb`** (optional)

The client's quest cache: `Cache/WDB/enUS/questcache.wdb` in the game's `_forever_` folder. It holds the quests the server has sent to that client, with their exact rewards, and adds quest rewards that QuestieDB lacks. It only covers quests that client has seen. The client also rewrites it with fewer records when you log out. So keep older copies and list them all in `questcache`: they are merged, and a later file wins for the same quest. A file from another build is skipped. With no quest cache, quest rewards come from QuestieDB alone.

**5. QuestieDB Forever** (GPLv3)

From https://github.com/Questie/QuestieDB. Copy these files into one folder (`questie_dir`):

| File | Path in the QuestieDB repository |
|---|---|
| `foreverItemDB.lua`, `foreverNpcDB.lua`, `foreverQuestDB.lua`, `foreverObjectDB.lua`, `conversion.json` | `data/Forever/` |
| `foreverBaseNpc.lua`, `foreverBaseQuest.lua` | `src/corrections/Forever/generated/` |
| `foreverNpcTraces.lua`, `foreverQuestTraces.lua` | `src/corrections/Forever/traces/` |
| `foreverNPCFixes.lua`, `foreverQuestFixes.lua` | `src/corrections/Forever/` |
| `provenance.json` (only logged) | `support/Forever/` |

The first four `data/Forever/` files and `conversion.json` are required. The others are layered on top when present. The generator logs the git blob hash of each file, so you can compare it with `git ls-tree` output.

**6. `dungeon_entrances.csv`** (committed): see "Dungeon entrances".

## Config

Copy `config.example.json` to `config.json` and edit the paths. A relative path is relative to the config file. `--config <file>` uses another file.

| Key | Meaning |
|---|---|
| `build` | Full client build of the tables, e.g. `1.60.1.70862` |
| `wago_dir` | Folder of the client table CSVs (required) |
| `dbd_dir` | Folder of the `.dbd` layouts (required with `dbcache`) |
| `dbcache` | `DBCache.bin` copy (optional) |
| `questcache` | List of `questcache.wdb` copies, oldest first (optional) |
| `questie_dir` | Folder of the QuestieDB Forever files (required) |
| `entrances` | Entrances CSV (default: `dungeon_entrances.csv` next to the script) |
| `out_dir` | Output folder: the `ForeverTransmogFinder_Data` add-on folder |
| `license_file`, `notice_file` | Copied into the output (default: `../LICENSE.txt`, `../NOTICE.txt`) |
| `version` | Add-on version written into the data TOC (`--version` overrides it) |

Inputs and outputs may not lie under a `WTF` folder; the generator refuses to start.

## Run

```
python -I build_mog_public.py --config config.json --version 0.3.1
```

| Option | Meaning |
|---|---|
| `--format 1` / `--format 2` | Data contract version (default 2; see Outputs). Forever Transmog Finder 0.3.1 and later read only format 2; format 1 is for 0.3.0 and older |
| `--version X` | Version for the data TOC; use the main add-on's version |
| `--out DIR` | Output folder (default: `out_dir`) |
| `--date YYYY-MM-DD` | Date written into the files (default: today); pin it to reproduce a build byte for byte |
| `--csv FILE` | Also write one CSV row per item with its best source |
| `--write-entrances` | Rewrite the entrances CSV from the client `Map` table instead of reading it |

The log lists the inputs, what was left out and why, the sources by kind, origin and faction, the instances without an entrance, and the file sizes.

## Outputs

The add-on folder `ForeverTransmogFinder_Data`:

- `ForeverTransmogFinder_Data.toc` (load on demand, grouped under and depending on `ForeverTransmogFinder`).
- `Places.lua`, `Items1.lua`, `Items2.lua`, `Sources1.lua`, `Sources2.lua`. They fill the global `ForeverTransmogFinderData`; the fields are described at the top of `build_mog_public.py`. Stale `Items<n>`/`Sources<n>` chunks from a bigger earlier build are removed.
- `LICENSE.txt` and `NOTICE.txt`, copied from `license_file` and `notice_file`. NOTICE is left out when no QuestieDB data was used.

**Format 1** (`D.version = 1`): each source is `{kind, where, "label", x, y, extra}`. A Horde-only quest or vendor has " (Horde)" appended to its label, and Horde-only sources sort last. Nothing marks an Alliance-only source. At most 8 sources per item.

**Format 2** (`D.version = 2`, Forever Transmog Finder 0.3.1 and later): labels carry no faction suffix. A source for one faction has a 7th field: `"A"` (Alliance only) or `"H"` (Horde only). A source for both factions, or of unknown faction, leaves the field out (nil); trailing nils are not written, so such a row is as long as in format 1. Rows can therefore hold nils: read field 7 by index (`e[7]`), never through `#e`. Sorting ignores the faction. Each item keeps the 8 best sources usable by each faction, in one best-first list, so a list can hold up to 16 sources. With build 1.60.1.70862 and the inputs below, format 2 has 16,993 sources: 2,402 `"A"`, 2,199 `"H"` and 12,392 for both factions. The two `Sources` files total about 720 KB, against 677 KB in format 1.

## Dungeon entrances

`dungeon_entrances.csv` has the columns `map_id, name, ui_map, x, y, source`, one row per dungeon or raid the item list uses. The coordinates are 0-100 on the zone map `ui_map`. A row with a blank `ui_map` means the entrance is unknown; the data then writes `0` and the add-on says the entrance is not in the list. An instance with no row falls back to its client `Map` corpse point.

Every row comes from client data. `--write-entrances` regenerates the file from the `Map` table's corpse point (where a ghost from that instance is sent), placed on the zone map. In build 1.60.1.70862, three instances have no entrance in the client data and stay blank: Naxxramas (533), City of Dalaran (2959) and Excavation Site: Wetlands (2998). They have no `Map` corpse point, and no `AreaPOI` or `AreaTrigger` row marks their entrance. A row filled in by hand must come from client data as well. `--write-entrances` overwrites hand edits.

## Reproducing the published item list

The item list of Forever Transmog Finder 0.3 comes from these inputs:

- Client tables of build 1.60.1.70862 (wago.tools), and `DBCache.bin` of build 70862. It held 80,936 hotfix entries, 13,490 of them for the four item tables.
- Four `questcache.wdb` copies of build 70862, merged: 4,679 quests.
- QuestieDB Forever. Its `provenance.json` has `upstream_seed_commit` 0529e8d82075316242b0796e2128afb40d300130 and `coordinate_source_checkout_commit` d94542ac92423f05c6fbde6574ada29b15c0d4e8. The files' git blob hashes:

  | File | git blob |
  |---|---|
  | foreverItemDB.lua | 8cacee3220dd7c370513ba80fed31801a5b44e41 |
  | foreverNpcDB.lua | 7940d463751b2e0ecffed4f63a7f75c807140e1e |
  | foreverQuestDB.lua | f4ea75ca02efc2333fd02dd955f42b68f4ffb14a |
  | foreverObjectDB.lua | 8d57a7f1d10949d5e154e19622426855cc7aec2a |
  | conversion.json | d4ada64003ffbcda61620f604cbe13424595a358 |
  | foreverBaseNpc.lua | a0435bd31bb9f28d821b415c8bff8bb969d1d879 |
  | foreverBaseQuest.lua | ab12cfb05caa4ca95bc91681e9ea442e76247ee0 |
  | foreverNpcTraces.lua | e3444272b48668ab57712707ce9a0e3f0d6c68f4 |
  | foreverQuestTraces.lua | c4f00f787389078fb162f7b664aac1dad2f5bf4a |
  | foreverNPCFixes.lua | 5dc1333573f76ced7cfd484abffb2575ea6022c3 |
  | foreverQuestFixes.lua | df8c7cf1ef477537e8d05a3665be63f59103f6f9 |

Result: 10,030 items, 6,442 appearances, 48 zones, 28 dungeons and raids. A different `DBCache.bin` or quest cache changes the item names and the quest-reward sources. Other inputs that match these pins give the same files.

## Licence

Copyright (C) 2026 Gitano Calvo. The generator is free software under the GNU General Public License, version 3 or (at your option) any later version (`SPDX-License-Identifier: GPL-3.0-or-later`). It comes with no warranty. See `LICENSE.txt`.

The generated data includes drop, quest, vendor and spawn data derived from QuestieDB (https://github.com/Questie/QuestieDB), which is licensed under GPL-3.0. The data add-on is therefore distributed under the GPL as well. The QuestieDB licence does not cover the Questie name or logo.

The client tables and caches are Blizzard Entertainment's data and are not part of this repository. The generated files hold item, NPC, quest and zone names, IDs and map coordinates taken from them.
