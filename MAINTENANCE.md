# Maintenance runbook

How this mod works, what it depends on in the game, and how to fix it fast when a Deadlock update breaks it.
For the research history behind these decisions, see [`NOTES.md`](NOTES.md). Known issues and planned fixes for
the next update: [`BACKLOG.md`](BACKLOG.md).

- **Built against:** Deadlock ClientVersion **6839** (Oct 31 2026), mod **v1.0.0**
- **Live:** [GitHub release](https://github.com/PassionateRain/deadlock-remember-party-lane-preference-mod/releases) ·
  [GameBanana 735153](https://gamebanana.com/mods/735153) · storage page
  `https://passionaterain.github.io/deadlock-remember-party-lane-preference-mod/`

---

## 1. Quick start after a Deadlock update

```powershell
.\tools\check-game-update.ps1
```

It prints the game version, diffs the game's current layouts against the baseline in `vanilla\`, and checks all
15 dependencies listed in [§3](#3-what-the-mod-depends-on-in-the-game).

| Result | Meaning | Do |
|---|---|---|
| All `[ok]` | Nothing we touch changed | Mod should work. If it doesn't, use the [symptom table](#4-symptom--cause--fix) |
| `[CHANGED]` layout | Valve edited a layout we override; our copy now hides their change | [§5 Updating after a game patch](#5-updating-after-a-game-patch) |
| `[MISSING]` dependency | An ID/class/token we rely on was renamed or removed | Find the new name in the decompiled file (`build\check\`), update the script, [§5](#5-updating-after-a-game-patch) |
| Decompile error | Layout file moved/renamed | Search for it: `.\tools\vpk.ps1 list -Vpk <game>\pak01_dir.vpk -Filter party` |

---

## 2. How it works

Two of Valve's Panorama layouts are replaced with copies that add our panels and scripts. Every addition is
marked with an `<!-- RPLP: ... -->` comment.

| File (in `src/mod/panorama/`) | Overrides | Adds |
|---|---|---|
| `layout/popups/popup_join_or_create_party.xml` | Valve's party popup | script include, `ToggleButton#RplpRemember` under the lane dropdown |
| `layout/citadel_party.xml` | Valve's party bar (main menu, top right) | script include, `#RplpIndicator` row under the avatars, hidden `CitadelHTMLPanel#RplpStore` |
| `scripts/rplp_popup.js` | (new) | applies the remembered choice when the popup opens; confirms values; auto-close |
| `scripts/rplp_bar.js` | (new) | indicator, storage, party tracking, auto-apply |
| `docs/index.html` | (GitHub Pages) | storage page |

**Shared state** lives on the UI root panel (survives popup re-creation for the whole session):
`root.Rplp = { remember, choice, loaded, dirty, inParty, epoch, confirmed, autoApply, blockedEpoch }`,
callbacks `root.RplpRefresh()`, `root.RplpSave()`.

**Key behaviours**
- The game resets the lane dropdown to Balanced every time the popup is created. With "Remember" on, the popup
  script selects the remembered choice 0.05 s after creation, always as a *real* change (if it's already
  selected: flip to the other option and back) so the game's own handler runs.
- **Confirmed-only indicator:** `confirmed = {value, epoch}` is set only in the dropdown's
  `DropDownSelectionChanged` handler, while in a party and the dropdown is enabled. Any party-size change (polled
  every 1 s) or party-bar reload bumps `epoch`, invalidating it. Opening the popup with "Remember" off clears it.
  Solo / unconfirmed / not leader → hidden. Never show a value that isn't confirmed.
- **Auto-apply:** in a party, "Remember" on, unconfirmed → dispatch `Activated` on `#JoinCreateParty`; the popup
  sees `state.autoApply` (< 3 s old), sets opacity 0, applies, closes via `Activated` on `#EscapeButton` after
  0.4 s. Max 2 attempts per epoch. Waits while the ESC menu is open or the button is disabled (in queue). If the
  dropdown is disabled (not party leader) → `blockedEpoch = epoch`, stop.
- **Storage:** panorama has no storage API. `rplp_bar.js` loads `docs/index.html` (GitHub Pages) in the hidden
  `CitadelHTMLPanel`. Request: `SetURL(PAGE_URL + "#" + encodeURIComponent(JSON))` with
  `{i, op:"get"}` or `{i, op:"set", remember, choice}`. Reply: page sets `document.title = "RPLP1:" + JSON`,
  delivered as the panel's `HTMLTitle` event `(title)` or `(panel, title)`. localStorage key `rplp.v1`.
  No write until the first read succeeded (3 tries, 5 s apart); offline → defaults (remember on, With Party).

---

## 3. What the mod depends on in the game

All checked by `tools\check-game-update.ps1` except the engine APIs (bottom rows), which only an in-game test proves.

| Dependency | Where | Used for |
|---|---|---|
| `panorama/layout/popups/popup_join_or_create_party.vxml_c` | pak01 | file we override |
| `panorama/layout/citadel_party.vxml_c` | pak01 | file we override |
| `#LanePreferenceSelector` DropDown with `lanepreference_0` / `lanepreference_1` | popup | read/set the lane preference |
| `#EscapeButton` | popup | close after auto-apply |
| `#JoinCreateParty` | party bar | open popup for auto-apply; `.enabled` = not in queue |
| `#PartyMembersList` children, classes `Empty` / `Invited` | party bar + css | count party members |
| `ShowEscapeMenu` class on an ancestor | css | don't auto-apply over the ESC menu |
| `ToggleButton` base style | citadel_base_styles | checkbox look |
| `#Citadel_LanePreference_WithParty`, `_BalancedLanes`, `_Title` | localization | indicator text + tooltip |
| `s2r://panorama/images/icons/icon_lanes.vsvg` | pak01 | indicator icon |
| `DropDownSelectionChanged` event, `DropDown.SetSelected/GetSelected`, `.enabled` | engine | apply + confirm |
| `$.DispatchEvent('Activated', panel, 'mouse')` | engine | open/close the popup |
| `CitadelHTMLPanel.SetURL`, `HTMLTitle` event, `https://` only | engine | storage |

---

## 4. Symptom → cause → fix

| Symptom | Likely cause | Fix |
|---|---|---|
| Party popup or party bar looks like vanilla, no checkbox/indicator | Mod not loaded: disabled in mod manager, `gameinfo.gi` reset by an update, or another mod overrides the same layout | Re-enable / let the mod manager repair `gameinfo.gi`; check for conflicts (`vpk.ps1 list` on other addons, filter `party`) |
| Popup is missing Valve's new elements, or Valve's new party feature doesn't work | Valve changed a layout we override | §5 |
| Checkbox shows but choice isn't re-applied | `LanePreferenceSelector` / option IDs renamed | Run checker, update IDs in `rplp_popup.js` |
| Indicator never appears in a party (as leader) | Auto-apply can't open popup (`JoinCreateParty` renamed or `Activated` no longer opens it), or member counting broke (`Empty`/`Invited` classes) | Run checker; watch `[RPLP]` lines in `vconsole2.exe` (Deadlock\game\bin\win64) |
| Popup flashes visibly or stays open after a friend joins | `#EscapeButton` renamed, or the popup's open animation changed | Update close logic in `rplp_popup.js`; adjust the 0.4 s delay |
| Settings not remembered after restart | Storage page unreachable (repo renamed/private, Pages disabled, offline) or Valve restricted `CitadelHTMLPanel` again | Open the page URL in a browser (tab title must read `RPLP1:loading`); check repo Settings > Pages = `main` `/docs`; if the panel API changed, see community mods (HP Colors v2, Roster Tools) for the new approach |
| Label wrong language / raw `#Citadel_...` text | Localization token renamed | Find new token in `resource/localization/citadel_main/citadel_main_english.txt` |
| Mod scanner warns about the browser panel | Expected: we use `CitadelHTMLPanel` for storage | Point to README "How saving works" + source |

---

## 5. Updating after a game patch

1. **Check:** `.\tools\check-game-update.ps1`. The new decompiled layouts are in `build\check\`.
2. **Merge:** for each `[CHANGED]` layout, start from the **new** Valve file in `build\check\` and re-apply our
   `RPLP` blocks from `src\mod` (they're small: a script include + one or two panels per file). Don't copy our
   old file over Valve's new one: that would hide their changes.
3. **Fix dependencies:** for each `[MISSING]` item, find the new name in `build\check\` and update the scripts.
4. **Build:** `.\tools\build.ps1 -Src src\mod -Name remember_party_lane_preference`
   (needs CS2 + Counter-Strike 2 Workshop Tools for `resourcecompiler.exe`).
5. **Verify the package:** `Source2Viewer-CLI.exe -i build\<copy>_dir.vpk --vpk_verify` and decompile one layout
   from it to confirm the `RPLP` additions are inside.
6. **Test in game** with the [checklist](#6-in-game-test-checklist).
7. **Save the new baseline:** `.\tools\check-game-update.ps1 -SaveBaseline`, and update "Built against" at the
   top of this file.
8. **Release:** [§7](#7-release-checklist).

---

## 6. In-game test checklist

Keep `vconsole2.exe` open with filter `RPLP`.

- [ ] Solo: indicator hidden; popup shows "Remember my choice" under the lane dropdown
- [ ] As leader, friend joins: `[RPLP] party changed` → `auto-applying …`; indicator appears within ~2 s; no visible popup / only a brief dim
- [ ] Pick Balanced in popup → indicator switches; restart game, party up → Balanced auto-applied
- [ ] Uncheck "Remember", reopen popup → indicator hidden
- [ ] As non-leader: dropdown disabled, indicator hidden, at most one `auto-applying` line
- [ ] After a match: indicator briefly hidden, then re-confirmed
- [ ] ESC menu open while a friend joins: no popup over the menu; applies after closing it

---

## 7. Release checklist

1. Pick up open items from [`BACKLOG.md`](BACKLOG.md); move shipped ones to "Done" with the version.
   Bump the version (`v1.0.1` for fixes): README "Built against", release notes, GameBanana Version field.
2. Commit + push source.
3. `gh release create vX.Y.Z build\remember_party_lane_preference.vpk --title vX.Y.Z --notes-file <notes>`.
   Include the SHA-256 of the VPK in the notes.
4. GameBanana (`https://gamebanana.com/mods/edit/735153`): Media tab → upload a new zip (VPK + README.txt;
   GameBanana doesn't accept bare `.vpk`), remove the old file, update Version on the Development tab.
5. Keep the AI disclosure in README, release notes and GameBanana description.

**Never** rename the repo, make it private, or disable GitHub Pages: every installed copy loads the storage page
from that URL. If the storage protocol or data format ever changes, bump the title prefix (`RPLP1:` → `RPLP2:`)
and storage key (`rplp.v1` → `rplp.v2`) together in `docs/index.html` and `rplp_bar.js`.
