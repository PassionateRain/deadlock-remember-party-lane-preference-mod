// Remember Party Lane Preference: party bar indicator, storage and auto-apply.
//
// Indicator: only ever shows a CONFIRMED value. A value is confirmed when the game's own lane dropdown fired
// its selection-changed event with it (while enabled) for the current party. Any party change (join/leave)
// invalidates it. Solo, unconfirmed or failed: the indicator is hidden rather than guessing.
//
// Storage: Deadlock's panorama has no storage API, so settings live in the localStorage of a tiny page
// (docs/index.html) loaded in the hidden #RplpStore browser panel:
//   request: SetURL(PAGE_URL + "#" + encodeURIComponent(JSON))   reply: page title "RPLP1:" + JSON
// Nothing is written until the saved values have been read, so defaults never overwrite a save.
//
// Auto-apply: the game only receives the lane preference from the party popup, so when the party changes
// this opens the popup through the game's own button; rplp_popup.js applies the remembered choice invisibly
// and closes it.
(function () {
    var DEFAULT_REMEMBER = true;
    var DEFAULT_CHOICE = 'lanepreference_1'; // With Party; keep in sync with rplp_popup.js
    var PAGE_URL = 'https://passionaterain.github.io/deadlock-remember-party-lane-preference-mod/';
    var TITLE_PREFIX = 'RPLP1:';
    var CHOICES = { lanepreference_0: true, lanepreference_1: true };
    var MAX_APPLY_ATTEMPTS = 2;     // per party change
    var MAX_LOAD_WAIT_TICKS = 15;   // seconds to wait for saved settings before using what we have

    var ctx = $.GetContextPanel();
    var root = ctx;
    while (root.GetParent()) root = root.GetParent();

    // Shared with rplp_popup.js. Lives on the UI root so it survives for the whole game session.
    //   epoch:     bumps on every party change; confirmed values are tied to it
    //   confirmed: { value, epoch } set by the popup from the game's dropdown event, or null
    if (!root.Rplp) {
        root.Rplp = {
            remember: DEFAULT_REMEMBER, choice: DEFAULT_CHOICE, loaded: false, dirty: false,
            inParty: false, epoch: 0, confirmed: null, autoApply: 0
        };
    }
    var state = root.Rplp;

    // ---- Indicator ----
    var indicator = ctx.FindChildTraverse('RplpIndicator');
    var withParty = ctx.FindChildTraverse('RplpWithParty');
    var balanced = ctx.FindChildTraverse('RplpBalanced');

    // Solo, nothing can be confirmed (the party's setting doesn't exist yet), so this is null and the
    // indicator stays hidden.
    function confirmedValue() {
        var c = state.confirmed;
        return state.inParty && c && c.epoch === state.epoch ? c.value : null;
    }

    function refresh() {
        if (!indicator || !withParty || !balanced) return;
        var value = confirmedValue();
        indicator.visible = value !== null;
        withParty.visible = value === 'lanepreference_1';
        balanced.visible = value === 'lanepreference_0';
    }

    // Called by the popup script after it confirms a value or changes settings.
    root.RplpRefresh = function () {
        try { if (!ctx.IsValid || ctx.IsValid()) refresh(); } catch (e) { }
    };

    // ---- Storage ----
    var store = ctx.FindChildTraverse('RplpStore');
    var nextId = 1;
    var pendingId = null;
    var loadAttempts = 0;

    function send(msg) {
        if (!store || !store.SetURL) return;
        msg.i = nextId++;
        pendingId = msg.i;
        store.SetURL(PAGE_URL + '#' + encodeURIComponent(JSON.stringify(msg)));
    }

    function save() { send({ op: 'set', remember: state.remember, choice: state.choice }); }

    function requestLoad() {
        if (state.loaded || loadAttempts >= 3) return;
        loadAttempts++;
        send({ op: 'get' });
        $.Schedule(5, requestLoad); // retry if the page didn't answer (slow start / offline)
    }

    function onLoaded(msg) {
        state.loaded = true;
        if (state.dirty) {
            // The user changed something before the saved values arrived: their change wins.
            save();
            return;
        }
        if (msg.ok && typeof msg.remember === 'boolean' && CHOICES[msg.choice]) {
            state.remember = msg.remember;
            state.choice = msg.choice;
        }
    }

    // Deadlock passes either (title) or (panel, title); it can also echo titles, so match prefix and id.
    function onTitle(panelOrTitle, eventTitle) {
        var title = arguments.length > 1 ? eventTitle : panelOrTitle;
        if (typeof title !== 'string' || title.indexOf(TITLE_PREFIX) !== 0) return;
        var msg;
        try { msg = JSON.parse(title.substring(TITLE_PREFIX.length)); } catch (e) { return; }
        if (!msg || msg.i !== pendingId) return;
        pendingId = null;
        if (!state.loaded) onLoaded(msg);
    }

    // Called by the popup script when the user changes the remembered choice or the toggle.
    root.RplpSave = function () {
        state.dirty = true;
        if (state.loaded) save();
    };

    if (store) {
        try { $.RegisterEventHandler('HTMLTitle', store, onTitle); requestLoad(); } catch (e) { }
    }

    // ---- Party tracking + auto-apply ----
    var membersList = ctx.FindChildTraverse('PartyMembersList');
    var joinButton = ctx.FindChildTraverse('JoinCreateParty');

    function memberCount() {
        var n = 0;
        try {
            for (var i = 0; i < membersList.GetChildCount(); i++) {
                var c = membersList.GetChild(i);
                if (!c.BHasClass('Empty') && !c.BHasClass('Invited')) n++;
            }
        } catch (e) { }
        return n;
    }

    function escapeMenuOpen() {
        for (var p = ctx; p; p = p.GetParent()) {
            if (p.BHasClass('ShowEscapeMenu')) return true;
        }
        return false;
    }

    var lastCount = membersList ? memberCount() : 0;
    state.inParty = lastCount > 0;
    // The party bar is rebuilt e.g. after a match; we can't know what happened meanwhile, so start unconfirmed.
    state.epoch++;
    var attempts = 0;
    var loadWaitTicks = 0;

    function needsApply() {
        return state.remember && state.inParty && confirmedValue() === null && attempts < MAX_APPLY_ATTEMPTS &&
            state.blockedEpoch !== state.epoch; // the popup found the dropdown disabled (not party leader)
    }

    function tryAutoApply() {
        if (!state.loaded && loadWaitTicks++ < MAX_LOAD_WAIT_TICKS) return;
        // Don't open a popup over the escape menu, while the game has the party button disabled (e.g. in
        // queue), or while a previous auto-apply is still running; try again next tick.
        if (escapeMenuOpen() || joinButton.enabled === false) return;
        if (state.autoApply && Date.now() - state.autoApply < 3000) return;
        attempts++;
        state.autoApply = Date.now();
        $.Msg('[RPLP] auto-applying ' + state.choice + ' (party epoch ' + state.epoch + ', attempt ' + attempts + ')');
        $.DispatchEvent('Activated', joinButton, 'mouse');
    }

    function tick() {
        try { if (ctx.IsValid && !ctx.IsValid()) return; } catch (e) { return; }
        var n = memberCount();
        if (n !== lastCount) {
            // Party changed: whatever was confirmed belonged to the previous party.
            lastCount = n;
            state.inParty = n > 0;
            state.epoch++;
            attempts = 0;
            loadWaitTicks = 0;
            $.Msg('[RPLP] party changed, members=' + n + ', epoch ' + state.epoch);
        }
        if (needsApply()) tryAutoApply();
        refresh();
        $.Schedule(1, tick);
    }

    refresh();
    if (membersList && joinButton) tick();
})();
