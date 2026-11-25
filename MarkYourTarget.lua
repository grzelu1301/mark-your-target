-- SPDX-License-Identifier: GPL-3.0-only
local _, addon = ...
local macroName = "Mark Your Target"
local minimapIcon = "Interface\\AddOns\\MarkYourTarget\\MarkYourTargetIcon.tga"
local quickButtonName = "MarkYourTargetQuickButton"
local quickBinding = "CLICK " .. quickButtonName .. ":LeftButton"
local huntersMarkSpellID = 1130
local huntersMarkIcon = 132212 -- Interface\Icons\Ability_Hunter_SniperShot
local macroStart = "/cleartarget\n/tar "
local macroEnd = "\n/cleartarget [dead]\n/tm [exists,nodead] !8\n/ping [@target,exists,nodead] Ping"
local maxNameBytes = 255 - #macroStart - #macroEnd
local rowCount, rowHeight = 10, 21
local lower = strlower or string.lower
local pingCVar = "enablePings"
local pingReminder = "! Pings are off. To see them, check Enable Pings in Options > Ping System."
local warningHeight = 34

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

local function buildMacro(raw, allowQuotes)
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
    return macroStart .. target .. macroEnd, nil, target
end

local function saveTarget(raw)
    local body, errorMessage = buildMacro(raw)
    if not body then
        return nil, errorMessage
    end
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
        return savedIndex, nil, not index
    end
    return nil, "WoW could not save the macro. Open /macro to check it."
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

local function findMatches(query, zoneNames, mapIDs)
    local exact = {}
    local nearby, other = {{}, {}, {}}, {{}, {}, {}}
    local localCount = 0
    local wordPattern = "%f[%w]" .. query:gsub("(%W)", "%%%1")
    for _, npc in ipairs(addon.npcs) do
        local name = npc[2]
        local start = name:find(query, 1, true)
        if start then
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

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    title:SetText(macroName)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() frame:Hide() end)

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 20, -53)
    label:SetText("Name of the target")
    local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", 25, -72)
    input:SetPoint("RIGHT", frame, "RIGHT", -106, 0)
    input:SetHeight(26)
    input:SetAutoFocus(false)
    input:SetMaxBytes(maxNameBytes)

    local save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    save:SetSize(77, 26)
    save:SetPoint("LEFT", input, "RIGHT", 8, 0)
    save:SetText("Save")

    local allZones = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    allZones:SetSize(24, 24)
    allZones:SetPoint("TOPLEFT", 16, -104)
    allZones:SetHitRectInsets(0, -50, 0, 0)
    local allZonesText = allZones:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    allZonesText:SetPoint("LEFT", allZones, "RIGHT", 3, 0)
    allZonesText:SetText("All zones")

    local summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", 20, -135)
    local list = CreateFrame("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 18, -154)
    list:SetPoint("RIGHT", frame, "RIGHT", -18, 0)
    list:EnableMouseWheel(true)

    local more = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    more:SetSize(126, 23)
    more:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -5)

    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("BOTTOMLEFT", 20, 13)
    status:SetPoint("BOTTOMRIGHT", -20, 13)
    status:SetHeight(29)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("MIDDLE")

    local warning = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
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

    local results, rows = {}, {}
    local expanded = false
    local function resizeWindow()
        local height = math.min(#results, rowCount) * rowHeight
        local extra = warning:IsShown() and warningHeight or 0
        frame:SetHeight(198 + height + (#results > rowCount and 28 or 0) + extra)
    end

    local function updatePingWarning()
        local disabled = pingsDisabled()
        warning:SetShown(disabled)
        status:ClearAllPoints()
        local bottom = 13 + (disabled and warningHeight or 0)
        status:SetPoint("BOTTOMLEFT", 20, bottom)
        status:SetPoint("BOTTOMRIGHT", -20, bottom)
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
            summary:SetText("Type a name to see suggestions.")
        else
            local localCount
            if allZones:GetChecked() then
                results, localCount = findMatches(query)
            else
                results, localCount = findMatches(query, currentZone())
            end
            if #results == 0 then
                summary:SetText("No suggestions. You can still save the name.")
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
            input:SetText(self.name)
            input:SetCursorPosition(#input:GetText())
            input:SetFocus()
        end)
        row:SetScript("OnMouseWheel", scroll)
        rows[i] = row
    end

    local function saveMacro()
        local index, errorMessage = saveTarget(input:GetText())
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
    input:SetScript("OnEnterPressed", saveMacro)
    input:SetScript("OnEscapePressed", function() frame:Hide() end)
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
        updatePingWarning()
        input:SetText(body and body:match("^/cleartarget\n/tar ([^\n]+)") or "")
        status:SetText("")
        refresh()
        input:SetFocus()
        input:HighlightText()
    end)
    frame:SetScript("OnHide", function() input:ClearFocus() end)
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

local quickPanel, quickButton, quickTargetName
BINDING_HEADER_MARKYOURTARGET = macroName
_G["BINDING_NAME_" .. quickBinding] = "Quick Target"
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
