local Menu = exports['feather-menu'].initiate()
local settingsMenu = Menu:RegisterMenu('feather-settings:main', {
    top='50%', left='50%', ['720width']='400px', ['1080width']='450px',
    ['2kwidth']='500px', ['4kwidth']='600px', draggable=true, canclose=true
})
local mainPage = settingsMenu:RegisterPage('feather-settings:main:page')
local languagePage = settingsMenu:RegisterPage('feather-settings:language')
local providerElements = {}

local function Translate(key)
    local result = exports['feather-core']:TranslateLocale(0, key)
    return type(result) == 'table' and result.ok and result.value or key
end
local function PvpState()
    local ok, state = pcall(function() return exports['feather-pvp']:GetState() end)
    return ok and type(state) == 'table' and state.enabled == true
end
local header = mainPage:RegisterElement('header', { value='Settings', slot='header' })
local pvpToggle
pvpToggle = mainPage:RegisterElement('toggle', { label='PVP', start=PvpState(), persist=true }, function()
    local ok, enabled = pcall(function() return exports['feather-pvp']:Toggle() end)
    if ok then pvpToggle:update({ value=enabled, label=enabled and 'PVP: On' or 'PVP: Off' }) end
end)
local languageButton = mainPage:RegisterElement('button', { label='Language', slot='content' }, function()
    languagePage:RouteTo()
end)

local function RemoveProviderElements(id)
    local elements = providerElements[id]
    if not elements then return end
    if elements.choice then elements.choice:UnRegister() end
    if elements.label then elements.label:UnRegister() end
    providerElements[id] = nil
end

local function ReadProviderValue(provider)
    local ok, value = pcall(provider.spec.getValue)
    return ok and value or nil
end

local function ProviderIsVisible(provider)
    if type(provider.spec.isVisible) ~= 'function' then return true end
    local ok, visible = pcall(provider.spec.isVisible)
    return ok and visible == true
end

local function RegisterProviderElements(id, provider)
    local spec = provider.spec
    local options = {}
    for _, option in ipairs(spec.options) do
        options[#options + 1] = { text=option.label, value=option.value }
    end

    local label = mainPage:RegisterElement('subheader', {
        id=('settings-provider:%s:label'):format(id), value=spec.label, slot='content'
    })
    local choice
    choice = mainPage:RegisterElement('dropdown', {
        id=('settings-provider:%s:choice'):format(id),
        options=options,
        selectedValue=ReadProviderValue(provider),
        placeholder=spec.label,
        slot='content',
        persist=false,
    }, function(data)
        local current = SettingsProviders.choices[id]
        if not current or current.owner ~= provider.owner then return end
        local ok, accepted = pcall(current.spec.setValue, data.value)
        if ok and accepted ~= false then
            choice:update({ selectedValue=ReadProviderValue(current) })
        end
    end)
    providerElements[id] = { label=label, choice=choice }
end

local function SyncProviderElements()
    for id in pairs(providerElements) do
        local provider = SettingsProviders.choices[id]
        if not provider or not ProviderIsVisible(provider) then RemoveProviderElements(id) end
    end

    for id, provider in pairs(SettingsProviders.choices) do
        if ProviderIsVisible(provider) then
            if not providerElements[id] then
                RegisterProviderElements(id, provider)
            else
                providerElements[id].label:update({ value=provider.spec.label })
                providerElements[id].choice:update({ selectedValue=ReadProviderValue(provider) })
            end
        end
    end
end

SettingsProviders.onChanged = function(id)
    RemoveProviderElements(id)
    local provider = SettingsProviders.choices[id]
    if provider and ProviderIsVisible(provider) then RegisterProviderElements(id, provider) end
    if Menu.activeMenu and Menu.activeMenu.menuID == 'feather-settings:main'
        and Menu.activeMenu.class.activePage == Menu.activeMenu.class.RegisteredPages['feather-settings:main:page'] then
        mainPage:RouteTo()
    end
end
for code, label in pairs(Config.Languages) do
    languagePage:RegisterElement('button', { label=label, slot='content' }, function()
        local updated = exports['feather-core']:CallRPCAsync('core.account.settings.update.v1', { locale=code })
        if type(updated) == 'table' and updated.ok then
            exports['feather-core']:SetClientLocale(updated.value.locale)
            languageButton:update({ label=('%s: %s'):format(Translate('ui_settings_locale_title'), label) })
            header:update({ value=Translate('ui_settings_title') })
        end
        mainPage:RouteTo()
    end)
end
languagePage:RegisterElement('bottomline', { slot='footer' })
languagePage:RegisterElement('button', { label='Back', slot='footer' }, function() mainPage:RouteTo() end)

local function ToggleMenu()
    if Menu.activeMenu and Menu.activeMenu.menuID == 'feather-settings:main' then settingsMenu:Close(); return end
    SyncProviderElements()
    settingsMenu:Open({ startupPage=mainPage })
    header:update({ value=Translate('ui_settings_title') })
    local enabled = PvpState()
    pvpToggle:update({ value=enabled, label=enabled and 'PVP: On' or 'PVP: Off' })
    local current = exports['feather-core']:CallRPCAsync('core.account.settings.get.v1', {})
    local locale = type(current) == 'table' and current.ok and current.value.locale or Config.DefaultLocale
    languageButton:update({ label=('%s: %s'):format(Translate('ui_settings_locale_title'), Config.Languages[locale] or locale) })
end
CreateThread(function()
    while true do
        Wait(0)
        if Citizen.InvokeNative(0x580417101DDB492F, 0, Config.Hotkey)
            or Citizen.InvokeNative(0x91AEF906BCA88877, 0, Config.Hotkey) then ToggleMenu() end
    end
end)
RegisterCommand('SettingsClientSmokeTest', function()
    local pvp = PvpState()
    local settings = exports['feather-core']:CallRPCAsync('core.account.settings.get.v1', {})
    print(('[SettingsClientSmokeTest] pvp provider            %s'):format(type(pvp) == 'boolean' and 'PASS' or 'FAIL'))
    print(('[SettingsClientSmokeTest] account settings route  %s'):format(type(settings) == 'table' and settings.ok and 'PASS' or 'FAIL'))
end, false)
