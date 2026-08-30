SettingsProviders = {
    choices = {},
    onChanged = nil,
}

local function IsChoiceSpecValid(spec)
    if type(spec) ~= 'table' or type(spec.id) ~= 'string' or spec.id == '' then return false end
    if #spec.id > 100 or not spec.id:match('^[%w%._:%-]+$') then return false end
    if type(spec.label) ~= 'string' or spec.label == '' then return false end
    if #spec.label > 100 then return false end
    if type(spec.options) ~= 'table' or #spec.options < 2 or #spec.options > 20 then return false end
    if type(spec.getValue) ~= 'function' or type(spec.setValue) ~= 'function' then return false end

    local values = {}
    for _, option in ipairs(spec.options) do
        if type(option) ~= 'table' or type(option.value) ~= 'string'
            or type(option.label) ~= 'string' then return false end
        if option.value == '' or #option.value > 100 or option.label == '' or #option.label > 100 then return false end
        if values[option.value] then return false end
        values[option.value] = true
    end
    return true
end

local function RemoveChoice(id, invokingResource)
    local registered = SettingsProviders.choices[id]
    if not registered then return false end
    if invokingResource and registered.owner ~= invokingResource then return false end

    SettingsProviders.choices[id] = nil
    if SettingsProviders.onChanged then SettingsProviders.onChanged(id) end
    return true
end

exports('RegisterChoice', function(spec)
    local owner = GetInvokingResource()
    if not owner or not IsChoiceSpecValid(spec) then return false end

    local existing = SettingsProviders.choices[spec.id]
    if existing and existing.owner ~= owner then return false end

    SettingsProviders.choices[spec.id] = {
        owner = owner,
        spec = spec,
    }
    if SettingsProviders.onChanged then SettingsProviders.onChanged(spec.id) end
    return true
end)

exports('UnregisterChoice', function(id)
    return RemoveChoice(id, GetInvokingResource())
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    local removed = {}
    for id, registered in pairs(SettingsProviders.choices) do
        if registered.owner == resourceName then removed[#removed + 1] = id end
    end
    for _, id in ipairs(removed) do RemoveChoice(id, resourceName) end
end)
