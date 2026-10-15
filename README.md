# Feather Settings

Owns the player settings menu and its PGUP input. It consumes the framework-agnostic `feather-menu-v2` Contract 1 API. Locale persistence remains a minimal Core account primitive, while PVP state is provided by `feather-pvp`.

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

## Grouping and ordering

Registrations and removal still return booleans. Existing registrations need no
migration: omitted group metadata places controls under the owner resource name.
Optional metadata:

```lua
group = { key = 'display', label = 'Display', order = 10 },
order = 20,
```

Group keys accept 1–64 identifier bytes (letters, digits, underscore, dot, colon,
hyphen); labels accept 1–100 bytes. Orders are finite integers from -1000 to 1000,
defaulting to zero. Groups belong to their actual registered owner; identical keys
from different owners remain separate. Groups sort by order then owner/key;
controls sort by order then choice ID. The lowest current choice ID supplies
conflicting group label/order metadata. General appears first and Session last.
Provider labels remain owner-supplied; re-register to change translations.
Registration copies presentation metadata/options, so later caller mutations do
not change the registered control. Malformed supplied metadata is rejected.

Settings validates option membership, disabled controls/options, and finite slider
range/step alignment before dispatch. Providers must still validate and authorize
writes themselves. Callback/export rejection (`false` or a thrown error) refreshes
the displayed owner value. Event success means dispatch only; it cannot establish
acceptance or persistence. No acknowledgement protocol is required.

Preferences apply immediately; each owner controls persistence. Session actions
invoke the existing Character `logout` and `savequit` commands. Core owns account
locale and PVP owns its preference.

Menu initialization tries readiness three times (3 seconds per attempt, 500ms
between attempts), then logs failure. PGUP retries a bounded initialization cycle.
Menu v2 start recreates at most one menu while initialization is in progress.
Settings stop destroys its menu. Regular refreshes preserve element identities;
layout or registration changes replace provider content only because Menu v2 has
no insert/move operation. Built-ins and the open menu are retained. Keyboard focus
and scroll after provider replacement still require live validation.

## Validation

Run `lua5.4 tests/behavior.lua` from this resource root. CI also syntax-checks Lua.
`SettingsClientSmokeTest` checks live dependency contracts in F8.
Current evidence and coordinated live acceptance are maintained in
[Settings delivery evidence](../feather-framework-docs/feather-settings/SCOPED_DELIVERY_EVIDENCE.md).
Do not restart shared dependencies without coordinating with their owners.
