local mq                            = require('mq')
local btnUtils                      = require('lib.buttonUtils')
local BMButtonHandlers              = require('bmButtonHandlers')

local WINDOW_SETTINGS_ICON_SIZE     = 22

local editTabPopup                  = "edit_tab_popup"

---@class BMHotbarClass
local BMHotbarClass                 = {}
BMHotbarClass.__index               = BMHotbarClass
BMHotbarClass.id                    = 1
BMHotbarClass.openGUI               = true
BMHotbarClass.shouldDrawGUI         = true
BMHotbarClass.lastWindowX           = 0
BMHotbarClass.lastWindowY           = 0
BMHotbarClass.lastWindowHeight      = 0
BMHotbarClass.lastWindowWidth       = 0
BMHotbarClass.buttonSizeDirty       = false
BMHotbarClass.visibleButtonCount    = 0
BMHotbarClass.cachedCols            = 0
BMHotbarClass.cachedRows            = 0

BMHotbarClass.importObjectPopupOpen = false

BMHotbarClass.validDecode           = false
BMHotbarClass.importText            = ""
BMHotbarClass.decodedObject         = {}

BMHotbarClass.newSetName            = ""
BMHotbarClass.currentSelectedSet    = 0

BMHotbarClass.lastFrameTime         = 0

BMHotbarClass.importTextChanged     = false

BMHotbarClass.updateWindowPosSize   = false
BMHotbarClass.newWidth              = 0
BMHotbarClass.newHeight             = 0
BMHotbarClass.newX                  = 0
BMHotbarClass.newY                  = 0

function BMHotbarClass.new(id, createFresh)
    local newBMHotbar = setmetatable({ id = id, }, BMHotbarClass)

    if createFresh then
        BMSettings:GetCharConfig().Windows[id] = { Visible = true, Sets = {}, Locked = false, HideTitleBar = false, CompactMode = false, }

        -- if this character doesn't have the sections in the config, create them
        newBMHotbar.updateWindowPosSize = true
        newBMHotbar.newWidth = 1000
        newBMHotbar.newHeight = 150
        newBMHotbar.newX = 500
        newBMHotbar.newY = 500

        BMSettings:SaveSettings(true)
    end

    return newBMHotbar
end

function BMHotbarClass:SetVisible(bVisible)
    BMSettings:GetCharacterWindow(self.id).Visible = bVisible
    self.openGUI = bVisible
    BMSettings:SaveSettings(true)
end

function BMHotbarClass:ToggleVisible()
    BMSettings:GetCharacterWindow(self.id).Visible = not BMSettings:GetCharacterWindow(self.id).Visible
    self.openGUI = BMSettings:GetCharacterWindow(self.id).Visible
    BMSettings:SaveSettings(true)
end

function BMHotbarClass:IsVisible()
    return BMSettings:GetCharacterWindow(self.id).Visible
end

function BMHotbarClass:RenderHotbar(flags)
    if not self:IsVisible() then return end
    ImGui.PushID("##MainWindow_" .. tostring(self.id))
    self.openGUI, self.shouldDrawGUI = ImGui.Begin(string.format('Button Master - %d', self.id), self.openGUI, flags)
    self.lastWindowX, self.lastWindowY = ImGui.GetWindowPos()

    local theme = BMSettings:GetSettings().Themes and BMSettings:GetSettings().Themes[self.id] or nil
    local themeColorPop = 0
    local themeStylePop = 0

    if self.openGUI and self.shouldDrawGUI then
        if theme ~= nil then
            for _, t in pairs(theme) do
                if t.color then
                    ImGui.PushStyleColor(ImGuiCol[t.element], t.color.r, t.color.g, t.color.b, t.color.a)
                    themeColorPop = themeColorPop + 1
                elseif t.stylevar then
                    ImGui.PushStyleVar(ImGuiStyleVar[t.stylevar], t.value)
                    themeStylePop = themeStylePop + 1
                end
            end
        end
        if self.updateWindowPosSize then
            self.updateWindowPosSize = false
            ImGui.SetWindowSize(self.newWidth, self.newHeight)
            ImGui.SetWindowPos(self.newX, self.newY)
        end

        self:RenderTabs()
        self:RenderImportButtonPopup()
    end
    if themeColorPop > 0 then
        ImGui.PopStyleColor(themeColorPop)
    end
    if themeStylePop > 0 then
        ImGui.PopStyleVar(themeStylePop)
    end
    ImGui.End()
    ImGui.PopID()

    if self.openGUI ~= self:IsVisible() then
        self:SetVisible(self.openGUI)
        self.openGUI = true
    end
end

function BMHotbarClass:RenderTabs()
    local lockedIcon = BMSettings:GetCharacterWindow(self.id).Locked and Icons.FA_LOCK .. '##lockTabButton' or
        Icons.FA_UNLOCK .. '##lockTablButton'

    if BMSettings:GetCharacterWindow(self.id).CompactMode then
        local start_x, start_y = ImGui.GetCursorPos()

        local iconPadding = 2
        local settingsIconSize = math.ceil(((BMSettings:GetCharacterWindow(self.id).ButtonSize or 6) * 10) / 2) - iconPadding
        ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, 0, iconPadding)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)

        if ImGui.Button(lockedIcon, settingsIconSize, settingsIconSize) then
            --ImGuiWindowFlags.NoMove
            BMSettings:GetCharacterWindow(self.id).Locked = not BMSettings:GetCharacterWindow(self.id).Locked
            BMSettings:SaveSettings(true)
        end

        ImGui.SetCursorPosY(ImGui.GetCursorPosY() + (iconPadding))
        ImGui.Button(Icons.MD_SETTINGS, settingsIconSize, settingsIconSize)
        ImGui.PopStyleVar(2)

        ImGui.SameLine()
        self:RenderTabContextMenu()
        self:RenderCreateTab()

        self.currentSelectedSet = 1

        local style = ImGui.GetStyle()
        ImGui.SetCursorPos(ImVec2(start_x + settingsIconSize + (style.ItemSpacing.x), start_y))

        ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.BeginChild("##buttons_child", nil, nil, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize))
        if BMSettings:GetCharacterWindowSets(self.id)[1] ~= nil then
            self:RenderButtons(BMSettings:GetCharacterWindowSets(self.id)[1])
        end
        ImGui.EndChild()
        ImGui.PopStyleVar(2)
    else
        if ImGui.Button(lockedIcon, WINDOW_SETTINGS_ICON_SIZE, WINDOW_SETTINGS_ICON_SIZE) then
            --ImGuiWindowFlags.NoMove
            BMSettings:GetCharacterWindow(self.id).Locked = not BMSettings:GetCharacterWindow(self.id).Locked
            BMSettings:SaveSettings(true)
        end

        ImGui.SameLine()
        ImGui.Button(Icons.MD_SETTINGS, WINDOW_SETTINGS_ICON_SIZE, WINDOW_SETTINGS_ICON_SIZE)
        ImGui.SameLine()
        self:RenderTabContextMenu()
        self:RenderCreateTab()

        if ImGui.BeginTabBar("Tabs", ImGuiTabBarFlags.Reorderable) then
            if #BMSettings:GetCharacterWindowSets(self.id) > 0 then
                for i, set in ipairs(BMSettings:GetCharacterWindowSets(self.id)) do
                    if ImGui.BeginTabItem(set) then
                        SetLabel = set
                        self.currentSelectedSet = i

                        -- tab edit popup
                        if ImGui.BeginPopupContextItem(set) then
                            ImGui.Text("Edit Name:")
                            local tmp, selected = ImGui.InputText("##edit", set, 0)
                            if selected then self.newSetName = tmp end
                            if ImGui.Button("Save") then
                                BMEditPopup:CloseEditPopup()
                                local newSetLabel = self.newSetName
                                if self.newSetName ~= nil then
                                    BMSettings:GetCharacterWindowSets(self.id)[i] = self.newSetName

                                    -- move the old button set to the new name
                                    BMSettings:GetSettings().Sets[newSetLabel], BMSettings:GetSettings().Sets[SetLabel] = BMSettings:GetSettings().Sets[SetLabel], nil

                                    -- update the character button set name
                                    for curCharKey, curCharData in pairs(BMSettings:GetSettings().Characters) do
                                        for windowIdx, windowData in ipairs(curCharData.Windows) do
                                            for setIdx, oldSetName in ipairs(windowData.Sets) do
                                                if oldSetName == set then
                                                    btnUtils.Output(string.format(
                                                        "\awUpdating section '\ag%s\aw' renaming \am%s\aw => \at%s", curCharKey,
                                                        oldSetName, self.newSetName))
                                                    BMSettings:GetSettings().Characters[curCharKey].Windows[windowIdx].Sets[setIdx] = self.newSetName
                                                end
                                            end
                                        end
                                    end

                                    -- update set to the new name so the button render doesn't fail
                                    SetLabel = newSetLabel
                                    BMSettings:SaveSettings(true)
                                end
                                ImGui.CloseCurrentPopup()
                            end
                            ImGui.EndPopup()
                        end

                        self:RenderButtons(SetLabel)
                        ImGui.EndTabItem()
                    end
                end
            end
        else
            ImGui.Text(string.format("No Sets Added! Add one by right-clicking on %s", Icons.MD_SETTINGS))
        end
        ImGui.EndTabBar()
    end
end

function BMHotbarClass:RenderTabContextMenu()
    local openPopup = false

    local unassigned = {}
    local charLoadedSets = {}
    for _, v in ipairs(BMSettings:GetCharacterWindowSets(self.id)) do
        charLoadedSets[v] = true
    end
    for k, _ in pairs(BMSettings:GetSettings().Sets) do
        if charLoadedSets[k] == nil then
            unassigned[k] = true
        end
    end

    if ImGui.BeginPopupContextItem() then
        if btnUtils.getTableSize(unassigned) > 0 then
            if ImGui.BeginMenu("Add Set") then
                for k, _ in pairs(unassigned) do
                    if ImGui.MenuItem(k) then
                        table.insert(BMSettings:GetCharacterWindowSets(self.id), k)
                        BMSettings:SaveSettings(true)
                        break
                    end
                end
                ImGui.EndMenu()
            end
        end

        if ImGui.BeginMenu("Remove Set") then
            for i, v in ipairs(BMSettings:GetCharacterWindowSets(self.id)) do
                if ImGui.MenuItem(v) then
                    table.remove(BMSettings:GetCharConfig().Windows[self.id].Sets, i)
                    BMSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Delete Set") then
            for k, _ in pairs(BMSettings:GetSettings().Sets) do
                if ImGui.MenuItem(k) then
                    -- clean up any references to this set.
                    for charConfigKey, charConfigValue in pairs(BMSettings:GetSettings().Characters) do
                        for setKey, setName in pairs(charConfigValue.Windows[self.id].Sets) do
                            if setName == k then
                                BMSettings:GetSettings().Characters[charConfigKey].Windows[self.id].Sets[setKey] = nil
                            end
                        end
                    end
                    BMSettings:GetSettings().Sets[k] = nil
                    BMSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.BeginMenu("Delete Hotkey") then
            local sortedButtons = {}
            for k, v in pairs(BMSettings:GetSettings().Buttons) do table.insert(sortedButtons, { Label = v.Label, id = k, }) end
            table.sort(sortedButtons, function(a, b) return a.Label < b.Label end)

            for _, buttonData in pairs(sortedButtons) do
                if ImGui.MenuItem(buttonData.Label) then
                    -- clean up any references to this Button.
                    for setNameKey, setButtons in pairs(BMSettings:GetSettings().Sets) do
                        for buttonKey, buttonName in pairs(setButtons) do
                            if buttonName == buttonData.id then
                                BMSettings:GetSettings().Sets[setNameKey][buttonKey] = nil
                            end
                        end
                    end
                    BMSettings:GetSettings().Buttons[buttonData.id] = nil
                    BMSettings:SaveSettings(true)
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
                local checked = BMSettings:GetCharacterWindow(self.id).ButtonSize == i
                if ImGui.MenuItem(tostring(i), nil, checked) then
                    BMSettings:GetCharacterWindow(self.id).ButtonSize = i
                    self.buttonSizeDirty = true
                    BMSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        local font_scale = {
            {
                label = "Tiny",
                size = 8,
            },
            {
                label = "Small",
                size = 9,
            },
            {
                label = "Normal",
                size = 10,
            },
            {
                label = "Large",
                size  = 11,
            },
        }

        if ImGui.BeginMenu("Font Scale") then
            for i, v in ipairs(font_scale) do
                local checked = BMSettings:GetCharacterWindow(self.id).Font == v.size
                if ImGui.MenuItem(v.label, nil, checked) then
                    BMSettings:GetCharacterWindow(self.id).Font = v.size
                    BMSettings:SaveSettings(true)
                    break
                end
            end
            ImGui.EndMenu()
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Share Set") then
            for k, _ in pairs(BMSettings:GetSettings().Sets) do
                if ImGui.MenuItem(k) then
                    BMButtonHandlers:ExportSetToClipBoard(k)
                    btnUtils.Output("Set: '%s' has been copied to your clipboard!", k)
                end
            end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Import Button or Set") then
            self.importObjectPopupOpen = true
            self.importText = ImGui.GetClipboardText() or ""
            self.importTextChanged = true
        end

        ImGui.Separator()

        if ImGui.BeginMenu("Display Settings") then
            if ImGui.MenuItem((BMSettings:GetCharacterWindow(self.id).HideTitleBar and "Show" or "Hide") .. " Title Bar") then
                BMSettings:GetCharacterWindow(self.id).HideTitleBar = not BMSettings:GetCharacterWindow(self.id).HideTitleBar
                BMSettings:SaveSettings(true)
            end
            if ImGui.MenuItem((BMSettings:GetCharacterWindow(self.id).CompactMode and "Normal" or "Compact") .. " Mode") then
                BMSettings:GetCharacterWindow(self.id).CompactMode = not BMSettings:GetCharacterWindow(self.id).CompactMode
                BMSettings:SaveSettings(true)
            end
            local fps_scale = {
                {
                    label = "Instant",
                    fps = 0,
                },
                {
                    label = "10 FPS",
                    fps = 1,
                },
                {
                    label = "4 FPS",
                    fps = 2.5,
                },
                {
                    label = "1 FPS",
                    fps   = 10,
                },
            }

            if ImGui.BeginMenu("Update FPS") then
                for _, v in ipairs(fps_scale) do
                    local checked = BMSettings:GetCharacterWindow(self.id).FPS == v.fps
                    if ImGui.MenuItem(v.label, nil, checked) then
                        BMSettings:GetCharacterWindow(self.id).FPS = v.fps
                        BMSettings:SaveSettings(true)
                        break
                    end
                end
                ImGui.EndMenu()
            end
            -- TODO: Make this a reference to a character since it can dynamically change.
            --if ImGui.MenuItem("Save Layout as Default") then
            --    BMSettings:GetSettings().Defaults = {
            --        width = self.lastWindowWidth,
            --        height = self.lastWindowHeight,
            --        x = self.lastWindowX,
            --        y = self.lastWindowY,
            --        CharSettings = BMSettings:GetCharConfig(),
            --    }
            --    BMSettings:SaveSettings(true)
            --end
            ImGui.EndMenu()
        end

        if ImGui.MenuItem("Create New Hotbar") then
            table.insert(BMHotbars, BMHotbarClass.new(BMSettings:GetNextWindowId(), true))
        end

        if ImGui.BeginMenu("Show/Hide Hotbar") then
            for hbIdx, hotbarClass in ipairs(BMHotbars) do
                if ImGui.MenuItem(string.format("Button Master - %d", hbIdx), nil, hotbarClass:IsVisible()) then
                    hotbarClass:ToggleVisible()
                end
            end
            ImGui.EndMenu()
        end

        --[[if ImGui.MenuItem("Replicate Size/Pos") then
            local x, y = ImGui.GetWindowPos()
            ButtonActors.send({
                from = mq.TLO.Me.DisplayName(),
                script = "ButtonMaster",
                event = "CopyLoc",
                width = self.lastWindowWidth,
                height = self.lastWindowHeight,
                x = self.lastWindowX,
                y = self.lastWindowY,
                windowId = self.id,
                hideTitleBar = BMSettings:GetCharacterWindow(self.id).HideTitleBar,
                compactMode = BMSettings:GetCharacterWindow(self.id).CompactMode,
            })
        end]]

        ImGui.Separator()

        if ImGui.BeginMenu("Dev") then
            if ImGui.MenuItem((btnUtils.enableDebug and "Disable" or "Enable") .. " Debug") then
                btnUtils.enableDebug = not btnUtils.enableDebug
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

function BMHotbarClass:RenderContextMenu(Set, Index, buttonID)
    local button = BMSettings:GetButtonBySetIndex(Set, Index)

    local unassigned = {}
    local keys = {}
    for _, v in pairs(BMSettings:GetSettings().Sets[Set] or {}) do keys[v] = true end
    for k, v in pairs(BMSettings:GetSettings().Buttons) do
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
                    local labelA = unassigned[a] and BMButtonHandlers.ResolveButtonLabel(unassigned[a], true)
                    local labelB = unassigned[b] and BMButtonHandlers.ResolveButtonLabel(unassigned[b], true)
                    return labelA < labelB
                end)

                for _, key in ipairs(sortedKeys) do
                    local value = unassigned[key]
                    if value ~= nil then
                        if ImGui.MenuItem(BMButtonHandlers.ResolveButtonLabel(value, true)) then
                            BMSettings:GetSettings().Sets[Set][Index] = key
                            BMSettings:SaveSettings(true)
                            break
                        end
                    end
                end
                ImGui.EndMenu()
            end
        end

        -- only show create new for unassigned buttons
        if button.Unassigned == true then
            if ImGui.MenuItem("Create New") then
                BMEditPopup:OpenEditPopup(Set, Index)
            end
        else
            if ImGui.MenuItem("Edit") then
                BMEditPopup:OpenEditPopup(Set, Index)
            end
            if ImGui.MenuItem("Unassign") then
                BMSettings:GetSettings().Sets[Set][Index] = nil
                BMSettings:SaveSettings(true)
            end
            if ImGui.MenuItem(Icons.MD_SHARE) then
                BMButtonHandlers.ExportButtonToClipBoard(button)
            end
            btnUtils.Tooltip("Copy contents of this button to share with friends.")
        end

        ImGui.EndPopup()
    end
end

---@param Set string
function BMHotbarClass:RenderButtons(Set)
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, ImVec2(4, 4))
    if ImGui.GetWindowWidth() ~= self.lastWindowWidth or ImGui.GetWindowHeight() ~= self.lastWindowHeight or self.buttonSizeDirty then
        self:RecalculateVisibleButtons(Set)
    end

    local btnSize = (BMSettings:GetCharacterWindow(self.id).ButtonSize or 6) * 10

    local renderButtonCount = self.visibleButtonCount

    for ButtonIndex = 1, renderButtonCount do
        local button = BMSettings:GetButtonBySetIndex(Set, ButtonIndex)
        local clicked = false

        local buttonID = string.format("##Button_%s_%d", Set, ButtonIndex)
        ImGui.PushID(buttonID)
        clicked = BMButtonHandlers.Render(button, btnSize, true, (BMSettings:GetCharacterWindow(self.id).Font or 10) / 10)
        ImGui.PopID()

        -- TODO Move this to button config class and out of the UI thread.
        if clicked then
            if button.Unassigned then
                BMEditPopup:CreateButtonFromCursor(Set, ButtonIndex)
            else
                BMButtonHandlers.Exec(button)
            end
        else
            -- setup drag and drop
            if ImGui.BeginDragDropSource() then
                ImGui.SetDragDropPayload("BTN", ButtonIndex)
                ImGui.Button(button.Label, btnSize, btnSize)
                ImGui.EndDragDropSource()
            end
            if ImGui.BeginDragDropTarget() then
                local payload = ImGui.AcceptDragDropPayload("BTN")
                if payload ~= nil then
                    ---@diagnostic disable-next-line: undefined-field
                    local num = payload.Data;
                    -- swap the keys in the button set
                    BMSettings:GetSettings().Sets[Set][num], BMSettings:GetSettings().Sets[Set][ButtonIndex] = BMSettings:GetSettings().Sets[Set][ButtonIndex],
                        BMSettings:GetSettings().Sets[Set][num]
                    BMSettings:SaveSettings(true)
                end
                ImGui.EndDragDropTarget()
            end

            self:RenderContextMenu(Set, ButtonIndex, buttonID)
        end

        -- button grid
        if ButtonIndex % self.cachedCols ~= 0 then ImGui.SameLine() end
    end
    ImGui.PopStyleVar(1)
end

function BMHotbarClass:RecalculateVisibleButtons(Set)
    self.buttonSizeDirty = false
    self.lastWindowWidth = ImGui.GetWindowWidth()
    self.lastWindowHeight = ImGui.GetWindowHeight()

    local cursorX, cursorY = ImGui.GetCursorPos() -- this will get us the x pos we start at which tells us of the offset from the main window border
    local style = ImGui.GetStyle()                -- this will get us ItemSpacing.x which is the amount of space between buttons

    -- global button configs
    local btnSize = (BMSettings:GetCharacterWindow(self.id).ButtonSize or 6) * 10
    self.cachedCols = math.floor((self.lastWindowWidth - cursorX) / (btnSize + style.ItemSpacing.x))
    self.cachedRows = math.floor((self.lastWindowHeight - cursorY) / (btnSize + style.ItemSpacing.y))

    local count = 100
    if self.cachedRows * self.cachedCols < 100 then count = self.cachedRows * self.cachedCols end

    -- get the last assigned button and make sure it is visible.
    local lastAssignedButton = 1
    for i = 1, 100 do if not BMSettings:GetButtonBySetIndex(Set, i).Unassigned then lastAssignedButton = i end end

    -- if the last forced visible buttons isn't the last in a row then render to the end of that row.
    -- stay with me here. The last button needs to look at the number of buttons per row (cols) and
    -- the position of this button in that row (button%cols) and add enough to get to the end of the row.
    if lastAssignedButton % self.cachedCols ~= 0 then
        lastAssignedButton = lastAssignedButton + (self.cachedCols - (lastAssignedButton % self.cachedCols))
    end

    self.visibleButtonCount = math.min(math.max(count, lastAssignedButton), 100)
end

function BMHotbarClass:RenderImportButtonPopup()
    if not self.importObjectPopupOpen then return end

    local shouldDrawImportPopup = false

    self.importObjectPopupOpen, shouldDrawImportPopup = ImGui.Begin("Import Button or Set", self.importObjectPopupOpen,
        ImGuiWindowFlags.None)
    if ImGui.GetWindowWidth() < 500 or ImGui.GetWindowHeight() < 100 then
        ImGui.SetWindowSize(math.max(500, ImGui.GetWindowWidth()), math.max(100, ImGui.GetWindowHeight()))
    end
    if self.importObjectPopupOpen and shouldDrawImportPopup then
        if ImGui.SmallButton(Icons.MD_CONTENT_PASTE) then
            self.importText = ImGui.GetClipboardText()
            self.importTextChanged = true
        end
        btnUtils.Tooltip("Paste from Clipboard")
        ImGui.SameLine()

        if self.importTextChanged then
            self.validDecode, self.decodedObject = btnUtils.decodeTable(self.importText)
            self.validDecode = type(self.decodedObject) == 'table' and self.validDecode or false
        end

        if self.validDecode then
            ImGui.PushStyleColor(ImGuiCol.Text, 0.02, 0.8, 0.02, 1.0)
        else
            ImGui.PushStyleColor(ImGuiCol.Text, 0.8, 0.02, 0.02, 1.0)
        end
        self.importText, self.importTextChanged = ImGui.InputText(
            (self.validDecode and Icons.MD_CHECK or Icons.MD_NOT_INTERESTED) .. " Import Code", self.importText,
            ImGuiInputTextFlags.None)
        ImGui.PopStyleColor()

        -- save button
        if self.validDecode and self.decodedObject then
            if ImGui.Button("Import " .. (self.decodedObject.Type or "Failed")) then
                if self.decodedObject.Type == "Button" then
                    BMSettings:ImportButtonAndSave(self.decodedObject.Button, true)
                elseif self.decodedObject.Type == "Set" then
                    BMSettings:ImportSetAndSave(self.decodedObject, self.id)
                else
                    btnUtils.Output("\arError: imported object was not a button or a set!")
                end
                -- reset everything
                self.decodedObject = {}
                self.importText = ""
                self.importObjectPopupOpen = false
            end
        end
    end
    ImGui.End()
end

function BMHotbarClass:RenderCreateTab()
    if ImGui.BeginPopup(editTabPopup) then
        ImGui.Text("New Button Set:")
        local tmp, selected = ImGui.InputText("##edit", '', 0)
        if selected then self.newSetName = tmp end
        if ImGui.Button("Save") then
            if self.newSetName ~= nil and self.newSetName:len() > 0 then
                if BMSettings:GetSettings().Sets[self.newSetName] == nil then
                    table.insert(BMSettings:GetCharConfig().Windows[self.id].Sets, self.newSetName)
                    BMSettings:GetSettings().Sets[self.newSetName] = {}
                    BMSettings:SaveSettings(true)
                else
                    btnUtils.Output("\arError Saving Set: A set with this name already exists!\ax")
                end
            else
                btnUtils.Output("\arError Saving Set: Name cannot be empty.\ax")
            end
            ImGui.CloseCurrentPopup()
        end
        ImGui.EndPopup()
    end
end

function BMHotbarClass:UpdatePosition(width, height, x, y, hideTitleBar, compactMode)
    self.updateWindowPosSize                            = true
    self.newWidth                                       = width
    self.newHeight                                      = height
    self.newX                                           = x
    self.newY                                           = y
    BMSettings:GetCharacterWindow(self.id).HideTitleBar = hideTitleBar
    BMSettings:GetCharacterWindow(self.id).CompactMode  = compactMode
    BMSettings:SaveSettings(true)
end

function BMHotbarClass:GiveTime()
    local now = os.clock()

    -- update every visible button to save on our FPS.
    if not BMSettings:GetCharacterWindow(self.id).FPS then
        BMSettings:GetCharacterWindow(self.id).FPS = 0
        BMSettings:SaveSettings(true)
    end

    local fps = BMSettings:GetCharacterWindow(self.id).FPS / 10

    if now - self.lastFrameTime < fps then return end
    self.lastFrameTime = now

    for i, set in ipairs(BMSettings:GetCharacterWindowSets(self.id)) do
        if self.currentSelectedSet == i then
            btnUtils.Debug("Caching Visibile Buttons for Set: %s / %d", set, i)
            local renderButtonCount = self.visibleButtonCount

            for ButtonIndex = 1, renderButtonCount do
                local button = BMSettings:GetButtonBySetIndex(set, ButtonIndex)

                BMButtonHandlers.EvaluateAndCache(button)
            end
        end
    end
end

return BMHotbarClass
