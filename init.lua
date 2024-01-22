--[[
    Created by Special.Ed
    Shout out to the homies:
        Lads
        Dannuic (my on again off again thing)
        Knightly (no, i won't take that bet)
    Thanks to the testers:
        Shwebro, Kevbro, RYN
--]]

local mq = require('mq')
local LIP = require('lib/LIP')
local Icons = require('mq.ICONS')
require('lib/ed/utils')

ButtonActors = require 'actors'

-- globals
local CharConfig = 'Char_' .. mq.TLO.EverQuest.Server() .. '_' .. mq.TLO.Me.CleanName() .. '_Config'
local DefaultSets = { 'Primary', 'Movement', }
local openGUI = true
local shouldDrawGUI = true
local initialRun = false
local updateWindowPosSize = false
local newWidth = 0
local newHeight = 0
local newX = 0
local newY = 0
local cachedRows = 0
local cachedCols = 0
local tmpButton = {}
local btnColor = {}
local txtColor = {}
local lastWindowHeight = 0
local lastWindowWidth = 0
local lastWindowX = 0
local lastWindowY = 0
local visibleButtonCount = 0
local editTabPopup = "edit_tab_popup"
local name
local settings_path = mq.configDir .. '/ButtonMaster.lua'
local settings = {}
local editButtonPopupOpen = false
local editButtonSet = ""
local editButtonIndex = 0
local editButtonTextChanged = false
local buttonSizeDirty = false

-- helpers
local Output = function(msg) print('\aw[' .. mq.TLO.Time() .. '] [\aoButton Master\aw] ::\a-t ' .. msg) end

local function SaveSettings(doBroadcast)
    if doBroadcast == nil then doBroadcast = true end

    mq.pickle(settings_path, settings)

    if doBroadcast then
        Output(string.format("\aySent Event from(\am%s\ay) event(\at%s\ay)", mq.TLO.Me.DisplayName(), "SaveSettings"))
        ButtonActors.send({ from = mq.TLO.Me.DisplayName(), script = "ButtonMaster", event = "SaveSettings", })
    end
end

-- binds
local BindBtn = function()
    openGUI = not openGUI
end

local GetButtonBySetIndex = function(Set, Index)
    return settings[settings[Set][Index]] or { Unassigned = true, Label = tostring(Index), }
end

local GetButtonSectionKeyBySetIndex = function(Set, Index)
    local key = settings[Set][Index]

    -- if the key doesn't exist, get the current button counter and add 1
    if key == nil then
        key = 'Button_' .. tonumber(settings['Global']['ButtonCount'] + 1)
    end
    return key
end

local DrawButtonTooltip = function(Button)
    -- hover tooltip
    if Button.Unassigned == nil and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(Button.Label)
        ImGui.EndTooltip()
    end
end

local RecalculateVisibleButtons = function(Set)
    buttonSizeDirty = false
    lastWindowWidth = ImGui.GetWindowWidth()
    lastWindowHeight = ImGui.GetWindowHeight()

    local cursorX, cursorY = ImGui.GetCursorPos() -- this will get us the x pos we start at which tells us of the offset from the main window border
    local style = ImGui.GetStyle()                -- this will get us ItemSpacing.x which is the amount of space between buttons

    -- global button configs
    local btnSize = (settings['Global']['ButtonSize'] or 6) * 10
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

local DrawTabContextMenu = function()
    local openPopup = false

    local max = 1
    local unassigned = {}
    local keys = {}
    for k, v in ipairs(settings[CharConfig]) do
        keys[v] = true
        max = k + 1
    end
    for k, v in pairs(settings['Sets']) do
        if keys[v] == nil then unassigned[k] = v end
    end

    if ImGui.BeginPopupContextItem() then
        if getTableSize(unassigned) > 0 then
            if ImGui.BeginMenu("Add Set") then
                for k, v in pairs(unassigned) do
                    if ImGui.MenuItem(v) then
                        settings[CharConfig][max] = v
                        SaveSettings()
                        break
                    end
                end
                ImGui.EndMenu()
            end
        end

        if ImGui.BeginMenu("Remove Set") then
            for i, v in ipairs(settings[CharConfig]) do
                if ImGui.MenuItem(v) then
                    table.remove(settings[CharConfig], i)
                    SaveSettings()
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Create New") then
            openPopup = true
        end

        if ImGui.BeginMenu("Button Size") then
            for i = 3, 10 do
                local checked = settings['Global']['ButtonSize'] == i
                if ImGui.MenuItem(tostring(i), nil, checked) then
                    settings['Global']['ButtonSize'] = i
                    buttonSizeDirty = true
                    SaveSettings()
                    break
                end
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
            })
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
                local checked = settings['Global']['Font'] == v.size
                if ImGui.MenuItem(v.label, nil, checked) then
                    settings['Global']['Font'] = v.size
                    SaveSettings()
                    break
                end
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

local DrawCreateTab = function()
    if ImGui.BeginPopup(editTabPopup) then
        ImGui.Text("New Button Set:")
        local tmp, selected = ImGui.InputText("##edit", '', 0)
        if selected then name = tmp end
        if ImGui.Button("Save") then
            if name ~= nil and name:len() > 0 then
                settings[CharConfig][getTableSize(settings[CharConfig]) + 1] =
                    name -- update the character button set name
                settings['Sets'][getTableSize(settings['Sets']) + 1] = name
                settings['Set_' .. name] = {}
                SaveSettings()
            else
                Output("\arError Saving Set: Name cannot be empty.\ax")
            end
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

local DrawContextMenu = function(Set, Index)
    local openPopup = false
    local Button = GetButtonBySetIndex(Set, Index)

    local unassigned = {}
    local keys = {}
    for _, v in pairs(settings[Set]) do keys[v] = true end
    for k, v in pairs(settings) do
        if k:find("^(Button_)") and keys[k] == nil then
            unassigned[k] = v
        end
    end

    if ImGui.BeginPopupContextItem() then
        --editPopupName = "edit_button_popup|" .. Index

        -- only list hotkeys that aren't already assigned to the button set
        if getTableSize(unassigned) > 0 then
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
                            settings[Set][Index] = key
                            SaveSettings()
                            break
                        end
                    end
                end
                -- hytiek: END ADD
                --[[ original display code:
                    for k, v in pairs(unassigned) do
                    if ImGui.MenuItem(v.Label) then
                        settings[Set][Index] = k
                        SaveSettings()
                        break
                    end
                end
                ]]
                --

                ImGui.EndMenu()
            end
        end

        -- only show create new for unassigned buttons
        if Button.Unassigned == true then
            if ImGui.MenuItem("Create New") then
                editButtonPopupOpen = true
                editButtonIndex = Index
                editButtonSet = Set
            end
        end

        -- only show edit & unassign for assigned buttons
        if Button.Unassigned == nil then
            if ImGui.MenuItem("Edit") then
                editButtonPopupOpen = true
                editButtonIndex = Index
                editButtonSet = Set
            end
            if ImGui.MenuItem("Unassign") then
                settings[Set][Index] = nil
                SaveSettings()
            end
        end

        ImGui.EndPopup()
    end
end

local DrawEditButtonPopup = function()
    if not editButtonPopupOpen then return end

    local ButtonKey = GetButtonSectionKeyBySetIndex(editButtonSet, editButtonIndex)
    local Button = GetButtonBySetIndex(editButtonSet, editButtonIndex)
    local shouldDrawEditPopup = false

    editButtonPopupOpen, shouldDrawEditPopup = ImGui.Begin("Edit Button", editButtonPopupOpen,
        editButtonTextChanged and ImGuiWindowFlags.UnsavedDocument or ImGuiWindowFlags.None)
    if editButtonPopupOpen and shouldDrawEditPopup then
        -- shallow copy original button incase we want to reset (close)
        if tmpButton[ButtonKey] == nil then
            tmpButton[ButtonKey] = shallowcopy(Button)
        end

        -- color pickers
        if tmpButton[ButtonKey].ButtonColorRGB ~= nil then
            local tColors = split(tmpButton[ButtonKey].ButtonColorRGB, ",")
            for i, v in ipairs(tColors) do btnColor[i] = tonumber(v / 255) end
        end
        local col, used = ImGui.ColorEdit3("Button Color", btnColor, ImGuiColorEditFlags.NoInputs)
        if used then
            editButtonTextChanged = true
            btnColor = shallowcopy(col)
            tmpButton[ButtonKey].ButtonColorRGB = string.format("%d,%d,%d", math.floor(col[1] * 255),
                math.floor(col[2] * 255), math.floor(col[3] * 255))
        end
        ImGui.SameLine()
        if tmpButton[ButtonKey].TextColorRGB ~= nil then
            local tColors = split(tmpButton[ButtonKey].TextColorRGB, ",")
            for i, v in ipairs(tColors) do txtColor[i] = tonumber(v / 255) end
        end
        col, used = ImGui.ColorEdit3("Text Color", txtColor, ImGuiColorEditFlags.NoInputs)
        if used then
            editButtonTextChanged = true
            txtColor = shallowcopy(col)
            tmpButton[ButtonKey].TextColorRGB = string.format("%d,%d,%d", math.floor(col[1] * 255),
                math.floor(col[2] * 255), math.floor(col[3] * 255))
        end

        -- color reset
        ImGui.SameLine()
        if ImGui.Button("Reset") then
            btnColor, txtColor = {}, {}
            tmpButton[ButtonKey].ButtonColorRGB = nil
            tmpButton[ButtonKey].TextColorRGB = nil
            editButtonTextChanged = true
        end

        local textChanged
        tmpButton[ButtonKey].Label, textChanged = ImGui.InputText('Button Label', tmpButton[ButtonKey].Label or '')
        editButtonTextChanged = editButtonTextChanged or textChanged

        local xPos = ImGui.GetCursorPosX()
        local footerHeight = 110
        local editHeight = ImGui.GetWindowHeight() - xPos - footerHeight
        tmpButton[ButtonKey].Cmd, textChanged = ImGui.InputTextMultiline("##_Cmd_Edit", tmpButton[ButtonKey].Cmd or "", ImVec2(ImGui.GetWindowWidth() * 0.98, editHeight))
        editButtonTextChanged = editButtonTextChanged or textChanged

        -- save button
        if ImGui.Button("Save") then
            -- make sure the button label isn't nil/empty/spaces
            if tmpButton[ButtonKey].Label ~= nil and tmpButton[ButtonKey].Label:gsub("%s+", ""):len() > 0 then
                settings[editButtonSet][editButtonIndex] = ButtonKey    -- add the button key for this button set index
                settings[ButtonKey] = shallowcopy(tmpButton[ButtonKey]) -- store the tmp button into the settings table
                settings[ButtonKey].Unassigned = nil                    -- clear the unassigned flag
                -- if we're saving this, update the button counter
                settings['Global']['ButtonCount'] = settings['Global']['ButtonCount'] + 1
                SaveSettings()
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
            tmpButton[ButtonKey] = shallowcopy(Button)
            editButtonPopupOpen = false
            editButtonIndex = 0
            editButtonSet = ""
        end

        ImGui.SameLine()

        local clearClick = ImGui.Button("Clear")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Clear hotbutton fields")
            ImGui.EndTooltip()
        end
        if clearClick then
            tmpButton[ButtonKey] = nil                     -- clear the buffer
            settings[editButtonSet][editButtonIndex] = nil -- clear the button set index
        end
    end
    ImGui.End()
end

local DrawButtons = function(Set)
    if ImGui.GetWindowWidth() ~= lastWindowWidth or ImGui.GetWindowHeight() ~= lastWindowHeight or buttonSizeDirty then
        RecalculateVisibleButtons(Set)
    end

    local btnSize = (settings['Global']['ButtonSize'] or 6) * 10

    local renderButtonCount = visibleButtonCount

    for ButtonIndex = 1, renderButtonCount do
        local Button = GetButtonBySetIndex(Set, ButtonIndex)

        -- push button styles if configured
        if Button.ButtonColorRGB ~= nil then
            local Colors = split(Button.ButtonColorRGB, ",")
            ImGui.PushStyleColor(ImGuiCol.Button, tonumber(Colors[1] / 255), tonumber(Colors[2] / 255),
                tonumber(Colors[3] / 255), 1)
        end
        if Button.TextColorRGB ~= nil then
            local Colors = split(Button.TextColorRGB, ",")
            ImGui.PushStyleColor(ImGuiCol.Text, tonumber(Colors[1] / 255), tonumber(Colors[2] / 255),
                tonumber(Colors[3] / 255), 1)
        end

        ImGui.SetWindowFontScale(settings['Global']['Font'] or 1)
        local clicked = ImGui.Button(tostring(Button.Label):gsub(" ", "\n"), btnSize, btnSize)
        ImGui.SetWindowFontScale(1)

        -- pop button styles as necessary
        if Button.ButtonColorRGB ~= nil then ImGui.PopStyleColor() end
        if Button.TextColorRGB ~= nil then ImGui.PopStyleColor() end

        if clicked then
            local cmds = split(Button.Cmd, "\n")
            for i, c in ipairs(cmds) do
                if c:find('^/') then
                    mq.cmdf(c)
                else
                    Output(string.format('\arInvalid command on Line %d : \ax%s', i, c))
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
                    settings[Set][num], settings[Set][ButtonIndex] = settings[Set][ButtonIndex], settings[Set][num]
                    SaveSettings()
                end
                ImGui.EndDragDropTarget()
            end

            -- render button pieces
            DrawButtonTooltip(Button)
            DrawContextMenu(Set, ButtonIndex)
        end

        -- button grid
        if ButtonIndex % cachedCols ~= 0 then ImGui.SameLine() end
    end
end

local DrawTabs = function()
    local Set
    local lockedIcon = settings[CharConfig].Locked and Icons.FA_LOCK .. '##lockTabButton' or Icons.FA_UNLOCK .. '##lockTablButton'
    if ImGui.Button(lockedIcon) then
        --ImGuiWindowFlags.NoMove
        settings[CharConfig].Locked = not settings[CharConfig].Locked
        if settings[CharConfig].Locked then
            SaveSettings(true)
        end
    end
    ImGui.SameLine()
    ImGui.Button("Settings")
    ImGui.SameLine()
    DrawTabContextMenu()
    DrawCreateTab()

    if ImGui.BeginTabBar("Tabs") then
        for i, set in ipairs(settings[CharConfig]) do
            if ImGui.BeginTabItem(set) then
                Set = 'Set_' .. set

                -- tab edit popup
                if ImGui.BeginPopupContextItem() then
                    ImGui.Text("Edit Name:")
                    local tmp, selected = ImGui.InputText("##edit", set, 0)
                    if selected then name = tmp end
                    if ImGui.Button("Save") then
                        if name ~= nil then
                            settings[CharConfig][i] =
                                name -- update the character button set name
                            settings['Set_' .. name], settings[Set] = settings[Set],
                                nil  -- move the old button set to the new name
                            Set = 'Set_' ..
                                name -- update set to the new name so the button render doesn't fail
                            SaveSettings()
                        end
                        ImGui.CloseCurrentPopup()
                    end
                    ImGui.EndPopup()
                end

                DrawButtons(Set)
                ImGui.EndTabItem()
            end
        end
        ImGui.EndTabBar();
    end
end

local ButtonGUI = function()
    if not openGUI then return end
    local flags = ImGuiWindowFlags.NoFocusOnAppearing
    if not settings[CharConfig] then return end

    if settings[CharConfig].Locked then flags = bit32.bor(flags, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize) end

    openGUI, shouldDrawGUI = ImGui.Begin('Button Master', openGUI, flags)
    lastWindowX, lastWindowY = ImGui.GetWindowPos()

    if openGUI and shouldDrawGUI then
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
    end
    ImGui.End()
end

local function convertOldStyleToNew()
    local needsSave = false
    -- Run through all settings and make sure they are in the new format.
    for key, value in pairs(settings) do
        -- TODO: Make buttons a seperate table instead of doing the string compare crap.
        if key:find("^(Button_)") and value.Cmd1 or value.Cmd2 or value.Cmd3 or value.Cmd4 or value.Cmd5 then
            Output(string.format("Key: %s Needs Converted!", key))
            value.Cmd  = string.format("%s\n%s\n%s\n%s\n%s\n%s", value.Cmd or '', value.Cmd1 or '', value.Cmd2 or '', value.Cmd3 or '', value.Cmd4 or '', value.Cmd5 or '')
            value.Cmd  = value.Cmd:gsub("\n+", "\n")
            value.Cmd  = value.Cmd:gsub("\n$", "")
            value.Cmd  = value.Cmd:gsub("^\n", "")
            value.Cmd1 = nil
            value.Cmd2 = nil
            value.Cmd3 = nil
            value.Cmd4 = nil
            value.Cmd5 = nil
            needsSave  = true
        end
    end
    if needsSave then
        SaveSettings(false)
    end
end

local function LoadSettings()
    local config, err = loadfile(settings_path)
    if err or not config then
        local old_settings_path = settings_path:gsub(".lua", ".ini")
        printf("\ayUnable to load global settings file(%s), creating a new one from legacy ini(%s) file!",
            settings_path, old_settings_path)
        if file_exists(old_settings_path) then
            settings = LIP.load(old_settings_path)

            -- fix up any numerical labels.
            for key, value in pairs(settings) do
                if type(value['Label']) == 'number' then
                    Output(string.format("\ayDetected a numerical label on button %s - changing it to a string!", key))
                    -- this is not valid all labels should be stirngs.
                    value.Label = tostring(value.Label)
                end
            end

            SaveSettings(false)
        else
            printf("\ayUnable to load legacy settings file(%s), creating a new config!", old_settings_path)
            settings = {
                Global = {
                    ButtonSize = 6,
                    ButtonCount = 4,
                },
                Sets = { 'Primary', 'Movement', },
                Set_Primary = { 'Button_1', 'Button_2', 'Button_3', },
                Set_Movement = { 'Button_4', },
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
                [CharConfig] = DefaultSets,
            }
            SaveSettings()
        end
    else
        settings = config()
    end

    -- if this character doesn't have the sections in the ini, create them
    if settings[CharConfig] == nil then
        settings[CharConfig] = settings.DefaultSets or DefaultSets -- use user defined Defaults before hardcoded ones.
        initialRun = true
        SaveSettings()
    end

    settings[CharConfig].Locked = settings[CharConfig].Locked or false

    -- Convert old Cmd1-5 buttons to new Cmd style
    convertOldStyleToNew()
end

local Setup = function()
    LoadSettings()
    Output('\ayButton Master by (\a-to_O\ay) Special.Ed, Derple (\a-to_O\ay) - \atLoaded ' .. settings_path)

    mq.imgui.init('ButtonGUI', ButtonGUI)
    mq.bind('/btn', BindBtn)
end

local CheckGameState = function()
    if mq.TLO.MacroQuest.GameState() ~= 'INGAME' then
        Output('\arNot in game, stopping button master.\ax')
        mq.exit()
    end
end

local Loop = function()
    while true do
        CheckGameState()
        mq.delay(10)
    end
end

-- Global Messaging callback
---@diagnostic disable-next-line: unused-local
local script_actor = ButtonActors.register(function(message)
    local msg = message()

    Output("MSG! " .. msg["script"] .. " " .. msg["from"])

    if msg["from"] == mq.TLO.Me.DisplayName() then
        return
    end
    if msg["script"] ~= "ButtonMaster" then
        return
    end

    ---@diagnostic disable-next-line: redundant-parameter
    Output(string.format("\ayGot Event from(\am%s\ay) event(\at%s\ay)", msg["from"], msg["event"]))

    if msg["event"] == "SaveSettings" then
        LoadSettings()
    elseif msg["event"] == "CopyLoc" then
        updateWindowPosSize = true
        newWidth = (tonumber(msg["width"]) or 100)
        newHeight = (tonumber(msg["height"]) or 100)
        newX = (tonumber(msg["x"]) or 0)
        newY = (tonumber(msg["y"]) or 0)

        printf("\agReplicating dimentions: \atw\ax(\am%d\ax) \ath\ax(\am%d\ax) \atx\ax(\am%d\ax) \aty\ax(\am%d\ax)",
            newWidth,
            newHeight, newX,
            newY)
    end
end)

Setup()
Loop()
