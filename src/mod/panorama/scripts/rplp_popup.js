// Remember Party Lane Preference: join/create party popup.
// Adds "Remember my choice": while checked, every time the popup opens it applies the remembered lane
// preference through the game's own dropdown (the game resets it to Balanced on each open).
//
// Confirmation: a value only counts as confirmed (and is shown by the party bar indicator) when the game's
// dropdown fires its selection-changed event while enabled and we're in a party. Opening the popup with
// "Remember" off invalidates the confirmed value, because the game's reset on open may have changed it.
//
// rplp_bar.js owns storage and opens this popup invisibly (state.autoApply) when the party changes.
(function () {
    var DEFAULT_REMEMBER = true;
    var DEFAULT_CHOICE = 'lanepreference_1'; // With Party; keep in sync with rplp_bar.js

    var ctx = $.GetContextPanel();
    var root = ctx;
    while (root.GetParent()) root = root.GetParent();

    if (!root.Rplp) {
        root.Rplp = {
            remember: DEFAULT_REMEMBER, choice: DEFAULT_CHOICE, loaded: false, dirty: false,
            inParty: false, epoch: 0, confirmed: null, autoApply: 0
        };
    }
    var state = root.Rplp;

    // Opened by rplp_bar.js: apply invisibly, then close.
    var auto = !!state.autoApply && Date.now() - state.autoApply < 3000;
    state.autoApply = 0;
    if (auto) ctx.style.opacity = '0';

    function close() {
        var button = ctx.FindChildTraverse('EscapeButton');
        if (button) $.DispatchEvent('Activated', button, 'mouse');
    }

    var dd = ctx.FindChildTraverse('LanePreferenceSelector');
    var toggle = ctx.FindChildTraverse('RplpRemember');
    if (!dd || !toggle) {
        if (auto) close();
        return;
    }

    function selectedId() {
        try { var s = dd.GetSelected(); return s ? s.id : null; } catch (e) { return null; }
    }
    function refreshBar() {
        try { if (root.RplpRefresh) root.RplpRefresh(); } catch (e) { }
    }
    function save() {
        try { if (root.RplpSave) root.RplpSave(); } catch (e) { }
    }

    toggle.checked = state.remember;

    // The game's own change event: the only thing we treat as "the game now has this value".
    $.RegisterEventHandler('DropDownSelectionChanged', dd, function () {
        var id = selectedId();
        if (!id) return;
        if (state.inParty && dd.enabled !== false) {
            state.confirmed = { value: id, epoch: state.epoch };
        }
        if (state.remember && !applying && state.choice !== id) {
            state.choice = id;
            save();
        }
        refreshBar();
    });

    ctx.RplpToggleRemember = function () {
        state.remember = !!toggle.checked;
        if (state.remember) {
            state.choice = selectedId() || state.choice;
            apply();
        }
        save();
        refreshBar();
    };

    // Make the game's dropdown select the remembered choice as a real change, so the game's handler runs and
    // the value is confirmed. Re-selecting the already-selected item changes nothing, so in that case flip to
    // the other option and back (same as two clicks); `applying` keeps the flip out of the remembered choice.
    var applying = false;
    function apply() {
        var target = state.choice;
        applying = true;
        try {
            if (selectedId() === target) {
                dd.SetSelected(target === 'lanepreference_1' ? 'lanepreference_0' : 'lanepreference_1');
            }
            dd.SetSelected(target);
        } finally {
            applying = false;
        }
    }

    // The game initialises the dropdown during popup creation; act one tick later so we land after it.
    $.Schedule(0.05, function () {
        if (state.remember) {
            apply();
        } else {
            // The game just reset the dropdown on open; we can't tell whether that changed the real setting.
            state.confirmed = null;
            refreshBar();
        }
        // Give the game a moment to handle the selection before closing.
        if (auto) $.Schedule(0.4, close);
    });
})();
