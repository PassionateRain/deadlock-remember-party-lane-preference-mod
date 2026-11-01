// Remember Party Lane Preference: join/create party popup.
// Adds "Remember my choice": while checked, every time the popup opens it re-selects the remembered lane
// preference (the game resets the dropdown to Balanced on each open). Saving is done by rplp_bar.js, which
// also opens this popup invisibly when someone joins the party (state.autoApply).
(function () {
    var DEFAULT_REMEMBER = true;
    var DEFAULT_CHOICE = 'lanepreference_1'; // With Party; keep in sync with rplp_bar.js

    var ctx = $.GetContextPanel();
    var root = ctx;
    while (root.GetParent()) root = root.GetParent();

    if (!root.Rplp) {
        root.Rplp = { remember: DEFAULT_REMEMBER, choice: DEFAULT_CHOICE, current: DEFAULT_CHOICE, loaded: false, dirty: false };
    }
    var state = root.Rplp;

    // Opened by rplp_bar.js when someone joined the party: apply invisibly, then close.
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

    $.RegisterEventHandler('DropDownSelectionChanged', dd, function () {
        var id = selectedId();
        if (!id) return;
        state.current = id;
        if (state.remember && state.choice !== id) {
            state.choice = id;
            save();
        }
        refreshBar();
    });

    ctx.RplpToggleRemember = function () {
        state.remember = !!toggle.checked;
        if (state.remember) state.choice = selectedId() || state.choice;
        save();
        refreshBar();
    };

    // The game initialises the dropdown during popup creation; apply one tick later so our selection
    // lands after it and goes through the game's own change handler.
    $.Schedule(0.05, function () {
        if (state.remember && selectedId() !== state.choice) {
            dd.SetSelected(state.choice);
        } else {
            state.current = selectedId() || state.current;
            refreshBar();
        }
        // Give the game a moment to handle the selection before closing.
        if (auto) $.Schedule(0.4, close);
    });
})();
