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
FactionBalance:RegisterEvent("ZONE_CHANGED_NEW_AREA") -- Новое событие для Dragonflight

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
    if factionData.total > 0 then
        local alliancePercent = (factionData.alliance / factionData.total) * 100
        local hordePercent = (factionData.horde / factionData.total) * 100
        
        allianceText:SetText(string.format("Alliance: %.1f%% (%d)", alliancePercent, factionData.alliance))
        hordeText:SetText(string.format("Horde: %.1f%% (%d)", hordePercent, factionData.horde))
        totalText:SetText(string.format("Total Players: %d", factionData.total))
        
        -- Добавляем точку на график
        AddGraphPoint()
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
    if factionData.dragonflightZones[currentZone] then
        -- Специальная обработка для зон Dragonflight
        SendChatMessage(".who " .. factionData.dragonflightZones[currentZone], "GUILD")
    else
        -- Стандартная обработка для других зон
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
    else
        print("|cFF00FF00FactionBalance команды:|r")
        print("|cFF00FF00/fb show|r - Показать окно")
        print("|cFF00FF00/fb hide|r - Скрыть окно")
        print("|cFF00FF00/fb reset|r - Сбросить позицию")
        print("|cFF00FF00/fb update|r - Обновить данные")
    end
end

-- Кнопка на миникарте
local minimapButton = CreateFrame("Button", "FactionBalanceMinimapButton", Minimap)
minimapButton:SetSize(32, 32)
minimapButton:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
minimapButton:SetNormalTexture("Interface\\AddOns\\Blizzard_GenericTraitUI\\Textures\\DragonflightButton")
minimapButton:SetHighlightTexture("Interface\\AddOns\\Blizzard_GenericTraitUI\\Textures\\DragonflightButtonHighlight")
minimapButton:SetPushedTexture("Interface\\AddOns\\Blizzard_GenericTraitUI\\Textures\\DragonflightButtonPressed")

minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" then
        if mainFrame:IsShown() then
            mainFrame:Hide()
        else
            mainFrame:Show()
        end
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Faction Balance")
    GameTooltip:AddLine("ЛКМ - Показать/Скрыть окно")
    GameTooltip:AddLine("ПКМ - Переместить кнопку")
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

-- Добавляем возможность перетаскивания кнопки миникарты
minimapButton:RegisterForDrag("RightButton")
minimapButton:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local angle = math.atan2(Minimap:GetCenter())
    self:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 
        math.cos(angle) * 80, 
        math.sin(angle) * 80)
end)

-- Обработчик событий
FactionBalance:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Создаем директорию для логов
        CreateLogDirectory()
        
        -- Инициализация при входе в игру
        if FactionBalanceDB then
            -- Восстанавливаем позицию окна
            if FactionBalanceDB.window then
                mainFrame:ClearAllPoints()
                mainFrame:SetPoint(FactionBalanceDB.window.point, UIParent, 
                    FactionBalanceDB.window.relativePoint, 
                    FactionBalanceDB.window.x, 
                    FactionBalanceDB.window.y)
            end
            
            -- Восстанавливаем позицию кнопки на миникарте
            if FactionBalanceDB.minimap then
                minimapButton:ClearAllPoints()
                minimapButton:SetPoint("CENTER", Minimap, "CENTER", 
                    math.cos(FactionBalanceDB.minimap.angle) * 80, 
                    math.sin(FactionBalanceDB.minimap.angle) * 80)
            end
        end
        
        -- Создаем сетку графика
        CreateGraphGrid()
        
        -- Запускаем таймер обновления данных
        C_Timer.NewTicker(300, UpdateFactionData) -- 300 секунд = 5 минут
        
        -- Запускаем таймер логирования
        C_Timer.NewTicker(600, function() -- 600 секунд = 10 минут
            LogFactionData(LOG_LEVELS.INFO, string.format("Current balance: Alliance %d, Horde %d, Total %d", 
                factionData.alliance, factionData.horde, factionData.total))
        end)
        
        -- Первое обновление данных
        UpdateFactionData()
    elseif event == "WHO_LIST_UPDATE" then
        -- Обработка обновления списка игроков
        local allianceCount = 0
        local hordeCount = 0
        
        for i = 1, GetNumWhoResults() do
            local name, guild, level, race, class, zone, classFileName = GetWhoInfo(i)
            if IsAllianceRace(race) then
                allianceCount = allianceCount + 1
            else
                hordeCount = hordeCount + 1
            end
        end
        
        factionData.alliance = allianceCount
        factionData.horde = hordeCount
        factionData.total = allianceCount + hordeCount
        
        -- Добавляем точку данных для графика
        AddGraphPoint()
        
        -- Проверяем дисбаланс
        if factionData.total > 0 then
            local alliancePercent = factionData.alliance / factionData.total
            local hordePercent = factionData.horde / factionData.total
            
            if math.abs(alliancePercent - hordePercent) > IMBALANCE_THRESHOLD then
                local currentTime = GetTime()
                if currentTime - factionData.lastNotification > NOTIFICATION_COOLDOWN then
                    factionData.lastNotification = currentTime
                    StartWarningAnimation()
                    LogFactionData(LOG_LEVELS.WARNING, 
                        string.format("Дисбаланс фракций: Альянс %.1f%% vs Орда %.1f%%", 
                        alliancePercent * 100, hordePercent * 100))
                end
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        if message:find("There are %d+ players online") then
            -- Сброс данных при получении сообщения о количестве игроков
            factionData.alliance = 0
            factionData.horde = 0
            factionData.total = 0
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        -- Обновляем данные при смене зоны
        UpdateFactionData()
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