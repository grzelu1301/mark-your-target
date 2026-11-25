# NPC data sources

- [QuestieDB](https://github.com/Questie/QuestieDB/tree/4377c981ac368d1593ec92788218e0a689a6a02b), GPLv3. The Forever export merges the Classic baseline, Forever corrections, and player traces. Mark Your Target retains documented spawn or patrol areas and maps them to WoW UI map IDs. Some inherited Classic placements remain approximate.
- Data from [Efficient Games](https://efficient.games), licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The [EG Link snapshots](https://github.com/JIVESCORP/eg-link-output-wowf/tree/d78a89020881ec338a4a7c1f2a89ee613f68554b/data/wowf) provide creature sightings, NPC interactions, and loot observations. Mark Your Target joins these by NPC ID and retains observed UI map IDs. English creature details also supply names.
- [EverlookDB](https://www.everlookdb.com/data.html), build 1.60.1.71091. Mark Your Target cross-checks names by ID, uses them as a fallback for documented NPCs, and uses the zone export for display-name matching. See [upstream credits and licenses](https://www.everlookdb.com/credits.html), including [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPLv3) and [AllTheThings](https://github.com/AllTheThings/AllTheThings) (MIT).
- Four Drowned City placements checked against the local creature cache and documented separately in [verified_locations.tsv](tools/verified_locations.tsv). Sources include [Forever Drop Rate’s corpse observations](https://www.foreverdroprate.com/zones/16550) and [Warcraft Wiki’s Zin'aka entry](https://warcraft.wiki.gg/wiki/Zin%27aka).

The generator merges the locations of NPC IDs sharing an English name and skips obvious script markers. A client definition or historical NPC name alone does not qualify an entry for suggestions. Blizzard’s server-side spawn data is unavailable, so uncataloged or changed encounters can still be missing. World of Warcraft names and game content belong to Blizzard Entertainment.

## Verification

The snapshot contains 10,694 NPC IDs across 10,312 distinct names. QuestieDB and EG Link overlap on 5,562 IDs with spawn or observation evidence. All 2,042 shared IDs agreed with the local Forever 1.60.1.71037 English creature cache. The selected names agreed on 10,627 of 10,693 QuestieDB names and 9,486 of 9,528 EverlookDB names by ID. When names differ, the generator prefers EG Link’s English creature details and live observations over older baseline names.

Ghostmaw (NPC 263380) appears on Riverglades UI map 2548 in QuestieDB. The local creature cache and EG Link confirm the name, and [Zephras records a Riverglades sighting](https://zephras.com/forever/enUS/npc/263380/).

## Rebuild

1. Check out the QuestieDB revision linked above and run its `tools/export-forever.lua --include-authored` from its repository root with Lua 5.1. QuestieDB includes a Lua executable.
2. Run this add-on’s `tools/export_questie_npcs.lua` with the QuestieDB checkout path as its argument. Redirect stdout to `questie-npcs.tsv` as UTF-8.
3. In an inputs directory, save `npcs.json`, `loot.json`, `creatures.json`, and `creature_details.enUS.json` from the pinned EG Link snapshot in their original build folders. This snapshot uses builds 70790, 70840, 70862, 70888, 70938, 70959, and 71037.
4. Download EverlookDB’s [NPC JSON](https://www.everlookdb.com/downloads/npcs.json) and [zone JSON](https://www.everlookdb.com/downloads/zones.json). These live exports can change.
5. From this repository, run the generator with Python 3.9 or later. Pass `--cache` with the optional path to the local `_forever_/Cache/WDB/enUS/creaturecache.wdb` to verify names. This reports counts and does not copy the cache.

```text
python tools/build_npcs.py questie-npcs.tsv eg-link-inputs everlook-npcs.json everlook-zones.json NPCs.lua
```

The EverlookDB snapshot SHA-256 values were `58690eca334865c0a566a0a76b9b44e70b2de6450023b276ffc1967812d51762` for NPCs and `5501c8e90566151ff1ae6c644e1caa53f6ec4ec658478aa6c448478f968` for zones.
