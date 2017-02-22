
local ModelSkillGroupPassive = requireFW("src.global.functions.class")("ModelSkillGroupPassive")

local SkillDataAccessors = requireFW("src.app.utilities.SkillDataAccessors")

local ipairs = ipairs

--------------------------------------------------------------------------------
-- The util functions.
--------------------------------------------------------------------------------
local function mergeSingleSkill(self, skillID, skillModifier)
    for _, skill in ipairs(self:getAllSkills()) do
        if (skill.id == skillID) then
            skill.modifier = skill.modifier + skillModifier
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- The constructor and initializer.
--------------------------------------------------------------------------------
function ModelSkillGroupPassive:ctor(param)
    self.m_Slots = param or {}

    return self
end

--------------------------------------------------------------------------------
-- The functions for serialization.
--------------------------------------------------------------------------------
function ModelSkillGroupPassive:toSerializableTable()
    return self.m_Slots
end

--------------------------------------------------------------------------------
-- The public functions.
--------------------------------------------------------------------------------
ModelSkillGroupPassive.isSkillGroupPassive = true

function ModelSkillGroupPassive:isEmpty()
    return #self.m_Slots == 0
end

function ModelSkillGroupPassive:getAllSkills()
    return self.m_Slots
end

function ModelSkillGroupPassive:pushBackSkill(skillID, skillLevel)
    self.m_Slots[#self.m_Slots + 1] = {
        id       = skillID,
        modifier = SkillDataAccessors.getSkillModifier(skillID, skillLevel, false),
    }

    return self
end

function ModelSkillGroupPassive:mergeSkillGroup(modelSkillGroup)
    local slots = self.m_Slots
    for _, mergingSkill in ipairs(modelSkillGroup:getAllSkills()) do
        if (not mergeSingleSkill(self, mergingSkill.id, mergingSkill.modifier)) then
            slots[#slots + 1] = mergingSkill
        end
    end

    return self
end

function ModelSkillGroupPassive:clearAllSkills()
    self.m_Slots = {}

    return self
end

return ModelSkillGroupPassive