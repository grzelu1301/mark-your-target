-- Run with Lua 5.1 after QuestieDB's tools/export-forever.lua --include-authored.
local source = assert(arg[1], "Expected the QuestieDB checkout path")
local zones = {private = {}}
QuestieLoader = {ImportModule = function() return zones end}

local zonePath = source .. "/support/Forever/Zones/"
dofile(zonePath .. "areaIdToUiMapId.lua")
dofile(zonePath .. "subZoneToParentZone.lua")
local function readMap(key)
    local values = assert(loadstring(zones.private[key]))()
    local overrides = assert(loadstring(zones.private[key .. "Override"]))()
    for id, value in pairs(overrides) do
        values[id] = value
    end
    return values
end
local areaToMap = readMap("areaIdToUiMapId")
local parents = readMap("subZoneToParentZone")

local function addAreaMaps(maps, area)
    local seen = {}
    while area and area > 0 and not seen[area] do
        seen[area] = true
        local map = areaToMap[area]
        if map and map > 0 then
            maps[map] = true
        end
        area = parents[area]
    end
end

local function hasPoint(points)
    for _, point in ipairs(points) do
        local x, y = point[1], point[2]
        if type(x) == "number" and type(y) == "number"
            and ((x >= 0 and x <= 100 and y >= 0 and y <= 100 and (x > 0 or y > 0))
                or (x == -1 and y == -1)) then
            -- Questie uses {-1,-1} to place a spawn on a dungeon's entrance map.
            return true
        end
    end
    return false
end

local npcs = dofile(source .. "/src/corrections/Forever/combined/foreverNpcDB.lua")
local ids = {}
for id in pairs(npcs) do ids[#ids + 1] = id end
table.sort(ids)
io.write("id\tname\tspawn\tmaps\n")
for _, id in ipairs(ids) do
    local npc = npcs[id]
    if type(npc[1]) == "string" and not npc[1]:find("%c") then
        local placed, mapSet = false, {}
        for _, field in ipairs({7, 8}) do -- spawns and patrol waypoints
            for area, points in pairs(npc[field] or {}) do
                if area > 0 and hasPoint(points) then
                    placed = true
                    addAreaMaps(mapSet, area)
                end
            end
        end
        local maps = {}
        for map in pairs(mapSet) do maps[#maps + 1] = map end
        table.sort(maps)
        io.write(id, "\t", npc[1], "\t", placed and "1" or "0", "\t", table.concat(maps, ","), "\n")
    end
end
