# Feather Settings

Owns the player settings menu and its PGUP input. Locale persistence remains a minimal Core account primitive, while PVP state is provided by `feather-pvp`.

Feature resources can add bounded choice controls without moving preference
ownership into Settings:

```lua
exports['feather-settings']:RegisterChoice({
    id = 'my-resource:display-mode',
    ownerResource = GetCurrentResourceName(),
    label = 'Display Mode',
    control = 'arrows',
    options = {
        { value='Temporary', label='Temporary' },
        { value='Always', label='Always' },
    },
    initialValue = GetDisplayMode(),
    setEvent = 'MyResource:Settings:SetDisplayMode',
})
```

Provider IDs are resource-owned and unique. Providers are removed automatically
when their resource stops and may re-register after either resource restarts.
Settings renders the control; the provider validates and persists its value.
Pass `ownerResource = GetCurrentResourceName()` because some CFX client export
paths do not preserve `GetInvokingResource()`. Call
`UnregisterChoice(id, GetCurrentResourceName())` for explicit removal.
For cross-resource controls, a scalar `initialValue` plus a local `setEvent` is
preferred: the owner validates, persists, and applies the event value without
depending on CFX callback or dynamic-export serialization.
Supported controls are `dropdown`, `arrows`, and `slider`. Sliders use numeric
`min`, `max`, and `step` fields; arrows use the same bounded option documents as
dropdowns.

Test in F8 with `SettingsClientSmokeTest`, then open the menu with PGUP and verify PVP and language changes.
