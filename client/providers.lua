SettingsProviders = {
    choices = {},
    onChanged = nil,
}

local function IsChoiceSpecValid(spec)
    if type(spec) ~= 'table' or type(spec.id) ~= 'string' or spec.id == '' then return false, 'invalid id' end
    if #spec.id > 100 or not spec.id:match('^[%w%._:%-]+$') then return false, 'invalid id' end
    if type(spec.label) ~= 'string' or spec.label == '' then return false, 'invalid label' end
    if #spec.label > 100 then return false, 'invalid label' end
    local control = spec.control or 'dropdown'
    if control ~= 'dropdown' and control ~= 'arrows' and control ~= 'slider' then
        return false, 'invalid control'
    end
    if control == 'slider' then
        if type(spec.min) ~= 'number' or type(spec.max) ~= 'number' or spec.min >= spec.max
            or type(spec.step) ~= 'number' or spec.step <= 0 then return false, 'invalid slider bounds' end
    elseif type(spec.options) ~= 'table' or #spec.options < 2 or #spec.options > 20 then
        return false, 'invalid options'
    end
    local callbackPair = type(spec.getValue) == 'function' and type(spec.setValue) == 'function'
    local exportPair = type(spec.getExport) == 'string' and spec.getExport ~= ''
        and type(spec.setExport) == 'string' and spec.setExport ~= ''
    local eventPair = spec.initialValue ~= nil and type(spec.setEvent) == 'string'
        and spec.setEvent ~= '' and #spec.setEvent <= 150
    if not callbackPair and not exportPair and not eventPair then
        return false, ('invalid accessors get=%s set=%s getExport=%s setExport=%s setEvent=%s'):format(
            type(spec.getValue), type(spec.setValue), type(spec.getExport), type(spec.setExport), type(spec.setEvent))
    end

    local values = {}
    for _, option in ipairs(spec.options or {}) do
        if type(option) ~= 'table' or type(option.value) ~= 'string'
            or type(option.label) ~= 'string' then return false, 'invalid option entry' end
        if option.value == '' or #option.value > 100 or option.label == '' or #option.label > 100 then
            return false, 'invalid option entry'
        end
        if values[option.value] then return false, 'duplicate option value' end
        values[option.value] = true
    end
    return true, nil
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
    local invokingResource = GetInvokingResource()
    local declaredOwner = type(spec) == 'table' and spec.ownerResource or nil
    if invokingResource and declaredOwner and invokingResource ~= declaredOwner then
        return false, 'owner does not match invoking resource'
    end
    local owner = invokingResource or declaredOwner
    if type(owner) ~= 'string' or owner == '' then return false, 'owner unavailable' end
    local valid, reason = IsChoiceSpecValid(spec)
    if not valid then return false, reason end

    local existing = SettingsProviders.choices[spec.id]
    if existing and existing.owner ~= owner then return false, 'choice belongs to another resource' end

    SettingsProviders.choices[spec.id] = {
        owner = owner,
        spec = spec,
        value = spec.initialValue,
    }
    if SettingsProviders.onChanged then SettingsProviders.onChanged(spec.id) end
    return true, nil
end)

exports('UnregisterChoice', function(id, ownerResource)
    local invokingResource = GetInvokingResource()
    if invokingResource and ownerResource and invokingResource ~= ownerResource then return false end
    return RemoveChoice(id, invokingResource or ownerResource)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    local removed = {}
    for id, registered in pairs(SettingsProviders.choices) do
        if registered.owner == resourceName then removed[#removed + 1] = id end
    end
    for _, id in ipairs(removed) do RemoveChoice(id, resourceName) end
end)
