local mq                 = require('mq')
local btnUtils           = require('lib.buttonUtils')

-- Icon Rendering
local animItems          = mq.FindTextureAnimation("A_DragItem")
local animSpellIcons     = mq.FindTextureAnimation('A_SpellIcons')

---@class BMButtonHandlers
local BMButtonHandlers   = {}
BMButtonHandlers.__index = BMButtonHandlers

---@param Button table # BMButtonConfig
function BMButtonHandlers.ExportButtonToClipBoard(Button)
    local sharableButton = { Type = "Button", Button = Button, }
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableButton))
    btnUtils.Output("Button: '%s' has been copied to your clipboard!", Button.Label)
    local printableButton = btnUtils.dumpTable(sharableButton):gsub("\n/", "\\n/")
    btnUtils.Output('\n' .. printableButton)
end

function BMButtonHandlers:ExportSetToClipBoard(setKey)
    local sharableSet = { Type = "Set", Key = setKey, Set = {}, Buttons = {}, }
    for index, btnName in pairs(BMSettings:GetSettings().Sets[setKey]) do
        sharableSet.Set[index] = btnName
    end
    for _, buttonKey in pairs(BMSettings:GetSettings().Sets[setKey] or {}) do
        sharableSet.Buttons[buttonKey] = BMSettings:GetSettings().Buttons[buttonKey]
    end
    ImGui.SetClipboardText(btnUtils.encodeTable(sharableSet))
end

---@param Button table # BMButtonConfig
---@return integer, integer, boolean #CountDown, CooldownTimer, Toggle Locked
function BMButtonHandlers.GetButtonCooldown(Button)
    local countDown, coolDowntimer, toggleLocked = 0, 0, false

    if Button.TimerType == "Custom Lua" then
        local success
        local result

        if Button.Timer and Button.Timer:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.Timer)
            if not success then
                btnUtils.Output("Failed to run Timer for Button(%s): %s", Button.Label, countDown)
                btnUtils.Output("RunEnv was:\n%s", Button.Timer)
                countDown = 0
            else
                countDown = tonumber(result) or 0
            end
        end
        if Button.Cooldown and Button.Cooldown:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.Cooldown)
            if not success then
                btnUtils.Output("Failed to run Cooldown for Button(%s): %s", Button.Label, Button.Cooldown)
                btnUtils.Output("RunEnv was:\n%s", Button.Cooldown)
                coolDowntimer = 0
            else
                coolDowntimer = tonumber(result) or 0
            end
        end
        if Button.ToggleCheck and Button.ToggleCheck:len() > 0 then
            success, result = btnUtils.EvaluateLua(Button.ToggleCheck)
            if not success then
                btnUtils.Output("Failed to run ToggleCheck for Button(%s): %s", Button.Label, Button.ToggleCheck)
                btnUtils.Output("RunEnv was:\n%s", Button.ToggleCheck)
                toggleLocked = false
            else
                toggleLocked = type(result) == 'boolean' and result or false
            end
        end
    elseif Button.TimerType == "Seconds Timer" then
        if Button.CooldownTimer then
            countDown = Button.CooldownTimer - os.clock()
            if countDown <= 0 then
                Button.CooldownTimer = nil
                return 0, 0, false
            end
            coolDowntimer = Button.Cooldown
        end
    elseif Button.TimerType == "Item" then
        countDown = mq.TLO.FindItem(Button.Cooldown).TimerReady() or 0
        coolDowntimer = mq.TLO.FindItem(Button.Cooldown).Clicky.TimerID() or 0
    elseif Button.TimerType == "Spell Gem" then
        countDown = (mq.TLO.Me.GemTimer(Button.Cooldown)() or 0) / 1000
        coolDowntimer = mq.TLO.Me.GemTimer(Button.Cooldown).TotalSeconds() or 0
    elseif Button.TimerType == "AA" then
        countDown = (mq.TLO.Me.AltAbilityTimer(Button.Cooldown)() or 0) / 1000
        coolDowntimer = mq.TLO.Me.AltAbility(Button.Cooldown).MyReuseTime() or 0
    elseif Button.TimerType == "Ability" then
        if mq.TLO.Me.AbilityTimer and mq.TLO.Me.AbilityTimerTotal then
            countDown = (mq.TLO.Me.AbilityTimer(Button.Cooldown)() or 0) / 1000
            coolDowntimer = (mq.TLO.Me.AbilityTimerTotal(Button.Cooldown)() or 0) / 1000
        end
    end

    return countDown, coolDowntimer, toggleLocked
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos table # cursor position on screen
---@param size number # button size
function BMButtonHandlers.RenderButtonCooldown(Button, cursorScreenPos, size)
    local countDown, coolDowntimer, toggleLocked = BMButtonHandlers.GetButtonCooldown(Button)
    if coolDowntimer == 0 and not toggleLocked then return end

    local ratio = 1 - (countDown / (coolDowntimer))

    if toggleLocked then
        ratio = 100
    end

    local start_angle = (1.5 * math.pi)
    local end_angle = math.pi * ((2 * ratio) - 0.5)
    local center = ImVec2(cursorScreenPos.x + (size / 2), cursorScreenPos.y + (size / 2))

    local draw_list = ImGui.GetWindowDrawList()
    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), true)
    draw_list:PathLineTo(center)
    draw_list:PathArcTo(center, size, start_angle, end_angle, 0)
    draw_list:PathFillConvex(ImGui.GetColorU32(0.8, 0.02, 0.02, 0.75))
    draw_list:PopClipRect()
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
function BMButtonHandlers.RenderButtonIcon(Button, cursorScreenPos, size)
    if not Button.Icon and (not Button.IconLua or Button.IconLua:len() == 0) then
        return BMButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, 255)
    end

    local draw_list = ImGui.GetWindowDrawList()

    local iconId = Button.Icon
    local iconType = Button.IconType

    if Button.IconLua and Button.IconLua:len() > 0 then
        local success
        success, iconId, iconType = btnUtils.EvaluateLua(Button.IconLua)
        if not success then
            btnUtils.Debug("Failed to evaluate IconLua: %s\nError:\n%s", Button.IconLua, iconId)
            iconId = Button.Icon
            iconType = Button.IconType
        end
    end

    local renderIconAnim = animItems
    if iconType == nil or iconType == "Spell" then
        animSpellIcons:SetTextureCell(tonumber(iconId) or 0)
        renderIconAnim = animSpellIcons
    else
        animItems:SetTextureCell(tonumber(iconId) or 0)
    end

    draw_list:AddTextureAnimation(renderIconAnim, cursorScreenPos, ImVec2(size, size))
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param alpha number # button alpha color
function BMButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, alpha)
    local draw_list = ImGui.GetWindowDrawList()
    local buttonStyle = ImGui.GetStyleColorVec4(ImGuiCol.Button)
    local Colors = btnUtils.split(Button.ButtonColorRGB, ",")
    local buttonBGCol = IM_COL32(tonumber(Colors[1]) or (buttonStyle.x * 255), tonumber(Colors[2]) or (buttonStyle.y * 255), tonumber(Colors[3]) or (buttonStyle.z * 255), alpha)

    draw_list:AddRectFilled(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), buttonBGCol)
end

---@param Button table # BMButtonConfig
---@param label string
function BMButtonHandlers.RenderButtonTooltip(Button, label)
    -- hover tooltip
    if Button.Unassigned == nil and ImGui.IsItemHovered() then
        local tooltipText = label

        -- check label instead of tooltipText because if there is no text we dont care about the timer.
        if label:len() > 0 then
            local countDown, _ = BMButtonHandlers.GetButtonCooldown(Button)
            if countDown ~= 0 then
                tooltipText = tooltipText .. "\n\n" .. btnUtils.FormatTime(math.ceil(countDown))
            end

            ImGui.BeginTooltip()
            ImGui.Text(tooltipText)
            ImGui.EndTooltip()
        end
    end
end

---@param Button table # BMButtonConfig
---@param cursorScreenPos ImVec2 # cursor position on screen
---@param size number # button size
---@param label string
function BMButtonHandlers.RenderButtonLabel(Button, cursorScreenPos, size, label)
    local Colors = btnUtils.split(Button.TextColorRGB, ",")
    local buttonLabelCol = IM_COL32(tonumber(Colors[1]) or 255, tonumber(Colors[2]) or 255, tonumber(Colors[3]) or 255, 255)
    local draw_list = ImGui.GetWindowDrawList()

    local label_x, label_y = ImGui.CalcTextSize(label)
    local midX = math.max((size - label_x) / 2, 0)
    local midY = (size - label_y) / 2

    draw_list:PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + size, cursorScreenPos.y + size), true)
    draw_list:AddText(ImVec2(cursorScreenPos.x + midX, cursorScreenPos.y + midY), buttonLabelCol, label)
    draw_list:PopClipRect()
end

---@param Button table # BMButtonConfig
function BMButtonHandlers.ResolveButtonLabel(Button)
    local success = true
    local evaluatedLabel = Button.Label

    if Button.EvaluateLabel then
        success, evaluatedLabel = btnUtils.EvaluateLua(Button.Label)
        if not success then
            btnUtils.Debug("Failed to evaluate Button Label:\n%s\nError:\n%s", Button.Label, evaluatedLabel)
        end
    end
    evaluatedLabel = tostring(evaluatedLabel)
    return evaluatedLabel:gsub(" ", "\n")
end

---@param Button table # BMButtonConfig
---@param size number # size to render the button as
---@param renderLabel boolean # render the label on top or not
---@param fontScale number # Font scale for text
---@return boolean # clicked
function BMButtonHandlers.Render(Button, size, renderLabel, fontScale)
    local evaluatedLabel = renderLabel and BMButtonHandlers.ResolveButtonLabel(Button) or ""
    local clicked = false

    local cursorScreenPos = ImGui.GetCursorScreenPosVec()

    BMButtonHandlers.RenderButtonIcon(Button, cursorScreenPos, size)
    clicked = ImGui.Selectable('', false, ImGuiSelectableFlags.DontClosePopups, size, size)
    if ImGui.IsItemHovered() then
        BMButtonHandlers.RenderButtonRect(Button, cursorScreenPos, size, 200)
    end

    BMButtonHandlers.RenderButtonCooldown(Button, cursorScreenPos, size)

    -- label and tooltip
    if renderLabel then
        ImGui.SetWindowFontScale(fontScale)
        BMButtonHandlers.RenderButtonLabel(Button, cursorScreenPos, size, evaluatedLabel)
        BMButtonHandlers.RenderButtonTooltip(Button, evaluatedLabel)
        ImGui.SetWindowFontScale(1)
    end

    return clicked
end

function BMButtonHandlers.FireTimer(Button)
    if Button.TimerType == "Seconds Timer" then
        Button.CooldownTimer = os.clock() + Button.Cooldown
    end
end

---@param Button table # BMButtonConfig
function BMButtonHandlers.Exec(Button)
    if Button.Cmd then
        if Button.Cmd:find("^--[ ]?lua") == nil then
            local cmds = btnUtils.split(Button.Cmd, "\n")
            for i, c in ipairs(cmds) do
                if c:len() > 0 and c:find('^#') == nil and c:find('^[-]+') == nil and c:find('^|') == nil then
                    if c:find('^/') then
                        -- don't use cmdf here because users might have %'s in their commands.
                        mq.cmd(c)
                    else
                        btnUtils.Output('\arInvalid command on Line %d : \ax%s', i, c)
                    end
                else
                    btnUtils.Debug("Ignored: %s", c)
                end
            end
        else
            btnUtils.EvaluateLua(Button.Cmd)
        end
        BMButtonHandlers.FireTimer(Button)
    end
end

return BMButtonHandlers
