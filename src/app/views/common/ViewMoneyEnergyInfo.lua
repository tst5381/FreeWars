
local ViewMoneyEnergyInfo = class("ViewMoneyEnergyInfo", cc.Node)

local LocalizationFunctions = requireFW("src.app.utilities.LocalizationFunctions")
local SingletonGetters      = requireFW("src.app.utilities.SingletonGetters")
local ViewUtils             = requireFW("src.app.utilities.ViewUtils")

local getCapInsets           = ViewUtils.getCapInsets
local getLocalizedText       = LocalizationFunctions.getLocalizedText
local getModelFogMap         = SingletonGetters.getModelFogMap
local getPlayerIndexLoggedIn = SingletonGetters.getPlayerIndexLoggedIn

local LABEL_Z_ORDER      = 1
local BACKGROUND_Z_ORDER = 0

local FONT_SIZE  = 14
local FONT_NAME  = "res/fonts/msyhbd.ttc"
local FONT_COLOR = {r = 255, g = 255, b = 255}

local VIEW_STATIC_INFO     = ViewUtils.getViewStaticInfo("ViewMoneyEnergyInfo")
local BACKGROUND_WIDTH     = VIEW_STATIC_INFO.width
local BACKGROUND_HEIGHT    = VIEW_STATIC_INFO.height
local BACKGROUND_POS_X     = VIEW_STATIC_INFO.x
local BACKGROUND_POS_Y     = VIEW_STATIC_INFO.y
local BACKGROUND_NAME      = "c03_t01_s05_f01.png"

local LABEL_MAX_WIDTH  = BACKGROUND_WIDTH - 10
local LABEL_MAX_HEIGHT = BACKGROUND_HEIGHT - 8
local LABEL_POS_X      = 5
local LABEL_POS_Y      = 2

--------------------------------------------------------------------------------
-- The composition elements.
--------------------------------------------------------------------------------
local function initBackground(self)
    local background = cc.Scale9Sprite:createWithSpriteFrameName(BACKGROUND_NAME, getCapInsets(BACKGROUND_NAME))
    background:ignoreAnchorPointForPosition(true)
        :setPosition(BACKGROUND_POS_X, BACKGROUND_POS_Y)
        :setContentSize(BACKGROUND_WIDTH, BACKGROUND_HEIGHT)

    self.m_Background = background
    self:addChild(background, BACKGROUND_Z_ORDER)
end

local function initLabel(self)
    local label = cc.Label:createWithTTF("", FONT_NAME, FONT_SIZE)
    label:setAnchorPoint(0, 0)
        :ignoreAnchorPointForPosition(true)
        :setPosition(LABEL_POS_X, LABEL_POS_Y)

        :setHorizontalAlignment(cc.TEXT_ALIGNMENT_LEFT)
        :setVerticalAlignment(cc.VERTICAL_TEXT_ALIGNMENT_BOTTOM)

        :setTextColor(FONT_COLOR)

    self.m_Label = label
    self.m_Background:addChild(label, LABEL_Z_ORDER)
end

--------------------------------------------------------------------------------
-- The constructor and initializers.
--------------------------------------------------------------------------------
function ViewMoneyEnergyInfo:ctor(param)
    initBackground(self)
    initLabel(     self)

    self:ignoreAnchorPointForPosition(true)

    return self
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
function ViewMoneyEnergyInfo:adjustPositionOnTouch(touch)
    return self
end

function ViewMoneyEnergyInfo:setInfoText(text)
    local label = self.m_Label
    label:setString(text)
        :setScaleX(math.min(1, LABEL_MAX_WIDTH / label:getContentSize().width))

    return self
end

function ViewMoneyEnergyInfo:updateWithPlayerIndex(playerIndex)
    return self
end

return ViewMoneyEnergyInfo
