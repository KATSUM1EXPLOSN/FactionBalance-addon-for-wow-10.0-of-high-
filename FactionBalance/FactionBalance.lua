--[[
    Faction Balance
    Author: KATSUMI EXPLOSN
    Version: 1.0.3 R1
    Interface: 100200 (Dragonflight)
]]--

local FactionBalance = CreateFrame("Frame")
FactionBalance:RegisterEvent("PLAYER_LOGIN")
FactionBalance:RegisterEvent("WHO_LIST_UPDATE")
FactionBalance:RegisterEvent("CHAT_MSG_SYSTEM")
FactionBalance:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FactionBalance:RegisterEvent("PLAYER_FLAGS_CHANGED")
FactionBalance:RegisterEvent("ADDON_LOADED")

-- Включаем отладочный режим
local DEBUG_MODE = true

-- Функция для отладочных сообщений
local function DebugPrint(message)
    if DEBUG_MODE then
        print("|cFF00FF00[FactionBalance Debug]|r " .. message)
    end
end

-- Проверка версии игры
local function CheckGameVersion()
    local version = GetBuildInfo()
    DebugPrint("Game version: " .. version)
    
    -- Проверяем, что мы в Dragonflight
    if not C_Map.GetBestMapForUnit then
        DebugPrint("Warning: This addon requires Dragonflight or later")
        return false
    end
    
    return true
end

-- Данные для хранения информации о фракциях
local factionData = {
    alliance = 0,
    horde = 0,
    total = 0,
    history = {}, -- История изменений
    lastNotification = 0, -- Время последнего уведомления
    graphData = {}, -- Данные для графика
    maxHistoryPoints = 20, -- Максимальное количество точек на графике
    dragonflightZones = { -- Новые зоны Dragonflight
        [2022] = "Берега Пробуждения",
        [2023] = "Равнины Он'ары",
        [2024] = "Запретное Хранилище",
        [2025] = "Тальдразус",
        [2026] = "Зарождающиеся Острова"
    },
    -- Новая статистика
    classStats = {
        alliance = {},
        horde = {}
    },
    raceStats = {
        alliance = {},
        horde = {}
    },
    levelStats = {
        alliance = {},
        horde = {}
    },
    zoneStats = {
        alliance = {},
        horde = {}
    },
    onlineTime = {
        alliance = {},
        horde = {}
    },
    peakHours = {
        alliance = {},
        horde = {}
    }
}

-- Константы для системы уведомлений
local NOTIFICATION_COOLDOWN = 300 -- 5 минут между уведомлениями
local IMBALANCE_THRESHOLD = 0.6 -- 60% дисбаланс для уведомления

-- Цвета для визуализации
local COLORS = {
    ALLIANCE = {r = 0, g = 0.44, b = 0.87},
    HORDE = {r = 0.77, g = 0.12, b = 0.23},
    BACKGROUND = {r = 0.1, g = 0.1, b = 0.1, a = 0.95},
    GRID = {r = 0.3, g = 0.3, b = 0.3, a = 0.3},
    WARNING = {r = 1, g = 0, b = 0, a = 0.5},
    DRAGONFLIGHT = { -- Новые цвета Dragonflight
        BLUE = {r = 0.0, g = 0.44, b = 0.87},
        GOLD = {r = 1.0, g = 0.84, b = 0.0},
        RED = {r = 0.77, g = 0.12, b = 0.23},
        GREEN = {r = 0.1, g = 0.79, b = 0.37}
    }
}

-- Уровни логирования
local LOG_LEVELS = {
    DEBUG = 1,
    INFO = 2,
    WARNING = 3,
    ERROR = 4
}

local LOG_COLORS = {
    [LOG_LEVELS.DEBUG] = "|cFF888888",
    [LOG_LEVELS.INFO] = "|cFF00FF00",
    [LOG_LEVELS.WARNING] = "|cFFFFFF00",
    [LOG_LEVELS.ERROR] = "|cFFFF0000"
}

-- Система логирования
local LOG_PATH = "Interface\\AddOns\\FactionBalance\\Logs"
local LOG_FILE = "faction_balance.log"
local MAX_LOG_SIZE = 1024 * 1024 -- 1MB
local currentLogSize = 0

-- Настройки фильтров
local filterSettings = {
    minLevel = 1,
    maxLevel = 70,
    zones = {},
    showAFK = true,
    showOffline = false
}

-- Настройки интерфейса
local interfaceSettings = {
    theme = "Dragonflight",
    displayMode = "graph", -- graph, numbers, percentages
    colors = {
        alliance = {r = 0, g = 0.44, b = 0.87},
        horde = {r = 0.77, g = 0.12, b = 0.23},
        background = {r = 0.1, g = 0.1, b = 0.1, a = 0.95}
    }
}

-- Сохранение профилей
local profiles = {
    default = {
        filters = filterSettings,
        interface = interfaceSettings
    }
}

-- Функция для создания директории логов
local function CreateLogDirectory()
    if not IsAddOnLoaded("FactionBalance") then return end
    
    -- Проверяем существование директории
    local file = io.open(LOG_PATH .. "\\test.tmp", "w")
    if file then
        file:close()
        os.remove(LOG_PATH .. "\\test.tmp")
    else
        -- Создаем директорию, если она не существует
        local success = CreateDirectory(LOG_PATH)
        if not success then
            print("|cFFFF0000FactionBalance: Failed to create log directory|r")
            return false
        end
    end
    return true
end

-- Функция для ротации логов
local function RotateLogs()
    local currentTime = date("%Y-%m-%d")
    local backupFile = LOG_PATH .. "\\faction_balance_" .. currentTime .. ".log"
    os.rename(LOG_PATH .. "\\" .. LOG_FILE, backupFile)
    currentLogSize = 0
end

-- Функция для логирования данных
local function LogFactionData(level, message)
    if not CreateLogDirectory() then return end
    
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local logEntry = string.format("[%s] [%s] %s\n", 
        timestamp, 
        LOG_COLORS[level] .. LOG_LEVELS[level] .. "|r",
        message)
    
    -- Проверяем размер файла
    if currentLogSize + #logEntry > MAX_LOG_SIZE then
        RotateLogs()
    end
    
    -- Запись в файл
    local file = io.open(LOG_PATH .. "\\" .. LOG_FILE, "a")
    if file then
        file:write(logEntry)
        file:close()
        currentLogSize = currentLogSize + #logEntry
    else
        print("|cFFFF0000FactionBalance: Failed to write to log file|r")
    end
end

-- Создание основного фрейма для отображения
local mainFrame = CreateFrame("Frame", "FactionBalanceFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(300, 200) -- Увеличиваем размер для графика
mainFrame:SetPoint("CENTER")
mainFrame:SetBackdrop(BACKDROP_DRAGONFLIGHT)
mainFrame:SetBackdropColor(COLORS.BACKGROUND.r, COLORS.BACKGROUND.g, COLORS.BACKGROUND.b, COLORS.BACKGROUND.a)
mainFrame:SetBackdropBorderColor(COLORS.DRAGONFLIGHT.GOLD.r, COLORS.DRAGONFLIGHT.GOLD.g, COLORS.DRAGONFLIGHT.GOLD.b, 1)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Сохраняем позицию окна
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    FactionBalanceDB = FactionBalanceDB or {}
    FactionBalanceDB.window = {
        point = point,
        relativePoint = relativePoint,
        x = xOfs,
        y = yOfs
    }
end)
mainFrame:Hide()

-- Добавляем драконий орнамент
local dragonOrnament = mainFrame:CreateTexture(nil, "OVERLAY")
dragonOrnament:SetTexture("Interface\\AddOns\\Blizzard_GenericTraitUI\\Textures\\DragonflightCorner")
dragonOrnament:SetPoint("TOPRIGHT", -5, -5)
dragonOrnament:SetSize(64, 64)

-- Добавляем драконий фон
local background = mainFrame:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\AddOns\\Blizzard_GenericTraitUI\\Textures\\DragonflightBackground")
background:SetAllPoints()
background:SetAlpha(0.2)

-- Создание фрейма для графика
local graphFrame = CreateFrame("Frame", nil, mainFrame)
graphFrame:SetSize(280, 100)
graphFrame:SetPoint("TOP", mainFrame, "TOP", 0, -30)

-- Создание сетки для графика
local function CreateGraphGrid()
    local grid = graphFrame:CreateTexture(nil, "BACKGROUND")
    grid:SetAllPoints()
    grid:SetColorTexture(COLORS.GRID.r, COLORS.GRID.g, COLORS.GRID.b, COLORS.GRID.a)
    
    -- Вертикальные линии
    for i = 1, 4 do
        local line = graphFrame:CreateTexture(nil, "BACKGROUND")
        line:SetSize(1, 100)
        line:SetPoint("LEFT", graphFrame, "LEFT", i * 70, 0)
        line:SetColorTexture(COLORS.GRID.r, COLORS.GRID.g, COLORS.GRID.b, COLORS.GRID.a)
    end
    
    -- Горизонтальные линии
    for i = 1, 4 do
        local line = graphFrame:CreateTexture(nil, "BACKGROUND")
        line:SetSize(280, 1)
        line:SetPoint("TOP", graphFrame, "TOP", 0, -i * 25)
        line:SetColorTexture(COLORS.GRID.r, COLORS.GRID.g, COLORS.GRID.b, COLORS.GRID.a)
    end
end

-- Создание линий графика
local allianceLine = graphFrame:CreateLine()
allianceLine:SetThickness(2)
allianceLine:SetColorTexture(COLORS.ALLIANCE.r, COLORS.ALLIANCE.g, COLORS.ALLIANCE.b, 1)

local hordeLine = graphFrame:CreateLine()
hordeLine:SetThickness(2)
hordeLine:SetColorTexture(COLORS.HORDE.r, COLORS.HORDE.g, COLORS.HORDE.b, 1)

-- Функция обновления графика
local function UpdateGraph()
    if #factionData.graphData == 0 then return end
    
    -- Очищаем предыдущие линии
    allianceLine:ClearLines()
    hordeLine:ClearLines()
    
    local width = graphFrame:GetWidth()
    local height = graphFrame:GetHeight()
    local step = width / (#factionData.graphData - 1)
    
    for i = 1, #factionData.graphData do
        local data = factionData.graphData[i]
        local x = (i - 1) * step
        local allianceY = height * (1 - data.alliancePercent)
        local hordeY = height * (1 - data.hordePercent)
        
        if i == 1 then
            allianceLine:SetStartPoint("TOPLEFT", graphFrame, "TOPLEFT", x, allianceY)
            hordeLine:SetStartPoint("TOPLEFT", graphFrame, "TOPLEFT", x, hordeY)
        else
            allianceLine:AddLine("TOPLEFT", graphFrame, "TOPLEFT", x, allianceY)
            hordeLine:AddLine("TOPLEFT", graphFrame, "TOPLEFT", x, hordeY)
        end
    end
end

-- Функция добавления точки данных
local function AddGraphPoint()
    if factionData.total > 0 then
        local alliancePercent = factionData.alliance / factionData.total
        local hordePercent = factionData.horde / factionData.total
        
        table.insert(factionData.graphData, {
            alliancePercent = alliancePercent,
            hordePercent = hordePercent,
            timestamp = GetTime()
        })
        
        -- Ограничиваем количество точек
        while #factionData.graphData > factionData.maxHistoryPoints do
            table.remove(factionData.graphData, 1)
        end
        
        UpdateGraph()
    end
end

-- Анимация предупреждения о дисбалансе
local warningAnimation = CreateFrame("Frame", nil, mainFrame)
warningAnimation:SetAllPoints()
warningAnimation:Hide()

local warningTexture = warningAnimation:CreateTexture(nil, "OVERLAY")
warningTexture:SetAllPoints()
warningTexture:SetColorTexture(COLORS.WARNING.r, COLORS.WARNING.g, COLORS.WARNING.b, COLORS.WARNING.a)

local function StartWarningAnimation()
    warningAnimation:Show()
    local fadeIn = warningAnimation:CreateAnimationGroup()
    local fadeOut = warningAnimation:CreateAnimationGroup()
    
    local fadeInAnim = fadeIn:CreateAnimation("Alpha")
    fadeInAnim:SetFromAlpha(0)
    fadeInAnim:SetToAlpha(0.5)
    fadeInAnim:SetDuration(0.5)
    
    local fadeOutAnim = fadeOut:CreateAnimation("Alpha")
    fadeOutAnim:SetFromAlpha(0.5)
    fadeOutAnim:SetToAlpha(0)
    fadeOutAnim:SetDuration(0.5)
    
    fadeIn:SetScript("OnFinished", function()
        fadeOut:Play()
    end)
    
    fadeOut:SetScript("OnFinished", function()
        warningAnimation:Hide()
    end)
    
    fadeIn:Play()
end

-- Обновленная функция проверки дисбаланса
local function CheckImbalance()
    if factionData.total == 0 then return end
    
    local alliancePercent = factionData.alliance / factionData.total
    local hordePercent = factionData.horde / factionData.total
    
    -- Проверяем дисбаланс
    if alliancePercent > IMBALANCE_THRESHOLD or hordePercent > IMBALANCE_THRESHOLD then
        local currentTime = GetTime()
        if currentTime - factionData.lastNotification > NOTIFICATION_COOLDOWN then
            local message = string.format("|cFFFF0000Warning: Faction imbalance detected!|r\nAlliance: %.1f%%\nHorde: %.1f%%", 
                alliancePercent * 100, hordePercent * 100)
            UIErrorsFrame:AddMessage(message, 1.0, 0.0, 0.0, 1.0)
            factionData.lastNotification = currentTime
            
            -- Запускаем анимацию предупреждения
            StartWarningAnimation()
            
            -- Логируем предупреждение
            LogFactionData(LOG_LEVELS.WARNING, string.format("Faction imbalance: Alliance %.1f%%, Horde %.1f%%", 
                alliancePercent * 100, hordePercent * 100))
        end
    end
end

-- Обновленная функция обновления отображения
local function UpdateDisplay()
    DebugPrint("Updating display")
    DebugPrint("Total players: " .. tostring(factionData.total))
    DebugPrint("Alliance: " .. tostring(factionData.alliance))
    DebugPrint("Horde: " .. tostring(factionData.horde))
    
    if factionData.total > 0 then
        local alliancePercent = (factionData.alliance / factionData.total) * 100
        local hordePercent = (factionData.horde / factionData.total) * 100
        
        DebugPrint("Alliance %: " .. string.format("%.1f", alliancePercent))
        DebugPrint("Horde %: " .. string.format("%.1f", hordePercent))
        
        allianceText:SetText(string.format("Alliance: %.1f%% (%d)", alliancePercent, factionData.alliance))
        hordeText:SetText(string.format("Horde: %.1f%% (%d)", hordePercent, factionData.horde))
        totalText:SetText(string.format("Total Players: %d", factionData.total))
        
        AddGraphPoint()
    else
        DebugPrint("No players found")
        allianceText:SetText("Alliance: 0% (0)")
        hordeText:SetText("Horde: 0% (0)")
        totalText:SetText("Total Players: 0")
    end
end

-- Заголовок
local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", mainFrame, "TOP", 0, -10)
title:SetText("Faction Balance")

-- Текст для отображения процентов
local allianceText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
allianceText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -40)
allianceText:SetTextColor(0, 0.44, 0.87) -- Синий цвет для Альянса

local hordeText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
hordeText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -60)
hordeText:SetTextColor(0.77, 0.12, 0.23) -- Красный цвет для Орды

local totalText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
totalText:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 20, -80)
totalText:SetTextColor(1, 1, 1) -- Белый цвет для общего количества

-- Функция обновления данных
local function UpdateFactionData()
    local currentZone = C_Map.GetBestMapForUnit("player")
    DebugPrint("Current zone: " .. tostring(currentZone))
    
    if factionData.dragonflightZones[currentZone] then
        DebugPrint("Sending .who for zone: " .. factionData.dragonflightZones[currentZone])
        SendChatMessage(".who " .. factionData.dragonflightZones[currentZone], "GUILD")
    else
        DebugPrint("Sending general .who")
        SendChatMessage(".who", "GUILD")
    end
end

-- Слэш-команды
SLASH_FACTIONBALANCE1 = "/factionbalance"
SLASH_FACTIONBALANCE2 = "/fb"
SlashCmdList["FACTIONBALANCE"] = function(msg)
    if msg == "show" then
        mainFrame:Show()
    elseif msg == "hide" then
        mainFrame:Hide()
    elseif msg == "reset" then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER")
    elseif msg == "update" then
        UpdateFactionData()
    elseif msg == "chat" then
        SendBalanceToChat()
    elseif msg == "stats" then
        ShowStatistics()
    elseif msg == "filter" then
        ToggleFilterMenu()
    elseif msg == "theme" then
        ToggleThemeMenu()
    elseif msg == "move" then
        MoveMinimapButton()
    else
        print("|cFF00FF00FactionBalance команды:|r")
        print("|cFF00FF00/fb show|r - Показать окно")
        print("|cFF00FF00/fb hide|r - Скрыть окно")
        print("|cFF00FF00/fb reset|r - Сбросить позицию")
        print("|cFF00FF00/fb update|r - Обновить данные")
        print("|cFF00FF00/fb chat|r - Отправить баланс фракций в чат")
        print("|cFF00FF00/fb stats|r - Показать статистику")
        print("|cFF00FF00/fb filter|r - Открыть меню фильтров")
        print("|cFF00FF00/fb theme|r - Переключить тему")
        print("|cFF00FF00/fb move|r - Переместить кнопку миникарты")
    end
end

-- Создание кнопки у миникарты
local function CreateMinimapButton()
    DebugPrint("Creating minimap button")
    
    -- Создаем кнопку
    local button = CreateFrame("Button", "FactionBalanceMinimapButton", Minimap)
    button:SetSize(27, 27)
    button:SetFrameStrata("LOW")
    button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -25, -60)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("RightButton")
    
    -- Создаем текстуру для кнопки
    local buttonTexture = button:CreateTexture(nil, "BACKGROUND")
    buttonTexture:SetTexture("Interface\\Icons\\INV_Misc_Scales_01")
    buttonTexture:SetAllPoints()
    button:SetNormalTexture(buttonTexture)
    
    -- Создаем текстуру для нажатия
    local pushedTexture = button:CreateTexture(nil, "BACKGROUND")
    pushedTexture:SetTexture("Interface\\Icons\\INV_Misc_Scales_01")
    pushedTexture:SetAllPoints()
    button:SetPushedTexture(pushedTexture)
    
    -- Добавляем рамку
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(46, 46)
    border:SetPoint("TOPLEFT")
    
    -- Добавляем подсветку
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    button:SetHighlightTexture(highlight)
    
    -- Обработчики событий
    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if mainFrame:IsShown() then
                mainFrame:Hide()
            else
                mainFrame:Show()
            end
        end
    end)
    
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Faction Balance")
        GameTooltip:AddLine("ЛКМ - Показать/Скрыть окно")
        GameTooltip:AddLine("ПКМ - Переместить кнопку")
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    button:SetScript("OnDragStart", function(self)
        self:StartMoving()
        GameTooltip:Hide()
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local angle = math.atan2(Minimap:GetCenter())
        self:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 
            math.cos(angle) * 80, 
            math.sin(angle) * 80)
        
        FactionBalanceDB = FactionBalanceDB or {}
        FactionBalanceDB.minimap = {
            angle = angle
        }
    end)
    
    -- Делаем кнопку видимой
    button:Show()
    DebugPrint("Minimap button created and shown")
    
    return button
end

-- Инициализация кнопки
local function InitializeMinimapButton()
    DebugPrint("Initializing minimap button")
    
    if not Minimap then
        DebugPrint("Minimap not found")
        return
    end
    
    if FactionBalanceDB and FactionBalanceDB.minimap and FactionBalanceMinimapButton then
        local angle = FactionBalanceDB.minimap.angle
        FactionBalanceMinimapButton:ClearAllPoints()
        FactionBalanceMinimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 
            math.cos(angle) * 80, 
            math.sin(angle) * 80)
        DebugPrint("Minimap button position restored")
    end
end

-- Функция для перемещения кнопки
local function MoveMinimapButton()
    if FactionBalanceMinimapButton then
        local angle = math.atan2(Minimap:GetCenter())
        FactionBalanceMinimapButton:ClearAllPoints()
        FactionBalanceMinimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 
            math.cos(angle) * 80, 
            math.sin(angle) * 80)
        
        FactionBalanceDB = FactionBalanceDB or {}
        FactionBalanceDB.minimap = {
            angle = angle
        }
        DebugPrint("Minimap button moved to new position")
    end
end

-- Регистрация событий для кнопки
local minimapFrame = CreateFrame("Frame")
minimapFrame:RegisterEvent("PLAYER_LOGIN")
minimapFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Ждем загрузки миникарты
        C_Timer.After(2, function()
            if Minimap then
                InitializeMinimapButton()
            end
        end)
    end
end)

-- Регистрируем события
FactionBalance:RegisterEvent("PLAYER_LOGIN")
FactionBalance:RegisterEvent("WHO_LIST_UPDATE")
FactionBalance:RegisterEvent("CHAT_MSG_SYSTEM")
FactionBalance:RegisterEvent("ZONE_CHANGED_NEW_AREA")
FactionBalance:RegisterEvent("PLAYER_FLAGS_CHANGED")

-- Обработчик событий
FactionBalance:SetScript("OnEvent", function(self, event, ...)
    DebugPrint("Event received: " .. event)
    
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "FactionBalance" then
            DebugPrint("Addon loaded")
            if not CheckGameVersion() then
                return
            end
        end
    elseif event == "PLAYER_LOGIN" then
        DebugPrint("Player login - Initializing addon")
        
        -- Ждем загрузки миникарты
        C_Timer.After(2, function()
            if Minimap then
                DebugPrint("Minimap found, initializing button")
                InitializeMinimapButton()
            else
                DebugPrint("Minimap not found after delay")
            end
        end)
        
        CreateLogDirectory()
        CreateGraphGrid()
        C_Timer.NewTicker(300, UpdateFactionData)
        UpdateFactionData()
    elseif event == "WHO_LIST_UPDATE" then
        DebugPrint("WHO_LIST_UPDATE received")
        local allianceCount = 0
        local hordeCount = 0
        
        for i = 1, GetNumWhoResults() do
            local name, guild, level, race, class, zone, classFileName = GetWhoInfo(i)
            DebugPrint(string.format("Player %d: %s (%s)", i, name, race))
            
            if IsAllianceRace(race) then
                allianceCount = allianceCount + 1
            else
                hordeCount = hordeCount + 1
            end
        end
        
        factionData.alliance = allianceCount
        factionData.horde = hordeCount
        factionData.total = allianceCount + hordeCount
        
        DebugPrint("Updated counts - Alliance: " .. allianceCount .. ", Horde: " .. hordeCount)
        UpdateDisplay()
        
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        DebugPrint("System message: " .. tostring(message))
        
        if message:find("There are %d+ players online") then
            DebugPrint("Resetting faction data")
            factionData.alliance = 0
            factionData.horde = 0
            factionData.total = 0
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        DebugPrint("Zone changed")
        UpdateFactionData()
    elseif event == "PLAYER_FLAGS_CHANGED" then
        UpdateAFKStatus()
    end
end)

-- Функция проверки расы на принадлежность к Альянсу
function IsAllianceRace(race)
    local allianceRaces = {
        ["Human"] = true,
        ["Dwarf"] = true,
        ["NightElf"] = true,
        ["Gnome"] = true,
        ["Draenei"] = true,
        ["Worgen"] = true,
        ["Pandaren"] = true,
        ["VoidElf"] = true,
        ["LightforgedDraenei"] = true,
        ["DarkIronDwarf"] = true,
        ["KulTiran"] = true,
        ["Mechagnome"] = true,
        ["Dracthyr"] = true -- Новая раса Dragonflight
    }
    return allianceRaces[race] or false
end

-- Функции для работы с профилями
local function SaveProfile(name)
    profiles[name] = {
        filters = CopyTable(filterSettings),
        interface = CopyTable(interfaceSettings)
    }
end

local function LoadProfile(name)
    if profiles[name] then
        filterSettings = CopyTable(profiles[name].filters)
        interfaceSettings = CopyTable(profiles[name].interface)
        UpdateDisplay()
    end
end

-- Функции для работы с чатом
local function SendBalanceToChat()
    local alliancePercent = math.floor((factionData.alliance / factionData.total) * 100)
    local hordePercent = math.floor((factionData.horde / factionData.total) * 100)
    SendChatMessage(string.format("Баланс фракций: Альянс %d%% (%d) | Орда %d%% (%d)", 
        alliancePercent, factionData.alliance, 
        hordePercent, factionData.horde), "SAY")
end

-- Функции для фильтрации
local function ApplyFilters()
    local filteredAlliance = 0
    local filteredHorde = 0
    
    for _, player in pairs(factionData.players) do
        if MeetsFilterCriteria(player) then
            if player.faction == "Alliance" then
                filteredAlliance = filteredAlliance + 1
            else
                filteredHorde = filteredHorde + 1
            end
        end
    end
    
    return filteredAlliance, filteredHorde
end

local function MeetsFilterCriteria(player)
    if player.level < filterSettings.minLevel or player.level > filterSettings.maxLevel then
        return false
    end
    
    if not filterSettings.showAFK and player.isAFK then
        return false
    end
    
    if not filterSettings.showOffline and not player.isOnline then
        return false
    end
    
    if #filterSettings.zones > 0 and not tContains(filterSettings.zones, player.zone) then
        return false
    end
    
    return true
end

-- Функции для статистики
local function UpdateStatistics()
    local currentHour = tonumber(date("%H"))
    
    -- Обновляем пиковые часы
    factionData.peakHours.alliance[currentHour] = (factionData.peakHours.alliance[currentHour] or 0) + 1
    factionData.peakHours.horde[currentHour] = (factionData.peakHours.horde[currentHour] or 0) + 1
    
    -- Обновляем время онлайн
    for _, player in pairs(factionData.players) do
        if player.isOnline then
            local faction = player.faction == "Alliance" and "alliance" or "horde"
            factionData.onlineTime[faction][player.name] = (factionData.onlineTime[faction][player.name] or 0) + 1
        end
    end
end

local function ShowStatistics()
    -- Создаем окно статистики
    local statsFrame = CreateFrame("Frame", "FactionBalanceStatsFrame", UIParent, "BackdropTemplate")
    statsFrame:SetSize(400, 500)
    statsFrame:SetPoint("CENTER")
    statsFrame:SetBackdrop(BACKDROP_DRAGONFLIGHT)
    statsFrame:SetMovable(true)
    statsFrame:EnableMouse(true)
    statsFrame:RegisterForDrag("LeftButton")
    
    -- Добавляем вкладки
    local tabs = {
        "Общая статистика",
        "Классы и расы",
        "Уровни",
        "Зоны",
        "Время онлайн"
    }
    
    for i, tabName in ipairs(tabs) do
        local tab = CreateFrame("Button", "FactionBalanceTab"..i, statsFrame)
        tab:SetSize(80, 30)
        tab:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", (i-1)*80, 0)
        tab:SetText(tabName)
        tab:SetScript("OnClick", function() ShowTabContent(i) end)
    end
end

-- Функции для обновления отображения
local function UpdateDisplay()
    if interfaceSettings.displayMode == "graph" then
        UpdateGraph()
    elseif interfaceSettings.displayMode == "numbers" then
        UpdateNumbersDisplay()
    elseif interfaceSettings.displayMode == "percentages" then
        UpdatePercentagesDisplay()
    end
end

local function UpdateNumbersDisplay()
    local alliance, horde = ApplyFilters()
    mainFrame.allianceText:SetText(string.format("Альянс: %d", alliance))
    mainFrame.hordeText:SetText(string.format("Орда: %d", horde))
end

local function UpdatePercentagesDisplay()
    local alliance, horde = ApplyFilters()
    local total = alliance + horde
    if total > 0 then
        local alliancePercent = math.floor((alliance / total) * 100)
        local hordePercent = math.floor((horde / total) * 100)
        mainFrame.allianceText:SetText(string.format("Альянс: %d%%", alliancePercent))
        mainFrame.hordeText:SetText(string.format("Орда: %d%%", hordePercent))
    end
end

-- Инициализация аддона
function InitializeAddon()
    -- Загрузка сохраненных настроек
    FactionBalanceDB = FactionBalanceDB or {}
    if FactionBalanceDB.profiles then
        profiles = FactionBalanceDB.profiles
    end
    
    -- Создание основного интерфейса
    CreateMainFrame()
    CreateMinimapButton()
    
    -- Инициализация системы логирования
    CreateLogDirectory()
    
    -- Запуск периодического обновления
    C_Timer.NewTicker(60, function() UpdateStatistics() end)
end 