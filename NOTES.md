# Deadlock party lane-preference mod: notes

## Naming
- Title: "Remember Party Lane Preference" (in Deadlock contexts), "Deadlock Remember Party Lane Preference" outside.
- GitHub repo: `deadlock-remember-party-lane-preference-mod` (also hosts the storage page via GitHub Pages:
  `https://<username>.github.io/deadlock-remember-party-lane-preference-mod/`).
- VPK: `remember_party_lane_preference.vpk`; internal prefix `rplp`.

## Goal
1. Add a "Remember my choice" toggle next to the party lane preference (Balanced / With Party).
2. Show the current lane preference on the party bar (left side of the main menu).

## Findings (2026-11-01)
- Lane preference UI lives in `panorama/layout/popups/popup_join_or_create_party.vxml`
  (styles: `panorama/styles/popups/popup_join_or_create_party.css`).
  Relevant IDs: `#LaneSection`, `#LanePreferenceContainer`, `#LanePreferenceSelector` (DropDown),
  `#LanePreferenceIcon`. The layout already contains a Toggle we can copy for the checkbox.
- Party bar layout: `panorama/layout/citadel_party.vxml`, styles `panorama/styles/citadel_party.css`.
- Localization tokens: `#Citadel_LanePreference_BalancedLanes` ("Balanced"),
  `#Citadel_LanePreference_WithParty` ("With Party"), `#Citadel_LanePreference_Title`.
- Base game ships almost no panorama JS (6 `.vts_c` files, none party-related): party logic is C++,
  wired through layout event attributes.
- Base game `.vxml_c` layouts are binary KV3 (`LaCo` block, compressed), not plaintext, so a decompiler
  (Source 2 Viewer / ValveResourceFormat) is needed to read them. `.vcss_c` contain plaintext CSS.
- Existing installed mod `addons/pak08_dir.vpk` ships custom `.vjs_c` scripts (plaintext JS) using
  `$.GetContextPanel`, `$.CreatePanel`, `$.RegisterEventHandler`, `$.Schedule`, `$.Msg`.
  So custom JS runs fine in Deadlock.
- Mods are managed by Deadlock Mod Manager (`addons/.dmm.json`, gameinfo.gi block). Slots pak01-pak12 used.
  No installed mod touches party files.

## Decompiled layouts (Source 2 Viewer 20.1, `decompiled/`)
- Popup root is a C++ panel `<PopupJoinOrCreateParty>`. The lane dropdown has NO onchange attribute:
  ```xml
  <DropDown id="LanePreferenceSelector">
    <Label id="lanepreference_0" value="0" text="#Citadel_LanePreference_BalancedLanes" .../>
    <Label id="lanepreference_1" value="1" text="#Citadel_LanePreference_WithParty" .../>
  </DropDown>
  ```
  So the C++ panel finds the dropdown by ID and listens for its selection event itself. A scripted
  `SetSelected('lanepreference_1')` fires the same `DropDownSelectionChanged` event, so it will most
  likely go through the same code path. To be confirmed in game.
- Party bar `<CitadelParty>`: `#JoinCreateParty` button opens the popup (`CitadelShowJoinOrCreatePartyPopup()`),
  then `#PartyMembersList` and `#LocalPlayer`. It knows nothing about lane preference, so the indicator has
  to get the value from the popup's dropdown (if the popup stays in the tree while hidden) or from our own
  saved value.
- The game's on/off control is `CitadelSettingsToggle` (label + `SwitchButton`, used in Settings).
  Plain panorama `ToggleButton` gives a classic checkbox. Either works for "Remember my choice".
- Mod script pattern (from pak08): `<scripts><include src="s2r://panorama/scripts/NAME.vjs_c" /></scripts>`,
  ES5-style JS wrapped in an IIFE, defensive try/catch around engine calls.

## Probe mod (`src/probe/`)
Two logging scripts plus layout copies that include them. The popup also gets a temporary
"PROBE: set With Party" button. Read results in the console (`-dev` / `-console` launch option),
filter on `[PartyLaneProbe]` / `[PartyBarProbe]`.

Test steps:
1. Open the party popup: check the log for storage APIs and the dropdown's initial selection.
2. Change the dropdown by hand: confirm `DropDownSelectionChanged` is logged.
3. Set it back to Balanced, close, reopen, click the PROBE button: does the selection stick after reopening?
   Does a party member see the change?
4. Watch `[PartyBarProbe]` ticks with the popup closed: is the dropdown still in the tree?

## Probe results (in game, 2026-11-01)
- Popup is recreated on every open (script runs each time). JS properties set on the UI root panel survive
  between opens for the whole session.
- The game resets the dropdown to `lanepreference_0` (Balanced) before our script runs.
- `dd.SetSelected('lanepreference_1')` fires `DropDownSelectionChanged` like a user click.
- No `$.persistentStorage`, no `GameInterfaceAPI`; `$` props aren't enumerable. No cross-restart storage,
  so the mod starts each session with built-in defaults (remember = on, choice = With Party).

## Mod (`src/mod/`, build: `.\tools\build.ps1 -Src src\mod -Name remember_party_lane_preference`)
- Popup: `ToggleButton#RplpRemember` under the dropdown; `rplp_popup.js` re-applies the remembered choice
  0.05 s after open. Defaults at the top of both scripts.
- Party bar: `#RplpIndicator` (lanes icon + localized label) as its own row under the avatar row,
  right-aligned (friends counter untouched below it); click opens the popup.
- Storage: hidden `CitadelHTMLPanel#RplpStore` in the party bar loads `docs/index.html` from GitHub Pages
  (`https://passionaterain.github.io/deadlock-remember-party-lane-preference-mod/`). `rplp_bar.js` sends
  `{op:get}` on load (3 tries, 5 s apart), `{op:set,remember,choice}` on change; replies arrive as page title
  `RPLP1:{...}` via the `HTMLTitle` event. No writes until the read completes; a change made before that wins.
- Shared state on the UI root: `root.Rplp` {remember, choice, loaded, dirty, inParty, epoch, confirmed,
  autoApply}; callbacks `root.RplpRefresh`, `root.RplpSave`.
- Confirmed-only indicator: `confirmed = {value, epoch}` is set only in the popup's `DropDownSelectionChanged`
  handler while in a party and `dd.enabled !== false`. Party member count change (polled 1 s) or party bar
  reload bumps `epoch`; opening the popup with remember off clears `confirmed`. Indicator hidden unless
  `confirmed.epoch === epoch`.
- Auto-apply: when remember is on, in a party and unconfirmed (max 2 attempts per epoch), the bar dispatches
  `Activated` on `#JoinCreateParty`; the popup sees `state.autoApply` (< 3 s old), sets opacity 0, applies,
  closes via `Activated` on `#EscapeButton` after 0.4 s. Skipped while ESC menu is open or button disabled.
- Apply always produces a real selection change: if the target is already selected, flip to the other option
  and back (`applying` flag keeps the flip out of the remembered choice).
- In-game results (2026-11-01, as party leader): indicator hidden solo, appears after a friend joins
  (auto-apply works), choice survives a game restart. Only the party leader can change the lane preference
  (dropdown disabled for members); non-leader path (`blockedEpoch`) not yet tested in game.

## Cross-session storage research (2026-11-01)
- No lane-preference convar exists (client.dll only has `lanepreference_` / `LanePreferenceSelector`).
  Settings controls bind to convars via `convar="..."`, but borrowing a real saved convar is too risky.
- Community workaround (HP Colors v2, Roster Tools, deadlock-ui-store, DeadlockUtils): hidden
  `CitadelHTMLPanel` loads a tiny HTTPS page (GitHub Pages) whose `localStorage` lives in Steam's CEF profile.
  - Request: `panel.SetURL(PAGE_URL + "#" + encodeURIComponent(JSON.stringify(msg)))` (hash change, no reload);
    page handles `hashchange`.
  - Reply: page sets `document.title = "PREFIX:" + JSON.stringify(reply)`; Panorama gets an `HTMLTitle` event.
  - Since a 2026-10-01 game update the panel only opens `https://` URLs (file:// and javascript: stopped working).
  - Offline -> no saved value that session (fall back to defaults). GitHub Pages caches ~10 min.
  - Some mod-safety scanners flag mods that use `CitadelHTMLPanel` (file-read exfiltration concern).
- Refs: github.com/Hantu-Raya/hpv2-store, github.com/piotrpanawas/deadlock-roster-tools-bridge,
  github.com/Hantu-Raya/Deadlock-mods-collection/pull/27, github.com/Slush97/grimoire/pull/401

## Open questions (answer with a probe mod)
- Is there a persistent storage API from JS (e.g. `$.persistentStorage`) or a writable archived convar?
- Does `DropDown.SetSelected(id)` from JS fire the same C++ handler as a user click (i.e. actually
  change the party setting)?
- Can a non-leader change the setting, or only the party creator?
- How can the party bar read the current lane preference when the popup is closed?

## Tooling
- `tools/vpk.ps1`: read-only VPK lister/extractor (`list` / `extract`). `-Panorama` decode only works for
  plaintext CSS/JS; layouts need Source 2 Viewer.
- `tools/s2v/Source2Viewer-CLI.exe` (ValveResourceFormat 20.1, from GitHub releases): decompile with
  `Source2Viewer-CLI.exe -i <file.vxml_c> -o <out.xml> -d`.
- Still needed to build: CS2 Workshop Tools (Steam > CS2 > Properties > DLC) for `resourcecompiler.exe`,
  then `tools\build.ps1` packs `build\<name>.vpk`. CS2 ships no `vpk.exe`, so packing uses our own
  `tools\vpkpack.ps1` (single-file VPK v2; passes Source 2 Viewer `--vpk_verify`). Install it through Deadlock Mod Manager, never by copying
  into `addons\` by hand (DMM owns pak numbering and `.dmm.json`).
