--[[
    IconPicker provides a UI for selecting abilities, such as for configuring
    what abilities to use in some automation script.

    Usage:
    -- Somewhere in main script execution:
    local IconPicker = require('IconPicker')
    local picker = IconPicker.new() -- optionally takes a table of ability types to display
    -- local picker = IconPicker.new({'Item','Spell','AA','CombatAbility','Skill'})
    picker:InitializeAbilities()

    -- Somewhere during ImGui callback execution:
    if ImGui.Button('Open Ability Picker') then picker:SetOpen() end
    picker:DrawIconPicker()

    -- Somewhere in main script execution:
    if picker.Selected then
        -- Process the item which was selected by the picker
        printf('Selected %s: %s', picker.Selected.Type, picker.Selected.Name)
        picker:ClearSelection()
    end

    -- In main loop, reload abilities if selected by user
    while true do
        picker.Reload()
    end

    When an ability is selected, IconPicker.Selected will contain the following values:
    - Type = 'Spell'
        - ID, Name, RankName, Level
    - Type = 'Disc'
        - ID, Name, RankName, Level
    - Type = 'AA'
        - ID, Name
    - Type = 'Item'
        - ID, Name, SpellName
    - Type = 'Skill'
        - ID, Name
]]

---@type Mq
local mq = require('mq')
---@type ImGui
require('ImGui')

local allTypes = { Spell = true, AA = true, CombatAbility = true, Item = true, Skill = true, }
local animSpellIcons = mq.FindTextureAnimation('A_SpellIcons')
local animItems = mq.FindTextureAnimation('A_DragItem')
local aaTypes = { 'General', 'Archtype', 'Class', 'Special', }

local IconPicker = {}
IconPicker.__index = IconPicker

function IconPicker.new(types)
    local newPicker = {
        Open = false,
        Draw = false,
        maxSpell = 180,
        maxItem = 0,
    }
    return setmetatable(newPicker, IconPicker)
end

local IconSize = 40
function IconPicker:renderSpellIcon(id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()
    -- icon
    animSpellIcons:SetTextureCell(id)
    ImGui.DrawTextureAnimation(animSpellIcons, IconSize, IconSize)
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushID(tostring(id) .. "SpellButton")
    if ImGui.InvisibleButton(tostring(id), ImVec2(IconSize, IconSize)) then
        self.Selected = id
    end
    ImGui.PopID()
end

function IconPicker:renderItemIcon(id)
    local cursor_x, cursor_y = ImGui.GetCursorPos()
    -- icon
    animItems:SetTextureCell(id)
    ImGui.DrawTextureAnimation(animItems, IconSize, IconSize)
    ImGui.SetCursorPos(cursor_x, cursor_y)
    ImGui.PushID(tostring(id) .. "ItemButton")
    if ImGui.InvisibleButton(tostring(id), ImVec2(IconSize, IconSize)) then
        self.Selected = id
    end
    ImGui.PopID()
end

function IconPicker:DrawIconPicker()
    if not self.Open then return end
    self.Open, self.Draw = ImGui.Begin('Icon Picker', self.Open, ImGuiWindowFlags.None)
    if self.Draw then
        local style = ImGui.GetStyle()
        local width = ImGui.GetWindowWidth()
        local cols = math.max(math.floor(width / (IconSize + style.ItemSpacing.x)), 1)

        if ImGui.BeginTable("Icons", cols) then
            for iconId = 1, self.maxSpell do
                ImGui.TableNextColumn()
                self:renderSpellIcon(iconId)
            end
            for iconId = 1, self.maxItem do
                ImGui.TableNextColumn()
                self:renderItemIcon(iconId)
            end
            ImGui.EndTable()
        end
    end
    ImGui.End()
end

function IconPicker:SetOpen()
    self.Open, self.Draw = true, true
end

function IconPicker:ClearSelection()
    self.Selected = nil
end

return IconPicker
