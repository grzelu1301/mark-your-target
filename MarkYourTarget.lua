-- SPDX-License-Identifier: GPL-3.0-only
local _, addon = ...
local macroName = "Mark Your Target"
local minimapIcon = "Interface\\AddOns\\MarkYourTarget\\MarkYourTargetIcon.tga"
local quickButtonName = "MarkYourTargetQuickButton"
local quickBinding = "CLICK " .. quickButtonName .. ":LeftButton"
local cycleButtonName = "MarkYourTargetCycleButton"
local cycleBinding = "CLICK " .. cycleButtonName .. ":LeftButton"
local huntersMarkSpellID = 1130
local huntersMarkIcon = 132212 -- Interface\Icons\Ability_Hunter_SniperShot
local macroStart = "/cleartarget\n/tar "
local macroEnd = "\n/cleartarget [dead]\n/tm [exists,nodead] !8\n/ping [@target,exists,nodead] Ping"
local maxMacroBytes = 255
local maxNameBytes = maxMacroBytes - #macroStart - #macroEnd
local listTargetCommand = "/targetexact [noexists][dead] "
local maxListTargets = math.min(8, math.floor((maxMacroBytes - #"/cleartarget" - #macroEnd) / (#listTargetCommand + 2)))
local rowCount, rowHeight = 10, 21
local lower = strlower or string.lower
local pingCVar = "enablePings"
local pingReminder = "! Pings are off. To see them, check Enable Pings in Options > Ping System."
local warningHeight = 34
local bindingPanelHeight = 286
local headerCenterY = -26
local panelInset = 20
local bindingPanel, quickPanel, quickButton, quickTargetName

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function pingsDisabled()
    return C_CVar.GetCVar(pingCVar) == "0"
end

local function currentTargetName()
    if InCombatLockdown() then
        return nil, "Leave combat to change the target."
    elseif not UnitExists("target") then
        return nil, "Select a target first, then try again."
    end

    -- On Forever, UnitName's second value is the character's surname.
    local name, surname = UnitName("target")
    if (issecretvalue and (issecretvalue(name) or issecretvalue(surname)))
        or not name or name == "" or name == UNKNOWNOBJECT then
        return nil, "WoW could not read this target's name. Type the name instead."
    end
    if surname and surname ~= "" then
        return name .. " " .. surname
    end
    return name
end

local function resolveTarget(raw)
    if lower(trim(raw)) == "[@target]" then
        return currentTargetName()
    end
    return raw
end

local function findMacro()
    local accountCount, characterCount = GetNumMacros()
    local accountMax = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    for i = accountMax + 1, accountMax + characterCount do
        local name, icon, body = GetMacroInfo(i)
        if name == macroName then
            return i, body, icon
        end
    end
    for i = 1, accountCount do
        local name, icon, body = GetMacroInfo(i)
        if name == macroName then
            return i, body, icon
        end
    end
end

local function showSavedMacro(index)
    ShowMacroFrame()
    if not MacroFrame or not MacroFrame:IsShown() then
        return false
    end

    local accountMax = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local characterMacro = index > accountMax
    MacroFrame:ChangeTab(characterMacro and 2 or 1)
    MacroFrame:SelectMacro(characterMacro and index - accountMax or index, true)
    return true
end

local function validateName(raw, allowQuotes)
    local target = trim(raw)
    if raw:find("[%c%[%];|]") then
        return nil, "Enter a plain target name without macro syntax."
    end
    if allowQuotes then
        local _, unquoted = target:match([[^(["'])(.-)%1$]])
        target = trim(unquoted or target)
    end
    if target == "" then
        return nil, "Enter a target name first."
    elseif #target > maxNameBytes then
        return nil, "That name is too long to fit in the macro."
    end
    return target
end

local function buildMacro(raw, allowQuotes)
    local name, errorMessage = validateName(raw, allowQuotes)
    if not name then
        return nil, errorMessage
    end
    return macroStart .. name .. macroEnd, nil, name
end

local function buildListMacro(names)
    if #names == 1 then
        return buildMacro(names[1])
    end

    local lines = { "/cleartarget" }
    for _, name in ipairs(names) do
        lines[#lines + 1] = listTargetCommand .. name
    end
    local body = table.concat(lines, "\n") .. macroEnd
    if #body > maxMacroBytes then
        return nil, "That name would exceed WoW's 255-byte macro limit."
    end
    return body
end

local function readTargetList(body)
    local names, seen = {}, {}
    for line in (body or ""):gmatch("[^\n]+") do
        if line:sub(1, #listTargetCommand) == listTargetCommand then
            local name = line:sub(#listTargetCommand + 1)
            local key = lower(name)
            if validateName(name) ~= name or seen[key] or #names >= maxListTargets then
                return {}
            end
            seen[key] = true
            names[#names + 1] = name
        end
    end
    if #names < 2 or buildListMacro(names) ~= body then
        return {}
    end
    return names
end

local cycleButton = CreateFrame("Button", cycleButtonName, UIParent, "SecureActionButtonTemplate")
cycleButton:RegisterForClicks("LeftButtonUp")
cycleButton:SetAttribute("useOnKeyDown", false)
cycleButton:SetAttribute("type1", "macro")
SecureHandlerWrapScript(cycleButton, "OnClick", cycleButton, [[
    local count = self:GetAttribute("targetCount") or 0
    if count == 0 then return end
    local index = self:GetAttribute("nextTarget") or 1
    self:SetAttribute("macrotext1", self:GetAttribute("targetMacro" .. index))
    self:SetAttribute("nextTarget", index % count + 1)
]])

local cycleSource
local function updateCycle()
    if InCombatLockdown() then
        return
    end
    local _, body = findMacro()
    if cycleSource == body then
        return
    end
    local names = readTargetList(body)
    local oldCount = cycleButton:GetAttribute("targetCount") or 0
    for i = 1, math.max(oldCount, #names) do
        local name = names[i]
        local commands = name and ("/cleartarget\n/targetexact " .. name
            .. macroEnd:gsub("!8", "!" .. (9 - i), 1))
        cycleButton:SetAttribute("targetMacro" .. i, commands)
    end
    cycleButton:SetAttribute("macrotext1", nil)
    cycleButton:SetAttribute("nextTarget", 1)
    cycleButton:SetAttribute("targetCount", #names)
    cycleSource = body
end

local cycleEvents = CreateFrame("Frame")
cycleEvents:RegisterEvent("PLAYER_LOGIN")
cycleEvents:RegisterEvent("UPDATE_MACROS")
cycleEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
cycleEvents:SetScript("OnEvent", updateCycle)

local function saveMacroBody(body)
    if InCombatLockdown() then
        return nil, "Leave combat to save the macro."
    end

    if MacroFrame and MacroFrame:IsShown() then
        MacroFrame:SaveMacro()
    end
    local index, oldBody, oldIcon = findMacro()
    local icon = C_Spell.GetSpellTexture(huntersMarkSpellID) or huntersMarkIcon
    if index then
        if oldBody ~= body or oldIcon ~= icon then
            pcall(EditMacro, index, nil, icon, body)
        end
    else
        local accountCount = GetNumMacros()
        if accountCount >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            return nil, "Free a slot in General Macros, then try again."
        end
        pcall(CreateMacro, macroName, icon, body, false)
    end

    local savedIndex, savedBody, savedIcon = findMacro()
    if savedBody == body and savedIcon == icon then
        updateCycle()
        return savedIndex, nil, not index
    end
    return nil, "WoW could not save the macro. Open /macro to check it."
end

local function saveTarget(raw)
    local body, errorMessage = buildMacro(raw)
    if not body then
        return nil, errorMessage
    end
    return saveMacroBody(body)
end

local function currentZone()
    local zoneNames, mapIDs = {}, {}
    local function addName(name)
        if name and name ~= "" then
            zoneNames[lower(name)] = true
        end
    end
    addName(GetRealZoneText())
    addName(GetZoneText())
    addName(GetSubZoneText())

    local mapID = C_Map.GetBestMapForUnit("player")
    while mapID and mapID > 0 and not mapIDs[mapID] do
        local info = C_Map.GetMapInfo(mapID)
        if not info or info.mapType < Enum.UIMapType.Zone then
            break
        end
        mapIDs[mapID] = true
        addName(info.name)
        mapID = info.parentMapID
    end
    return zoneNames, mapIDs
end

local function isInZone(npc, zoneNames, mapIDs)
    for i = 3, #npc do
        if zoneNames[npc[i]] or mapIDs[npc[i]] then
            return true
        end
    end
    return false
end

local function findMatches(query, excluded, zoneNames, mapIDs)
    local exact = {}
    local nearby, other = {{}, {}, {}}, {{}, {}, {}}
    local localCount = 0
    local wordPattern = "%f[%w]" .. query:gsub("(%W)", "%%%1")
    for _, npc in ipairs(addon.npcs) do
        local name = npc[2]
        local start = name:find(query, 1, true)
        if start and not excluded[name] then
            local localMatch = zoneNames and isInZone(npc, zoneNames, mapIDs)
            if localMatch then
                localCount = localCount + 1
            end
            if name == query then
                exact[#exact + 1] = npc[1]
            else
                local ranks = localMatch and nearby or other
                local rank = start == 1 and 1 or (name:find(wordPattern) and 2 or 3)
                local bucket = ranks[rank]
                bucket[#bucket + 1] = npc[1]
            end
        end
    end
    for _, ranks in ipairs({nearby, other}) do
        for _, bucket in ipairs(ranks) do
            for _, name in ipairs(bucket) do
                exact[#exact + 1] = name
            end
        end
    end
    return exact, localCount
end

local modifierKeys = {
    LALT = true, RALT = true, LCTRL = true, RCTRL = true,
    LSHIFT = true, RSHIFT = true, LMETA = true, RMETA = true,
}

local function createBindingPanel(parent, picker, resizePicker)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetAllPoints(parent)
    panel:SetFrameLevel(parent:GetFrameLevel() + 8)
    panel:SetBackdrop(parent:GetBackdrop())
    panel:SetBackdropColor(0.055, 0.06, 0.075, 1)
    panel:SetBackdropBorderColor(0.55, 0.45, 0.29, 1)
    panel:EnableMouse(true)
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", panel, "TOPLEFT", panelInset, headerCenterY)
    title:SetText("Keybindings")
    local back = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    back:SetPoint("RIGHT", panel, "TOPRIGHT", -panelInset, headerCenterY)
    back:SetSize(68, 26)
    back:SetText("Back")
    back:SetScript("OnClick", function() panel:Hide() end)

    local macroHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    macroHint:SetPoint("TOPLEFT", 20, -229)
    macroHint:SetText("Action-bar macro: marks the first living match on the list.")

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 20, -250)
    status:SetPoint("TOPRIGHT", -20, -250)
    status:SetJustifyH("LEFT")

    local divider = panel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 20, -137)
    divider:SetPoint("TOPRIGHT", -20, -137)
    divider:SetHeight(1)
    divider:SetColorTexture(0.55, 0.45, 0.29, 0.4)

    local rows = {}
    local listening
    local function updateRows()
        for _, row in ipairs(rows) do
            local key = GetBindingKey(row.action)
            row.button:SetText(listening == row and "Press a key" or (key and GetBindingText(key) or "Unbound"))
            row.clear:SetEnabled(key ~= nil)
        end
    end

    function panel:RefreshReadiness()
        local armed = quickPanel and quickPanel:IsShown()
        rows[1].readiness:SetText(armed and ("Prepared: " .. quickTargetName:GetText()) or "No quick target prepared.")
        local count = cycleButton:GetAttribute("targetCount") or 0
        rows[2].readiness:SetText(count >= 2 and ("Saved targets: " .. count) or "No list of two or more targets saved.")
    end

    local function stopListening()
        listening = nil
        panel:SetScript("OnKeyDown", nil)
        panel:EnableKeyboard(false)
        updateRows()
    end

    local function setKey(row, key)
        if InCombatLockdown() then
            status:SetText("Leave combat to change a keybind.")
            return
        end

        local oldKey = GetBindingKey(row.action)
        if key == oldKey then
            return
        end
        if key then
            local taken = GetBindingAction(key)
            if taken == row.action then
                status:SetText("That key is already assigned to this action.")
                return
            elseif taken and taken ~= "" then
                local actionName = _G["BINDING_NAME_" .. taken] or taken
                status:SetFormattedText("%s is already bound to %s.", GetBindingText(key) or key, actionName)
                return
            end
            if not SetBinding(key, row.action) then
                status:SetText("WoW could not assign that key.")
                return
            end
        end
        if oldKey and not SetBinding(oldKey) then
            if key then
                SetBinding(key)
            end
            status:SetText("WoW could not replace the existing key.")
            return
        end
        SaveBindings(GetCurrentBindingSet())
        updateRows()
        status:SetText(key and "Keybind saved." or "Keybind cleared.")
    end

    local function onKeyDown(_, key)
        if modifierKeys[key] or key == "UNKNOWN" then
            return
        end
        local row = listening
        stopListening()
        status:SetText("")
        if key ~= "ESCAPE" then
            local modifiers = (IsAltKeyDown() and "ALT-" or "")
                .. (IsControlKeyDown() and "CTRL-" or "")
                .. (IsShiftKeyDown() and "SHIFT-" or "")
            setKey(row, modifiers .. key)
        end
    end

    local actions = {
        { quickBinding, "Skull-marks and pings one target.", "Type /mytgt Ghostmaw, then press the key." },
        { cycleBinding, "Tries the next name and uses a different marker for each.", "In /myt, add at least two names and click Save list." },
    }
    for i, action in ipairs(actions) do
        local row = { action = action[1] }
        local y = -60 - (i - 1) * 96
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetText(_G["BINDING_NAME_" .. row.action])
        local function detail(offset, font)
            local text = panel:CreateFontString(nil, "ARTWORK", font)
            text:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - offset)
            text:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -20, y - offset)
            text:SetJustifyH("LEFT")
            return text
        end
        detail(17, "GameFontHighlightSmall"):SetText(action[2])
        detail(32, "GameFontHighlightSmall"):SetText(action[3])
        row.readiness = detail(49, "GameFontNormalSmall")
        row.readiness:SetWordWrap(false)
        row.clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        row.clear:SetPoint("RIGHT", panel, "TOPRIGHT", -panelInset, y)
        row.clear:SetSize(58, 24)
        row.clear:SetText("Clear")
        row.button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        row.button:SetPoint("RIGHT", row.clear, "LEFT", -6, 0)
        row.button:SetSize(132, 24)
        label:SetPoint("LEFT", panel, "TOPLEFT", panelInset, y)
        label:SetPoint("RIGHT", row.button, "LEFT", -8, 0)
        label:SetJustifyH("LEFT")
        row.button:SetScript("OnClick", function()
            if listening == row then
                stopListening()
                status:SetText("")
            elseif InCombatLockdown() then
                status:SetText("Leave combat to change a keybind.")
            else
                listening = row
                panel:SetScript("OnKeyDown", onKeyDown)
                panel:EnableKeyboard(true)
                panel:SetPropagateKeyboardInput(false)
                status:SetText("Press a key or key combination. Esc cancels.")
                updateRows()
            end
        end)
        row.clear:SetScript("OnClick", function()
            stopListening()
            setKey(row)
        end)
        rows[i] = row
    end

    panel:SetScript("OnShow", function()
        picker:Hide()
        resizePicker()
        status:SetText("Click a key field to change its binding.")
        updateRows()
        panel:RefreshReadiness()
    end)
    panel:SetScript("OnHide", function()
        stopListening()
        picker:Show()
        resizePicker()
    end)
    panel:RegisterEvent("UPDATE_BINDINGS")
    panel:RegisterEvent("UPDATE_MACROS")
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and listening then
            stopListening()
            status:SetText("Leave combat to change a keybind.")
        elseif panel:IsVisible() then
            updateRows()
            if event == "UPDATE_MACROS" or event == "PLAYER_REGEN_ENABLED" then
                updateCycle()
                panel:RefreshReadiness()
            end
        end
    end)
    return panel
end

local function createWindow()
    local frame = CreateFrame("Frame", "MarkYourTargetWindow", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER")
    frame:SetWidth(396)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 15,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.055, 0.06, 0.075, 0.97)
    frame:SetBackdropBorderColor(0.55, 0.45, 0.29, 1)
    frame:Hide()
    tinsert(UISpecialFrames, frame:GetName())

    local picker = CreateFrame("Frame", nil, frame)
    picker:SetAllPoints(frame)

    local title = picker:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("LEFT", picker, "TOPLEFT", panelInset, headerCenterY)
    title:SetText(macroName)
    local close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", picker, "TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local keys = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    keys:SetPoint("RIGHT", picker, "TOPRIGHT", -42, headerCenterY)
    keys:SetSize(100, 24)
    keys:SetText("Keybindings")

    local label = picker:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 20, -53)
    label:SetText("Name of the target")
    local input = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 25, -72)
    input:SetPoint("RIGHT", frame, "RIGHT", -106, 0)
    input:SetHeight(26)
    input:SetAutoFocus(false)
    input:SetMaxBytes(maxNameBytes)
    local save = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    save:SetSize(77, 26)
    save:SetText("Save")

    local allZones = CreateFrame("CheckButton", nil, picker, "UICheckButtonTemplate")
    allZones:SetSize(24, 24)
    allZones:SetPoint("TOPLEFT", 16, -104)
    allZones:SetHitRectInsets(0, -50, 0, 0)
    local allZonesText = allZones:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    allZonesText:SetPoint("LEFT", allZones, "RIGHT", 3, 0)
    allZonesText:SetText("All zones")

    local add = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    add:SetSize(105, 23)
    add:SetText("Add to list")

    local targetList = CreateFrame("Frame", nil, picker)
    local listTitle = targetList:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    listTitle:SetPoint("TOPLEFT")
    listTitle:SetText("Target list (first living match wins)")
    local cycleHint = targetList:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    cycleHint:SetPoint("TOPLEFT", 0, -18)
    cycleHint:SetText("Set Cycle Targets under Keybindings.")

    local summary = picker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 20, -135)
    local list = CreateFrame("Frame", nil, picker)
    list:SetPoint("TOPLEFT", 18, -154)
    list:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    list:EnableMouseWheel(true)

    local more = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    more:SetSize(126, 23)
    more:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -5)

    local status = picker:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 20, 13)
    status:SetPoint("BOTTOMRIGHT", -20, 13)
    status:SetHeight(29)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("MIDDLE")

    local warning = picker:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    warning:SetPoint("BOTTOMLEFT", 20, 13)
    warning:SetPoint("BOTTOMRIGHT", -20, 13)
    warning:SetHeight(warningHeight)
    warning:SetJustifyH("LEFT")
    warning:SetJustifyV("MIDDLE")
    warning:SetText(pingReminder)
    warning:Hide()

    local slider = CreateFrame("Slider", nil, list)
    slider:SetWidth(14)
    slider:SetPoint("TOPRIGHT", -2, -3)
    slider:SetPoint("BOTTOMRIGHT", -2, 3)
    slider:SetOrientation("VERTICAL")
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", 0, -4)
    track:SetPoint("BOTTOM", 0, 4)
    track:SetWidth(3)
    track:SetColorTexture(0.35, 0.30, 0.22, 0.8)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 18)
    thumb:SetColorTexture(0.75, 0.64, 0.42, 1)
    slider:SetThumbTexture(thumb)

    local results, rows, names, targetRows = {}, {}, {}, {}
    local expanded = false
    local targetListHeight = 0
    local function alignInputAction(control)
        control:SetPoint("RIGHT", picker, "TOPRIGHT", -panelInset, -85)
    end
    local function layoutFooter()
        local editingList = #names > 0
        local bottom = 13 + (warning:IsShown() and warningHeight or 0)
        label:SetText(editingList and "Find another target" or "Name of the target")
        add:ClearAllPoints()
        save:ClearAllPoints()
        if editingList then
            add:SetSize(77, 26)
            alignInputAction(add)
            add:SetText("Add")
            save:SetWidth(102)
            save:SetPoint("BOTTOMRIGHT", -panelInset, bottom)
            save:SetText("Save list")
        else
            add:SetSize(105, 23)
            add:SetPoint("RIGHT", picker, "TOPRIGHT", -panelInset, -116)
            add:SetText("Add to list")
            save:SetWidth(77)
            alignInputAction(save)
            save:SetText("Save")
        end
        status:ClearAllPoints()
        status:SetPoint("BOTTOMLEFT", 20, bottom)
        status:SetPoint("BOTTOMRIGHT", editingList and -130 or -20, bottom)
    end

    local function resizeWindow()
        if bindingPanel and bindingPanel:IsShown() then
            frame:SetHeight(bindingPanelHeight)
            return
        end
        local height = math.min(#results, rowCount) * rowHeight
        local extra = warning:IsShown() and warningHeight or 0
        frame:SetHeight(198 + targetListHeight + height + (#results > rowCount and 28 or 0) + extra)
    end
    keys:SetScript("OnClick", function()
        input:ClearFocus()
        bindingPanel = bindingPanel or createBindingPanel(frame, picker, resizeWindow)
        bindingPanel:Show()
    end)

    local function renderTargetList()
        targetListHeight = #names > 0 and (41 + #names * rowHeight) or 0
        targetList:SetShown(#names > 0)
        targetList:SetHeight(math.max(1, targetListHeight))
        for i, row in ipairs(targetRows) do
            local name = names[i]
            row:SetShown(name ~= nil)
            row.text:SetFormattedText("%d. %s", i, name or "")
        end
        layoutFooter()
        resizeWindow()
    end

    local function updatePingWarning()
        warning:SetShown(pingsDisabled())
        layoutFooter()
    end

    local function renderRows()
        local offset = expanded and math.floor(slider:GetValue() + 0.5) or 0
        for i, row in ipairs(rows) do
            local name = results[offset + i]
            row.name = name
            row:SetShown(name ~= nil)
            row.text:SetText(name or "")
        end
    end

    local function renderList()
        local count = #results
        local canExpand = count > rowCount
        local scrollable = expanded and canExpand
        local height = math.min(count, rowCount) * rowHeight
        list:SetHeight(math.max(height, 1))
        more:SetShown(canExpand)
        more:SetText(expanded and "Show less" or "Show more")
        local listGap = canExpand and -36 or -8
        targetList:ClearAllPoints()
        targetList:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, listGap)
        targetList:SetPoint("RIGHT", picker, "RIGHT", -panelInset, 0)
        slider:SetShown(scrollable)
        slider:SetMinMaxValues(0, math.max(0, count - rowCount))
        slider:SetValue(0)
        resizeWindow()
        renderRows()
    end

    local function refresh()
        local query = lower(trim(input:GetText()))
        expanded = false
        if query == "" then
            results = {}
            add:Disable()
            summary:SetText(#names > 0 and "Type another name to search." or "Type a name to see suggestions.")
        else
            local excluded = {}
            for _, name in ipairs(names) do
                excluded[lower(name)] = true
            end
            if excluded[query] then
                add:Disable()
            else
                add:Enable()
            end
            local localCount
            if allZones:GetChecked() then
                results, localCount = findMatches(query, excluded)
            else
                results, localCount = findMatches(query, excluded, currentZone())
            end
            if #results == 0 then
                if excluded[query] then
                    summary:SetText("Already in the list.")
                else
                    summary:SetText(#names > 0 and "No suggestions. You can still add the name."
                        or "No suggestions. You can still save the name.")
                end
            elseif allZones:GetChecked() then
                summary:SetFormattedText("%d across all zones", #results)
            elseif localCount == #results then
                summary:SetFormattedText("%d in this zone", localCount)
            elseif localCount > 0 then
                summary:SetFormattedText("%d in this zone, %d other matches", localCount, #results - localCount)
            else
                summary:SetFormattedText("No local matches. Showing %d across all zones.", #results)
            end
        end
        renderList()
    end

    local function scroll(_, delta)
        if slider:IsShown() then
            local first, last = slider:GetMinMaxValues()
            slider:SetValue(math.max(first, math.min(last, slider:GetValue() - delta * 3)))
        end
    end

    for i = 1, maxListTargets do
        local row = CreateFrame("Frame", nil, targetList)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -35 - (i - 1) * rowHeight)
        row:SetPoint("RIGHT", targetList, "RIGHT", 0, 0)
        local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        remove:SetPoint("RIGHT")
        remove:SetSize(64, 20)
        remove:SetText("Remove")
        local index = i
        remove:SetScript("OnClick", function()
            table.remove(names, index)
            status:SetText("")
            renderTargetList()
            refresh()
        end)
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT")
        row.text:SetPoint("RIGHT", remove, "LEFT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        targetRows[i] = row
    end

    local function addTarget(text)
        local raw, errorMessage = resolveTarget(text)
        local name
        if raw then
            name, errorMessage = validateName(raw)
        end
        if not name then
            status:SetText(errorMessage)
            return
        end
        for _, existing in ipairs(names) do
            if lower(existing) == lower(name) then
                status:SetText("That target is already in the list.")
                return
            end
        end
        if #names >= maxListTargets then
            status:SetText("The list has reached WoW's macro size limit.")
            return
        end
        names[#names + 1] = name
        local body, buildError = buildListMacro(names)
        if not body then
            names[#names] = nil
            status:SetText(buildError)
            return
        end
        input:SetText("")
        renderTargetList()
        input:SetFocus()
    end

    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, list)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
        row:SetPoint("RIGHT", list, "RIGHT", -18, 0)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        row.text:SetPoint("LEFT", 3, 0)
        row.text:SetPoint("RIGHT", -3, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            if #names > 0 then
                addTarget(self.name)
            else
                input:SetText(self.name)
                input:SetCursorPosition(#input:GetText())
                input:SetFocus()
            end
        end)
        row:SetScript("OnMouseWheel", scroll)
        rows[i] = row
    end

    local function saveMacro()
        local index, errorMessage
        if #names == 0 then
            index, errorMessage = saveTarget(input:GetText())
        else
            local body
            body, errorMessage = buildListMacro(names)
            if body then
                index, errorMessage = saveMacroBody(body)
            end
        end
        if not index then
            status:SetText(errorMessage)
            return
        end
        input:ClearFocus()
        if showSavedMacro(index) then
            frame:Hide()
        else
            status:SetText("Macro saved. Use /macro to put it on an action bar.")
        end
    end

    input:SetScript("OnTextChanged", function()
        status:SetText("")
        refresh()
    end)
    input:SetScript("OnEnterPressed", function()
        if #names > 0 and trim(input:GetText()) ~= "" then
            addTarget(input:GetText())
        else
            saveMacro()
        end
    end)
    input:SetScript("OnEscapePressed", function() frame:Hide() end)
    add:SetScript("OnClick", function() addTarget(input:GetText()) end)
    save:SetScript("OnClick", saveMacro)
    allZones:SetScript("OnClick", refresh)
    slider:SetScript("OnValueChanged", renderRows)
    list:SetScript("OnMouseWheel", scroll)
    more:SetScript("OnClick", function()
        expanded = not expanded
        renderList()
    end)
    frame:SetScript("OnShow", function()
        local _, body = findMacro()
        names = readTargetList(body)
        updatePingWarning()
        input:SetText(body and body:match("^/cleartarget\n/tar ([^\n]+)") or "")
        status:SetText("")
        renderTargetList()
        refresh()
        input:SetFocus()
        input:HighlightText()
    end)
    frame:SetScript("OnHide", function()
        input:ClearFocus()
        if bindingPanel then
            bindingPanel:Hide()
        end
    end)
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("ZONE_CHANGED")
    frame:RegisterEvent("CVAR_UPDATE")
    frame:SetScript("OnEvent", function(self, event, name)
        if not self:IsShown() then
            return
        end
        if event == "CVAR_UPDATE" then
            if name and lower(name) == lower(pingCVar) then
                updatePingWarning()
                resizeWindow()
            end
        elseif not allZones:GetChecked() then
            refresh()
        end
    end)
    return frame
end

local window
local function toggleWindow()
    window = window or createWindow()
    window:SetShown(not window:IsShown())
end

local function refreshQuickTargetReadiness()
    if bindingPanel and bindingPanel:IsVisible() then
        bindingPanel:RefreshReadiness()
    end
end

local function createQuickPanel()
    local panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    panel:SetSize(320, 79)
    panel:SetPoint("TOP", UIParent, "TOP", 0, -140)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.055, 0.06, 0.075, 0.97)
    panel:SetBackdropBorderColor(0.55, 0.45, 0.29, 1)
    panel:Hide()

    local name = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    name:SetPoint("TOPLEFT", 32, -12)
    name:SetPoint("TOPRIGHT", -32, -12)
    name:SetWordWrap(false)
    name:SetJustifyH("CENTER")

    local button = CreateFrame("Button", quickButtonName, panel, "UIPanelButtonTemplate,SecureActionButtonTemplate")
    button:SetSize(140, 24)
    button:SetPoint("BOTTOM", 0, 10)
    button:SetText("Quick Target")
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:SetAttribute("type1", "macro")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function()
        if InCombatLockdown() then
            print(macroName .. ": Leave combat to close Quick Target.")
            return
        end
        button:SetAttribute("macrotext1", nil)
        panel:Hide()
        refreshQuickTargetReadiness()
    end)
    return panel, button, name
end

SLASH_MARKYOURTARGET1 = "/myt"
SlashCmdList.MARKYOURTARGET = function(raw)
    local target = trim(raw or "")
    if target == "" then
        toggleWindow()
        return
    end

    if pingsDisabled() then
        print(macroName .. ": " .. pingReminder)
    end
    local resolved, resolveError = resolveTarget(raw)
    if not resolved then
        print(macroName .. ": " .. resolveError)
        return
    end

    local index, errorMessage, created = saveTarget(resolved)
    if not index then
        print(macroName .. ": " .. errorMessage)
        return
    end
    if window and window:IsShown() then
        window:Hide()
    end
    local message = macroName .. ": Macro saved for " .. trim(resolved) .. "."
    if created then
        message = message .. " Use /macro to put it on an action bar."
    end
    print(message)
end

_G["BINDING_NAME_" .. quickBinding] = "Quick Target"
_G["BINDING_NAME_" .. cycleBinding] = "Cycle Targets"
SLASH_MARKYOURTARGETQUICK1 = "/mytgt"
SlashCmdList.MARKYOURTARGETQUICK = function(raw)
    if trim(raw or "") == "" then
        print(macroName .. ": Use /mytgt <name> or /mytgt [@target].")
        return
    end
    local resolved, resolveError = resolveTarget(raw)
    if not resolved then
        print(macroName .. ": " .. resolveError)
        return
    end
    local body, errorMessage, target = buildMacro(resolved, true)
    if not body then
        print(macroName .. ": " .. errorMessage)
        return
    end
    if InCombatLockdown() then
        print(macroName .. ": Leave combat to set a new Quick Target.")
        return
    end
    if not quickPanel then
        quickPanel, quickButton, quickTargetName = createQuickPanel()
    end
    quickButton:SetAttribute("macrotext1", body)
    quickTargetName:SetText(target)
    quickPanel:Show()
    refreshQuickTargetReadiness()

    if pingsDisabled() then
        print(macroName .. ": " .. pingReminder)
    end
    local key = GetBindingKey(quickBinding)
    local action = key and ("Press " .. key .. " or click Quick Target.") or "Click Quick Target."
    print(macroName .. ": " .. target .. " is ready. " .. action)
end

-- A named Minimap child is picked up by MinimapButtonButton's normal scan.
local button = CreateFrame("Button", "MarkYourTargetMinimapButton", Minimap)
button:SetSize(31, 31)
local function placeMinimapButton()
    if button:GetParent() ~= Minimap then
        return
    end
    local x, y = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    -- Place the icon at the lower-left edge of the round Classic minimap.
    if not GetMinimapShape or GetMinimapShape() ~= "SQUARE" then
        local diagonal = math.sqrt(0.5)
        x, y = x * diagonal, y * diagonal
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", -x, -y)
end
placeMinimapButton()
Minimap:HookScript("OnSizeChanged", placeMinimapButton)
Minimap:HookScript("OnShow", placeMinimapButton)
button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetSize(20, 20)
background:SetPoint("TOPLEFT", 7, -5)
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture(minimapIcon)
icon:SetSize(19, 19)
icon:SetPoint("TOPLEFT", 7, -6)
-- Blizzard's tracking border has padding and sits at the button's top-left.
local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")
button:SetScript("OnClick", toggleWindow)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(macroName)
    GameTooltip:AddLine("Click to open the macro editor.", 1, 1, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)
