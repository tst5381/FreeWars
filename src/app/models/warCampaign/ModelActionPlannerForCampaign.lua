
local ModelActionPlannerForCampaign = class("ModelActionPlannerForCampaign")

local Producible                  = requireFW("src.app.components.Producible")
local ActionCodeFunctions         = requireFW("src.app.utilities.ActionCodeFunctions")
local AnimationLoader             = requireFW("src.app.utilities.AnimationLoader")
local AttackableGridListFunctions = requireFW("src.app.utilities.AttackableGridListFunctions")
local GridIndexFunctions          = requireFW("src.app.utilities.GridIndexFunctions")
local LocalizationFunctions       = requireFW("src.app.utilities.LocalizationFunctions")
local MovePathFunctions           = requireFW("src.app.utilities.MovePathFunctions")
local ReachableAreaFunctions      = requireFW("src.app.utilities.ReachableAreaFunctions")
local SingletonGetters            = requireFW("src.app.utilities.SingletonGetters")
local VisibilityFunctions         = requireFW("src.app.utilities.VisibilityFunctions")
local Actor                       = requireFW("src.global.actors.Actor")

local createPathForDispatch    = MovePathFunctions.createPathForDispatch
local getLocalizedText         = LocalizationFunctions.getLocalizedText
local getModelFogMap           = SingletonGetters.getModelFogMap
local getModelMessageIndicator = SingletonGetters.getModelMessageIndicator
local getModelTileMap          = SingletonGetters.getModelTileMap
local getModelTurnManager      = SingletonGetters.getModelTurnManager
local getModelUnitMap          = SingletonGetters.getModelUnitMap
local getScriptEventDispatcher = SingletonGetters.getScriptEventDispatcher

--------------------------------------------------------------------------------
-- The util functions.
--------------------------------------------------------------------------------
local function isUnitVisible(self, modelUnit)
    return VisibilityFunctions.isUnitOnMapVisibleToPlayerIndex(
        self.m_ModelWar,
        modelUnit:getGridIndex(),
        modelUnit:getUnitType(),
        (modelUnit.isDiving) and (modelUnit:isDiving()),
        modelUnit:getPlayerIndex(),
        self.m_PlayerIndexForHuman
    )
end

local function getPathNodesDestination(pathNodes)
    return pathNodes[#pathNodes]
end

local function getMoveCost(self, gridIndex, modelUnit)
    local modelUnitMap = getModelUnitMap(self.m_ModelWar)
    if (not GridIndexFunctions.isWithinMap(gridIndex, modelUnitMap:getMapSize())) then
        return nil
    else
        local existingModelUnit = modelUnitMap:getModelUnit(gridIndex)
        if ((existingModelUnit) and (existingModelUnit:getTeamIndex() ~= modelUnit:getTeamIndex()) and (isUnitVisible(self, existingModelUnit))) then
            return nil
        else
            return getModelTileMap(self.m_ModelWar):getModelTile(gridIndex):getMoveCostWithModelUnit(modelUnit)
        end
    end
end

local function canUnitStayInGrid(self, modelUnit, gridIndex)
    if (GridIndexFunctions.isEqual(modelUnit:getGridIndex(), gridIndex)) then
        return true
    else
        local existingModelUnit = getModelUnitMap(self.m_ModelWar):getModelUnit(gridIndex)
        local tileType          = getModelTileMap(self.m_ModelWar):getModelTile(gridIndex):getTileType()
        return (not existingModelUnit)                                                                       or
            (not isUnitVisible(self, existingModelUnit))                                                     or
            (modelUnit:canJoinModelUnit(existingModelUnit))                                                  or
            (existingModelUnit.canLoadModelUnit and existingModelUnit:canLoadModelUnit(modelUnit, tileType))
    end
end

local function isDropGridAvailable(gridIndex, availableDropGrids)
    for _, availableGridIndex in pairs(availableDropGrids) do
        if (GridIndexFunctions.isEqual(gridIndex, availableGridIndex)) then
            return true
        end
    end

    return false
end

local function isDropGridSelected(gridIndex, selectedDropDestinations)
    for _, dropDestination in pairs(selectedDropDestinations) do
        if (GridIndexFunctions.isEqual(gridIndex, dropDestination.gridIndex)) then
            return true
        end
    end

    return false
end

local function getAvailableDropGrids(self, droppingModelUnit, loaderBeginningGridIndex, loaderEndingGridIndex, dropDestinations)
    local modelWar     = self.m_ModelWar
    local modelTileMap = getModelTileMap(modelWar)
    if (not modelTileMap:getModelTile(loaderEndingGridIndex):getMoveCostWithModelUnit(droppingModelUnit)) then
        return {}
    end

    local modelUnitMap = getModelUnitMap(modelWar)
    local mapSize      = modelTileMap:getMapSize()
    local grids        = {}
    for _, gridIndex in pairs(GridIndexFunctions.getAdjacentGrids(loaderEndingGridIndex)) do
        if ((GridIndexFunctions.isWithinMap(gridIndex, mapSize))                               and
            (modelTileMap:getModelTile(gridIndex):getMoveCostWithModelUnit(droppingModelUnit)) and
            (not isDropGridSelected(gridIndex, dropDestinations)))                             then

            local existingModelUnit = modelUnitMap:getModelUnit(gridIndex)
            if ((not existingModelUnit) or (GridIndexFunctions.isEqual(gridIndex, loaderBeginningGridIndex)) or (not isUnitVisible(self, existingModelUnit))) then
                grids[#grids + 1] = gridIndex
            end
        end
    end

    return grids
end

local function pushBackDropDestination(dropDestinations, unitID, destination, modelUnit)
    dropDestinations[#dropDestinations + 1] = {
        unitID    = unitID,
        gridIndex = destination,
        modelUnit = modelUnit,
    }
end

local function popBackDropDestination(dropDestinations)
    local dropDestination = dropDestinations[#dropDestinations]
    dropDestinations[#dropDestinations] = nil

    return dropDestination
end

local function isModelUnitDropped(unitID, dropDestinations)
    for _, dropDestination in pairs(dropDestinations) do
        if (unitID == dropDestination.unitID) then
            return true
        end
    end

    return false
end

local function canDoAdditionalDropAction(self)
    local focusModelUnit   = self.m_FocusModelUnit
    local dropDestinations = self.m_SelectedDropDestinations
    if (focusModelUnit:getCurrentLoadCount() <= #dropDestinations) then
        return false
    end

    local modelUnitMap             = getModelUnitMap(self.m_ModelWar)
    local modelTileMap             = getModelTileMap(self.m_ModelWar)
    local loaderBeginningGridIndex = focusModelUnit:getGridIndex()
    local loaderEndingGridIndex    = getPathNodesDestination(self.m_PathNodes)
    for _, unitID in pairs(focusModelUnit:getLoadUnitIdList()) do
        if ((not isModelUnitDropped(unitID, dropDestinations)) and
            (#getAvailableDropGrids(self, modelUnitMap:getLoadedModelUnitWithUnitId(unitID), loaderBeginningGridIndex, loaderEndingGridIndex, dropDestinations) > 0)) then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- The functions for MovePath and ReachableArea.
--------------------------------------------------------------------------------
local function updateMovePathWithDestinationGrid(self, gridIndex)
    local maxRange     = math.min(self.m_FocusModelUnit:getMoveRange(), self.m_FocusModelUnit:getCurrentFuel())
    local nextMoveCost = getMoveCost(self, gridIndex, self.m_FocusModelUnit)

    if ((not MovePathFunctions.truncateToGridIndex(self.m_PathNodes, gridIndex))                        and
        (not MovePathFunctions.extendToGridIndex(self.m_PathNodes, gridIndex, nextMoveCost, maxRange))) then
        self.m_PathNodes = MovePathFunctions.createShortestPath(gridIndex, self.m_ReachableArea)
    end

    if (self.m_View) then
        self.m_View:setMovePath(self.m_PathNodes)
    end
end

local function resetMovePath(self, gridIndex)
    self.m_PathNodes = {{
        x             = gridIndex.x,
        y             = gridIndex.y,
        totalMoveCost = 0,
    }}
    if (self.m_View) then
        self.m_View:setMovePath(self.m_PathNodes)
    end
end

local function resetReachableArea(self, focusModelUnit)
    self.m_ReachableArea = ReachableAreaFunctions.createArea(
        focusModelUnit:getGridIndex(),
        math.min(focusModelUnit:getMoveRange(), focusModelUnit:getCurrentFuel()),
        function(gridIndex)
            return getMoveCost(self, gridIndex, focusModelUnit)
        end
    )

    self.m_View:setReachableArea(self.m_ReachableArea)
end

--------------------------------------------------------------------------------
-- The functions for dispatching events.
--------------------------------------------------------------------------------
local function dispatchEvtPreviewBattleDamage(self, attackDamage, counterDamage)
    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({
        name          = "EvtPreviewBattleDamage",
        attackDamage  = attackDamage,
        counterDamage = counterDamage,
    })
end

local function dispatchEvtPreviewNoBattleDatame(self)
    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtPreviewNoBattleDamage"})
end

--------------------------------------------------------------------------------
-- The functions for sending actions to the server.
--------------------------------------------------------------------------------
local function createAndSendAction(self, rawAction)
    local modelWar     = self.m_ModelWar
    rawAction.actionID = SingletonGetters.getActionId(modelWar) + 1

    self:setStateIdle(true)
    modelWar:translateAndExecuteAction(rawAction)
end

local function sendActionAttack(self, targetGridIndex)
    createAndSendAction(self, {
        actionCode      = ActionCodeFunctions.getActionCode("ActionAttack"),
        path            = createPathForDispatch(self.m_PathNodes),
        targetGridIndex = GridIndexFunctions.clone(targetGridIndex),
        launchUnitID    = self.m_LaunchUnitID,
    })
end

local function sendActionBuildModelTile(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionBuildModelTile"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionCaptureModelTile(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionCaptureModelTile"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionDive(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionDive"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionDropModelUnit(self)
    local dropDestinations = {}
    for _, dropDestination in ipairs(self.m_SelectedDropDestinations) do
        dropDestinations[#dropDestinations + 1] = {
            unitID    = dropDestination.unitID,
            gridIndex = dropDestination.gridIndex,
        }
    end

    createAndSendAction(self, {
        actionCode       = ActionCodeFunctions.getActionCode("ActionDropModelUnit"),
        path             = createPathForDispatch(self.m_PathNodes),
        dropDestinations = dropDestinations,
        launchUnitID     = self.m_LaunchUnitID,
    })
end

local function sendActionJoinModelUnit(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionJoinModelUnit"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionLaunchFlare(self, gridIndex)
    createAndSendAction(self, {
        actionCode      = ActionCodeFunctions.getActionCode("ActionLaunchFlare"),
        path            = createPathForDispatch(self.m_PathNodes),
        launchUnitID    = self.m_LaunchUnitID,
        targetGridIndex = gridIndex,
    })
end

local function sendActionLaunchSilo(self, targetGridIndex)
    createAndSendAction(self, {
        actionCode      = ActionCodeFunctions.getActionCode("ActionLaunchSilo"),
        path            = createPathForDispatch(self.m_PathNodes),
        launchUnitID    = self.m_LaunchUnitID,
        targetGridIndex = targetGridIndex,
    })
end

local function sendActionLoadModelUnit(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionLoadModelUnit"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionProduceModelUnitOnTile(self, gridIndex, tiledID)
    createAndSendAction(self, {
        actionCode = ActionCodeFunctions.getActionCode("ActionProduceModelUnitOnTile"),
        gridIndex  = GridIndexFunctions.clone(gridIndex),
        tiledID    = tiledID,
    })
end

local function sendActionProduceModelUnitOnUnit(self)
    createAndSendAction(self, {
        actionCode = ActionCodeFunctions.getActionCode("ActionProduceModelUnitOnUnit"),
        path       = createPathForDispatch(self.m_PathNodes),
    })
end

local function sendActionSupplyModelUnit(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionSupplyModelUnit"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionSurface(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionSurface"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

local function sendActionWait(self)
    createAndSendAction(self, {
        actionCode   = ActionCodeFunctions.getActionCode("ActionWait"),
        path         = createPathForDispatch(self.m_PathNodes),
        launchUnitID = self.m_LaunchUnitID,
    })
end

--------------------------------------------------------------------------------
-- The functions for available action list.
--------------------------------------------------------------------------------
local setStatePreviewingAttackableArea
local setStatePreviewingReachableArea
local setStateChoosingProductionTarget
local setStateMakingMovePath
local setStateChoosingAction
local setStateChoosingAttackTarget
local setStateChoosingFlareTarget
local setStateChoosingSiloTarget
local setStateChoosingDropDestination
local setStateChoosingAdditionalDropAction

local function getActionLoadModelUnit(self)
    local destination = getPathNodesDestination(self.m_PathNodes)
    if (GridIndexFunctions.isEqual(self.m_FocusModelUnit:getGridIndex(), destination)) then
        return nil
    else
        local loaderModelUnit = getModelUnitMap(self.m_ModelWar):getModelUnit(destination)
        local tileType        = getModelTileMap(self.m_ModelWar):getModelTile(destination):getTileType()
        if ((loaderModelUnit)                                                    and
            (loaderModelUnit.canLoadModelUnit)                                   and
            (loaderModelUnit:canLoadModelUnit(self.m_FocusModelUnit, tileType))) then
            return {
                name     = getLocalizedText(78, "LoadModelUnit"),
                callback = function()
                    sendActionLoadModelUnit(self)
                end
            }
        end
    end
end

local function getActionJoinModelUnit(self)
    local existingModelUnit = getModelUnitMap(self.m_ModelWar):getModelUnit(getPathNodesDestination(self.m_PathNodes))
    if ((#self.m_PathNodes > 1)                                      and
        (existingModelUnit)                                          and
        (self.m_FocusModelUnit:canJoinModelUnit(existingModelUnit))) then
        return {
            name     = getLocalizedText(78, "JoinModelUnit"),
            callback = function()
                sendActionJoinModelUnit(self)
            end
        }
    else
        return nil
    end
end

local function getActionAttack(self)
    if (#self.m_AttackableGridList == 0) then
        return nil
    else
        return {
            name     = getLocalizedText(78, "Attack"),
            callback = function()
                setStateChoosingAttackTarget(self, getPathNodesDestination(self.m_PathNodes))
            end,
        }
    end
end

local function getActionCapture(self)
    local modelTile = getModelTileMap(self.m_ModelWar):getModelTile(getPathNodesDestination(self.m_PathNodes))
    if ((self.m_FocusModelUnit.canCaptureModelTile) and (self.m_FocusModelUnit:canCaptureModelTile(modelTile))) then
        return {
            name     = getLocalizedText(78, "CaptureModelTile"),
            callback = function()
                sendActionCaptureModelTile(self)
            end,
        }
    else
        return nil
    end
end

local function getActionDive(self)
    local focusModelUnit = self.m_FocusModelUnit
    if ((focusModelUnit.canDive) and (focusModelUnit:canDive())) then
        return {
            name     = getLocalizedText(78, "Dive"),
            callback = function()
                sendActionDive(self)
            end,
        }
    end
end

local function getActionBuildModelTile(self)
    local tileType       = getModelTileMap(self.m_ModelWar):getModelTile(getPathNodesDestination(self.m_PathNodes)):getTileType()
    local focusModelUnit = self.m_FocusModelUnit

    if ((focusModelUnit.canBuildOnTileType)           and
        (focusModelUnit:canBuildOnTileType(tileType)) and
        (focusModelUnit:getCurrentMaterial() > 0))    then
        local buildTiledId = focusModelUnit:getBuildTiledIdWithTileType(tileType)
        local icon         = cc.Sprite:create()
        icon:setAnchorPoint(0, 0)
            :setScale(0.5)
            :playAnimationForever(AnimationLoader.getTileAnimationWithTiledId(buildTiledId))

        return {
            name     = getLocalizedText(78, "BuildModelTile"),
            icon     = icon,
            callback = function()
                sendActionBuildModelTile(self)
            end,
        }
    end
end

local function getActionSupplyModelUnit(self)
    local focusModelUnit = self.m_FocusModelUnit
    if (not focusModelUnit.canSupplyModelUnit) then
        return nil
    end

    local modelUnitMap = getModelUnitMap(self.m_ModelWar)
    for _, gridIndex in pairs(GridIndexFunctions.getAdjacentGrids(getPathNodesDestination(self.m_PathNodes), modelUnitMap:getMapSize())) do
        local modelUnit = modelUnitMap:getModelUnit(gridIndex)
        if ((modelUnit)                                     and
            (modelUnit ~= focusModelUnit)                   and
            (focusModelUnit:canSupplyModelUnit(modelUnit))) then
            return {
                name     = getLocalizedText(78, "SupplyModelUnit"),
                callback = function()
                    sendActionSupplyModelUnit(self)
                end,
            }
        end
    end

    return nil
end

local function getActionSurface(self)
    local focusModelUnit = self.m_FocusModelUnit
    if ((focusModelUnit.isDiving) and (focusModelUnit:isDiving())) then
        return {
            name     = getLocalizedText(78, "Surface"),
            callback = function()
                sendActionSurface(self)
            end,
        }
    end
end

local function getSingleActionLaunchModelUnit(self, unitID)
    local beginningGridIndex = self.m_PathNodes[1]
    local icon               = Actor.createView("common.ViewUnit")
    icon:updateWithModelUnit(getModelUnitMap(self.m_ModelWar):getFocusModelUnit(beginningGridIndex, unitID))
        :setScale(0.5)

    return {
        name     = getLocalizedText(78, "LaunchModelUnit"),
        icon     = icon,
        callback = function()
            setStateMakingMovePath(self, beginningGridIndex, unitID)
        end,
    }
end

local function getActionsLaunchModelUnit(self)
    local focusModelUnit = self.m_FocusModelUnit
    if ((#self.m_PathNodes ~= 1)                   or
        (not focusModelUnit.canLaunchModelUnit)    or
        (not focusModelUnit:canLaunchModelUnit())) then
        return {}
    end

    local actions      = {}
    local modelUnitMap = getModelUnitMap(self.m_ModelWar)
    local modelTile    = getModelTileMap(self.m_ModelWar):getModelTile(getPathNodesDestination(self.m_PathNodes))
    for _, unitID in ipairs(focusModelUnit:getLoadUnitIdList()) do
        local launchModelUnit = modelUnitMap:getLoadedModelUnitWithUnitId(unitID)
        if ((launchModelUnit:isStateIdle())                        and
            (modelTile:getMoveCostWithModelUnit(launchModelUnit))) then
            actions[#actions + 1] = getSingleActionLaunchModelUnit(self, unitID)
        end
    end

    return actions
end

local function getSingleActionDropModelUnit(self, unitID)
    local icon = Actor.createView("common.ViewUnit")
    icon:updateWithModelUnit(getModelUnitMap(self.m_ModelWar):getLoadedModelUnitWithUnitId(unitID))
        :ignoreAnchorPointForPosition(true)
        :setScale(0.5)

    return {
        name     = getLocalizedText(78, "DropModelUnit"),
        icon     = icon,
        callback = function()
            setStateChoosingDropDestination(self, unitID)
        end,
    }
end

local function getActionsDropModelUnit(self)
    local focusModelUnit        = self.m_FocusModelUnit
    local dropDestinations      = self.m_SelectedDropDestinations
    local modelTileMap          = getModelTileMap(self.m_ModelWar)
    local loaderEndingGridIndex = getPathNodesDestination(self.m_PathNodes)

    if ((not focusModelUnit.getCurrentLoadCount)                                                               or
        (focusModelUnit:getCurrentLoadCount() <= #dropDestinations)                                            or
        (not focusModelUnit:canDropModelUnit(modelTileMap:getModelTile(loaderEndingGridIndex):getTileType()))) then
        return {}
    end

    local actions = {}
    local loaderBeginningGridIndex = self.m_FocusModelUnit:getGridIndex()
    local modelUnitMap             = getModelUnitMap(self.m_ModelWar)

    for _, unitID in ipairs(focusModelUnit:getLoadUnitIdList()) do
        if (not isModelUnitDropped(unitID, dropDestinations)) then
            local droppingModelUnit = getModelUnitMap(self.m_ModelWar):getLoadedModelUnitWithUnitId(unitID)
            if (#getAvailableDropGrids(self, droppingModelUnit, loaderBeginningGridIndex, loaderEndingGridIndex, dropDestinations) > 0) then
                actions[#actions + 1] = getSingleActionDropModelUnit(self, unitID)
            end
        end
    end

    return actions
end

local function getActionLaunchFlare(self)
    local focusModelUnit = self.m_FocusModelUnit
    if ((not getModelFogMap(self.m_ModelWar):isFogOfWarCurrently()) or
        (#self.m_PathNodes ~= 1)                                         or
        (not focusModelUnit.getCurrentFlareAmmo)                         or
        (focusModelUnit:getCurrentFlareAmmo() == 0))                     then
        return nil
    else
        return {
            name     = getLocalizedText(78, "LaunchFlare"),
            callback = function()
                setStateChoosingFlareTarget(self)
            end,
        }
    end
end

local function getActionLaunchSilo(self)
    local focusModelUnit = self.m_FocusModelUnit
    local modelTile      = getModelTileMap(self.m_ModelWar):getModelTile(getPathNodesDestination(self.m_PathNodes))

    if ((focusModelUnit.canLaunchSiloOnTileType) and
        (focusModelUnit:canLaunchSiloOnTileType(modelTile:getTileType()))) then
        return {
            name     = getLocalizedText(78, "LaunchSilo"),
            callback = function()
                setStateChoosingSiloTarget(self)
            end,
        }
    else
        return nil
    end
end

local function getActionProduceModelUnitOnUnit(self)
    local focusModelUnit = self.m_FocusModelUnit
    if ((self.m_LaunchUnitID)                            or
        (#self.m_PathNodes ~= 1)                         or
        (not focusModelUnit.getCurrentMaterial)          or
        (not focusModelUnit.getMovableProductionTiledId) or
        (not focusModelUnit.getCurrentLoadCount))        then
        return nil
    else
        local produceTiledId = focusModelUnit:getMovableProductionTiledId()
        local icon           = cc.Sprite:create()
        icon:setAnchorPoint(0, 0)
            :setScale(0.5)
            :playAnimationForever(AnimationLoader.getUnitAnimationWithTiledId(produceTiledId))

        return {
            name        = string.format("%s\n%d",
                getLocalizedText(78, "ProduceModelUnitOnUnit"),
                Producible.getProductionCostWithTiledId(produceTiledId, self.m_ModelPlayerManager)
            ),
            icon        = icon,
            isAvailable = (focusModelUnit:getCurrentMaterial() >= 1)                                and
                (focusModelUnit:getMovableProductionCost() <= self.m_ModelPlayerForHuman:getFund()) and
                (focusModelUnit:getCurrentLoadCount() < focusModelUnit:getMaxLoadCount()),
            callback    = function()
                sendActionProduceModelUnitOnUnit(self)
            end,
        }
    end
end

local function getActionWait(self)
    local existingModelUnit = getModelUnitMap(self.m_ModelWar):getModelUnit(getPathNodesDestination(self.m_PathNodes))
    if (not existingModelUnit) or (not isUnitVisible(self, existingModelUnit)) or (self.m_FocusModelUnit == existingModelUnit) then
        return {
            name     = getLocalizedText(78, "Wait"),
            callback = function()
                sendActionWait(self)
            end
        }
    else
        return nil
    end
end

local function getAvailableActionList(self)
    local actionLoad = getActionLoadModelUnit(self)
    if (actionLoad) then
        return {actionLoad}
    end
    local actionJoin = getActionJoinModelUnit(self)
    if (actionJoin) then
        return {actionJoin}
    end

    local list = {}
    list[#list + 1] = getActionAttack(                self)
    list[#list + 1] = getActionCapture(               self)
    list[#list + 1] = getActionDive(                  self)
    list[#list + 1] = getActionSurface(               self)
    list[#list + 1] = getActionBuildModelTile(        self)
    list[#list + 1] = getActionSupplyModelUnit(       self)
    for _, action in ipairs(getActionsLaunchModelUnit(self)) do
        list[#list + 1] = action
    end
    for _, action in ipairs(getActionsDropModelUnit(self)) do
        list[#list + 1] = action
    end
    list[#list + 1] = getActionLaunchFlare(           self)
    list[#list + 1] = getActionLaunchSilo(            self)
    list[#list + 1] = getActionProduceModelUnitOnUnit(self)

    local itemWait = getActionWait(self)
    assert((#list > 0) or (itemWait), "ModelActionPlannerForCampaign-getAvailableActionList() the generated list has no valid action item.")
    return list, itemWait
end

local function getAdditionalDropActionList(self)
    local list = {}
    for _, action in ipairs(getActionsDropModelUnit(self)) do
        list[#list + 1] = action
    end

    return list, {
        name     = getLocalizedText(78, "Wait"),
        callback = function()
            sendActionDropModelUnit(self)
        end,
    }
end

--------------------------------------------------------------------------------
-- The set state functions.
--------------------------------------------------------------------------------
local function canSetStatePreviewingAttackableArea(self, gridIndex)
    local modelWar    = self.m_ModelWar
    local modelUnit   = getModelUnitMap(modelWar):getModelUnit(gridIndex)
    local playerIndex = self.m_PlayerIndexForHuman
    if ((not modelUnit) or (not modelUnit.getAttackRangeMinMax) or (not isUnitVisible(self, modelUnit))) then
        return false
    elseif (not modelUnit:isStateIdle()) then
        return true
    else
        return (playerIndex ~= modelUnit:getPlayerIndex()) or (playerIndex ~= getModelTurnManager(modelWar):getPlayerIndex())
    end
end

setStatePreviewingAttackableArea = function(self, gridIndex)
    self.m_State = "previewingAttackableArea"
    local modelUnit = getModelUnitMap(self.m_ModelWar):getModelUnit(gridIndex)
    for _, existingModelUnit in pairs(self.m_PreviewAttackModelUnits) do
        if (modelUnit == existingModelUnit) then
            return
        end
    end

    self.m_PreviewAttackModelUnits[#self.m_PreviewAttackModelUnits + 1] = modelUnit
    self.m_PreviewAttackableArea = AttackableGridListFunctions.createAttackableArea(gridIndex, getModelTileMap(self.m_ModelWar), getModelUnitMap(self.m_ModelWar), self.m_PreviewAttackableArea)

    self.m_View:setPreviewAttackableArea(self.m_PreviewAttackableArea)
        :setPreviewAttackableAreaVisible(true)
    modelUnit:showMovingAnimation()
end

local function canSetStatePreviewingReachableArea(self, gridIndex)
    local modelWar    = self.m_ModelWar
    local modelUnit   = getModelUnitMap(modelWar):getModelUnit(gridIndex)
    local playerIndex = self.m_PlayerIndexForHuman
    if ((not modelUnit) or (modelUnit.getAttackRangeMinMax) or (not isUnitVisible(self, modelUnit))) then
        return false
    elseif (not modelUnit:isStateIdle()) then
        return true
    else
        return (playerIndex ~= modelUnit:getPlayerIndex()) or (playerIndex ~= getModelTurnManager(modelWar):getPlayerIndex())
    end
end

setStatePreviewingReachableArea = function(self, gridIndex)
    self.m_State = "previewingReachableArea"

    local modelUnit              = getModelUnitMap(self.m_ModelWar):getModelUnit(gridIndex)
    self.m_PreviewReachModelUnit = modelUnit
    self.m_PreviewReachableArea  = ReachableAreaFunctions.createArea(
        gridIndex,
        math.min(modelUnit:getMoveRange(), modelUnit:getCurrentFuel()),
        function(gridIndex)
            return getMoveCost(self, gridIndex, modelUnit)
        end
    )

    self.m_View:setPreviewReachableArea(self.m_PreviewReachableArea)
        :setPreviewReachableAreaVisible(true)
    modelUnit:showMovingAnimation()
end

local function canSetStateChoosingProductionTarget(self, gridIndex)
    local playerIndexForHuman = self.m_PlayerIndexForHuman
    local modelTurnManager    = getModelTurnManager(self.m_ModelWar)
    if ((modelTurnManager:getPlayerIndex() ~= playerIndexForHuman) or
        (not modelTurnManager:isTurnPhaseMain()))                  then
        return false
    else
        local modelTile = getModelTileMap(self.m_ModelWar):getModelTile(gridIndex)
        return (not getModelUnitMap(self.m_ModelWar):getModelUnit(gridIndex))  and
            (modelTile:getPlayerIndex() == playerIndexForHuman) and
            (modelTile.getProductionList)
    end
end

setStateChoosingProductionTarget = function(self, gridIndex)
    self.m_State = "choosingProductionTarget"
    local modelTile      = getModelTileMap(self.m_ModelWar):getModelTile(gridIndex)
    local productionList = modelTile:getProductionList()

    for _, listItem in ipairs(productionList) do
        listItem.callback = function()
            sendActionProduceModelUnitOnTile(self, gridIndex, listItem.tiledID)
        end
    end

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({
        name           = "EvtActionPlannerChoosingProductionTarget",
        productionList = productionList,
    })
end

local function canSetStateMakingMovePath(self, beginningGridIndex, launchUnitID)
    local playerIndexForHuman = self.m_PlayerIndexForHuman
    local modelTurnManager    = getModelTurnManager(self.m_ModelWar)
    if ((modelTurnManager:getPlayerIndex() ~= playerIndexForHuman) or
        (not modelTurnManager:isTurnPhaseMain()))                  then
        return false
    else
        local modelUnit = getModelUnitMap(self.m_ModelWar):getFocusModelUnit(beginningGridIndex, launchUnitID)
        return (modelUnit) and (modelUnit:isStateIdle()) and (modelUnit:getPlayerIndex() == playerIndexForHuman)
    end
end

setStateMakingMovePath = function(self, beginningGridIndex, launchUnitID)
    local focusModelUnit = getModelUnitMap(self.m_ModelWar):getFocusModelUnit(beginningGridIndex, launchUnitID)
    if (self.m_FocusModelUnit ~= focusModelUnit) then
        self.m_FocusModelUnit = focusModelUnit
        resetReachableArea(self, focusModelUnit)
        resetMovePath(self, beginningGridIndex)
    end

    self.m_State          = "makingMovePath"
    self.m_LaunchUnitID   = launchUnitID

    focusModelUnit:showMovingAnimation()
    self.m_View:setReachableAreaVisible(true)
        :setAttackableGridsVisible(false)
        :setMovePathVisible(true)
        :setMovePathDestinationVisible(false)

    if (launchUnitID) then
        getModelUnitMap(self.m_ModelWar):setPreviewLaunchUnit(focusModelUnit, beginningGridIndex)
            :setPreviewLaunchUnitVisible(true)
    else
        getModelUnitMap(self.m_ModelWar):setPreviewLaunchUnitVisible(false)
    end

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtActionPlannerMakingMovePath"})
end

setStateChoosingAction = function(self, destination, launchUnitID)
    local beginningGridIndex = self.m_PathNodes[1]
    local focusModelUnit     = getModelUnitMap(self.m_ModelWar):getFocusModelUnit(beginningGridIndex, launchUnitID)
    if (self.m_FocusModelUnit ~= focusModelUnit) then
        self.m_FocusModelUnit  = focusModelUnit
        destination            = beginningGridIndex
        resetReachableArea(self, focusModelUnit)
    end

    updateMovePathWithDestinationGrid(self, destination)
    self.m_State              = "choosingAction"
    self.m_AttackableGridList = AttackableGridListFunctions.createList(self.m_ModelWar, self.m_PathNodes, launchUnitID)
    self.m_LaunchUnitID       = launchUnitID

    if (self.m_View) then
        self.m_View:setReachableAreaVisible(false)
            :setAttackableGridsVisible(false)
            :setMovePathVisible(true)
            :setMovePathDestination(destination)
            :setMovePathDestinationVisible(true)
            :setDroppableGridsVisible(false)
            :setPreviewDropDestinationVisible(false)
            :setDropDestinationsVisible(false)
            :setFlareGridsVisible(false)

        if (not launchUnitID) then
            getModelUnitMap(self.m_ModelWar):setPreviewLaunchUnitVisible(false)
        end
    end

    local list, itemWait = getAvailableActionList(self)
    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({
        name     = "EvtActionPlannerChoosingAction",
        list     = list,
        itemWait = itemWait,
    })
end

setStateChoosingAttackTarget = function(self, destination)
    self.m_State = "choosingAttackTarget"

    if (self.m_View) then
        self.m_View:setAttackableGrids(self.m_AttackableGridList)
            :setAttackableGridsVisible(true)
    end

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtActionPlannerChoosingAttackTarget"})
end

setStateChoosingFlareTarget = function(self)
    self.m_State = "choosingFlareTarget"

    if (self.m_View) then
        self.m_View:setFlareGrids(getPathNodesDestination(self.m_PathNodes), self.m_FocusModelUnit:getMaxFlareRange())
            :setFlareGridsVisible(true)
    end

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtActionPlannerChoosingFlareTarget"})
end

setStateChoosingSiloTarget = function(self)
    self.m_State = "choosingSiloTarget"

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtActionPlannerChoosingSiloTarget"})
end

setStateChoosingDropDestination = function(self, unitID)
    self.m_State = "choosingDropDestination"

    local droppingModelUnit   = getModelUnitMap(self.m_ModelWar):getLoadedModelUnitWithUnitId(unitID)
    self.m_AvailableDropGrids = getAvailableDropGrids(self, droppingModelUnit, self.m_FocusModelUnit:getGridIndex(), getPathNodesDestination(self.m_PathNodes), self.m_SelectedDropDestinations)
    self.m_DroppingUnitID     = unitID

    if (self.m_View) then
        self.m_View:setDroppableGrids(self.m_AvailableDropGrids)
            :setDroppableGridsVisible(true)
            :setDropDestinations(self.m_SelectedDropDestinations)
            :setDropDestinationsVisible(true)
            :setPreviewDropDestinationVisible(false)
    end

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtActionPlannerChoosingDropDestination"})
end

setStateChoosingAdditionalDropAction = function(self)
    self.m_State = "choosingAdditionalDropAction"

    if (self.m_View) then
        self.m_View:setDroppableGridsVisible( false)
            :setPreviewDropDestinationVisible(false)
            :setDropDestinations(self.m_SelectedDropDestinations)
            :setDropDestinationsVisible(true)
    end

    local list, itemWait = getAdditionalDropActionList(self)
    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({
        name     = "EvtActionPlannerChoosingAction",
        list     = list,
        itemWait = itemWait,
    })
end

--------------------------------------------------------------------------------
-- The private callback functions on script events.
--------------------------------------------------------------------------------
local function onEvtPlayerIndexUpdated(self, event)
    self:setStateIdle(true)
end

local function onEvtWarCommandMenuUpdated(self, event)
    if (event.modelWarCommandMenu:isEnabled()) then
        self:setStateIdle(true)
    end
end

local function onEvtMapCursorMoved(self, event)
    if (getModelTurnManager(self.m_ModelWar):getPlayerIndex() ~= self.m_PlayerIndexForHuman) then
        return
    end

    local state     = self.m_State
    local gridIndex = event.gridIndex

    if (state == "choosingProductionTarget") then
        self:setStateIdle(true)
    elseif (state == "makingMovePath") then
        if (ReachableAreaFunctions.getAreaNode(self.m_ReachableArea, gridIndex)) then
            updateMovePathWithDestinationGrid(self, gridIndex)
        end
    elseif (state == "choosingAttackTarget") then
        local listNode = AttackableGridListFunctions.getListNode(self.m_AttackableGridList, gridIndex)
        if (listNode) then
            dispatchEvtPreviewBattleDamage(self, listNode.estimatedAttackDamage, listNode.estimatedCounterDamage)
        else
            dispatchEvtPreviewNoBattleDatame(self)
        end
    elseif (state == "choosingDropDestination") then
        if (self.m_View) then
            if (isDropGridAvailable(gridIndex, self.m_AvailableDropGrids)) then
                self.m_View:setPreviewDropDestination(gridIndex, getModelUnitMap(self.m_ModelWar):getLoadedModelUnitWithUnitId(self.m_DroppingUnitID))
                    :setPreviewDropDestinationVisible(true)
            else
                self.m_View:setPreviewDropDestinationVisible(false)
            end
        end
    end

    self.m_CursorGridIndex = GridIndexFunctions.clone(gridIndex)
end

local function onEvtGridSelected(self, event)
    local state     = self.m_State
    local gridIndex = event.gridIndex

    if (state == "idle") then
        if     (canSetStateMakingMovePath(          self, gridIndex)) then setStateMakingMovePath(          self, gridIndex)
        elseif (canSetStateChoosingProductionTarget(self, gridIndex)) then setStateChoosingProductionTarget(self, gridIndex)
        elseif (canSetStatePreviewingAttackableArea(self, gridIndex)) then setStatePreviewingAttackableArea(self, gridIndex)
        elseif (canSetStatePreviewingReachableArea( self, gridIndex)) then setStatePreviewingReachableArea( self, gridIndex)
        end
    elseif (state == "choosingProductionTarget") then
        self:setStateIdle(true)
    elseif (state == "makingMovePath") then
        if (not ReachableAreaFunctions.getAreaNode(self.m_ReachableArea, gridIndex)) then
            if (self.m_LaunchUnitID) then
                setStateChoosingAction(self, self.m_PathNodes[1])
            else
                self:setStateIdle(true)
            end
        elseif (canUnitStayInGrid(self, self.m_FocusModelUnit, gridIndex)) then
            if ((self.m_LaunchUnitID) and (GridIndexFunctions.isEqual(self.m_FocusModelUnit:getGridIndex(), gridIndex))) then
                setStateChoosingAction(self, self.m_PathNodes[1])
            else
                setStateChoosingAction(self, gridIndex, self.m_LaunchUnitID)
            end
        end
    elseif (state == "choosingAction") then
        setStateMakingMovePath(self, self.m_PathNodes[1], self.m_LaunchUnitID)
    elseif (state == "choosingAttackTarget") then
        local listNode = AttackableGridListFunctions.getListNode(self.m_AttackableGridList, gridIndex)
        if (not listNode) then
            setStateChoosingAction(self, getPathNodesDestination(self.m_PathNodes), self.m_LaunchUnitID)
        else
            if (GridIndexFunctions.isEqual(self.m_CursorGridIndex, gridIndex)) then
                sendActionAttack(self, gridIndex)
            else
                dispatchEvtPreviewBattleDamage(self, listNode.estimatedAttackDamage, listNode.estimatedCounterDamage)
            end
        end
    elseif (state == "choosingFlareTarget") then
        local destination = getPathNodesDestination(self.m_PathNodes)
        if (GridIndexFunctions.getDistance(gridIndex, destination) > self.m_FocusModelUnit:getMaxFlareRange()) then
            setStateChoosingAction(self, destination, self.m_LaunchUnitID)
        elseif (GridIndexFunctions.isEqual(gridIndex, self.m_CursorGridIndex)) then
            sendActionLaunchFlare(self, gridIndex)
        end
    elseif (state == "choosingSiloTarget") then
        if (GridIndexFunctions.isEqual(gridIndex, self.m_CursorGridIndex)) then
            sendActionLaunchSilo(self, gridIndex)
        elseif (GridIndexFunctions.getDistance(gridIndex, self.m_CursorGridIndex) > 2) then
            setStateChoosingAction(self, getPathNodesDestination(self.m_PathNodes), self.m_LaunchUnitID)
        end
    elseif (state == "choosingDropDestination") then
        if (isDropGridAvailable(gridIndex, self.m_AvailableDropGrids)) then
            pushBackDropDestination(self.m_SelectedDropDestinations, self.m_DroppingUnitID, gridIndex, getModelUnitMap(self.m_ModelWar):getLoadedModelUnitWithUnitId(self.m_DroppingUnitID))
            if (not canDoAdditionalDropAction(self)) then
                sendActionDropModelUnit(self)
            else
                setStateChoosingAdditionalDropAction(self)
            end
        else
            if (#self.m_SelectedDropDestinations == 0) then
                setStateChoosingAction(self, getPathNodesDestination(self.m_PathNodes), self.m_LaunchUnitID)
            else
                setStateChoosingAdditionalDropAction(self)
            end
        end
    elseif (state == "choosingAdditionalDropAction") then
        setStateChoosingDropDestination(self, popBackDropDestination(self.m_SelectedDropDestinations).unitID)
    elseif (state == "previewingAttackableArea") then
        if (canSetStatePreviewingAttackableArea(self, gridIndex)) then
            setStatePreviewingAttackableArea(self, gridIndex)
        else
            self:setStateIdle(true)
        end
    elseif (state == "previewingReachableArea") then
        self:setStateIdle(true)
    else
        error("ModelActionPlannerForCampaign-onEvtGridSelected() the state of the planner is invalid.")
    end

    self.m_CursorGridIndex = GridIndexFunctions.clone(gridIndex)
end

--------------------------------------------------------------------------------
-- The constructor and initializers.
--------------------------------------------------------------------------------
function ModelActionPlannerForCampaign:ctor(param)
    self.m_State                      = "idle"
    self.m_PreviewAttackModelUnits    = {}
    self.m_SelectedDropDestinations   = {}

    return self
end

--------------------------------------------------------------------------------
-- The callback functions on start running/script events.
--------------------------------------------------------------------------------
function ModelActionPlannerForCampaign:onStartRunning(modelWar)
    self.m_ModelWar = modelWar
    getScriptEventDispatcher(modelWar)
        :addEventListener("EvtGridSelected",               self)
        :addEventListener("EvtMapCursorMoved",             self)
        :addEventListener("EvtPlayerIndexUpdated",         self)
        :addEventListener("EvtWarCommandMenuUpdated",      self)

    self.m_ModelPlayerManager                              = SingletonGetters.getModelPlayerManager(modelWar)
    self.m_PlayerIndexForHuman, self.m_ModelPlayerForHuman = self.m_ModelPlayerManager:getPlayerIndexForHuman()
    self.m_View:setMapSize(getModelTileMap(modelWar):getMapSize())
    self:setStateIdle(true)

    return self
end

function ModelActionPlannerForCampaign:onEvent(event)
    local name = event.name
    if     (name == "EvtGridSelected")               then onEvtGridSelected(              self, event)
    elseif (name == "EvtPlayerIndexUpdated")         then onEvtPlayerIndexUpdated(        self, event)
    elseif (name == "EvtMapCursorMoved")             then onEvtMapCursorMoved(            self, event)
    elseif (name == "EvtWarCommandMenuUpdated")      then onEvtWarCommandMenuUpdated(     self, event)
    end

    return self
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
function ModelActionPlannerForCampaign:setStateIdle(resetUnitAnimation)
    if (self.m_View) then
        self.m_View:setReachableAreaVisible(  false)
            :setAttackableGridsVisible(       false)
            :setMovePathVisible(              false)
            :setMovePathDestinationVisible(   false)
            :setDroppableGridsVisible(        false)
            :setPreviewDropDestinationVisible(false)
            :setDropDestinationsVisible(      false)
            :setPreviewAttackableAreaVisible( false)
            :setPreviewReachableAreaVisible(  false)
            :setFlareGridsVisible(            false)

        getModelUnitMap(self.m_ModelWar):setPreviewLaunchUnitVisible(false)
        if ((resetUnitAnimation) and (self.m_FocusModelUnit)) then
            self.m_FocusModelUnit:showNormalAnimation()
        end
        for _, modelUnit in pairs(self.m_PreviewAttackModelUnits) do
            modelUnit:showNormalAnimation()
        end
        if (self.m_PreviewReachModelUnit) then
            self.m_PreviewReachModelUnit:showNormalAnimation()
        end
    end

    self.m_State                    = "idle"
    self.m_FocusModelUnit           = nil
    self.m_PreviewAttackModelUnits  = {}
    self.m_PreviewAttackableArea    = {}
    self.m_PreviewReachModelUnit    = nil
    self.m_LaunchUnitID             = nil
    self.m_SelectedDropDestinations = {}

    getScriptEventDispatcher(self.m_ModelWar):dispatchEvent({name = "EvtActionPlannerIdle"})

    return self
end

return ModelActionPlannerForCampaign