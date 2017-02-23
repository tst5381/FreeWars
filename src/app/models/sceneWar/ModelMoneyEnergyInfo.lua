
--[[--------------------------------------------------------------------------------
-- ModelMoneyEnergyInfo用于显示玩家的金钱和能量，同时也负责在被点击时弹出战场操作菜单（ModelWarCommandMenu）。
--
-- 主要职责及使用场景举例：
--   同上
--
-- 其他：
--   点击时弹出战场操作菜单本来与本类没有关系，但为了节省屏幕空间，所以就这么设定了。
--]]--------------------------------------------------------------------------------

local ModelMoneyEnergyInfo = class("ModelMoneyEnergyInfo")

local LocalizationFunctions = requireFW("src.app.utilities.LocalizationFunctions")
local SingletonGetters      = requireFW("src.app.utilities.SingletonGetters")

local getLocalizedText       = LocalizationFunctions.getLocalizedText
local getModelFogMap         = SingletonGetters.getModelFogMap
local getPlayerIndexLoggedIn = SingletonGetters.getPlayerIndexLoggedIn
local isTotalReplay          = SingletonGetters.isTotalReplay
local string                 = string

--------------------------------------------------------------------------------
-- The util functions.
--------------------------------------------------------------------------------
local function generateInfoText(self)
    local modelSceneWar = self.m_ModelSceneWar
    local playerIndex   = self.m_PlayerIndex
    local modelPlayer   = SingletonGetters.getModelPlayerManager(modelSceneWar):getModelPlayer(playerIndex)
    return string.format("%s: %s\n%s: %s\n%s: %d",
        getLocalizedText(25, "Player"),  modelPlayer:getNickname(),
        getLocalizedText(25, "Fund"),    ((not isTotalReplay(modelSceneWar)) and (getModelFogMap(modelSceneWar):isFogOfWarCurrently()) and (playerIndex ~= getPlayerIndexLoggedIn(modelSceneWar))) and ("--") or (modelPlayer:getFund()),
        getLocalizedText(25, "Energy"),  modelPlayer:getEnergy()
    )
end

--------------------------------------------------------------------------------
-- The private callback functions on script events.
--------------------------------------------------------------------------------
local function onEvtChatManagerUpdated(self, event)
    local menu = self.m_ModelWarCommandMenu
    self.m_View:setVisible((not menu:isEnabled()) and (not menu:isHiddenWithHideUI()) and (not self.m_ModelChatManager:isEnabled()))
end

local function onEvtPlayerIndexUpdated(self, event)
    local playerIndex = event.playerIndex
    self.m_PlayerIndex = playerIndex

    self.m_View:setInfoText(generateInfoText(self))
        :updateWithPlayerIndex(playerIndex)
end

local function onEvtModelPlayerUpdated(self, event)
    if ((self.m_PlayerIndex == event.playerIndex) and (self.m_View)) then
        self.m_View:setInfoText(generateInfoText(self))
    end
end

local function onEvtWarCommandMenuUpdated(self, event)
    local menu = self.m_ModelWarCommandMenu
    self.m_View:setVisible((not menu:isEnabled()) and (not menu:isHiddenWithHideUI()) and (not self.m_ModelChatManager:isEnabled()))
end

--------------------------------------------------------------------------------
-- The constructor and initializers.
--------------------------------------------------------------------------------
function ModelMoneyEnergyInfo:ctor(param)
    return self
end

--------------------------------------------------------------------------------
-- The callback functions on start running/script events.
--------------------------------------------------------------------------------
function ModelMoneyEnergyInfo:onStartRunning(modelSceneWar)
    self.m_ModelSceneWar       = modelSceneWar
    self.m_ModelChatManager    = SingletonGetters.getModelChatManager(   modelSceneWar)
    self.m_ModelWarCommandMenu = SingletonGetters.getModelWarCommandMenu(modelSceneWar)

    SingletonGetters.getScriptEventDispatcher(modelSceneWar)
        :addEventListener("EvtChatManagerUpdated",    self)
        :addEventListener("EvtModelPlayerUpdated",    self)
        :addEventListener("EvtPlayerIndexUpdated",    self)
        :addEventListener("EvtWarCommandMenuUpdated", self)

    local playerIndex  = SingletonGetters.getModelTurnManager(modelSceneWar):getPlayerIndex()
    self.m_PlayerIndex = playerIndex

    self.m_View:setInfoText(generateInfoText(self))
        :updateWithPlayerIndex(playerIndex)

    return self
end

function ModelMoneyEnergyInfo:onEvent(event)
    local eventName = event.name
    if     (eventName == "EvtChatManagerUpdated")    then onEvtChatManagerUpdated(   self, event)
    elseif (eventName == "EvtModelPlayerUpdated")    then onEvtModelPlayerUpdated(   self, event)
    elseif (eventName == "EvtPlayerIndexUpdated")    then onEvtPlayerIndexUpdated(   self, event)
    elseif (eventName == "EvtWarCommandMenuUpdated") then onEvtWarCommandMenuUpdated(self, event)
    end

    return self
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
function ModelMoneyEnergyInfo:onPlayerTouch()
    local modelSceneWar = self.m_ModelSceneWar
    if ((modelSceneWar:isTotalReplay()) and (modelSceneWar:isAutoReplay())) then
        modelSceneWar:setAutoReplay(false)
        SingletonGetters.getModelReplayController(modelSceneWar):setButtonPlayVisible(true)
    end
    SingletonGetters.getModelWarCommandMenu(modelSceneWar):setEnabled(true)

    return self
end

function ModelMoneyEnergyInfo:adjustPositionOnTouch(touch)
    if (self.m_View) then
        self.m_View:adjustPositionOnTouch(touch)
    end

    return self
end

return ModelMoneyEnergyInfo
