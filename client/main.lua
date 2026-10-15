local Menu = exports['feather-menu-v2']
local menuId, mainPageId, languagePageId
local elements, providerElements = {}, {}
local initialized, rebuilding = false, false
local layout = {}
local groupElements = {}
local epoch = 0
local InitializeMenu

local function IsCallable(value)
    if type(value) == 'function' then return true end
    if type(value) ~= 'table' and type(value) ~= 'userdata' then return false end
    local metatable = getmetatable(value)
    return type(metatable) == 'table' and type(metatable.__call) == 'function'
end

local function Require(result, label)
    if type(result) ~= 'table' or result.ok ~= true then
        error(('[feather-settings] %s failed: %s %s'):format(label, tostring(result and result.code), tostring(result and result.message)))
    end
    return result.value
end
local function Translate(key)
    local result = exports['feather-core']:TranslateLocale(0, key)
    return type(result) == 'table' and result.ok and result.value or key
end
local function PvpState()
    local ok, state = pcall(function() return exports['feather-pvp']:GetState() end)
    return ok and type(state) == 'table' and state.enabled == true
end
local function CharacterActive()
    if GetResourceState('feather-character') ~= 'started' then return false end
    local ok, active = pcall(function()
        return exports['feather-character']:HasActiveCharacter()
    end)
    return ok and active == true
end
local function CurrentLocale()
    local current = exports['feather-core']:CallRPCAsync('core.account.settings.get.v1', {})
    return type(current) == 'table' and current.ok and current.value.locale or Config.DefaultLocale
end
local function LanguageLabel(locale)
    return ('%s: %s'):format(Translate('ui_settings_locale_title'), Config.Languages[locale] or locale)
end
local function UpdateElement(reference, changes, label)
    return Require(Menu:UpdateElement(menuId, reference.pageId, reference.elementId, changes), label or 'UpdateElement')
end
local function Add(pageId, elementType, spec, callback)
    local value = Require(Menu:AddElement(menuId, pageId, elementType, spec, callback), 'AddElement ' .. spec.key)
    return { pageId = pageId, elementId = value.elementId }
end

local function RemoveProviderElement(id)
    local reference = providerElements[id]
    if not reference then return end
    local result = Menu:RemoveElement(menuId, reference.pageId, reference.elementId)
    if type(result) ~= 'table' or result.ok ~= true then
        print(('[feather-settings] provider element removal failed id=%s code=%s'):format(tostring(id), tostring(result and result.code)))
    end
    providerElements[id] = nil
end
local function ReadProviderValue(provider)
    if provider.spec.setEvent then return provider.value end
    local ok, value
    if type(provider.spec.getExport) == 'string' then
        ok, value = pcall(function() return exports[provider.owner][provider.spec.getExport]() end)
    else ok, value = pcall(provider.spec.getValue) end
    return ok and value or nil
end
local function WriteProviderValue(provider, value)
    if type(provider.spec.setEvent) == 'string' then
        local ok, failure = pcall(TriggerEvent, provider.spec.setEvent, value)
        if ok then provider.value = value end
        return ok, ok and true or failure
    end
    if type(provider.spec.setExport) == 'string' then
        return pcall(function() return exports[provider.owner][provider.spec.setExport](value) end)
    end
    return pcall(provider.spec.setValue, value)
end
local function ProviderIsVisible(provider)
    if not IsCallable(provider.spec.isVisible) then return true end
    local ok, visible = pcall(provider.spec.isVisible)
    return ok and visible == true
end
local function ProviderOptions(spec)
    local options = {}
    for _, option in ipairs(spec.options or {}) do
        options[#options + 1] = { label = option.label, value = option.value, disabled = option.disabled == true }
    end
    return options
end
local function RegisterProviderElement(id, provider)
    local spec, controlType = provider.spec, provider.spec.control or 'dropdown'
    local initial = ReadProviderValue(provider)
    local elementSpec = { key = 'provider-' .. id, label = spec.label, value = initial, slot = 'content', persist = false }
    if controlType == 'slider' then
        elementSpec.value = type(initial) == 'number' and initial or spec.min
        elementSpec.min, elementSpec.max, elementSpec.step = spec.min, spec.max, spec.step
    else
        elementSpec.options = ProviderOptions(spec)
        if elementSpec.value == nil and elementSpec.options[1] then elementSpec.value = elementSpec.options[1].value end
        if controlType == 'dropdown' then elementSpec.maxVisibleOptions = math.min(10, math.max(3, spec.maxVisibleOptions or 6)) end
    end
    elementSpec.disabled = spec.disabled == true
    local reference
    local generation = epoch
    reference = Add(mainPageId, controlType, elementSpec, function(event)
        local current = SettingsProviders.choices[id]
        if current ~= provider or generation ~= epoch or providerElements[id] ~= reference then return end
        local value = controlType == 'slider' and tonumber(event.value) or event.value
        current.writeRevision = (current.writeRevision or 0) + 1
        local writeRevision = current.writeRevision
        local previous = ReadProviderValue(current)
        if SettingsProviders.choices[id] ~= current or current.writeRevision ~= writeRevision or generation ~= epoch then return end
        if not SettingsProviders.ValidValue(current.spec, value) then
            UpdateElement(reference, { value = previous }, 'Restore invalid provider value')
            return
        end
        local ok, accepted = WriteProviderValue(current, value)
        if SettingsProviders.choices[id] ~= current or current.writeRevision ~= writeRevision or generation ~= epoch or providerElements[id] ~= reference then return end
        if not ok or accepted == false then
            print(('[feather-settings] provider write rejected id=%s value=%s detail=%s'):format(tostring(id), tostring(value), tostring(accepted)))
            UpdateElement(reference, { value = ReadProviderValue(current) or previous }, 'Restore rejected provider value')
            return
        end
        UpdateElement(reference, { value = ReadProviderValue(current) }, 'Update provider value')
    end)
    providerElements[id] = reference
end
local function SyncProviderElements()
    local groups = SettingsProviders.Groups(ProviderIsVisible)
    local nextLayout = {}
    for _, group in ipairs(groups) do
        nextLayout[#nextLayout + 1] = group.key .. ':' .. group.label
        for _, choice in ipairs(group.choices) do nextLayout[#nextLayout + 1] = choice.provider end
    end
    local changed = #layout ~= #nextLayout
    for i, value in ipairs(nextLayout) do if layout[i] ~= value then changed = true end end
    if changed then
        -- Contract 1 has no insertion/move operation. Replace provider content only.
        for id in pairs(providerElements) do RemoveProviderElement(id) end
        for _, reference in ipairs(groupElements) do
            Require(Menu:RemoveElement(menuId, reference.pageId, reference.elementId), 'Remove provider heading')
        end
        groupElements = {}
        for i, group in ipairs(groups) do
            groupElements[#groupElements + 1] = Add(mainPageId, 'subheader', {
                key = 'provider-group-' .. i, value = group.label,
            })
            for _, choice in ipairs(group.choices) do RegisterProviderElement(choice.id, choice.provider) end
        end
        layout = nextLayout
    else
        for id, reference in pairs(providerElements) do
            UpdateElement(reference, { value = ReadProviderValue(SettingsProviders.choices[id]) }, 'Sync provider')
        end
    end
end

local function UpdateTranslatedLabels(locale)
    local labels = {
        general = { 'value', 'ui_settings_general' }, guidance = { 'value', 'ui_settings_guidance' },
        session = { 'value', 'ui_settings_session' }, sessionHelp = { 'value', 'ui_settings_session_help' },
        logout = { 'label', 'ui_settings_logout' }, saveQuit = { 'label', 'ui_settings_disconnect' },
        back = { 'label', 'ui_settings_back' },
    }
    for name, definition in pairs(labels) do
        UpdateElement(elements[name], { [definition[1]] = Translate(definition[2]) })
    end
    UpdateElement(elements.pvp, { onLabel = Translate('ui_settings_enabled'), offLabel = Translate('ui_settings_disabled') })
    Require(Menu:ApplyPatch(menuId, {
        { op = 'updateElement', pageId = elements.header.pageId, elementId = elements.header.elementId,
            changes = { value = Translate('ui_settings_title') } },
        { op = 'updateElement', pageId = elements.languageButton.pageId, elementId = elements.languageButton.elementId,
            changes = { label = LanguageLabel(locale) } },
        { op = 'updateElement', pageId = elements.languageHeader.pageId, elementId = elements.languageHeader.elementId,
            changes = { value = Translate('ui_settings_locale_title') } },
    }), 'Apply translated labels')
end
local function BuildMenu()
    epoch = epoch + 1
    elements, providerElements, groupElements, layout = {}, {}, {}, {}
    menuId = Require(Menu:CreateMenu({
        key = 'main', draggable = true, closable = true, resizable = false, persistPosition = true,
        size = { width = '28rem', maxWidth = '90vw', maxHeight = '85vh', breakpoints = {
            ['720'] = '25rem', ['1080'] = '28rem', ['1440'] = '31rem', ['2160'] = '34rem',
        } }, theme = { preset = 'redemption', accent = '#a73732', radius = '8px' },
    }), 'CreateMenu').menuId
    mainPageId = Require(Menu:CreatePage(menuId, { key = 'main' }), 'CreatePage main').pageId
    languagePageId = Require(Menu:CreatePage(menuId, { key = 'language' }), 'CreatePage language').pageId
    elements.header = Add(mainPageId, 'header', { key = 'title', value = Translate('ui_settings_title'), slot = 'header' })
    elements.general = Add(mainPageId, 'subheader', { key = 'general', value = Translate('ui_settings_general') })
    elements.guidance = Add(mainPageId, 'textdisplay', { key = 'guidance', value = Translate('ui_settings_guidance') })
    elements.pvp = Add(mainPageId, 'toggle', {
        key = 'pvp', label = 'PVP', value = PvpState(), onLabel = Translate('ui_settings_enabled'), offLabel = Translate('ui_settings_disabled'), persist = false,
    }, function()
        local ok, enabled = pcall(function() return exports['feather-pvp']:Toggle() end)
        if ok then UpdateElement(elements.pvp, { value = enabled }, 'Update PVP') end
    end)
    elements.languageButton = Add(mainPageId, 'button', {
        key = 'language', label = LanguageLabel(CurrentLocale()), slot = 'content',
    }, function() Require(Menu:NavigateToPage(menuId, languagePageId), 'Navigate language') end)
    Add(mainPageId, 'bottomline', { key = 'session-bottom-line', slot = 'footer' })
    elements.session = Add(mainPageId, 'subheader', { key = 'session', value = Translate('ui_settings_session'), slot = 'footer' })
    elements.sessionHelp = Add(mainPageId, 'textdisplay', { key = 'session-help', value = Translate('ui_settings_session_help'), slot = 'footer' })
    elements.logout = Add(mainPageId, 'button', {
        key = 'logout', label = Translate('ui_settings_logout'), slot = 'footer', disabled = true,
    }, function()
        if not CharacterActive() then return end
        Require(Menu:CloseMenu(menuId), 'Close settings before logout')
        ExecuteCommand('logout')
    end)
    elements.saveQuit = Add(mainPageId, 'button', {
        key = 'save-quit', label = Translate('ui_settings_disconnect'), slot = 'footer', disabled = true,
    }, function()
        if not CharacterActive() then return end
        Require(Menu:CloseMenu(menuId), 'Close settings before save and quit')
        ExecuteCommand('savequit')
    end)
    elements.languageHeader = Add(languagePageId, 'header', {
        key = 'title', value = Translate('ui_settings_locale_title'), slot = 'header',
    })
    local codes = {}
    for code in pairs(Config.Languages) do codes[#codes + 1] = code end
    table.sort(codes)
    for _, code in ipairs(codes) do
        local label = Config.Languages[code]
        Add(languagePageId, 'button', { key = 'locale-' .. code, label = label }, function()
            local updated = exports['feather-core']:CallRPCAsync('core.account.settings.update.v1', { locale = code })
            if type(updated) == 'table' and updated.ok then
                exports['feather-core']:SetClientLocale(updated.value.locale)
                UpdateTranslatedLabels(updated.value.locale)
            end
            Require(Menu:NavigateToPage(menuId, mainPageId), 'Navigate main after locale')
        end)
    end
    Add(languagePageId, 'bottomline', { key = 'bottom-line', slot = 'footer' })
    elements.back = Add(languagePageId, 'button', { key = 'back', label = Translate('ui_settings_back'), slot = 'footer' }, function()
        Require(Menu:NavigateToPage(menuId, mainPageId), 'Navigate main')
    end)
    initialized = true
end

InitializeMenu = function()
    if initialized or rebuilding then return end
    rebuilding = true
    local requestEpoch = epoch
    local ok, problem = pcall(function()
        local ready
        for attempt = 1, 3 do
            ready = Menu:AwaitReady(3000)
            if type(ready) == 'table' and ready.ok then break end
            if attempt < 3 then Wait(500) end
        end
        if epoch ~= requestEpoch then return end
        Require(ready, 'AwaitReady after 3 attempts; PGUP retries')
        BuildMenu()
    end)
    if epoch ~= requestEpoch and not initialized then return end
    rebuilding = false
    if not ok then
        if menuId then pcall(function() Menu:DestroyMenu(menuId) end) end
        initialized, menuId = false, nil
        print(('[feather-settings] menu initialization failed: %s'):format(tostring(problem)))
    end
end

SettingsProviders.onChanged = function()
    if initialized then SyncProviderElements() end
end
local function ToggleMenu()
    if not initialized then InitializeMenu() end
    if not initialized then return end
    local state = Menu:GetMenuState(menuId)
    if type(state) == 'table' and state.ok and state.value.open then Require(Menu:CloseMenu(menuId), 'CloseMenu'); return end
    SyncProviderElements()
    UpdateTranslatedLabels(CurrentLocale())
    local characterActive = CharacterActive()
    Require(Menu:ApplyPatch(menuId, {
        { op = 'updateElement', pageId = elements.pvp.pageId, elementId = elements.pvp.elementId, changes = { value = PvpState() } },
        { op = 'updateElement', pageId = elements.header.pageId, elementId = elements.header.elementId,
            changes = { value = Translate('ui_settings_title') } },
        { op = 'updateElement', pageId = elements.languageButton.pageId, elementId = elements.languageButton.elementId,
            changes = { label = LanguageLabel(CurrentLocale()) } },
        { op = 'updateElement', pageId = elements.logout.pageId, elementId = elements.logout.elementId,
            changes = { disabled = not characterActive } },
        { op = 'updateElement', pageId = elements.saveQuit.pageId, elementId = elements.saveQuit.elementId,
            changes = { disabled = not characterActive } },
    }), 'Refresh settings values')
    Require(Menu:OpenMenu(menuId, { pageId = mainPageId }), 'OpenMenu')
end

local function MenuInputCaptured()
    if menuId then
        local state = Menu:GetMenuState(menuId)
        if type(state) == 'table' and state.ok and state.value.open then return false end
    end
    if GetResourceState('feather-menu-v2') ~= 'started' then return false end
    local ok, captured = pcall(function()
        return exports['feather-menu-v2']:IsInputCaptured()
    end)
    return ok and captured == true
end

CreateThread(function()
    InitializeMenu()
    while true do
        Wait(0)
        if Citizen.InvokeNative(0x580417101DDB492F, 0, Config.Hotkey)
            or Citizen.InvokeNative(0x91AEF906BCA88877, 0, Config.Hotkey) then
            if not MenuInputCaptured() then ToggleMenu() end
        end
    end
end)
AddEventHandler('onClientResourceStop', function(stopped)
    if stopped ~= 'feather-menu-v2' and stopped ~= GetCurrentResourceName() then return end
    epoch = epoch + 1
    if stopped == GetCurrentResourceName() and menuId then pcall(function() Menu:DestroyMenu(menuId) end) end
    initialized, rebuilding = false, false
    menuId, mainPageId, languagePageId = nil, nil, nil
    elements, providerElements = {}, {}
end)
AddEventHandler('onClientResourceStart', function(started)
    if started ~= 'feather-menu-v2' then return end
    CreateThread(function()
        Wait(0)
        InitializeMenu()
    end)
end)
RegisterCommand('SettingsClientSmokeTest', function()
    local pvp = PvpState()
    local settings = exports['feather-core']:CallRPCAsync('core.account.settings.get.v1', {})
    local menu = initialized and Menu:GetMenuState(menuId) or nil
    print(('[SettingsClientSmokeTest] pvp provider            %s'):format(type(pvp) == 'boolean' and 'PASS' or 'FAIL'))
    print(('[SettingsClientSmokeTest] account settings route  %s'):format(type(settings) == 'table' and settings.ok and 'PASS' or 'FAIL'))
    print(('[SettingsClientSmokeTest] menu v2 contract         %s'):format(type(menu) == 'table' and menu.ok and 'PASS' or 'FAIL'))
end, false)

AddEventHandler('feather-core:locale:changed', function()
    if initialized then UpdateTranslatedLabels(CurrentLocale()) end
end)
