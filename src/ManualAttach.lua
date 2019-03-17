ManualAttach = {}

ManualAttach.COSANGLE_THRESHOLD = math.cos(math.rad(70))
ManualAttach.PLAYER_MIN_DISTANCE = 9
ManualAttach.PLAYER_DISTANCE = math.huge
ManualAttach.TIMER_THRESHOLD = 300 -- ms
ManualAttach.DETACHING_NOT_ALLOWED_TIME = 50 -- ms
ManualAttach.DETACHING_PRIORITY_NOT_ALLOWED = 6
ManualAttach.ATTACHING_PRIORITY_ALLOWED = 1
ManualAttach.DEFAULT_JOINT_DISTANCE = 1.3
ManualAttach.JOINT_DISTANCE = ManualAttach.DEFAULT_JOINT_DISTANCE
ManualAttach.JOINT_SEQUENCE = 0.5 * 0.5
ManualAttach.FORCED_ACTIVE_TIME_INCREASMENT = 600 -- ms

local function mapJointTypeNameToInt(typeName)
    local jointType = AttacherJoints.jointTypeNameToInt[typeName]
    -- Custom joints need a check if it exists in the game
    return jointType ~= nil and jointType or -1
end

ManualAttach.AUTO_ATTACH_JOINTYPES = {
    [mapJointTypeNameToInt("skidSteer")] = true,
    [mapJointTypeNameToInt("cutter")] = true,
    [mapJointTypeNameToInt("cutterHarvester")] = true,
    [mapJointTypeNameToInt("wheelLoader")] = true,
    [mapJointTypeNameToInt("frontloader")] = true,
    [mapJointTypeNameToInt("telehandler")] = true,
    [mapJointTypeNameToInt("hookLift")] = true,
    [mapJointTypeNameToInt("semitrailer")] = true,
    [mapJointTypeNameToInt("semitrailerHook")] = true,
    [mapJointTypeNameToInt("fastCoupler")] = true
}

local ManualAttach_mt = Class(ManualAttach)

function ManualAttach:new(mission, modDirectory)
    local self = setmetatable({}, ManualAttach_mt)

    self.isServer = mission:getIsServer()
    self.isClient = mission:getIsClient()
    self.mission = mission
    self.modDirectory = modDirectory
    self.detectionHandler = ManualAttachDetectionHandler:new(self.isServer, self.isClient, modDirectory)

    if self.isClient then
        self.detectionHandler:addDetectionListener(self)
    end

    return self
end

function ManualAttach:onMissionStart(mission)
    self.detectionHandler:load()

    self.vehicles = {}
    self.hasHoseEventInput = 0
    self.allowPtoEvent = true
    self.hoseEventCurrentDelay = ManualAttach.TIMER_THRESHOLD

    self:resetAttachValues()
end

function ManualAttach:delete()
    self.detectionHandler:delete()
end

function ManualAttach:update(dt)
    if not self.isClient then
        return
    end

    local lastHasHoseEventInput = self.hasHoseEventInput
    self.hasHoseEventInput = 0

    if lastHasHoseEventInput ~= 0 then
        self.hoseEventCurrentDelay = self.hoseEventCurrentDelay - dt

        if self.hoseEventCurrentDelay < 0 then
            self.hoseEventCurrentDelay = ManualAttach.TIMER_THRESHOLD
            self.allowPtoEvent = false

            self:onConnectionHoseEvent()
        end
    else
        if self.allowPtoEvent then
            if self.hoseEventCurrentDelay ~= ManualAttach.TIMER_THRESHOLD and self.hoseEventCurrentDelay ~= 0 then
                self:onPowerTakeOffEvent()
            end
        end

        self.hoseEventCurrentDelay = ManualAttach.TIMER_THRESHOLD
        self.allowPtoEvent = true
    end

    if self:hasVehicles() then
        self.attacherVehicle, self.attacherVehicleJointDescIndex, self.attachable, self.attachableJointDescIndex, self.attachedImplement = ManualAttachUtil.findVehicleInAttachRange(self.vehicles, AttacherJoints.MAX_ATTACH_DISTANCE_SQ, AttacherJoints.MAX_ATTACH_ANGLE)
    end
end

local function setActionEventText(id, text, priority, visibility)
    g_inputBinding:setActionEventText(id, text)
    g_inputBinding:setActionEventTextPriority(id, priority)
    g_inputBinding:setActionEventTextVisibility(id, visibility)
end

function ManualAttach:draw(dt)
    if not self.isClient then
        return
    end

    if self:hasVehicles() then
        local attachEventVisibility = false
        local attachEventPrio = GS_PRIO_VERY_LOW
        local attachEventText = ""

        local ptoEventVisibility = false
        local ptoEventText = ""
        local hoseEventVisibility = false
        local hoseEventText = ""

        local object = self.attachedImplement

        if object ~= nil and not object.isDeleted then
            local attacherVehicle = object:getAttacherVehicle()

            if attacherVehicle ~= nil then
                if object.isDetachAllowed ~= nil and object:isDetachAllowed() then
                    attachEventVisibility = true
                    attachEventText = g_i18n:getText("action_detach")
                end

                if object.getInputPowerTakeOffs ~= nil then
                    if ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle) then
                        ptoEventText = g_i18n:getText("action_detach_pto")
                    else
                        ptoEventText = g_i18n:getText("action_attach_pto")
                    end

                    ptoEventVisibility = true
                end

                if object.getIsConnectionHoseUsed ~= nil then
                    if ManualAttachUtil.hasAttachedConnectionHoses(object) then
                        hoseEventText = g_i18n:getText("info_detach_hose")
                    else
                        hoseEventText = g_i18n:getText("info_attach_hose")
                    end

                    g_currentMission:addExtraPrintText(hoseEventText)

                    hoseEventVisibility = true
                end
            end
        end

        if self.attachable ~= nil then
            if g_currentMission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
                attachEventVisibility = true
                attachEventText = g_i18n:getText("action_attach")
                attachEventPrio = GS_PRIO_VERY_HIGH
                g_currentMission:showAttachContext(self.attachable)
            end
        end

        setActionEventText(self.attachEvent, attachEventText, attachEventPrio, attachEventVisibility)
        setActionEventText(self.handleEventId, ptoEventText, GS_PRIO_VERY_LOW, ptoEventVisibility)
    end
end

function ManualAttach:hasVehicles()
    return #self.vehicles ~= 0
end

function ManualAttach:resetAttachValues()
    -- Inrange values
    self.attacherVehicle = nil
    self.attacherVehicleJointDescIndex = nil
    self.attachable = nil
    self.attachableJointDescIndex = nil
    self.attachedImplement = nil

    g_inputBinding:setActionEventTextVisibility(self.attachEvent, false)
    g_inputBinding:setActionEventTextVisibility(self.handleEventId, false)
end

function ManualAttach:onVehicleListChanged(vehicles)
    self.vehicles = vehicles

    if not self:hasVehicles() then
        self:resetAttachValues()
    end
end

function ManualAttach:getIsValidPlayer()
    local player = g_currentMission.controlPlayer
    return player
            and not player.isCarryingObject
            and not player:hasHandtoolEquipped()
end

function ManualAttach:onAttachEvent()
    if self.attachable ~= nil then
        -- attach
        if self.attachable ~= nil and g_currentMission.accessHandler:canFarmAccess(self.attacherVehicle:getActiveFarm(), self.attachable) then
            local jointDesc = self.attacherVehicle.spec_attacherJoints.attacherJoints[self.attacherVehicleJointDescIndex]

            if jointDesc.jointIndex == 0 then
                self.attacherVehicle:attachImplement(self.attachable, self.attachableJointDescIndex, self.attacherVehicleJointDescIndex)

                local allowsLowering = self.attachable:getAllowsLowering()
                if allowsLowering and jointDesc.allowsLowering then
                    self.attacherVehicle:handleLowerImplementByAttacherJointIndex(self.attacherVehicleJointDescIndex)
                end
            end
        end
    else
        -- detach
        local object = self.attachedImplement
        if object ~= nil and object ~= self.attacherVehicle and object.isDetachAllowed ~= nil then
            local detachAllowed, warning, showWarning = object:isDetachAllowed()
            local attacherVehicle = object:getAttacherVehicle()
            local jointDesc = attacherVehicle:getAttacherJointDescFromObject(object)

            if ManualAttachUtil.isManualJointType(jointDesc) then
                local allowsLowering = object:getAllowsLowering()

                if allowsLowering and jointDesc.allowsLowering then
                    if not jointDesc.moveDown then
                        detachAllowed = false
                        warning = g_i18n:getText("info_lower_warning"):format(object:getName())
                    end
                end
            end

            if detachAllowed then
                if ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle) then
                    detachAllowed = false
                    warning = g_i18n:getText("info_detach_pto_warning"):format(object:getName())
                end
            end

            if detachAllowed then
                if ManualAttachUtil.hasAttachedConnectionHoses(object) then
                    detachAllowed = false
                    warning = g_i18n:getText("info_detach_hoses_warning"):format(object:getName())
                end
            end

            if detachAllowed then
                if attacherVehicle ~= nil then
                    attacherVehicle:detachImplementByObject(object)
                end
            elseif showWarning == nil or showWarning then
                g_currentMission:showBlinkingWarning(warning or g_i18n:getText("warning_detachNotAllowed"), 2000)
            end
        end
    end
end

function ManualAttach:onPowerTakeOffEvent()
    if self.allowPtoEvent then
        local object = self.attachedImplement
        if object ~= nil then
            local attacherVehicle = object:getAttacherVehicle()
            local implement = attacherVehicle:getImplementByObject(object)
            if object.getInputPowerTakeOffs ~= nil then
                local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
                local jointDescIndex = implement.jointDescIndex

                if ManualAttachUtil.hasAttachedPowerTakeOffs(object, attacherVehicle) then
                    attacherVehicle:detachPowerTakeOff(attacherVehicle, implement)
                else
                    attacherVehicle:attachPowerTakeOff(object, inputJointDescIndex, jointDescIndex)
                    attacherVehicle:handlePowerTakeOffPostAttach(jointDescIndex)
                end
            end
        end
    end
end

function ManualAttach:onConnectionHoseEvent()
    local object = self.attachedImplement
    if object ~= nil then
        local attacherVehicle = object:getAttacherVehicle()
        local implement = attacherVehicle:getImplementByObject(object)
        local inputJointDescIndex = object.spec_attachable.inputAttacherJointDescIndex
        local jointDescIndex = implement.jointDescIndex

        if ManualAttachUtil.hasAttachedConnectionHoses(object) then
            object:disconnectHoses(attacherVehicle)
        else
            object:connectHosesToAttacherVehicle(attacherVehicle, inputJointDescIndex, jointDescIndex)
            object:updateAttachedConnectionHoses(attacherVehicle) -- update once
        end
    end
end

function ManualAttach:onPowerTakeOffAndConnectionHoseEvent(actionName, inputValue)
    self.hasHoseEventInput = inputValue
end

function ManualAttach:registerActionEvents()
    local _, attachEventId = g_inputBinding:registerActionEvent(InputAction.MA_ATTACH_VEHICLE, self, self.onAttachEvent, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(attachEventId, false)

    local _, handleEventId = g_inputBinding:registerActionEvent(InputAction.MA_ATTACH_HOSE, self, self.onPowerTakeOffAndConnectionHoseEvent, false, true, true, true)
    g_inputBinding:setActionEventTextVisibility(hoseEventId, false)

    self.attachEvent = attachEventId
    self.handleEventId = handleEventId
end

function ManualAttach:unregisterActionEvents()
    g_inputBinding:removeActionEventsByTarget(self)
end

function ManualAttach.inj_registerActionEvents(mission)
    g_manualAttach:registerActionEvents()
end

function ManualAttach.inj_unregisterActionEvents(mission)
    g_manualAttach:unregisterActionEvents()
end

function ManualAttach.installSpecializations(vehicleTypeManager, specializationManager, modDirectory, modName)
    specializationManager:addSpecialization("manualAttachExtension", "ManualAttachExtension", Utils.getFilename("src/vehicle/ManualAttachExtension.lua", modDirectory), nil)

    for typeName, typeEntry in pairs(vehicleTypeManager:getVehicleTypes()) do
        if SpecializationUtil.hasSpecialization(Attachable, typeEntry.specializations)
                or SpecializationUtil.hasSpecialization(AttacherJoints, typeEntry.specializations) then
            -- Make sure to namespace the spec again
            vehicleTypeManager:addSpecialization(typeName, modName .. ".manualAttachExtension")
        end
    end
end
