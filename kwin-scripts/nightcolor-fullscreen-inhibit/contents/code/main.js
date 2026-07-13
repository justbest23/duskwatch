function isFullscreenLike(client) {
    if (!client) return false;
    if (client.desktopWindow || client.dock) return false;
    if (client.fullScreen) return true;
    if (!client.normalWindow) return false;
    // A maximized window is not the same thing as fullscreen, even if some
    // window rule strips its border - maximize and fullscreen are distinct
    // KWin states, so explicitly exclude maximized windows here rather than
    // relying on geometry/border alone to tell them apart.
    if (client.maximizeMode !== 0) return false;
    // Borderless fullscreen: undecorated normal window covering the whole output
    var output = client.output;
    if (!output) return false;
    var geo = client.frameGeometry;
    var screenGeo = output.geometry;
    return !client.decorationHasAlpha && client.noBorder &&
           geo.width === screenGeo.width && geo.height === screenGeo.height &&
           geo.x === screenGeo.x && geo.y === screenGeo.y;
}

// A window counts toward the fullscreen-output set as long as it's actually
// visible somewhere - focus is deliberately NOT required, so clicking over to
// a window on another monitor doesn't drop the game's screen back to the
// dimmed level while the game is still on show (github issue #1).
function isEligible(client) {
    if (!isFullscreenLike(client)) return false;
    if (client.minimized) return false;
    // Skip windows parked on another virtual desktop; an empty desktops list
    // means "on all desktops".
    if (client.desktops && client.desktops.length > 0 &&
        client.desktops.indexOf(workspace.currentDesktop) === -1) return false;
    return true;
}

// Inhibit/uninhibit is delegated to the duskwatch helper service instead of
// calling org.kde.KWin.NightLight directly: callDBus() marshals JS numbers as
// int32 (KDE bug 486024, fix unmerged), so uninhibit(uint cookie) can never
// dispatch from here and the inhibit gets stuck until the compositor
// restarts. Strings marshal fine, and the helper is D-Bus activated, so this
// call also starts it on demand.
//
// What's sent is the comma-joined set of outputs that currently have a
// fullscreen-like window (e.g. "DP-2" or "DP-2,HDMI-A-1", "" for none). The
// helper inhibits Night Color while the set is non-empty (that part is
// compositor-global either way - KWin has no per-output color temperature)
// and republishes the set for fullscreen-brightness-watch.sh, which uses it
// for per-screen brightness when FULLSCREEN_BRIGHTNESS_SCOPE=active-screen.
var lastSent = null; // null forces the initial state to be sent

function update() {
    var outputs = [];
    workspace.windowList().forEach(function(client) {
        if (!isEligible(client) || !client.output) return;
        var name = client.output.name;
        if (outputs.indexOf(name) === -1) outputs.push(name);
    });
    var list = outputs.sort().join(",");
    if (list === lastSent) return;
    lastSent = list;
    callDBus("org.duskwatch.NightLightInhibit", "/org/duskwatch/NightLightInhibit",
        "org.duskwatch.NightLightInhibit", "SetFullscreenOutputs", list);
}

function watch(client) {
    client.fullScreenChanged.connect(update);
    client.frameGeometryChanged.connect(update);
    client.minimizedChanged.connect(update);
    client.outputChanged.connect(update);
    client.desktopsChanged.connect(update);
}

workspace.windowAdded.connect(function(client) { watch(client); update(); });
workspace.windowRemoved.connect(update);
workspace.currentDesktopChanged.connect(update);
workspace.windowList().forEach(watch);
update();
