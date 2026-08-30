# Feather Settings

Owns the player settings menu and its PGUP input. Locale persistence remains a minimal Core account primitive, while PVP state is provided by `feather-pvp`.

Feature resources can add bounded choice controls without moving preference
ownership into Settings:

```lua
exports['feather-settings']:RegisterChoice({
    id = 'my-resource:display-mode',
    label = 'Display Mode',
    options = {
        { value='Temporary', label='Temporary' },
        { value='Always', label='Always' },
    },
    isVisible = function() return true end,
    getValue = function() return exports['my-resource']:GetDisplayMode() end,
    setValue = function(value) return exports['my-resource']:SetDisplayMode(value) end,
})
```

Provider IDs are resource-owned and unique. Providers are removed automatically
when their resource stops and may re-register after either resource restarts.
Settings renders the control; the provider validates and persists its value.
Call `UnregisterChoice(id)` for explicit removal.

Test in F8 with `SettingsClientSmokeTest`, then open the menu with PGUP and verify PVP and language changes.
