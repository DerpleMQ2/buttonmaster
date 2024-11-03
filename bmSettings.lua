local mq                         = require('mq')
local btnUtils                   = require('lib.buttonUtils')
local PackageMan                 = require('mq.PackageMan')
local sqlite3                    = PackageMan.Require('lsqlite3')

local settings_base              = mq.configDir .. '/ButtonMaster'
local settings_path              = settings_base .. '.lua '
local dbPath                     = string.format('%s/ButtonMaster.db', mq.configDir)
local configFile                 = mq.configDir .. '/ButtonMaster.lua'

local BMSettings                 = {}
BMSettings.__index               = BMSettings
BMSettings.settings              = {}
BMSettings.CharConfig            = string.format("%s_%s", mq.TLO.EverQuest.Server(), mq.TLO.Me.DisplayName())
BMSettings.Constants             = {}

BMSettings.Globals               = {}
BMSettings.Globals.Version       = 8
BMSettings.Globals.CustomThemes  = {}

BMSettings.Constants.TimerTypes  = {
    "Seconds Timer",
    "Item",
    "Spell Gem",
    "AA",
    "Ability",
    "Disc",
    "Custom Lua",
}

BMSettings.Constants.UpdateRates = {
    { Display = "Unlimited",     Value = 0, },
    { Display = "1 per second",  Value = 1, },
    { Display = "2 per second",  Value = 0.5, },
    { Display = "4 per second",  Value = 0.25, },
    { Display = "10 per second", Value = 0.1, },
    { Display = "20 per second", Value = 0.05, },
}

function BMSettings:InitializeDB()
    local db = sqlite3.open(dbPath)
    db:exec([[
        CREATE TABLE IF NOT EXISTS settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server TEXT NOT NULL,
            character TEXT NOT NULL,
            settings_version INTEGER NOT NULL,
            settings_last_backup INTEGER NOT NULL,
            UNIQUE(server, character)
        );
        CREATE TABLE IF NOT EXISTS sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            set_name TEXT NOT NULL,
            button_number INTEGER NOT NULL,
            button_id TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS buttons (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            button_number TEXT NOT NULL,
            button_label TEXT NOT NULL,
            button_render INTEGER NOT NULL,
            button_text_color TEXT,
            button_button_color TEXT,
            button_cached_countdown INTEGER,
            button_cached_cooldown INTEGER,
            button_cached_toggle_locked INTEGER,
            button_cached_last_run NUMERIC,
            button_label_mid_x INTEGER,
            button_label_mid_y INTEGER,
            button_cached_label TEXT,
            button_cmd TEXT,
            button_evaluate_label INTEGER,
            button_show_label INTEGER,
            button_icon INTEGER,
            button_icon_type TEXT,
            button_icon_lua TEXT,
            button_timer_type TEXT,
            button_cooldown TEXT
        );
        CREATE TABLE IF NOT EXISTS windows (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            server TEXT NOT NULL,
            character TEXT NOT NULL,
            window_id INTEGER NOT NULL,
            window_fps INTEGER NOT NULL,
            window_button_size INTEGER NOT NULL,
            window_advtooltip INTEGER NOT NULL,
            window_compact INTEGER NOT NULL,
            window_hide_title INTEGER NOT NULL,
            window_width INTEGER NOT NULL,
            window_height INTEGER NOT NULL,
            window_x INTEGER NOT NULL,
            window_y INTEGER NOT NULL,
            window_visible INTEGER NOT NULL,
            window_font_size INTEGER NOT NULL,
            window_locked INTEGER NOT NULL,
            window_theme TEXT NOT NULL,
            window_set_id INTEGER NOT NULL,
            window_set_name TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS characters (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            character TEXT NOT NULL,
            character_locked INTEGER NOT NULL,
            character_hide_title INTEGER NOT NULL
        );
    ]])
    return db
end

function BMSettings:saveToDB(db, query, ...)
    local stmt = db:prepare(query)
    stmt:bind_values(...)
    stmt:step()
    stmt:finalize()
end

function BMSettings:loadFromDB(db, query, ...)
    local stmt = db:prepare(query)
    stmt:bind_values(...)
    local data = {}
    for row in stmt:nrows() do
        table.insert(data, row)
    end
    stmt:finalize()
    return data
end

function BMSettings:updateButtonDB(buttonData, id)
    local db = self:InitializeDB()
    local icon = buttonData.Icon or 0
    local showLabel = icon == 0 and true or buttonData.ShowLabel ~= nil and buttonData.ShowLabel or true
    self:saveToDB(db, [[
    INSERT OR REPLACE INTO buttons (
        button_number, button_label, button_render, button_text_color, button_button_color,
        button_cached_countdown, button_cached_cooldown, button_cached_toggle_locked,
        button_cached_last_run, button_label_mid_x, button_label_mid_y, button_cached_label,
        button_cmd, button_evaluate_label, button_show_label, button_icon,
        button_icon_type, button_icon_lua, button_timer_type, button_cooldown
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        id, buttonData.Label or "", buttonData.highestRenderTime or 0, buttonData.TextColorRGB or "", buttonData.ButtonColorRGB or "",
        buttonData.CachedCountDown or 0, buttonData.CachedCoolDownTimer or 0, buttonData.CachedToggleLocked or 0,
        buttonData.CachedLastRan or 0, buttonData.labelMidX or 0, buttonData.labelMidY or 0, buttonData.CachedLabel or "",
        buttonData.Cmd or "", buttonData.EvaluateLabel and 1 or 0, showLabel and 1 or 0, icon,
        buttonData.IconType or "", buttonData.IconLua or "", buttonData.TimerType or "", buttonData.Cooldown or ""
    )
    db:close()
end

function BMSettings:updateSetDB(setName, buttonNumber, buttonID)
    local db = self:InitializeDB()

    self:saveToDB(db, "INSERT OR REPLACE INTO sets (set_name, button_number, button_id) VALUES (?, ?, ?)",
        setName, buttonNumber, buttonID)
    db:close()
end

function BMSettings:updateCharacterDB(charName, charData)
    local db = self:InitializeDB()

    self:saveToDB(db, "INSERT INTO characters (character, character_locked, character_hide_title) VALUES (?, ?, ?)",
        charName, charData.Locked and 1 or 0, charData.HideTitleBar and 1 or 0)

    if charData.Windows then
        for windowID, windowData in ipairs(charData.Windows or {}) do
            windowData.Pos = windowData.Pos or { x = 0, y = 0, } -- Default position
            for setIndex, setName in ipairs(windowData.Sets or {}) do
                self:saveToDB(db, [[
                    INSERT OR REPLACE INTO windows (
                        server, character, window_id, window_fps, window_button_size, window_advtooltip,
                        window_compact, window_hide_title, window_width, window_height, window_x, window_y,
                        window_visible, window_font_size, window_locked, window_theme, window_set_id, window_set_name
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                    mq.TLO.EverQuest.Server(), charName, windowID, windowData.FPS or 0, windowData.ButtonSize or 0, windowData.AdvTooltips and 1 or 0,
                    windowData.CompactMode and 1 or 0, windowData.HideTitleBar and 1 or 0, windowData.Width or 0, windowData.Height or 0,
                    windowData.Pos.x or 0, windowData.Pos.y or 0, windowData.Visible and 1 or 0, windowData.Font or 0,
                    windowData.Locked and 1 or 0, windowData.Theme or "", setIndex, setName
                )
            end
        end
    end
    db:close()
end

function BMSettings:deleteButtonFromDB(id)
    local db = self:InitializeDB()
    self:saveToDB(db, "DELETE FROM buttons WHERE button_number = ?", id)
    db:close()
end

function BMSettings:deleteSetFromDB(setName)
    local db = self:InitializeDB()
    self:saveToDB(db, "DELETE FROM sets WHERE set_name = ?", setName)
    db:close()
end

function BMSettings:deleteButtonFromSetDB(setName, buttonNumber)
    local db = self:InitializeDB()
    self:saveToDB(db, "DELETE FROM sets WHERE set_name = ? AND button_number = ?", setName, buttonNumber)
    db:close()
end

function BMSettings:deleteSetFromCharacterDB(charName, SetName)
    local db = self:InitializeDB()
    self:saveToDB(db, "DELETE FROM windows WHERE character = ? AND window_set_name = ?", charName, SetName)
    db:close()
end

-- Main Function to Convert Config to DB
function BMSettings:convertConfigToDB(table_name)
    if table_name == nil then table_name = "all" end
    local db = self:InitializeDB()
    local config, err = loadfile(configFile)
    if err or not config then
        print("Error loading config file:", err)
        return
    end


    local settings = config()

    if table_name == "all" or table_name == "global" then
        -- Save Global Settings
        self:saveToDB(db, "INSERT OR REPLACE INTO settings (server, character, settings_version, settings_last_backup) VALUES (?, ?, ?, ?)",
            "global", "global", self.Globals.Version, settings.LastBackup or 0)
    end

    if table_name == "all" or table_name == "sets" then
        -- Save Sets
        for setName, buttons in pairs(settings.Sets) do
            for buttonNumber, buttonID in pairs(buttons) do
                self:saveToDB(db, "INSERT OR REPLACE INTO sets (set_name, button_number, button_id) VALUES (?, ?, ?)", setName, buttonNumber, buttonID)
            end
        end
    end


    if table_name == "all" or table_name == "buttons" then
        -- Save Buttons
        for buttonID, buttonData in pairs(settings.Buttons) do
            local icon = buttonData.Icon or -1
            local showLabel = icon == 0 and true or buttonData.ShowLabel ~= nil and buttonData.ShowLabel or true
            self:saveToDB(db, [[
            INSERT OR REPLACE INTO buttons (
                button_number, button_label, button_render, button_text_color, button_button_color,
                button_cached_countdown, button_cached_cooldown, button_cached_toggle_locked,
                button_cached_last_run, button_label_mid_x, button_label_mid_y, button_cached_label,
                button_cmd, button_evaluate_label, button_show_label, button_icon,
                button_icon_type, button_icon_lua, button_timer_type, button_cooldown
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                buttonID, buttonData.Label or "", buttonData.highestRenderTime or 0, buttonData.TextColorRGB or "", buttonData.ButtonColorRGB or "",
                buttonData.CachedCountDown or 0, buttonData.CachedCoolDownTimer or 0, buttonData.CachedToggleLocked or 0,
                buttonData.CachedLastRan or 0, buttonData.labelMidX or 0, buttonData.labelMidY or 0, buttonData.CachedLabel or "",
                buttonData.Cmd or "", buttonData.EvaluateLabel and 1 or 0, showLabel and 1 or 0, icon,
                buttonData.IconType or "", buttonData.IconLua or "", buttonData.TimerType or "", buttonData.Cooldown or ""
            )
        end
    end

    if table_name == "all" or table_name == "characters" then
        -- Save Character Data
        for charName, charData in pairs(settings.Characters or {}) do
            self:saveToDB(db, "INSERT INTO characters (character, character_locked, character_hide_title) VALUES (?, ?, ?)",
                charName, charData.Locked and 1 or 0, charData.HideTitleBar and 1 or 0)

            if charData.Windows then
                for windowID, windowData in ipairs(charData.Windows or {}) do
                    windowData.Pos = windowData.Pos or { x = 0, y = 0, } -- Default position
                    for setIndex, setName in ipairs(windowData.Sets or {}) do
                        self:saveToDB(db, [[
                        INSERT OR REPLACE INTO windows (
                            server, character, window_id, window_fps, window_button_size, window_advtooltip,
                            window_compact, window_hide_title, window_width, window_height, window_x, window_y,
                            window_visible, window_font_size, window_locked, window_theme, window_set_id, window_set_name
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
                            mq.TLO.EverQuest.Server(), charName, windowID, windowData.FPS or 0, windowData.ButtonSize or 0, windowData.AdvTooltips and 1 or 0,
                            windowData.CompactMode and 1 or 0, windowData.HideTitleBar and 1 or 0, windowData.Width or 0, windowData.Height or 0,
                            windowData.Pos.x or 0, windowData.Pos.y or 0, windowData.Visible and 1 or 0, windowData.Font or 0,
                            windowData.Locked and 1 or 0, windowData.Theme or "", setIndex, setName
                        )
                    end
                end
            end
        end
    end
    db:close()
    print("Conversion complete!")
end

-- Retrieve and Deserialize Data
function BMSettings:retrieveDataFromDB()
    local db = self:InitializeDB()
    self.settings = {
        Global = {},
        Version = 8,
        LastBackup = os.time(),
        Sets = {},
        Buttons = {},
        Characters = {},
    }

    local globalSettingsData = self:loadFromDB(db, "SELECT settings_version, settings_last_backup FROM settings WHERE server='global' AND character='global'")
    if globalSettingsData[1] then
        -- self.settings.Global = {
        --     ButtonSize = globalSettingsData[1].settings_button_size,
        -- }
        self.settings.Version = globalSettingsData[1].settings_version
        self.settings.LastBackup = globalSettingsData[1].settings_last_backup
    end

    local setsData = self:loadFromDB(db, "SELECT set_name, button_number, button_id FROM sets")
    for _, set in ipairs(setsData) do
        self.settings.Sets[set.set_name] = self.settings.Sets[set.set_name] or {}
        self.settings.Sets[set.set_name][set.button_number] = set.button_id
    end

    local buttonsData = self:loadFromDB(db, "SELECT * FROM buttons")
    for _, button in ipairs(buttonsData) do
        self.settings.Buttons[button.button_number] = {
            Label = button.button_label,
            highestRenderTime = button.button_render,
            TextColorRGB = button.button_text_color ~= "" and button.button_text_color or nil,
            ButtonColorRGB = button.button_button_color ~= "" and button.button_button_color or nil,
            CachedCountDown = button.button_cached_countdown,
            CachedCoolDownTimer = button.button_cached_cooldown,
            CachedToggleLocked = button.button_cached_toggle_locked,
            CachedLastRan = button.button_cached_last_run,
            labelMidX = button.button_label_mid_x,
            labelMidY = button.button_label_mid_y,
            CachedLabel = button.button_cached_label,
            Cmd = button.button_cmd,
            EvaluateLabel = button.button_evaluate_label == 1,
            ShowLabel = button.button_show_label == 1,
            Icon = button.button_icon > 0 and button.button_icon or nil,
            IconType = button.button_icon_type,
            IconLua = button.button_icon_lua,
            TimerType = button.button_timer_type,
            Cooldown = button.button_cooldown,
        }
    end

    local charactersData = self:loadFromDB(db, "SELECT character, character_locked, character_hide_title FROM characters")
    for _, char in ipairs(charactersData) do
        self.settings.Characters[char.character] = {
            Locked = char.character_locked == 1,
            HideTitleBar = char.character_hide_title == 1,
            Windows = {},
        }
    end

    local windowsData = self:loadFromDB(db, "SELECT * FROM windows ")
    for _, window in ipairs(windowsData) do
        local character = self.settings.Characters[window.character]
        character.Windows[window.window_id] = character.Windows[window.window_id] or {
            Sets = {},
        }
        local win = character.Windows[window.window_id]
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

    return self.settings
end

function BMSettings.new()
    local newSettings      = setmetatable({}, BMSettings)
    newSettings.CharConfig = string.format("%s_%s", mq.TLO.EverQuest.Server(), mq.TLO.Me.DisplayName())


    local config, err = loadfile(mq.configDir .. '/Button_Master_Theme.lua')
    if not err and config then
        BMSettings.Globals.CustomThemes = config()
    end

    return newSettings
end

function BMSettings:SaveSettings(doBroadcast)
    if doBroadcast == nil then doBroadcast = true end

    if not self.settings.LastBackup or os.time() - self.settings.LastBackup > 3600 * 24 then
        self.settings.LastBackup = os.time()
        mq.pickle(mq.configDir .. "/Buttonmaster-Backups/ButtonMaster-backup-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua",
            self.settings)
    end

    mq.pickle(settings_path, self.settings)

    if doBroadcast and mq.TLO.MacroQuest.GameState() == "INGAME" then
        btnUtils.Output("\aySent Event from(\am%s\ay) event(\at%s\ay)", mq.TLO.Me.DisplayName(), "SaveSettings")
        ButtonActors.send({
            from = mq.TLO.Me.DisplayName(),
            script = "ButtonMaster",
            event = "SaveSettings",
            newSettings =
                self.settings,
        })
    end
end

function BMSettings:NeedUpgrade()
    return (self.settings.Version or 0) < BMSettings.Globals.Version
end

function BMSettings:GetSettings()
    return self.settings
end

function BMSettings:GetSetting(settingKey)
    -- main setting
    if self.settings.Global[settingKey] ~= nil then return self.settings.Global[settingKey] end

    -- character sertting
    if self.settings.Characters[self.CharConfig] ~= nil and self.settings.Characters[self.CharConfig][settingKey] ~= nil then
        return self.settings.Characters[self.CharConfig]
            [settingKey]
    end

    -- not found.
    btnUtils.Debug("Setting not Found: %s", settingKey)
end

function BMSettings:GetCharacterWindow(windowId)
    return self.settings.Characters[self.CharConfig].Windows[windowId]
end

function BMSettings:GetCharacterWindowSets(windowId)
    if not self.settings.Characters or
        not self.settings.Characters[self.CharConfig] or
        not self.settings.Characters[self.CharConfig].Windows or
        not self.settings.Characters[self.CharConfig].Windows[windowId] or
        not self.settings.Characters[self.CharConfig].Windows[windowId].Sets then
        return {}
    end

    return self.settings.Characters[self.CharConfig].Windows[windowId].Sets
end

function BMSettings:GetCharConfig()
    return self.settings.Characters[self.CharConfig]
end

function BMSettings:GetButtonSectionKeyBySetIndex(Set, Index)
    -- somehow an invalid set exists. Just make it empty.
    if not self.settings.Sets[Set] then
        self.settings.Sets[Set] = {}
        btnUtils.Debug("Set: %s does not exist. Creating it.", Set)
    end

    local key = self.settings.Sets[Set][Index]

    -- if the key doesn't exist, get the current button counter and add 1
    if key == nil then
        key = self:GenerateButtonKey()
    end
    return key
end

function BMSettings:GetNextWindowId()
    return #self:GetCharConfig().Windows + 1
end

function BMSettings:GenerateButtonKey()
    local i = 1
    while (true) do
        local buttonKey = string.format("Button_%d", i)
        if self.settings.Buttons[buttonKey] == nil then
            return buttonKey
        end
        i = i + 1
    end
end

function BMSettings:ImportButtonAndSave(button, save)
    local key = self:GenerateButtonKey()
    self.settings.Buttons[key] = button
    if save then
        self:SaveSettings(true)
        self:updateButtonDB(button, key)
    end
    return key
end

---comment
---@param Set string
---@param Index number
---@return table
function BMSettings:GetButtonBySetIndex(Set, Index)
    if self.settings.Sets[Set] and self.settings.Sets[Set][Index] and self.settings.Buttons[self.settings.Sets[Set][Index]] then
        return self.settings.Buttons[self.settings.Sets[Set][Index]]
    end

    return { Unassigned = true, Label = tostring(Index), }
end

function BMSettings:ImportSetAndSave(sharableSet, windowId)
    -- is setname unqiue?
    local setName = sharableSet.Key
    if self.settings.Sets[setName] ~= nil then
        local newSetName = setName .. "_Imported_" .. os.date("%m-%d-%y-%H-%M-%S")
        btnUtils.Output("\ayImport Set Warning: Set name: \at%s\ay already exists renaming it to \at%s\ax", setName,
            newSetName)
        setName = newSetName
    end

    self.settings.Sets[setName] = {}
    for index, btnName in pairs(sharableSet.Set) do
        local newButtonName = self:ImportButtonAndSave(sharableSet.Buttons[btnName], false)
        self.settings.Sets[setName][index] = newButtonName
        self:updateSetDB(setName, index, newButtonName)
    end

    -- add set to user
    table.insert(self.settings.Characters[self.CharConfig].Windows[windowId].Sets, setName)

    self:SaveSettings(true)
    self:updateCharacterDB(self.CharConfig, self.settings.Characters[self.CharConfig])
end

function BMSettings:ConvertToLatestConfigVersion()
    self:LoadSettings()
    local needsSave = false
    local newSettings = {}

    if not self.settings.Version then
        -- version 2
        -- Run through all settings and make sure they are in the new format.
        for key, value in pairs(self.settings or {}) do
            -- TODO: Make buttons a seperate table instead of doing the string compare crap.
            if type(value) == 'table' then
                if key:find("^(Button_)") and value.Cmd1 or value.Cmd2 or value.Cmd3 or value.Cmd4 or value.Cmd5 then
                    btnUtils.Output("Key: %s Needs Converted!", key)
                    value.Cmd  = string.format("%s\n%s\n%s\n%s\n%s\n%s", value.Cmd or '', value.Cmd1 or '',
                        value.Cmd2 or '',
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
                    btnUtils.Output("\atUpgraded to \amv2\at!")
                end
            end
        end

        -- version 3
        -- Okay now that a similar but lua-based config is stabalized the next pass is going to be
        -- cleaning up the data model so we aren't doing a ton of string compares all over.
        newSettings.Buttons = {}
        newSettings.Sets = {}
        newSettings.Characters = {}
        newSettings.Global = self.settings.Global
        for key, value in pairs(self.settings) do
            local sStart, sEnd = key:find("^Button_")
            if sStart then
                local newKey = key --key:sub(sEnd + 1)
                btnUtils.Output("Old Key: \am%s\ax, New Key: \at%s\ax", key, newKey)
                newSettings.Buttons[newKey] = newSettings.Buttons[newKey] or {}
                if type(value) == 'table' then
                    for subKey, subValue in pairs(value) do
                        newSettings.Buttons[newKey][subKey] = tostring(subValue)
                    end
                end
                needsSave = true
            end
            sStart, sEnd = key:find("^Set_")
            if sStart then
                local newKey = key:sub(sEnd + 1)
                btnUtils.Output("Old Key: \am%s\ax, New Key: \at%s\ax", key, newKey)
                newSettings.Sets[newKey] = value
                needsSave                = true
            end
            sStart, sEnd = key:find("^Char_(.*)_Config")
            if sStart then
                local newKey = key:sub(sStart + 5, sEnd - 7)
                btnUtils.Output("Old Key: \am%s\ax, New Key: \at%s\ax", key, newKey)
                newSettings.Characters[newKey] = newSettings.Characters[newKey] or {}
                if type(value) == 'table' then
                    for subKey, subValue in pairs(value) do
                        newSettings.Characters[newKey].Sets = newSettings.Characters[newKey].Sets or {}
                        if type(subKey) == "number" then
                            table.insert(newSettings.Characters[newKey].Sets, subValue)
                        else
                            newSettings.Characters[newKey][subKey] = subValue
                        end
                    end
                end

                needsSave = true
            end
        end

        if needsSave then
            -- be nice and make a backup.
            mq.pickle(mq.configDir .. "/ButtonMaster-v3-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua", self.settings)
            self.settings = newSettings
            self:SaveSettings(true)
            needsSave = false
            btnUtils.Output("\atUpgraded to \amv3\at!")
        end
    end

    -- version 4 same as 5 but moved the version data around
    -- version 5
    -- Move Character sets to a specific window name
    if (self.settings.Version or 0) < 5 then
        mq.pickle(mq.configDir .. "/ButtonMaster-v4-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua", self.settings)

        needsSave = true
        newSettings = self.settings
        newSettings.Version = 5
        for charKey, _ in pairs(self.settings.Characters or {}) do
            if self.settings.Characters[charKey] and self.settings.Characters[charKey].Sets ~= nil then
                newSettings.Characters[charKey].Windows = {}
                table.insert(newSettings.Characters[charKey].Windows,
                    { Sets = newSettings.Characters[charKey].Sets, Visible = true, })
                newSettings.Characters[charKey].Sets = nil
                needsSave = true
            end
        end
        if needsSave then
            self.settings = newSettings
            self:SaveSettings(true)
            btnUtils.Output("\atUpgraded to \amv5\at!")
        end
    end

    -- version 6
    -- Moved TitleBar/Locked into the window settings
    -- Removed Button Count
    -- Removed Defaults for now
    if (self.settings.Version or 0) < 6 then
        mq.pickle(mq.configDir .. "/ButtonMaster-v5-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua", self.settings)
        needsSave = true
        newSettings = self.settings
        newSettings.Version = 6
        newSettings.Defaults = nil

        for _, curCharData in pairs(newSettings.Characters or {}) do
            for _, windowData in ipairs(curCharData.Windows or {}) do
                windowData.Locked = curCharData.Locked or false
                windowData.HideTitleBar = curCharData.HideTitleBar or false
            end
            curCharData.HideTitleBar = nil
            curCharData.Locked = nil
        end

        newSettings.Global.ButtonCount = nil

        if needsSave then
            self.settings = newSettings
            self:SaveSettings(true)
            btnUtils.Output("\atUpgraded to \amv6\at!")
        end
    end

    -- version 7
    -- moved ButtonSize and Font to each hotbar
    if (self.settings.Version or 0) < 7 then
        mq.pickle(mq.configDir .. "/ButtonMaster-v6-" .. os.date("%m-%d-%y-%H-%M-%S") .. ".lua", self.settings)
        needsSave = true
        newSettings = self.settings
        newSettings.Version = 7

        for _, curCharData in pairs(newSettings.Characters or {}) do
            for _, windowData in ipairs(curCharData.Windows or {}) do
                windowData.Font = (newSettings.Global.Font or 1) * 10
                windowData.ButtonSize = newSettings.Global.ButtnSize or 6
            end
        end

        newSettings.Global.Font = nil
        newSettings.Global.ButtonSize = nil
        newSettings.Global = nil

        if needsSave then
            self.settings = newSettings
            self:SaveSettings(true)
            btnUtils.Output("\atUpgraded to \amv%d\at!", BMSettings.Globals.Version)
        end
    end

    if self.settings.Version or 0 < 8 then
        self:convertConfigToDB()
        self.settings = self:retrieveDataFromDB()
    end
end

function BMSettings:InvalidateButtonCache()
    for _, button in pairs(self.settings.Buttons) do
        button.CachedLabel = nil
    end
end

function BMSettings:LoadSettings()
    if not io.open(dbPath, "r") then
        local config, err = loadfile(settings_path)
        if err or not config then
            local old_settings_path = settings_path:gsub(".lua", ".ini")
            printf("\ayUnable to load global settings file(%s), creating a new one from legacy ini(%s) file!",
                settings_path, old_settings_path)
            if btnUtils.file_exists(old_settings_path) then
                self.settings = btnUtils.loadINI(old_settings_path)
                self:SaveSettings(true)
            else
                printf("\ayUnable to load legacy settings file(%s), creating a new config!", old_settings_path)
                self.settings = {
                    Version = BMSettings.Globals.Version,
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
                        [self.CharConfig] = {
                            Windows = { [1] = { Visible = true, Pos = { x = 10, y = 10, }, Sets = {}, Locked = false, }, },
                        },
                    },
                }
                self:SaveSettings(true)
            end
        else
            self.settings = config()
        end
    else
        self.settings = self:retrieveDataFromDB()
    end

    -- if we need to upgrade anyway then bail after the load.
    if self:NeedUpgrade() then return false end

    self.settings.Characters[self.CharConfig] = self.settings.Characters[self.CharConfig] or {}
    self.settings.Characters[self.CharConfig].Windows = self.settings.Characters[self.CharConfig].Windows or
        { [1] = { Visible = true, Pos = { x = 10, y = 10, }, Sets = {}, Locked = false, }, }

    self:InvalidateButtonCache()
    return true
end

return BMSettings
