"""Build the English target-picker catalog from Forever spawn evidence."""

import argparse
import csv
import json
import re
import struct
from collections import Counter, defaultdict
from pathlib import Path


def json_data(path):
    return json.loads(path.read_bytes())


def valid_name(name):
    return (
        isinstance(name, str)
        and name.strip()
        and not re.search(r"[\x00-\x1f\x7f\[\];|]", name)
    )


def is_script_marker(name):
    name = name.lower()
    return (
        "trigger" in name.split()
        or name in {"invisible man", "invisible stalker", "gong boy dnd dnr"}
    )


def creature_cache(path):
    """Read the enUS BOMW v4 creature cache. The cache has no spawn locations."""
    data = path.read_bytes()
    if data[:4] != b"BOMW" or data[8:12] != b"SUne" or data[16:20] != b"\x04\0\0\0":
        raise ValueError("Expected a Forever enUS BOMW v4 creature cache")
    offset = 24
    names = {}
    while offset + 8 <= len(data):
        npc_id, size = struct.unpack_from("<II", data, offset)
        if (npc_id, size) == (0, 0) and offset + 8 == len(data):
            return names
        end = offset + 8 + size
        if not npc_id or size < 16 or end > len(data):
            raise ValueError(f"Invalid creature cache record at offset {offset}")
        first_name, separator, _ = data[offset + 23:end].partition(b"\0")
        if not separator:
            raise ValueError(f"Missing creature name terminator at offset {offset}")
        name = first_name.decode("utf-8")
        if valid_name(name):
            names[npc_id] = name
        offset = end
    raise ValueError("Missing creature cache terminator")


def read_observations(root):
    seen = set()
    names = {}
    client_names = {}
    maps = defaultdict(set)
    builds = sorted(root.glob("1.60.1.*"), key=lambda path: int(path.suffix[1:]))
    if not builds:
        raise ValueError("No EG Link build folders found")

    def add_positions(npc_id, row):
        for point in row.get("positions", []):
            map_id = point.get("uiMap")
            if isinstance(map_id, int) and map_id > 0:
                maps[npc_id].add(map_id)

    for build in builds:
        for file, key in (("creatures.json", "creatures"), ("npcs.json", "npcs")):
            for raw_id, row in json_data(build / file)[key].items():
                npc_id = int(raw_id)
                seen.add(npc_id)
                if valid_name(row.get("name")):
                    names[npc_id] = row["name"]
                add_positions(npc_id, row)
        loot = json_data(build / "loot.json")
        for raw_id in loot["sources"].keys() | loot["kills"].keys():
            match = re.fullmatch(r"npc:(\d+)(?:\|\w+)?", raw_id)
            if match:
                npc_id = int(match[1])
                seen.add(npc_id)
                add_positions(npc_id, loot["sources"].get(raw_id, {}))
        details = json_data(build / "creature_details.enUS.json")["creatures"]
        for raw_id, row in details.items():
            if valid_name(row.get("name")):
                client_names[int(raw_id)] = row["name"]
    return seen, names, client_names, maps


def lua_array(values):
    return "    {" + ", ".join(json.dumps(value, ensure_ascii=False) for value in values) + "},\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("questie", type=Path, help="TSV from export_questie_npcs.lua")
    parser.add_argument("eg_link", type=Path, help="Directory containing EG Link folders named by build")
    parser.add_argument("everlook_npcs", type=Path, help="EverlookDB NPC JSON")
    parser.add_argument("everlook_zones", type=Path, help="EverlookDB zone JSON")
    parser.add_argument("output", type=Path)
    parser.add_argument("--cache", type=Path, help="Optional local creaturecache.wdb for verification")
    args = parser.parse_args()

    maps = defaultdict(set)
    placed = set()
    questie_names = {}
    with args.questie.open(encoding="utf-8-sig", newline="") as source:
        for row in csv.DictReader(source, dialect="excel-tab", quoting=csv.QUOTE_NONE):
            npc_id = int(row["id"])
            if valid_name(row["name"]):
                questie_names[npc_id] = row["name"]
            if row["spawn"] == "1":
                placed.add(npc_id)
                maps[npc_id].update(int(map_id) for map_id in row["maps"].split(",") if map_id)

    seen, observed_names, detail_names, observed_maps = read_observations(args.eg_link)
    for npc_id, values in observed_maps.items():
        maps[npc_id].update(values)
    everlook = {
        row["id"]: row["name"]
        for row in json_data(args.everlook_npcs)["data"]
        if not row["internal"] and valid_name(row["name"])
    }
    map_names = {
        row["id"]: row["name"].lower()
        for row in json_data(args.everlook_zones)["data"]
        if row["name"]
    }

    location_labels = {}
    with Path(__file__).with_name("verified_locations.tsv").open(encoding="utf-8", newline="") as source:
        for row in csv.DictReader(source, dialect="excel-tab"):
            location_labels[int(row["id"])] = row["zones"].split(",")

    # An entity must have a documented placement or a live observation. Client
    # definitions and historical data can resolve names but cannot add entities.
    names_by_id = {}
    catalog = {}
    missing_names = 0
    script_markers = 0
    for npc_id in sorted(placed | seen | location_labels.keys()):
        name = next(
            (source[npc_id] for source in (detail_names, observed_names, questie_names, everlook)
             if npc_id in source),
            None,
        )
        if not name:
            missing_names += 1
            continue
        name = name.strip()
        if is_script_marker(name):
            script_markers += 1
            continue
        names_by_id[npc_id] = name
        key = name.lower()
        _, zone_maps, labels = catalog.setdefault(key, (name, set(), set()))
        zone_maps.update(maps[npc_id])
        labels.update(location_labels.get(npc_id, ()))

    ghostmaw = names_by_id.get(263380)
    if ghostmaw != "Ghostmaw" or 2548 not in catalog[ghostmaw.lower()][1]:
        raise ValueError("Expected Ghostmaw (263380) on the Riverglades map (2548)")
    header = """-- Generated by tools/build_npcs.py. See DATA-CREDITS.md for sources and licenses.
-- QuestieDB Forever spawn data (GPL-3.0).
-- Data from Efficient Games (https://efficient.games), licensed under CC BY 4.0.
-- English display names and map metadata also checked against EverlookDB.
-- World of Warcraft names and game content belong to Blizzard Entertainment.
local _, addon = ...
addon.npcs = {
"""
    with args.output.open("w", encoding="utf-8", newline="\n") as out:
        out.write(header)
        for key, (name, zone_maps, labels) in sorted(catalog.items()):
            labels = labels | {map_names[map_id] for map_id in zone_maps if map_id in map_names}
            out.write(lua_array([name, key, *sorted(labels), *sorted(zone_maps)]))
        out.write("}\n")

    print(f"{len(names_by_id):,} NPC IDs across {len(catalog):,} distinct names")
    print(f"{sum(bool(zones or labels) for _, zones, labels in catalog.values()):,} names with zone data")
    print(f"{sum(2548 in zones for _, zones, _ in catalog.values()):,} Riverglades names")
    print(f"{len(placed & names_by_id.keys()):,} QuestieDB placements, {len(seen & names_by_id.keys()):,} "
          f"EG Link observed IDs, {len(placed & seen & names_by_id.keys()):,} present in both")
    print(f"{missing_names:,} spawn IDs without usable names, {script_markers:,} script marker IDs excluded")

    def compare(label, names):
        matched = Counter(
            names_by_id[npc_id].casefold() == names[npc_id].strip().casefold()
            for npc_id in names_by_id.keys() & names.keys()
        )
        print(f"{label}: {matched[True]:,} names agree, {matched[False]:,} differ "
              f"on {sum(matched.values()):,} shared IDs")

    compare("QuestieDB", questie_names)
    compare("EverlookDB", everlook)
    if args.cache:
        cached = creature_cache(args.cache)
        compare("Local client cache", cached)
        print(f"Ghostmaw in local cache: {cached.get(263380, 'not present')}")


if __name__ == "__main__":
    main()
