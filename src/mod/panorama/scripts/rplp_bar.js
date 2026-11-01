// Remember Party Lane Preference: party bar indicator + storage.
//
// Shows the current lane preference ("With Party" / "Balanced") under the party avatars, owns the
// saved settings, and re-applies the remembered choice when someone joins the party. Deadlock's panorama has no storage API, so settings live in the localStorage of a tiny
// page (docs/index.html) loaded in the hidden #RplpStore browser panel:
//   request: SetURL(PAGE_URL + "#" + encodeURIComponent(JSON))   reply: page title "RPLP1:" + JSON
// Nothing is written until the saved values have been read, so defaults never overwrite a save.
(function () {
    var DEFAULT_REMEMBER = true;
    var DEFAULT_CHOICE = 'lanepreference_1'; // With Party; keep in sync with rplp_popup.js
    var PAGE_URL = 'https://passionaterain.github.io/deadlock-remember-party-lane-preference-mod/';
    var TITLE_PREFIX = 'RPLP1:';
    var CHOICES = { lanepreference_0: true, lanepreference_1: true };

    var ctx = $.GetContextPanel();
    var root = ctx;
    while (root.GetParent()) root = root.GetParent();

    // Shared with rplp_popup.js. Lives on the UI root so it survives for the whole game session.
    if (!root.Rplp) {
        root.Rplp = { remember: DEFAULT_REMEMBER, choice: DEFAULT_CHOICE, current: DEFAULT_CHOICE, loaded: false, dirty: false, autoApply: 0 };
    }
    var state = root.Rplp;

    // Indicator.
    var withParty = ctx.FindChildTraverse('RplpWithParty');
    var balanced = ctx.FindChildTraverse('RplpBalanced');

    function refresh() {
        if (!withParty || !balanced) return;
        var isParty = state.current === 'lanepreference_1';
        withParty.visible = isParty;
        balanced.visible = !isParty;
    }

    // Called by the popup script whenever the selection or the remember toggle changes.
    root.RplpRefresh = function () {
        try { if (!ctx.IsValid || ctx.IsValid()) refresh(); } catch (e) { }
    };
    refresh();

    // Storage.
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
            state.current = msg.remember ? msg.choice : 'lanepreference_0';
            refresh();
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

    // Auto-apply. The game only receives the lane preference from the party popup, and a new party starts on
    // Balanced. So when someone joins the party, open the popup through the game's own button; rplp_popup.js
    // sees state.autoApply, applies the remembered choice invisibly and closes itself.
    var membersList = ctx.FindChildTraverse('PartyMembersList');
    var joinButton = ctx.FindChildTraverse('JoinCreateParty');
    var MAX_LOAD_WAIT_TICKS = 15; // seconds to wait for saved settings before using what we have

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
    var pendingApply = false;
    var loadWaitTicks = 0;

    function tryAutoApply() {
        if (!state.remember) { pendingApply = false; return; }
        if (!state.loaded && loadWaitTicks++ < MAX_LOAD_WAIT_TICKS) return;
        // Don't open a popup over the escape menu or while the game has the party button disabled
        // (e.g. in queue); try again next tick.
        if (escapeMenuOpen() || joinButton.enabled === false) return;
        pendingApply = false;
        loadWaitTicks = 0;
        state.autoApply = Date.now();
        $.Msg('[RPLP] party member joined, auto-applying ' + state.choice);
        $.DispatchEvent('Activated', joinButton, 'mouse');
    }

    function tick() {
        try { if (ctx.IsValid && !ctx.IsValid()) return; } catch (e) { return; }
        var n = memberCount();
        if (n > lastCount) pendingApply = true;
        lastCount = n;
        if (pendingApply) tryAutoApply();
        $.Schedule(1, tick);
    }

    if (membersList && joinButton) tick();
})();
