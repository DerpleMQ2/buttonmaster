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

local version          = "2.3"
local mq               = require('mq')

ButtonActors           = require 'actors'
Icons                  = require('mq.ICONS')
BMSettings             = require('bmSettings').new()
BMEditPopup            = require('bmEditButtonPopup')

local BMHotbarClass    = require('bmHotbarClass')
local btnUtils         = require('lib.buttonUtils')
local BMButtonHandlers = require('bmButtonHandlers')

-- globals
BMHotbars              = {}
BMReloadSettings       = false
BMUpdateSettings       = false
BMCopy                 = false
BMCopyKey              = nil
-- [[ UI ]] --
local openGUI          = true

-- binds
local function BindBtn(num)
    if not num then num = 1 else num = (tonumber(num) or 1) end
    if BMHotbars[num] then
        BMHotbars[num]:ToggleVisible()
    end
end

-- function CopyLocalSet(key)
--     local newTable = btnUtils.deepcopy(BMSettings:GetSettings().Characters[key])
--     BMSettings:GetSettings().Characters[BMSettings.CharConfig] = newTable
--     BMSettings:SaveSettings(true)
--     BMSettings:UpdateCharacterDB(BMSettings.CharConfig, BMSettings:GetCharConfig())
--     BMUpdateSettings = true
-- end

function CopyLocalSet(key)
    local db = BMSettings:InitializeDB()
    local newCharacterData = {
        Locked = false,
        HideTitleBar = false,
        Windows = {},
    }

    -- Retrieve character data from the `characters` table
    local charData = BMSettings:loadFromDB(db, "SELECT character_locked, character_hide_title FROM characters WHERE character = ?", key)
    if #charData > 0 then
        newCharacterData.Locked = charData[1].character_locked == 1
        newCharacterData.HideTitleBar = charData[1].character_hide_title == 1
    end

    -- Retrieve window data from the `windows` table for the specified character
    local windowsData = BMSettings:loadFromDB(db, "SELECT * FROM windows WHERE character = ?", key)
    for _, window in ipairs(windowsData) do
        local windowID = window.window_id
        newCharacterData.Windows[windowID] = newCharacterData.Windows[windowID] or { Sets = {}, }
        local win = newCharacterData.Windows[windowID]

        -- Populate window properties
        win.FPS = window.window_fps
        win.ButtonSize = window.window_button_size
        win.AdvTooltips = window.window_advtooltip == 1
        win.CompactMode = window.window_compact == 1
        win.HideTitleBar = window.window_hide_title == 1
        win.Width = window.window_width
        win.Height = window.window_height
        win.Pos = { x = window.window_x, y = window.window_y, }
        win.Visible = window.window_visible == 1
        win.Font = window.window_font_size
        win.Locked = window.window_locked == 1
        win.Theme = window.window_theme
        win.Sets[window.window_set_id] = window.window_set_name
    end

    db:close()

    -- Deep-copy the retrieved data into the current character settings
    BMSettings:GetSettings().Characters[BMSettings.CharConfig] = btnUtils.deepcopy(newCharacterData)

    -- Save and update the settings in the database
    BMSettings:SaveSettings(true)
    BMSettings:updateCharacterDB(BMSettings.CharConfig, BMSettings:GetCharConfig())
    BMUpdateSettings = true
end

local function BindBtnCopy(server, character)
    if not server or not character then return end

    local cname = character:sub(1, 1):upper() .. character:sub(2)
    local key = server:lower() .. "_" .. cname
    if not BMSettings:GetSettings().Characters[key] then
        btnUtils.Output("\arError: \ayProfile: \at%s\ay not found!", key)
        return
    end

    -- CopyLocalSet(key)
    BMCopy = true
    BMCopyKey = key
end

local function BindBtnExec(set, index)
    if not set or not index then
        btnUtils.Output("\agUsage\aw: \am/btnexec \aw<\at\"set\"\aw> \aw<\atindex\aw>")
        return
    end

    index = tonumber(index) or 0
    local Button = BMSettings:GetButtonBySetIndex(set, index)

    if Button.Unassigned then
        btnUtils.Output("\arError\aw: \amSet: \at'%s' \amButtonIndex: \at%d \awIs Not Assigned!", set, index)
        for s, data in pairs(BMSettings:GetSettings().Sets) do
            btnUtils.Output("\awSet: \at%s", s)
            for i, b in ipairs(data) do
                btnUtils.Output("\t \aw[\at%d\aw] \am%s", i, b)
            end
        end
        return
    end

    btnUtils.Output("\agRunning\aw: \amSet: \at%s \amButtonIndex: \at%d \aw:: \at%s", set, index, Button.Label)
    BMButtonHandlers.Exec(Button)
end

local function ButtonGUI()
    if not openGUI then return end
    if not BMSettings:GetCharConfig() then return end

    -- Set this way up here so the theme can override.
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.9, 0.9, 0.5)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.9, 0.9, 0.9, 0.0)
    if BMHotbars ~= nil then
        for hotbarId, bmHotbar in ipairs(BMHotbars) do
            if BMSettings:GetCharacterWindow(hotbarId) ~= nil then
                local hideTitleBar = BMSettings:GetCharacterWindow(hotbarId).HideTitleBar ~= nil and BMSettings:GetCharacterWindow(hotbarId).HideTitleBar or false
                local locked = BMSettings:GetCharacterWindow(hotbarId).Locked ~= nil and BMSettings:GetCharacterWindow(hotbarId).Locked or false
                local hideScrollbar = BMSettings:GetCharacterWindow(hotbarId).HideScrollbar ~= nil and BMSettings:GetCharacterWindow(hotbarId).HideScrollbar or false
                local flags = ImGuiWindowFlags.NoFocusOnAppearing
                if hideTitleBar then
                    flags = bit32.bor(flags, ImGuiWindowFlags.NoTitleBar)
                end
                if locked then
                    flags = bit32.bor(flags, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
                end
                if hideScrollbar then
                    flags = bit32.bor(flags, ImGuiWindowFlags.NoScrollbar)
                end
                bmHotbar:RenderHotbar(flags)
            end
        end
    end
    BMEditPopup:RenderEditButtonPopup()
    ImGui.PopStyleColor(2)
end

local function Setup()
    if not BMSettings:LoadSettings() then return end

    BMHotbars = {}

    for idx, _ in ipairs(BMSettings:GetCharConfig().Windows or {}) do
        table.insert(BMHotbars, BMHotbarClass.new(idx, false))
    end

    if #BMHotbars == 0 then
        table.insert(BMHotbars, BMHotbarClass.new(1, true))
    end

    BMEditPopup:CloseEditPopup()
    btnUtils.Output('\ayButton Master v%s by (\a-to_O\ay) Derple, Special.Ed (\a-to_O\ay) - \atLoaded!', version)
end

local args = ... or ""
if args:lower() == "upgrade" then
    BMSettings:ConvertToLatestConfigVersion()
    mq.exit()
end

local function GiveTime()
    while mq.TLO.MacroQuest.GameState() == "INGAME" do
        mq.delay(10)
        if BMCopy then
            BMCopy = false
            CopyLocalSet(BMCopyKey)
            BMCopyKey = nil
        end

        if BMReloadSettings then
            BMReloadSettings = false
            BMSettings:LoadSettings()
        end

        if BMUpdateSettings then
            BMUpdateSettings = false

            Setup()

            for _, bmHotbar in ipairs(BMHotbars) do
                bmHotbar:ReloadConfig()
            end
        end

        if #BMHotbars > 0 then
            for _, bmHB in ipairs(BMHotbars) do
                if bmHB:IsVisible() then
                    bmHB:GiveTime()
                end
            end
        end
    end
    btnUtils.Output('\arNot in game, stopping button master.\ax')
end

-- Global Messaging callback
---@diagnostic disable-next-line: unused-local
local script_actor = ButtonActors.register(function(message)
    local msg = message()

    if mq.TLO.MacroQuest.GameState() ~= "INGAME" then return end

    btnUtils.Debug("MSG! " .. msg["script"] .. " " .. msg["from"])

    if msg["from"] == mq.TLO.Me.DisplayName() then
        return
    end
    if msg["script"] ~= "ButtonMaster" then
        return
    end

    btnUtils.Output("\ayGot Event from(\am%s\ay) event(\at%s\ay)", msg["from"], msg["event"])

    if msg["event"] == "SaveSettings" then
        btnUtils.Debug("Got new settings:\n%s", btnUtils.dumpTable(msg.newSettings))
        BMSettings.settings = msg.newSettings
    elseif msg["event"] == "CopyLoc" then
        if msg.windowId <= #BMHotbars then
            BMHotbars[msg.windowId]:UpdatePosition((tonumber(msg["width"]) or 100), (tonumber(msg["height"]) or 100), (tonumber(msg["x"]) or 0), (tonumber(msg["y"]) or 0),
                msg["hideTitleBar"], msg["compactMode"])
            btnUtils.Debug("\agReplicating dimentions: \atw\ax(\am%d\ax) \ath\ax(\am%d\ax) \atx\ax(\am%d\ax) \aty\ax(\am%d\ax)",
                BMSettings.Globals.newWidth,
                BMSettings.Globals.newHeight,
                BMSettings.Globals.newX,
                BMSettings.Globals.newY)
        else
            btnUtils.Output("\ayFailed to replicate dimentions, you don't have a window id = %d", msg.windowId)
        end
    end
end)

Setup()

if BMSettings:NeedUpgrade() then
    btnUtils.Output("\awButton Master Needs to upgrade! Please Run: \at'/lua run buttonmaster upgrade'\ay on a single character to upgrade and then try again!")
    mq.exit()
end

-- Make sure to start after the settings are validated.
mq.imgui.init('ButtonGUI', ButtonGUI)
mq.bind('/btn', BindBtn)
mq.bind('/btnexec', BindBtnExec)
mq.bind('/btncopy', BindBtnCopy)

GiveTime()
