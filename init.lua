--[[
    Resurrected and Updated since 1/2024 By: Derple

    Original Version: Created by Special.Ed
    Shout out to the homies:
        Lads
        Dannuic (my on again off again thing)
        Knightly (no, i won't take that bet)
    Thanks to the testers:
        Shwebro, Kevbro, RYN
--]]

local mq                    = require('mq')

ButtonActors                = require 'actors'
Icons                       = require('mq.ICONS')

local picker                = require('lib.IconPicker').new()
local btnUtils              = require('lib.buttonUtils')

-- globals
local CharConfig            = string.format("%s_%s", mq.TLO.EverQuest.Server(), mq.TLO.Me.DisplayName())

-- [[ UI ]] --
local openGUI               = true
local shouldDrawGUI         = true
local importObjectPopupOpen = false
local editButtonPopupOpen   = false
local editButtonUseCursor   = false
local editButtonAdvanced    = false

-- Icon Rendering
local animItems             = mq.FindTextureAnimation("A_DragItem")
local animBox               = mq.FindTextureAnimation("A_RecessedBox")
local animSpellIcons        = mq.FindTextureAnimation('A_SpellIcons')
local animSpellGemIcons     = mq.FindTextureAnimation('A_SpellGems')
local animSpellGemHolder    = mq.FindTextureAnimation('A_SpellGemHolder')
local animSpellGemBG        = mq.FindTextureAnimation('A_SpellGemBackground')
local animSquareButton      = mq.FindTextureAnimation('A_SquareBtnNormal')

-- Constants
local ICON_WIDTH            = 40
local ICON_HEIGHT           = 40
local COUNT_X_OFFSET        = 39
local COUNT_Y_OFFSET        = 23
local EQ_ICON_OFFSET        = 500

-- [[ Global Objects ]] --
local initialRun            = false
local updateWindowPosSize   = false
local newWidth              = 0
local newHeight             = 0
local newX                  = 0
local newY                  = 0
local cachedRows            = 0
local cachedCols            = 0
local tmpButton             = {}
local lastWindowHeight      = 0
local lastWindowWidth       = 0
local lastWindowX           = 0
local lastWindowY           = 0
local visibleButtonCount    = 0
local editButtonSet         = ""
local editButtonIndex       = 0
local editButtonTextChanged = false
local buttonSizeDirty       = false
local editTabPopup          = "edit_tab_popup"
local name
local settings_path         = mq.configDir .. '/ButtonMaster.lua'
local settings              = {}
local importText            = ""
local decodedObject         = {}
local validDecode           = false
local importTextChanged     = false
local enableDebug           = false
local reloadSettings        = false

-- [[ Timer Types ]] --
local selectedTimerType     = 1
local TimerTypes            = {
    "Seconds Timer",
    "Item",
    "Spell Gem",
    "AA",
    "Ability",
    "Custom Lua",
}

-- helpers
local function Output(msg, ...)
    local formatted = msg
    if ... then
        formatted = string.format(msg, ...)
    end

    printf('\aw[' .. mq.TLO.Time() .. '] [\aoButton Master\aw] ::\a-t %s', formatted)
end

local function Debug(msg, ...)
    if not enableDebug then return end
    Output('\ay<\atDEBUG\ay>\aw ' .. msg, ...)
end

local function SaveSettings(doBroadcast)
    if doBroadcast == nil then doBroadcast = true end

    mq.pickle(settings_path, settings)

    if doBroadcast and mq.TLO.MacroQuest.GameState() == "INGAME" then
        Output("\aySent Event from(\am%s\ay) event(\at%s\ay)", mq.TLO.Me.DisplayName(), "SaveSettings")
        ButtonActors.send({ from = mq.TLO.Me.DisplayName(), script = "ButtonMaster", event = "SaveSettings", })
    end
end

-- binds
local function BindBtn()
    openGUI = not openGUI
end

-- UI
local function DisplayItemOnCursor()
    if mq.TLO.CursorAttachment.Type() then
        local draw_list = ImGui.GetForegroundDrawList()
        local window_x, window_y = ImGui.GetWindowPos()
        local window_w, window_h = ImGui.GetWindowSize()
        local mouse_x, mouse_y = ImGui.GetMousePos()

        if mouse_x < window_x or mouse_x > window_x + window_w then return end
        if mouse_y < window_y or mouse_y > window_y + window_h then return end

        local icon_x = mouse_x + 10
        local icon_y = mouse_y + 10
        local stack_x = icon_x + COUNT_X_OFFSET + 10
        local stack_y = (icon_y + COUNT_Y_OFFSET)

        local attachType = mq.TLO.CursorAttachment.Type():lower()
        if attachType == "item" or attachType == "item_link" then
            local cursor_item = mq.TLO.CursorAttachment.Item
            animItems:SetTextureCell(cursor_item.Icon() - EQ_ICON_OFFSET)
            if attachType == "item_link" then
                draw_list:AddTextureAnimation(animBox, ImVec2(icon_x, icon_y), ImVec2(ICON_WIDTH, ICON_HEIGHT))
            end
            draw_list:AddTextureAnimation(animItems, ImVec2(icon_x, icon_y), ImVec2(ICON_WIDTH, ICON_HEIGHT))
            if cursor_item.Stackable() then
                local text_size = ImGui.CalcTextSize(tostring(cursor_item.Stack()))
                draw_list:AddTextureAnimation(animBox, ImVec2(stack_x, stack_y),
                    ImVec2(text_size, ImGui.GetTextLineHeight()))
                draw_list:AddText(ImVec2(stack_x, stack_y), IM_COL32(255, 255, 255, 255), tostring(cursor_item.Stack()))
            end
        elseif attachType == "spell_gem" then
            local gem_offset_x = 7
            local gem_offset_y = 5
            local cursor_item = mq.TLO.CursorAttachment.Spell
            animSpellGemIcons:SetTextureCell(cursor_item.SpellIcon())
            draw_list:AddTextureAnimation(animSpellGemHolder, ImVec2(icon_x, icon_y), ImVec2(39, 32))
            draw_list:AddTextureAnimation(animSpellGemBG, ImVec2(icon_x, icon_y), ImVec2(39, 32))
            draw_list:AddTextureAnimation(animSpellGemIcons, ImVec2(icon_x + gem_offset_x, icon_y + gem_offset_y),
                ImVec2(24, 24))
        elseif attachType == "skill" or attachType == "social" then
            local buttonLabel = mq.TLO.CursorAttachment.ButtonText()
            local label_x, label_y = ImGui.CalcTextSize(buttonLabel)
            local midX = math.max((ICON_WIDTH - label_x) / 2, 0)
            local midY = (ICON_WIDTH - label_y) / 2
            draw_list:AddTextureAnimation(animSquareButton, ImVec2(icon_x, icon_y), ImVec2(ICON_WIDTH, ICON_WIDTH))
            draw_list:AddText(nil, 13, ImVec2(icon_x + midX, icon_y + midY), IM_COL32(255, 255, 255, 255), buttonLabel)
        end
    end
end

local function CloseEditPopup()
    editButtonPopupOpen = false
    editButtonIndex = 0
    editButtonSet = ""
end

local function GetButtonBySetIndex(Set, Index)
    if settings.Sets[Set] and settings.Sets[Set][Index] and settings.Buttons[settings.Sets[Set][Index]] then
        return settings.Buttons[settings.Sets[Set][Index]]
    end
    return { Unassigned = true, Label = tostring(Index), }
end

local function OpenEditPopup(Set, Index)
    editButtonPopupOpen = true
    editButtonIndex = Index
    editButtonSet = Set
    selectedTimerType = 1
    local button = GetButtonBySetIndex(Set, Index)
    if not button.Unassigned and button.TimerType and button.TimerType:len() > 0 then
        for index, type in ipairs(TimerTypes) do
            if type == button.TimerType then
                selectedTimerType = index
                break
            end
        end
    end
end

local function ExportButtonToClipBoard(button)
    local sharableButton = { Type = "Button", Button = button, }
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableButton))
    Output("Button: '%s' has been copied to your clipboard!", button.Label)
    local printableButton = btnUtils.dumpTable(sharableButton):gsub("\n/", "\\n/")
    Output('\n' .. printableButton)
end

local function GenerateButtonKey()
    return 'Button_' .. tonumber(settings.Global.ButtonCount + 1)
end

local function ImportButtonAndSave(button, save)
    local key = GenerateButtonKey()
    settings.Buttons[key] = button
    settings.Global.ButtonCount = settings.Global.ButtonCount + 1
    if save then
        SaveSettings(true)
    end
    return key
end

local function ExportSetToClipBoard(setKey)
    local sharableSet = { Type = "Set", Key = setKey, Set = {}, Buttons = {}, }
    for index, btnName in pairs(settings.Sets[setKey]) do
        sharableSet.Set[index] = btnName
    end
    for _, buttonKey in pairs(settings.Sets[setKey] or {}) do
        sharableSet.Buttons[buttonKey] = settings.Buttons[buttonKey]
    end
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableSet))
end

local function ImportSetAndSave(sharableSet)
    -- is setname unqiue?
    local setName = sharableSet.Key
    if settings.Sets[setName] ~= nil then
        local newSetName = setName .. "_Imported_" .. os.date("%m-%d-%y-%H-%M-%S")
        Output("\ayImport Set Warning: Set name: \at%s\ay already exists renaming it to \at%s\ax", setName, newSetName)
        setName = newSetName
    end

    settings.Sets[setName] = {}
    for index, btnName in pairs(sharableSet.Set) do
        local newButtonName = ImportButtonAndSave(sharableSet.Buttons[btnName], false)
        settings.Sets[setName][index] = newButtonName
    end

    -- add set to user
    table.insert(settings.Characters[CharConfig].Windows[1].Sets, setName)

    SaveSettings(true)
end

local function GetButtonSectionKeyBySetIndex(Set, Index)
    local key = settings.Sets[Set][Index]

    -- if the key doesn't exist, get the current button counter and add 1
    if key == nil then
        key = GenerateButtonKey()
    end
    return key
end

local function PCallString(str)
    local func, err = load(str)
    if not func then
        return false, err
    end

    return pcall(func)
end

local function EvaluateLua(str)
    local runEnv = [[mq = require('mq')
        %s
        ]]

    return PCallString(string.format(runEnv, str))
end

---@param button any
---@return integer, integer, boolean #CountDown, CooldownTimer, Toggle Locked
local function GetButtonCooldown(button)
    local countDown, coolDowntimer, toggleLocked = 0, 0, false

    if button.TimerType == "Custom Lua" then
        local success
        local result

        if button.Timer and button.Timer:len() > 0 then
            success, result = EvaluateLua(button.Timer)
            if not success then
                Output("Failed to run Timer for Button(%s): %s", button.Label, countDown)
                Output("RunEnv was:\n%s", button.Timer)
                countDown = 0
            else
                countDown = tonumber(result) or 0
            end
        end
        if button.Cooldown and button.Cooldown:len() > 0 then
            success, result = EvaluateLua(button.Cooldown)
            if not success then
                Output("Failed to run Cooldown for Button(%s): %s", button.Label, button.Cooldown)
                Output("RunEnv was:\n%s", button.Cooldown)
                coolDowntimer = 0
            else
                coolDowntimer = tonumber(result) or 0
            end
        end
        if button.ToggleCheck and button.ToggleCheck:len() > 0 then
            success, result = EvaluateLua(button.ToggleCheck)
            if not success then
                Output("Failed to run ToggleCheck for Button(%s): %s", button.Label, button.ToggleCheck)
                Output("RunEnv was:\n%s", button.ToggleCheck)
                toggleLocked = false
            else
                toggleLocked = type(result) == 'boolean' and result or false
            end
        end
    elseif button.TimerType == "Seconds Timer" then
        if button.CooldownTimer then
            countDown = button.CooldownTimer - os.clock()
            if countDown <= 0 then
                button.CooldownTimer = nil
                return 0, 0, false
            end
            coolDowntimer = button.Cooldown
        end
    elseif button.TimerType == "Item" then
        countDown = mq.TLO.FindItem(button.Cooldown).TimerReady() or 0
        coolDowntimer = mq.TLO.FindItem(button.Cooldown).Clicky.TimerID() or 0
    elseif button.TimerType == "Spell Gem" then
        countDown = (mq.TLO.Me.GemTimer(button.Cooldown)() or 0) / 1000
        coolDowntimer = mq.TLO.Me.GemTimer(button.Cooldown).TotalSeconds() or 0
    elseif button.TimerType == "AA" then
        countDown = (mq.TLO.Me.AltAbilityTimer(button.Cooldown)() or 0) / 1000
        coolDowntimer = mq.TLO.Me.AltAbility(button.Cooldown).MyReuseTime() or 0
    elseif button.TimerType == "Ability" then
        if mq.TLO.Me.AbilityTimer and mq.TLO.Me.AbilityTimerTotal then
            countDown = (mq.TLO.Me.AbilityTimer(button.Cooldown)() or 0) / 1000
            coolDowntimer = (mq.TLO.Me.AbilityTimerTotal(button.Cooldown)() or 0) / 1000
        end
    end

    return countDown, coolDowntimer, toggleLocked
end

local function RenderButtonCooldown(button, cursorScreenPos, btnSize)
    local countDown, coolDowntimer, toggleLocked = GetButtonCooldown(button)
    if coolDowntimer == 0 and not toggleLocked then return end

    local ratio = 1 - (countDown / (coolDowntimer))

    if toggleLocked then
        ratio = 100
    end

    local start_angle = (1.5 * math.pi)
    local end_angle = math.pi * ((2 * ratio) - 0.5)
    local center = ImVec2(cursorScreenPos.x + (btnSize / 2), cursorScreenPos.y + (btnSize / 2))

    local draw_list = ImGui.GetWindowDrawList()
    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + btnSize, cursorScreenPos.y + btnSize), true)
    draw_list:PathLineTo(center)
    draw_list:PathArcTo(center, btnSize, start_angle, end_angle, 0)
    draw_list:PathFillConvex(ImGui.GetColorU32(0.8, 0.02, 0.02, 0.75))
    draw_list:PopClipRect()
end

local function ResolveButtonLabel(renderButton)
    local success = true
    local evaluatedLabel = renderButton.Label

    if renderButton.EvaluateLabel then
        local test
        success, evaluatedLabel = EvaluateLua(renderButton.Label)
        if not success then
            Debug("Failed to evaluate Button Label:\n%s\nError:\n%s", renderButton.Label, evaluatedLabel)
        end
    end
    evaluatedLabel = tostring(evaluatedLabel)
    return evaluatedLabel:gsub(" ", "\n")
end

local function DrawButtonTooltip(Button, label)
    -- hover tooltip
    if Button.Unassigned == nil and ImGui.IsItemHovered() then
        local tooltipText = label

        -- check label instead of tooltipText because if there is no text we dont care about the timer.
        if label:len() > 0 then
            local countDown, _ = GetButtonCooldown(Button)
            if countDown ~= 0 then
                tooltipText = tooltipText .. "\n\n" .. btnUtils.FormatTime(math.ceil(countDown))
            end

            ImGui.BeginTooltip()
            ImGui.Text(tooltipText)
            ImGui.EndTooltip()
        end
    end
end

local function RenderButton(renderButton, size, renderLabel)
    local evaluatedLabel = renderLabel and ResolveButtonLabel(renderButton) or ""
    local clicked = false

    -- icon
    if renderButton.Icon or (renderButton.IconLua and renderButton.IconLua:len() > 0) then
        local iconId = renderButton.Icon
        local iconType = renderButton.IconType

        if renderButton.IconLua and renderButton.IconLua:len() > 0 then
            local success
            success, iconId, iconType = EvaluateLua(renderButton.IconLua)
            if not success then
                Debug("Failed to evaluate IconLua: %s\nError:\n%s", renderButton.IconLua, iconId)
                iconId = renderButton.Icon
                iconType = renderButton.IconType
            end
        end

        local cursor_x, cursor_y = ImGui.GetCursorPos()
        if iconType == nil or iconType == "Spell" then
            animSpellIcons:SetTextureCell(tonumber(iconId) or 0)
            ImGui.DrawTextureAnimation(animSpellIcons, size, size)
        else
            animItems:SetTextureCell(tonumber(iconId) or 0)
            ImGui.DrawTextureAnimation(animItems, size, size)
        end

        -- label
        if renderButton.ShowLabel == nil or renderButton.ShowLabel then
            local label_x, label_y = ImGui.CalcTextSize(evaluatedLabel)
            local midX = math.max((size - label_x) / 2, 0)
            local midY = (size - label_y) / 2
            ImGui.SetCursorPos(cursor_x + midX, cursor_y + midY)
            ImGui.Text(evaluatedLabel)
        end

        ImGui.SetCursorPos(cursor_x, cursor_y)
        clicked = ImGui.Selectable('', false, ImGuiSelectableFlags.DontClosePopups, size, size)
    else
        -- button
        clicked = ImGui.Button(evaluatedLabel, size, size)
    end
    -- tooltip
    if renderLabel then
        DrawButtonTooltip(renderButton, evaluatedLabel)
    end

    return clicked
end

local function RecalculateVisibleButtons(Set)
    buttonSizeDirty = false
    lastWindowWidth = ImGui.GetWindowWidth()
    lastWindowHeight = ImGui.GetWindowHeight()

    local cursorX, cursorY = ImGui.GetCursorPos() -- this will get us the x pos we start at which tells us of the offset from the main window border
    local style = ImGui.GetStyle()                -- this will get us ItemSpacing.x which is the amount of space between buttons

    -- global button configs
    local btnSize = (settings.Global.ButtonSize or 6) * 10
    cachedCols = math.floor((lastWindowWidth - cursorX) / (btnSize + style.ItemSpacing.x))
    cachedRows = math.floor((lastWindowHeight - cursorY) / (btnSize + style.ItemSpacing.y))

    local count = 100
    if cachedRows * cachedCols < 100 then count = cachedRows * cachedCols end

    -- get the last assigned button and make sure it is visible.
    local lastAssignedButton = 1
    for i = 1, 100 do if not GetButtonBySetIndex(Set, i).Unassigned then lastAssignedButton = i end end

    -- if the last forced visible buttons isn't the last in a row then render to the end of that row.
    -- stay with me here. The last button needs to look at the number of buttons per row (cols) and
    -- the position of this button in that row (button%cols) and add enough to get to the end of the row.
    if lastAssignedButton % cachedCols ~= 0 then
        lastAssignedButton = lastAssignedButton + (cachedCols - (lastAssignedButton % cachedCols))
    end

    visibleButtonCount = math.min(math.max(count, lastAssignedButton), 100)
end

local function DrawTabContextMenu()
    local openPopup = false

    local unassigned = {}
    local charLoadedSets = {}
    for _, v in ipairs(settings.Characters[CharConfig].Windows[1].Sets) do
        charLoadedSets[v] = true
    end
    for k, _ in pairs(settings.Sets) do
        if charLoadedSets[k] == nil then
            unassigned[k] = true
        end
    end

    if ImGui.BeginPopupContextItem() then
        if btnUtils.getTableSize(unassigned) > 0 then
            if ImGui.BeginMenu("Add Set") then
                for k, _ in pairs(unassigned) do
                    if ImGui.MenuItem(k) then
                        table.insert(settings.Characters[CharConfig].Windows[1].Sets, k)
                        SaveSettings(true)
                        break
                    end
                end
                ImGui.EndMenu()
            end
        end

        if ImGui.BeginMenu("Remove Set") then
            for i, v in ipairs(settings.Characters[CharConfig].Windows[1].Sets) do
                if ImGui.MenuItem(v) then
                    table.remove(settings.Characters[CharConfig].Windows[1].Sets, i)
                    SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Delete Set") then
            for k, _ in pairs(settings.Sets) do
                if ImGui.MenuItem(k) then
                    -- clean up any references to this set.
                    for charConfigKey, charConfigValue in pairs(settings.Characters) do
                        for setKey, setName in pairs(charConfigValue.Windows[1].Sets) do
                            if setName == k then
                                settings.Characters[charConfigKey].Windows[1].Sets[setKey] = nil
                            end
                        end
                    end
                    settings.Sets[k] = nil
                    SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Delete Hotkey") then
            local sortedButtons = {}
            for k, v in pairs(settings.Buttons) do table.insert(sortedButtons, { Label = v.Label, id = k, }) end
            table.sort(sortedButtons, function(a, b) return a.Label < b.Label end)

            for _, buttonData in pairs(sortedButtons) do
                if ImGui.MenuItem(buttonData.Label) then
                    -- clean up any references to this Button.
                    for setNameKey, setButtons in pairs(settings.Sets) do
                        for buttonKey, buttonName in pairs(setButtons) do
                            if buttonName == buttonData.id then
                                settings.Sets[setNameKey][buttonKey] = nil
                            end
                        end
                    end
                    settings.Buttons[buttonData.id] = nil
                    SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Create New Set") then
            openPopup = true
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Button Size") then
            for i = 3, 10 do
                local checked = settings.Global.ButtonSize == i
                if ImGui.MenuItem(tostring(i), nil, checked) then
                    settings.Global.ButtonSize = i
                    buttonSizeDirty = true
                    SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        local font_scale = {
            {
                label = "Tiny",
                size = 0.8,
            },
            {
                label = "Small",
                size = 0.9,
            },
            {
                label = "Normal",
                size = 1.0,
            },
            {
                label = "Large",
                size  = 1.1,
            },
        }

        if ImGui.BeginMenu("Font Scale") then
            for i, v in ipairs(font_scale) do
                local checked = settings.Global.Font == v.size
                if ImGui.MenuItem(v.label, nil, checked) then
                    settings.Global.Font = v.size
                    SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Share Set") then
            for k, _ in pairs(settings.Sets) do
                if ImGui.MenuItem(k) then
                    ExportSetToClipBoard(k)
                    Output("Set: '%s' has been copied to your clipboard!", k)
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Import Button or Set") then
            importObjectPopupOpen = true
            importText = ImGui.GetClipboardText() or ""
            importTextChanged = true
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Display Settings") then
            if ImGui.MenuItem((settings.Characters[CharConfig].HideTitleBar and "Show" or "Hide") .. " Title Bar") then
                settings.Characters[CharConfig].HideTitleBar = not settings.Characters[CharConfig].HideTitleBar
                SaveSettings(true)
            end
            if ImGui.MenuItem("Save Layout as Default") then
                settings.Defaults = {
                    width = lastWindowWidth,
                    height = lastWindowHeight,
                    x = lastWindowX,
                    y = lastWindowY,
                    CharSettings = settings.Characters[CharConfig],
                }
                SaveSettings(true)
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Replicate Size/Pos") then
            local x, y = ImGui.GetWindowPos()
            ButtonActors.send({
                from = mq.TLO.Me.DisplayName(),
                script = "ButtonMaster",
                event = "CopyLoc",
                width = lastWindowWidth,
                height = lastWindowHeight,
                x = lastWindowX,
                y = lastWindowY,
                hideTitleBar = settings.Characters[CharConfig].HideTitleBar,
            })
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Dev") then
            if ImGui.MenuItem((enableDebug and "Disable" or "Enable") .. " Debug") then
                enableDebug = not enableDebug
            end
            ImGui.EndMenu()
        end

        ImGui.EndPopup()
    end

    if openPopup and ImGui.IsPopupOpen(editTabPopup) == false then
        ImGui.OpenPopup(editTabPopup)
        openPopup = false
    end
end

local function DrawCreateTab()
    if ImGui.BeginPopup(editTabPopup) then
        ImGui.Text("New Button Set:")
        local tmp, selected = ImGui.InputText("##edit", '', 0)
        if selected then name = tmp end
        if ImGui.Button("Save") then
            if name ~= nil and name:len() > 0 then
                if settings.Sets[name] == nil then
                    table.insert(settings.Characters[CharConfig].Windows[1].Sets, name)
                    settings.Sets[name] = {}
                    SaveSettings(true)
                else
                    Output("\arError Saving Set: A set with this name already exists!\ax")
                end
            else
                Output("\arError Saving Set: Name cannot be empty.\ax")
            end
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

local function DrawContextMenu(Set, Index, buttonID)
    local Button = GetButtonBySetIndex(Set, Index)

    local unassigned = {}
    local keys = {}
    for _, v in pairs(settings.Sets[Set]) do keys[v] = true end
    for k, v in pairs(settings.Buttons) do
        if keys[k] == nil then
            unassigned[k] = v
        end
    end

    if ImGui.BeginPopupContextItem(buttonID) then
        --editPopupName = "edit_button_popup|" .. Index
        -- only list hotkeys that aren't already assigned to the button set
        if btnUtils.getTableSize(unassigned) > 0 then
            if ImGui.BeginMenu("Assign Hotkey") then
                -- hytiek: BEGIN ADD
                -- Create an array to store the sorted keys
                local sortedKeys = {}

                -- Populate the array with non-nil keys from the original table
                for key, value in pairs(unassigned) do
                    if value ~= nil then
                        table.insert(sortedKeys, key)
                    end
                end

                -- Sort the keys based on the Label field
                table.sort(sortedKeys, function(a, b)
                    local labelA = unassigned[a] and unassigned[a].Label
                    local labelB = unassigned[b] and unassigned[b].Label
                    return labelA < labelB
                end)

                for _, key in ipairs(sortedKeys) do
                    local value = unassigned[key]
                    if value ~= nil then
                        if ImGui.MenuItem(tostring(value.Label)) then
                            settings.Sets[Set][Index] = key
                            SaveSettings(true)
                            break
                        end
                    end
                end
                ImGui.EndMenu()
            end
        end

        -- only show create new for unassigned buttons
        if Button.Unassigned == true then
            if ImGui.MenuItem("Create New") then
                OpenEditPopup(Set, Index)
            end
        end

        -- only show edit & unassign for assigned buttons
        if Button.Unassigned == nil then
            if ImGui.MenuItem("Edit") then
                OpenEditPopup(Set, Index)
            end
            if ImGui.MenuItem("Unassign") then
                settings.Sets[Set][Index] = nil
                SaveSettings(true)
            end
            if ImGui.MenuItem(Icons.MD_SHARE) then
                local button = GetButtonBySetIndex(Set, Index)
                ExportButtonToClipBoard(button)
            end
            btnUtils.Tooltip("Copy contents of this button to share with friends.")
        end

        ImGui.EndPopup()
    end
end

local function RenderOptionNumber(id, text, cur, min, max, step)
    ImGui.PushID("##num_spin_" .. id)
    ImGui.PushItemWidth(100)
    local input, changed = ImGui.InputInt(text, cur, step, step * 10)
    ImGui.PopItemWidth()
    ImGui.PopID()

    if input > max then input = max end
    if input < min then input = min end

    changed = cur ~= input
    return input, changed
end

local function RenderColorPicker(id, buttonTypeName, renderButton, key)
    local btnColor = {}

    if renderButton[key] ~= nil then
        local tColors = btnUtils.split(renderButton[key], ",")
        for i, v in ipairs(tColors) do btnColor[i] = tonumber(v / 255) end
    else
        btnColor[1] = 0
        btnColor[2] = 0
        btnColor[3] = 0
    end

    ImGui.PushID(id)
    local col, used = ImGui.ColorEdit3(string.format("%s Color", buttonTypeName), btnColor, ImGuiColorEditFlags.NoInputs)
    if used then
        editButtonTextChanged = true
        btnColor = btnUtils.shallowcopy(col)
        renderButton[key] = string.format("%d,%d,%d", math.floor(col[1] * 255),
            math.floor(col[2] * 255), math.floor(col[3] * 255))
    end
    if ImGui.BeginPopupContextItem(id) then
        if ImGui.MenuItem(string.format("Clear %s Color", buttonTypeName)) then
            renderButton[key] = nil
            SaveSettings(true)
        end
        ImGui.EndPopup()
    end
    ImGui.PopID()
end

local function RenderIconPicker(renderButton)
    if renderButton.Icon then
        local objectID = string.format("##IconPicker_%s_%d", editButtonSet, editButtonIndex)
        ImGui.PushID(objectID)
        if RenderButton(renderButton, 20, false) then
            picker:SetOpen()
        end
        ImGui.PopID()
        if ImGui.BeginPopupContextItem(objectID) then
            if ImGui.MenuItem("Clear Icon") then
                renderButton.Icon = nil
                SaveSettings(true)
            end
            ImGui.EndPopup()
        end
    else
        if ImGui.Button('', ImVec2(20, 20)) then
            picker:SetOpen()
        end
    end
end

local function RenderTimerPanel(renderButton)
    selectedTimerType, _ = ImGui.Combo("Timer Type", selectedTimerType, TimerTypes)

    renderButton.TimerType = TimerTypes[selectedTimerType]

    if TimerTypes[selectedTimerType] == "Custom Lua" then
        renderButton.Timer = ImGui.InputText("Custom Timer Lua", renderButton.Timer)
        btnUtils.Tooltip(
            "Lua expression that describes how much longer is left until this button is usable.\ni.e. 'return mq.TLO.Item(\"Potion of Clarity IV\").TimerReady()'")
        renderButton.Cooldown = ImGui.InputText("Custom Cooldown Lua", tostring(renderButton.Cooldown))
        btnUtils.Tooltip(
            "Lua expression that describes how long the timer is in total.\ni.e. 'return mq.TLO.Item(\"Potion of Clarity IV\").Clicky.TimerID()'")
        renderButton.ToggleCheck = ImGui.InputText("Custom Toggle Check Lua",
            renderButton.ToggleCheck and tostring(renderButton.ToggleCheck) or "")
        btnUtils.Tooltip(
            "Lua expression that must result in a bool: true if the button is locked and false if it is unlocked.")
    elseif TimerTypes[selectedTimerType] == "Seconds Timer" then
        renderButton.Cooldown, _ = RenderOptionNumber("##cooldown", "Manual Cooldown",
            tonumber(renderButton.Cooldown) or 0, 0, 3600, 1)
        btnUtils.Tooltip("Amount of time in seconds to display the cooldown overlay.")
    elseif TimerTypes[selectedTimerType] == "Item" then
        renderButton.Cooldown = ImGui.InputText("Item Name", tostring(renderButton.Cooldown))
        btnUtils.Tooltip("Name of the item that you want to track the cooldown of.")
    elseif TimerTypes[selectedTimerType] == "Spell Gem" then
        renderButton.Cooldown = ImGui.InputInt("Spell Gem", tonumber(renderButton.Cooldown) or 1, 1)
        if renderButton.Cooldown < 1 then renderButton.Cooldown = 1 end
        if renderButton.Cooldown > mq.TLO.Me.NumGems() then renderButton.Cooldown = mq.TLO.Me.NumGems() end
        btnUtils.Tooltip("Spell Gem Number that you want to track the cooldown of.")
    elseif TimerTypes[selectedTimerType] == "AA" then
        renderButton.Cooldown = ImGui.InputText("Alt Ability Name or ID", tostring(renderButton.Cooldown))
        btnUtils.Tooltip("Name or ID of the AA that you want to track the cooldown of.")
    elseif TimerTypes[selectedTimerType] == "Ability" then
        renderButton.Cooldown = ImGui.InputText("Ability Name", tostring(renderButton.Cooldown))
        btnUtils.Tooltip("Name of the Ability that you want to track the cooldown of.")
    end
end

local function RenderButtonEditUI(renderButton, enableShare, enableEdit)
    -- Share Buttton
    if enableShare then
        if ImGui.Button(Icons.MD_SHARE) then
            ImGui.SetClipboardText(btnUtils.encodeTable(renderButton))
            ExportButtonToClipBoard(renderButton)
        end
        btnUtils.Tooltip("Copy contents of this button to share with friends.")
        ImGui.SameLine()
    end

    -- color pickers
    RenderColorPicker(string.format("##ButtonColorPicker1_%s", renderButton.Label), 'Button', renderButton,
        'ButtonColorRGB')

    ImGui.SameLine()
    RenderColorPicker(string.format("##TextColorPicker1_%s", renderButton.Label), 'Text', renderButton, 'TextColorRGB')

    ImGui.SameLine()
    RenderIconPicker(renderButton)

    ImGui.SameLine()
    ImGui.Text("Icon")

    if picker.Selected then
        renderButton.Icon = picker.Selected
        renderButton.IconType = picker.SelectedType
        picker:ClearSelection()
    end

    if renderButton.Icon ~= nil then
        ImGui.SameLine()
        if renderButton.ShowLabel == nil then renderButton.ShowLabel = true end
        renderButton.ShowLabel = ImGui.Checkbox("Show Button Label", renderButton.ShowLabel)
    end

    ImGui.SameLine()

    -- reset
    ImGui.SameLine()
    if ImGui.Button("Reset All") then
        renderButton.ButtonColorRGB = nil
        renderButton.TextColorRGB   = nil
        renderButton.Icon           = nil
        renderButton.IconType       = nil
        renderButton.Timer          = nil
        renderButton.Cooldown       = nil
        renderButton.ToggleCheck    = nil
        renderButton.ShowLabel      = nil
        renderButton.EvaluateLabel  = nil
        editButtonTextChanged       = true
    end

    ImGui.SameLine()
    editButtonAdvanced, _ = btnUtils.RenderOptionToggle(string.format("advanced_toggle_%s", renderButton.Label),
        "Show Advanced", editButtonAdvanced)

    local textChanged
    renderButton.Label, textChanged = ImGui.InputText('Button Label', renderButton.Label or '')
    editButtonTextChanged = editButtonTextChanged or textChanged

    if editButtonAdvanced then
        ImGui.SameLine()
        renderButton.EvaluateLabel, _ = ImGui.Checkbox("Evaluate Label", renderButton.EvaluateLabel or false)
        btnUtils.Tooltip("Treat the Label as a Lua function and evaluate it.")

        renderButton.IconLua, textChanged = ImGui.InputText('Icon Lua', renderButton.IconLua or '')
        btnUtils.Tooltip(
            "Dynamically override the IconID with this Lua function. \nNote: This MUST return number, string : IconId, IconType")
        editButtonTextChanged = editButtonTextChanged or textChanged
    end

    ImGui.Separator()
    RenderTimerPanel(renderButton)

    ImGui.Separator()

    ImGui.Text("Commands:")
    local yPos = ImGui.GetCursorPosY()
    local footerHeight = 35
    local editHeight = ImGui.GetWindowHeight() - yPos - footerHeight
    renderButton.Cmd, textChanged = ImGui.InputTextMultiline("##_Cmd_Edit", renderButton.Cmd or "",
        ImVec2(ImGui.GetWindowWidth() * 0.98, editHeight))
    editButtonTextChanged = editButtonTextChanged or textChanged
end

local function DrawImportButtonPopup()
    if not importObjectPopupOpen then return end

    local shouldDrawImportPopup = false

    importObjectPopupOpen, shouldDrawImportPopup = ImGui.Begin("Import Button or Set", importObjectPopupOpen,
        ImGuiWindowFlags.None)
    if ImGui.GetWindowWidth() < 500 or ImGui.GetWindowHeight() < 100 then
        ImGui.SetWindowSize(math.max(500, ImGui.GetWindowWidth()), math.max(100, ImGui.GetWindowHeight()))
    end
    if importObjectPopupOpen and shouldDrawImportPopup then
        if ImGui.SmallButton(Icons.MD_CONTENT_PASTE) then
            importText = ImGui.GetClipboardText()
            importTextChanged = true
        end
        btnUtils.Tooltip("Paste from Clipboard")
        ImGui.SameLine()

        if importTextChanged then
            validDecode, decodedObject = btnUtils.decodeTable(importText)
            btnUtils.dumpTable(decodedObject)
            validDecode = type(decodedObject) == 'table' and validDecode or false
        end

        if validDecode then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.02, 0.8, 0.02, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.02, 0.02, 1.0)
        end
        importText, importTextChanged = ImGui.InputText(
            (validDecode and Icons.MD_CHECK or Icons.MD_NOT_INTERESTED) .. " Import Code", importText,
            ImGuiInputTextFlags.None)
        ImGui.PopStyleColor()

        -- save button
        if validDecode and decodedObject then
            if ImGui.Button("Import " .. decodedObject.Type) then
                if decodedObject.Type == "Button" then
                    ImportButtonAndSave(decodedObject.Button, true)
                elseif decodedObject.Type == "Set" then
                    ImportSetAndSave(decodedObject)
                else
                    Output("\arError: imported object was not a button or a set!")
                end
                -- reset everything
                decodedObject = {}
                importText = ""
                importObjectPopupOpen = false
            end
        end
    end
    ImGui.End()
end

local function CreateButtonFromCursor(Set, Index)
    editButtonUseCursor = true
    OpenEditPopup(Set, Index)
end

local function DrawEditButtonPopup()
    if not editButtonPopupOpen then
        picker:SetClosed()
        return
    end

    local ButtonKey = GetButtonSectionKeyBySetIndex(editButtonSet, editButtonIndex)
    local Button = GetButtonBySetIndex(editButtonSet, editButtonIndex)
    local shouldDrawEditPopup = false

    editButtonPopupOpen, shouldDrawEditPopup = ImGui.Begin("Edit Button", editButtonPopupOpen,
        editButtonTextChanged and ImGuiWindowFlags.UnsavedDocument or ImGuiWindowFlags.None)
    if editButtonPopupOpen and shouldDrawEditPopup then
        -- shallow copy original button incase we want to reset (close)
        if tmpButton[ButtonKey] == nil then
            tmpButton[ButtonKey] = btnUtils.shallowcopy(Button)
        end

        if editButtonUseCursor then
            editButtonUseCursor = false
            if mq.TLO.CursorAttachment and mq.TLO.CursorAttachment.Type() then
                local cursorIndex = mq.TLO.CursorAttachment.Index()
                local buttonText = mq.TLO.CursorAttachment.ButtonText():gsub("\n", " ")
                local attachmentType = mq.TLO.CursorAttachment.Type():lower()
                if attachmentType == "item" or attachmentType == "item_link" then
                    tmpButton[ButtonKey].Label = mq.TLO.CursorAttachment.Item()
                    tmpButton[ButtonKey].Cmd = string.format("/useitem \"%s\"", mq.TLO.CursorAttachment.Item())
                    tmpButton[ButtonKey].Icon = tostring(mq.TLO.CursorAttachment.Item.Icon() - 500)
                    tmpButton[ButtonKey].IconType = "Item"
                    tmpButton[ButtonKey].Cooldown = mq.TLO.CursorAttachment.Item()
                    tmpButton[ButtonKey].TimerType = "Item"
                elseif attachmentType == "spell_gem" then
                    local gem = mq.TLO.Me.Gem(mq.TLO.CursorAttachment.Spell.RankName() or "")() or 0
                    tmpButton[ButtonKey].Label = mq.TLO.CursorAttachment.Spell.RankName()
                    tmpButton[ButtonKey].Cmd = string.format("/cast %d", gem)
                    tmpButton[ButtonKey].Icon = tostring(mq.TLO.CursorAttachment.Spell.SpellIcon())
                    tmpButton[ButtonKey].IconType = "Spell"
                    tmpButton[ButtonKey].Cooldown = gem
                    tmpButton[ButtonKey].TimerType = "Spell Gem"
                elseif attachmentType == "skill" then
                    tmpButton[ButtonKey].Label = buttonText
                    tmpButton[ButtonKey].Cmd = string.format("/doability %s", buttonText)
                    tmpButton[ButtonKey].Icon = nil
                    tmpButton[ButtonKey].Cooldown = buttonText
                    tmpButton[ButtonKey].TimerType = "Ability"
                elseif attachmentType == "social" then
                    tmpButton[ButtonKey].Label = buttonText
                    if cursorIndex >= 120 then
                        tmpButton[ButtonKey].Cmd = string.format("/alt act %d", cursorIndex)
                        tmpButton[ButtonKey].Icon = nil
                        tmpButton[ButtonKey].Cooldown = buttonText
                        tmpButton[ButtonKey].TimerType = "AA"
                    else
                        if mq.TLO.Social then
                            tmpButton[ButtonKey].Cmd = ""
                            for i = 0, 4 do
                                local cmd = mq.TLO.Social(cursorIndex).Cmd(i)()
                                if cmd:len() > 0 then
                                    tmpButton[ButtonKey].Cmd = string.format("%s%s%s", tmpButton[ButtonKey].Cmd, tmpButton[ButtonKey].Cmd:len() > 0 and "\n" or "", cmd)
                                end
                            end
                        end
                    end
                end

                for index, type in ipairs(TimerTypes) do
                    if type == tmpButton[ButtonKey].TimerType then
                        selectedTimerType = index
                        break
                    end
                end
            end
        end

        RenderButtonEditUI(tmpButton[ButtonKey], true, true)

        -- save button
        if ImGui.Button("Save") then
            -- make sure the button label isn't nil/empty/spaces
            if tmpButton[ButtonKey].Label ~= nil and tmpButton[ButtonKey].Label:gsub("%s+", ""):len() > 0 then
                settings.Sets[editButtonSet][editButtonIndex] =
                    ButtonKey                                                            -- add the button key for this button set index
                settings.Buttons[ButtonKey] = btnUtils.shallowcopy(tmpButton[ButtonKey]) -- store the tmp button into the settings table
                settings.Buttons[ButtonKey].Unassigned = nil                             -- clear the unassigned flag
                -- if we're saving this, update the button counter
                settings.Global.ButtonCount = settings.Global.ButtonCount + 1
                SaveSettings(true)
                editButtonTextChanged = false
            else
                tmpButton[ButtonKey] = nil
                Output("\arSave failed.  Button Label cannot be empty.")
            end
        end

        ImGui.SameLine()

        -- close button
        local closeClick = ImGui.Button("Close")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Close edit dialog without saving")
            ImGui.EndTooltip()
        end
        if closeClick then
            picker:SetClosed()
            tmpButton[ButtonKey] = btnUtils.shallowcopy(Button)
            CloseEditPopup()
        end

        ImGui.SameLine()

        local clearClick = ImGui.Button("Clear")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Clear hotbutton fields")
            ImGui.EndTooltip()
        end
        if clearClick then
            tmpButton[ButtonKey] = nil                          -- clear the buffer
            settings.Sets[editButtonSet][editButtonIndex] = nil -- clear the button set index
        end
    end
    ImGui.End()
end

local function DrawButtons(Set)
    if ImGui.GetWindowWidth() ~= lastWindowWidth or ImGui.GetWindowHeight() ~= lastWindowHeight or buttonSizeDirty then
        RecalculateVisibleButtons(Set)
    end

    local btnSize = (settings.Global.ButtonSize or 6) * 10

    local renderButtonCount = visibleButtonCount

    for ButtonIndex = 1, renderButtonCount do
        local Button = GetButtonBySetIndex(Set, ButtonIndex)

        -- push button styles if configured
        if Button.ButtonColorRGB ~= nil then
            local Colors = btnUtils.split(Button.ButtonColorRGB, ",")
            ImGui.PushStyleColor(ImGuiCol.Button, tonumber(Colors[1] / 255) or 1.0, tonumber(Colors[2] / 255) or 1.0,
                tonumber(Colors[3] / 255) or 1.0, 1)
        end
        if Button.TextColorRGB ~= nil then
            local Colors = btnUtils.split(Button.TextColorRGB, ",")
            ImGui.PushStyleColor(ImGuiCol.Text, tonumber(Colors[1] / 255) or 1.0, tonumber(Colors[2] / 255) or 1.0,
                tonumber(Colors[3] / 255) or 1.0, 1)
        end

        local cursorScreenPos = ImGui.GetCursorScreenPosVec()

        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.9, 0.9, 0.5)
        ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.9, 0.9, 0.9, 0.5)
        ImGui.SetWindowFontScale(settings.Global.Font or 1)
        local clicked
        local buttonID = string.format("##Button_%s_%d", Set, ButtonIndex)
        ImGui.PushID(buttonID)
        clicked = RenderButton(Button, btnSize, true)
        ImGui.PopID()
        ImGui.SetWindowFontScale(1)
        ImGui.PopStyleColor(2)

        RenderButtonCooldown(Button, cursorScreenPos, btnSize)
        -- pop button styles as necessary
        if Button.ButtonColorRGB ~= nil then ImGui.PopStyleColor() end
        if Button.TextColorRGB ~= nil then ImGui.PopStyleColor() end

        if clicked then
            if Button.Unassigned then
                CreateButtonFromCursor(Set, ButtonIndex)
            end
            local cmds = btnUtils.split(Button.Cmd, "\n")
            for i, c in ipairs(cmds) do
                if c:len() > 0 and c:find('^#') == nil and c:find('^[-]+') == nil and c:find('^|') == nil then
                    if c:find('^/') then
                        -- don't use cmdf here because users might have %'s in their commands.
                        mq.cmd(c)
                    else
                        Output('\arInvalid command on Line %d : \ax%s', i, c)
                    end
                    if Button.TimerType == "Seconds Timer" then
                        Button.CooldownTimer = os.clock() + Button.Cooldown
                    end
                else
                    Debug("Ignored: %s", c)
                end
            end
        else
            -- setup drag and drop
            if ImGui.BeginDragDropSource() then
                ImGui.SetDragDropPayload("BTN", ButtonIndex)
                ImGui.Button(Button.Label, btnSize, btnSize)
                ImGui.EndDragDropSource()
            end
            if ImGui.BeginDragDropTarget() then
                local payload = ImGui.AcceptDragDropPayload("BTN")
                if payload ~= nil then
                    ---@diagnostic disable-next-line: undefined-field
                    local num = payload.Data;
                    -- swap the keys in the button set
                    settings.Sets[Set][num], settings.Sets[Set][ButtonIndex] = settings.Sets[Set][ButtonIndex],
                        settings.Sets[Set][num]
                    SaveSettings(true)
                end
                ImGui.EndDragDropTarget()
            end

            -- render button pieces
            --DrawButtonTooltip(Button)
            DrawContextMenu(Set, ButtonIndex, buttonID)
        end

        -- button grid
        if ButtonIndex % cachedCols ~= 0 then ImGui.SameLine() end
    end
end

local function DrawTabs()
    local lockedIcon = settings.Characters[CharConfig].Locked and Icons.FA_LOCK .. '##lockTabButton' or
        Icons.FA_UNLOCK .. '##lockTablButton'
    if ImGui.Button(lockedIcon) then
        --ImGuiWindowFlags.NoMove
        settings.Characters[CharConfig].Locked = not settings.Characters[CharConfig].Locked
        if settings.Characters[CharConfig].Locked then
            SaveSettings(true)
        end
    end
    ImGui.SameLine()
    ImGui.Button("Settings")
    ImGui.SameLine()
    DrawTabContextMenu()
    DrawCreateTab()

    if ImGui.BeginTabBar("Tabs") then
        for i, set in ipairs(settings.Characters[CharConfig].Windows[1].Sets) do
            if ImGui.BeginTabItem(set) then
                SetLabel = set

                -- tab edit popup
                if ImGui.BeginPopupContextItem(set) then
                    ImGui.Text("Edit Name:")
                    local tmp, selected = ImGui.InputText("##edit", set, 0)
                    if selected then name = tmp end
                    if ImGui.Button("Save") then
                        CloseEditPopup()
                        picker:SetClosed()
                        local newSetLabel = name
                        if name ~= nil then
                            -- update the character button set name
                            settings.Characters[CharConfig].Windows[1].Sets[i] = name

                            -- move the old button set to the new name
                            settings.Sets[newSetLabel], settings.Sets[SetLabel] = settings.Sets[SetLabel], nil

                            -- update set names
                            for idx, oldSetName in ipairs(settings.Sets) do
                                if oldSetName == set then
                                    settings.Sets[idx] = name
                                end
                            end

                            -- update other chacters who might have been using this same set.
                            for curCharKey, curCharData in pairs(settings.Characters) do
                                if curCharKey ~= CharConfig then
                                    for setIdx, oldSetName in ipairs(curCharData.Sets) do
                                        if oldSetName == set then
                                            Output(string.format(
                                                "\awUpdating section '\ag%s\aw' renaming \am%s\aw => \at%s", curCharKey,
                                                oldSetName, name))
                                            settings.Characters[curCharKey].Sets[setIdx] = name
                                        end
                                    end
                                end
                            end

                            -- update set to the new name so the button render doesn't fail
                            SetLabel = newSetLabel
                            SaveSettings(true)
                        end
                        ImGui.CloseCurrentPopup()
                    end
                    ImGui.EndPopup()
                end

                DrawButtons(SetLabel)
                ImGui.EndTabItem()
            end
        end
        ImGui.EndTabBar();
    end
end

local function DrawButtonWindow(id, flags)
    ImGui.PushID("##MainWindow_" .. tostring(id))
    openGUI, shouldDrawGUI = ImGui.Begin('Button Master', openGUI, flags)
    lastWindowX, lastWindowY = ImGui.GetWindowPos()

    local theme = settings.Themes and settings.Themes[id] or nil
    local themeStylePop = 0

    if openGUI and shouldDrawGUI then
        if theme ~= nil then
            for _, t in pairs(theme) do
                ImGui.PushStyleColor(ImGuiCol[t.element], t.color.r, t.color.g, t.color.b, t.color.a)
                themeStylePop = themeStylePop + 1
            end
        end
        if initialRun then
            ImGui.SetWindowSize(280, 318)
            initialRun = false
        end
        if updateWindowPosSize then
            updateWindowPosSize = false
            ImGui.SetWindowSize(newWidth, newHeight)
            ImGui.SetWindowPos(newX, newY)
        end

        DrawTabs()
        DrawEditButtonPopup()
        DrawImportButtonPopup()
        picker:DrawIconPicker()
        DisplayItemOnCursor()
    end
    if themeStylePop > 0 then
        ImGui.PopStyleColor(themeStylePop)
    end
    ImGui.End()
    ImGui.PopID()
end

local function ButtonGUI()
    if not openGUI then return end
    local flags = ImGuiWindowFlags.NoFocusOnAppearing
    if not settings.Characters[CharConfig] then return end

    if settings.Characters[CharConfig].Locked then
        flags = bit32.bor(flags, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
    end

    if settings.Characters[CharConfig].HideTitleBar then
        flags = bit32.bor(flags, ImGuiWindowFlags.NoTitleBar)
    end
    if false then
    else
        DrawButtonWindow(1, flags)
    end
end

local function NeedUpgrade()
    return (settings.Version or 0) < 5
end

local function LoadSettings()
    CloseEditPopup()
    picker:SetClosed()

    local config, err = loadfile(settings_path)
    if err or not config then
        local old_settings_path = settings_path:gsub(".lua", ".ini")
        printf("\ayUnable to load global settings file(%s), creating a new one from legacy ini(%s) file!",
            settings_path, old_settings_path)
        if btnUtils.file_exists(old_settings_path) then
            settings = btnUtils.loadINI(old_settings_path)
            SaveSettings(true)
        else
            printf("\ayUnable to load legacy settings file(%s), creating a new config!", old_settings_path)
            settings = {
                Version = 5,
                Global = {
                    ButtonSize = 6,
                    ButtonCount = 4,
                },
                Sets = {
                    ['Primary'] = { 'Button_1', 'Button_2', 'Button_3', },
                    ['Movement'] = { 'Button_4', },
                },
                Buttons = {
                    Button_1 = {
                        Label = 'Burn (all)',
                        Cmd = '/bcaa //burn\n/timed 500 /bcaa //burn',
                    },
                    Button_2 = {
                        Label = 'Pause (all)',
                        Cmd = '/bcaa //multi ; /twist off ; /mqp on',
                    },
                    Button_3 = {
                        Label = 'Unpause (all)',
                        Cmd = '/bcaa //mqp off',
                    },
                    Button_4 = {
                        Label = 'Nav Target (bca)',
                        Cmd = '/bca //nav id ${Target.ID}',
                    },
                },
                Characters = {
                    [CharConfig] = {
                        Windows = { [1] = { Visible = true, Sets = {}, }, },
                        Locked = false,
                    },
                },
            }
            SaveSettings(true)
        end
    else
        settings = config()
    end

    -- if we need to upgrade anyway then bail after the load.
    if NeedUpgrade() then return end

    -- if this character doesn't have the sections in the config, create them
    if settings.Characters[CharConfig] == nil then
        if not settings.Defaults then
            settings.Characters[CharConfig] = { Version = 4, Windows = { [1] = { Visible = true, Sets = {}, }, }, Locked = false, } -- use user defined Defaults before hardcoded ones.
        else
            updateWindowPosSize = true
            newWidth = (tonumber(settings.Defaults.width) or 100)
            newHeight = (tonumber(settings.Defaults.height) or 100)
            newX = (tonumber(settings.Defaults.x) or 0)
            newY = (tonumber(settings.Defaults.y) or 0)
            settings.Characters[CharConfig] = settings.Defaults.CharSettings
        end
        initialRun = true
        SaveSettings(true)
    end

    settings.Characters[CharConfig].Locked       = settings.Characters[CharConfig].Locked or false
    settings.Characters[CharConfig].HideTitleBar = settings.Characters[CharConfig].HideTitleBar or false
end

local function ConvertToLatestConfigVersion()
    LoadSettings()
    local needsSave = false
    -- version 2
    -- Run through all settings and make sure they are in the new format.
    for key, value in pairs(settings or {}) do
        -- TODO: Make buttons a seperate table instead of doing the string compare crap.
        if type(value) == 'table' then
            if key:find("^(Button_)") and value.Cmd1 or value.Cmd2 or value.Cmd3 or value.Cmd4 or value.Cmd5 then
                Output("Key: %s Needs Converted!", key)
                value.Cmd  = string.format("%s\n%s\n%s\n%s\n%s\n%s", value.Cmd or '', value.Cmd1 or '', value.Cmd2 or '',
                    value.Cmd3 or '', value.Cmd4 or '', value.Cmd5 or '')
                value.Cmd  = value.Cmd:gsub("\n+", "\n")
                value.Cmd  = value.Cmd:gsub("\n$", "")
                value.Cmd  = value.Cmd:gsub("^\n", "")
                value.Cmd1 = nil
                value.Cmd2 = nil
                value.Cmd3 = nil
                value.Cmd4 = nil
                value.Cmd5 = nil
                needsSave  = true
                Output("\atUpgraded to \amv2\at!")
            end
        end
    end

    -- version 3
    -- Okay now that a similar but lua-based config is stabalized the next pass is going to be
    -- cleaning up the data model so we aren't doing a ton of string compares all over.
    local newSettings = {}
    newSettings.Buttons = {}
    newSettings.Sets = {}
    newSettings.Characters = {}
    newSettings.Global = settings.Global
    for key, value in pairs(settings) do
        local sStart, sEnd = key:find("^Button_")
        if sStart then
            local newKey = key --key:sub(sEnd + 1)
            Output("Old Key: \am%s\ax, New Key: \at%s\ax", key, newKey)
            newSettings.Buttons[newKey] = newSettings.Buttons[newKey] or {}
            for subKey, subValue in pairs(value) do
                newSettings.Buttons[newKey][subKey] = tostring(subValue)
            end
            needsSave = true
        end
        sStart, sEnd = key:find("^Set_")
        if sStart then
            local newKey = key:sub(sEnd + 1)
            Output("Old Key: \am%s\ax, New Key: \at%s\ax", key, newKey)
            newSettings.Sets[newKey] = value
            needsSave                = true
        end
        sStart, sEnd = key:find("^Char_(.*)_Config")
        if sStart then
            local newKey = key:sub(sStart + 5, sEnd - 7)
            Output("Old Key: \am%s\ax, New Key: \at%s\ax", key, newKey)
            newSettings.Characters[newKey] = newSettings.Characters[newKey] or {}
            for subKey, subValue in pairs(value) do
                newSettings.Characters[newKey].Sets = newSettings.Characters[newKey].Sets or {}
                if type(subKey) == "number" then
                    table.insert(newSettings.Characters[newKey].Sets, subValue)
                else
                    newSettings.Characters[newKey][subKey] = subValue
                end
            end

            needsSave = true
        end
    end

    if needsSave then
        -- be nice and make a backup.
        mq.pickle(mq.configDir .. "/ButtonMaster-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua", settings)
        settings = newSettings
        SaveSettings(true)
        needsSave = false
        Output("\atUpgraded to \amv3\at!")
    end

    -- version 4 same as 5 but moved the version data around
    -- version 5
    -- Move Character sets to a specific window name
    if (settings.Version or 0) < 5 then
        needsSave = true
        newSettings = settings
        newSettings.Version = 5
        print(settings.Characters)
        for charKey, _ in pairs(settings.Characters) do
            if settings.Characters[charKey] and settings.Characters[charKey].Sets ~= nil then
                newSettings.Characters[charKey].Windows = {}
                table.insert(newSettings.Characters[charKey].Windows,
                    { Sets = newSettings.Characters[charKey].Sets, Visible = true, })
                newSettings.Characters[charKey].Sets = nil
                needsSave = true
            end
        end
        if needsSave then
            -- be nice and make a backup.
            mq.pickle(mq.configDir .. "/ButtonMaster-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua", settings)
            settings = newSettings
            SaveSettings(true)
            Output("\atUpgraded to \amv5\at!")
        end
    end
end

local function Setup()
    LoadSettings()
    Output('\ayButton Master v2 by (\a-to_O\ay) Derple, Special.Ed (\a-to_O\ay) - \atLoaded ' .. settings_path)

    mq.imgui.init('ButtonGUI', ButtonGUI)
    mq.bind('/btn', BindBtn)
end

local args = ... or ""
if args:lower() == "upgrade" then
    ConvertToLatestConfigVersion()
    mq.exit()
end

local function Loop()
    while mq.TLO.MacroQuest.GameState() == "INGAME" do
        mq.delay(10)
        if reloadSettings then
            reloadSettings = false
            LoadSettings()
        end
    end
    Output('\arNot in game, stopping button master.\ax')
end

-- Global Messaging callback
---@diagnostic disable-next-line: unused-local
local script_actor = ButtonActors.register(function(message)
    local msg = message()

    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    Debug("MSG! " .. msg["script"] .. " " .. msg["from"])

    if msg["from"] == mq.TLO.Me.DisplayName() then
        return
    end
    if msg["script"] ~= "ButtonMaster" then
        return
    end

    Output("\ayGot Event from(\am%s\ay) event(\at%s\ay)", msg["from"], msg["event"])

    if msg["event"] == "SaveSettings" then
        reloadSettings = true
    elseif msg["event"] == "CopyLoc" then
        updateWindowPosSize = true
        newWidth = (tonumber(msg["width"]) or 100)
        newHeight = (tonumber(msg["height"]) or 100)
        newX = (tonumber(msg["x"]) or 0)
        newY = (tonumber(msg["y"]) or 0)
        settings.Characters[CharConfig].HideTitleBar = msg["hideTitleBar"]

        Debug("\agReplicating dimentions: \atw\ax(\am%d\ax) \ath\ax(\am%d\ax) \atx\ax(\am%d\ax) \aty\ax(\am%d\ax)",
            newWidth,
            newHeight, newX,
            newY)
    end
end)

Setup()

if NeedUpgrade() then
    Output("\awButton Master Needs to upgrade! Please Run: \at'/lua run buttonmaster upgrade'\ay on a single character to upgrade and then try again!")
    mq.exit()
end

Loop()
