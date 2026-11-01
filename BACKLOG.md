# Backlog

Known issues and ideas to pick up in the next update. Newest first within each section.
When an item ships, move it to "Done" with the version.

## Open

### UI: dropdown option tooltip covers the "Remember my choice" checkbox
- **Found:** 2026-11-01, v1.0.0, game build 6839
- **What:** In the party popup, the game's tooltip for a lane option ("Lane assignments will prioritize keeping
  your party together.") appears to the right of where the opened dropdown list was, overlapping the checkbox
  label ("Remember my choi…"). The tooltip seems to stay visible after the list closes.
- **Cause (likely):** vanilla behaviour made visible by our layout. The option labels show
  `UIShowTextTooltipStyled(...)` on mouseover and hide it on mouseout; when the list closes under the cursor the
  mouseout may never fire, leaving the tooltip anchored at the old option position, which is where our checkbox
  now sits (`ToggleButton#RplpRemember`, directly under `#LanePreferenceSelector`).
- **Fix options:**
  1. Move the checkbox out of the list's footprint, e.g. into the left column under the "Lane preference" title,
     or add enough top margin. Cheapest, no script changes.
  2. Hide the stale tooltip ourselves: on `DropDownSelectionChanged` (and when the menu closes) dispatch
     `UIHideTextTooltip`. Check `$.DispatchEvent('UIHideTextTooltip')` works from script.
  3. Both.
- **Verify:** open the dropdown, hover each option, pick one, move the mouse to the checkbox: label fully readable,
  no lingering tooltip; also check with the popup at different resolutions.

### Leadership handed over without a member change isn't detected
- **What:** Auto-apply re-runs only when the party size changes. If the leader promotes you (no join/leave),
  `blockedEpoch` keeps auto-apply off for that party and the indicator stays hidden until you open the popup.
- **Fix idea:** also re-check when the party bar's leader marker changes (find a class/attribute on the party
  members that marks the leader), or retry once when the popup is opened manually and the dropdown is enabled
  (already happens) and periodically re-probe `JoinCreateParty`/dropdown state.
- **Priority:** low (rare; opening the popup fixes it).

### Non-leader path not tested in game
- **What:** `blockedEpoch` (stop retrying when the dropdown is disabled) shipped in v1.0.0 but was only tested
  as party leader.
- **Verify:** friend creates the party and invites you; expect indicator hidden and at most one `[RPLP] auto-applying`
  line in `vconsole2.exe`, no visible popup.

## Done
- v1.0.0 (2026-11-01): initial release.
