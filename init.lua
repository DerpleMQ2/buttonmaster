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

local version        = "2.3"
local mq             = require('mq')

ButtonActors         = require 'actors'
Icons                = require('mq.ICONS')
BMSettings           = require('bmSettings').new()
BMEditPopup          = require('bmEditButtonPopup')

local BMHotbarClass  = require('bmHotbarClass')
local btnUtils       = require('lib.buttonUtils')

-- globals
BMHotbars            = {}

-- [[ UI ]] --
local openGUI        = true
local reloadSettings = false

-- binds
local function BindBtn(num)
    if not num then num = 1 else num = (tonumber(num) or 1) end
    if BMHotbars[num] then
        BMHotbars[num]:ToggleVisible()
    end
end

local function ButtonGUI()
    if not openGUI then return end
    if not BMSettings:GetCharConfig() then return end

    -- Set this way up here so the theme can override.
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.9, 0.9, 0.9, 0.5)
    ImGui.PushStyleColor(ImGuiCol.HeaderHovered, 0.9, 0.9, 0.9, 0.0)
    for hotbarId, bmHotbar in ipairs(BMHotbars) do
        local flags = ImGuiWindowFlags.NoFocusOnAppearing
        if BMSettings:GetCharacterWindow(hotbarId).HideTitleBar then
            flags = bit32.bor(flags, ImGuiWindowFlags.NoTitleBar)
        end
        if BMSettings:GetCharacterWindow(hotbarId).Locked then
            flags = bit32.bor(flags, ImGuiWindowFlags.NoMove, ImGuiWindowFlags.NoResize)
        end
        bmHotbar:RenderHotbar(flags)
    end
    BMEditPopup:RenderEditButtonPopup()
    ImGui.PopStyleColor(2)
end

local function Setup()
    if not BMSettings:LoadSettings() then return end

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
        if reloadSettings then
            reloadSettings = false
            BMSettings:LoadSettings()
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
        reloadSettings = true
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

GiveTime()
