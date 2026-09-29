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

Test in F8 with `SettingsClientSmokeTest`, then open the menu with PGUP and verify PVP and language changes. Locale labels update reactively through `ApplyPatch`; the menu is not closed, rebuilt, or reopened to refresh translated Lua strings.

For the v2 migration live gate:

1. start Legacy `feather-menu`, `feather-menu-v2`, and `feather-settings` together;
2. run `SettingsClientSmokeTest` and require all three rows to pass;
3. open Settings with PGUP, toggle PVP, and exercise any registered dropdown/arrows/slider providers;
4. change locale and confirm the translated title and language label update without the menu closing or flashing;
5. restart `feather-menu-v2` while Settings remains loaded, wait for v2 readiness, and confirm PGUP opens one rebuilt Settings menu with no duplicate provider controls; and
6. restart `feather-settings` and confirm providers return once without duplicates.

## Next Settings UX pass

Live review on 2026-09-29 confirmed that Chat's registered theme, density,
timestamp, motion, text-scale, and idle-opacity controls render and apply
correctly alongside Inventory controls. The current flat list becomes difficult
to scan as more feature resources register preferences, and the footer session
buttons can be mistaken for settings persistence controls.

A live `feather-settings` restart on 2026-09-29 restored exactly one copy of
each Chat control with its persisted value. Provider ordering changed across
the restart, confirming that the future grouping/order contract must define a
deterministic presentation order rather than relying on Lua table iteration or
resource registration timing.

The next Settings design pass should:

- Add an explicit grouping contract for built-in and provider-owned controls.
  A likely shape is a stable group key, localized group label, group order, and
  control order. Provider registration order must not determine presentation.
- Present coherent sections such as General, Chat, Inventory, and other feature
  resources without making Settings own those feature values.
- Keep session actions visually and semantically separate from preference
  controls, ideally under a clearly labeled `Session` or `Character Session`
  section.
- State near the preference controls that changes apply immediately; there is
  no settings-wide Save button.
- Replace ambiguous footer labels with action-specific language. In particular,
  `Save and Quit` invokes Character's `/savequit`, which saves the active
  character position and disconnects the player; it does not save Settings.
  A candidate label is `Save Character & Disconnect`.
- Consider similarly clarifying `Logout to character selection` as
  `Save Character & Return to Character Select`, subject to final space and
  localization review.
- Add short descriptions or confirmation treatment for destructive/session
  navigation actions without adding confirmation friction to ordinary setting
  changes.
- Preserve keyboard navigation, focus visibility, responsive height, and
  restart-safe dynamic provider reconciliation after grouping is introduced.

Do not solve grouping by hard-coding Chat or Inventory IDs into Settings. The
registration contract should remain framework-agnostic and owner-scoped so
future resources can join a validated section without Settings taking ownership
of their preferences.
