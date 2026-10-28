// Pure transitions shared by QML and the offline Node tests.
function create(session) {
    return { session: session, serial: 0, selection: "", active: null, queued: "",
        applied: "", revision: null, phase: "idle", error: "", closed: false };
}

function begin(state, wallpaper) {
    state.serial += 1;
    state.active = { requestId: state.session + "-" + state.serial, wallpaper: wallpaper,
        stdout: null, code: null, exitStatus: null };
    state.phase = "pending";
    state.error = "";
}

function validHash(value) {
    return typeof value === "string" && /^[0-9a-f]{64}$/i.test(value);
}

function resultFor(active) {
    try {
        var result = JSON.parse(active.stdout);
        if (!result || result.schema_version !== 1 || result.request_id !== active.requestId
                || result.wallpaper !== active.wallpaper
                || ["applied", "failed", "rolled_back"].indexOf(result.status) < 0
                || !(result.palette_revision === null || validHash(result.palette_revision))
                || !(result.error_code === null || (typeof result.error_code === "string" && result.error_code.length > 0)))
            return null;
        if (result.status === "applied" && (!validHash(result.palette_revision) || result.error_code !== null))
            return null;
        return result;
    } catch (error) {
        return null;
    }
}

function finish(state) {
    var active = state.active;
    if (active.stdout === null || active.code === null) return;
    var result = resultFor(active);
    if (result && active.exitStatus === 0
            && active.code === (result.status === "applied" ? 0 : 1)) {
        state.phase = result.status;
        state.error = result.error_code || "";
        if (result.status === "applied") {
            state.applied = active.wallpaper;
            state.revision = result.palette_revision;
        }
    } else {
        state.phase = "unknown";
        state.error = "unconfirmed_result";
    }
    state.active = null;
    if (state.queued) {
        var next = state.queued;
        state.queued = "";
        begin(state, next);
    }
}

function reduce(previous, event) {
    var state = Object.assign({}, previous);
    if (event.type === "select") {
        state.selection = event.wallpaper;
    } else if (event.type === "request") {
        if (state.closed || typeof event.wallpaper !== "string" || !event.wallpaper) return previous;
        if (state.active) {
            state.queued = event.wallpaper === state.active.wallpaper ? "" : event.wallpaper;
        } else {
            begin(state, event.wallpaper);
        }
    } else if (event.type === "close") {
        // Closing only hides the view. Explicitly queued work still completes.
        state.closed = true;
    } else {
        if (!state.active || state.active.requestId !== event.requestId) return previous;
        state.active = Object.assign({}, state.active);
        if (event.type === "stdout") {
            if (state.active.stdout !== null) return previous;
            state.active.stdout = event.text;
        } else if (event.type === "exit") {
            if (state.active.code !== null) return previous;
            state.active.code = event.code;
            state.active.exitStatus = event.exitStatus;
        } else if (event.type === "timeout") {
            state.phase = "unknown";
            state.error = "timeout";
            return state;
        } else if (event.type === "launch_failed") {
            state.active.stdout = "";
            state.active.code = 127;
            state.active.exitStatus = 0;
            finish(state);
            if (!state.active) {
                state.phase = "failed";
                state.error = "process_start_failed";
            }
            return state;
        } else {
            return previous;
        }
        finish(state);
    }
    return state;
}

function paletteRevision(generation, resultGeneration, text, code, exitStatus) {
    if (generation !== resultGeneration || code !== 0 || exitStatus !== 0) return null;
    // GNU sha256sum --zero: hash, space, mode marker, literal filename, NUL.
    var match = /^([0-9a-f]{64}) [ *][^\0]+\0$/i.exec(text);
    return match ? match[1].toLowerCase() : null;
}

function adaptivePalette(text, mode, revision) {
    try {
        var token = JSON.parse(text);
        if (!token || token.schema_version !== 1 || ["dark", "light"].indexOf(mode) < 0
                || token.mode !== mode || !validHash(revision)
                || token.source_palette_sha256 !== revision
                || !validHash(token.wallpaper_sha256) || !token.colors
                || !token.contrast || token.contrast.satisfied !== true)
            return null;
        for (var role of ["background", "surface_low", "surface", "surface_high", "text_primary",
                "text_secondary", "accent", "on_accent", "outline", "focus_ring", "danger"])
            if (typeof token.colors[role] !== "string" || !/^#[0-9a-f]{6}$/i.test(token.colors[role]))
                return null;
        var opacity = token.materials && token.materials.panel && token.materials.panel.opacity;
        if (typeof opacity !== "number" || !isFinite(opacity) || opacity < 0 || opacity > 1) return null;
        var colors = token.colors;
        return { mPrimary: colors.accent, mOnPrimary: colors.on_accent, mSurface: colors.surface,
            mOnSurface: colors.text_primary, mSurfaceVariant: colors.surface_high,
            mOnSurfaceVariant: colors.text_secondary, mOutline: colors.outline,
            mFocusRing: colors.focus_ring, mError: colors.danger, panelOpacity: opacity };
    } catch (error) {
        return null;
    }
}

function createPreview(session) {
    return {session: session, serial: 0, requestId: "", wallpaper: "", mode: "dark",
        phase: "idle", swatches: []};
}

function selectPreview(previous, wallpaper, mode) {
    if (previous.wallpaper === wallpaper && previous.mode === mode) return previous;
    var state = Object.assign({}, previous);
    state.serial += 1;
    state.requestId = state.session + "-" + state.serial;
    state.wallpaper = wallpaper;
    state.mode = mode;
    state.phase = wallpaper ? "pending" : "idle";
    state.swatches = [];
    return state;
}

function finishPreview(previous, requestId, text, code, exitStatus) {
    if (requestId !== previous.requestId || previous.phase !== "pending") return previous;
    var state = Object.assign({}, previous, {phase: "failed", swatches: []});
    try {
        var result = JSON.parse(text);
        if (code !== 0 || exitStatus !== 0 || !result || result.schema_version !== 1
                || result.request_id !== requestId || result.wallpaper !== state.wallpaper
                || result.mode !== state.mode || !Array.isArray(result.swatches) || result.swatches.length !== 5)
            return state;
        for (var color of result.swatches)
            if (typeof color !== "string" || !/^#[0-9a-f]{6}$/i.test(color)) return state;
        state.swatches = result.swatches;
        state.phase = "ready";
    } catch (error) {
        // A failed preview never changes the current palette or the apply transaction.
    }
    return state;
}
