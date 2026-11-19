function orderedWindows(windows, origin, workspace = "") {
    return windows.filter(window => window && window.workspace
        && /^(0x)?[0-9a-f]+$/i.test(window.address))
        .sort((a, b) => Number(b.address === origin) - Number(a.address === origin)
            || Number(b.workspace.name === workspace) - Number(a.workspace.name === workspace)
            || a.workspace.id - b.workspace.id || a.address.localeCompare(b.address));
}

function stepAddress(windows, address, direction) {
    if (!windows.length) return "";
    const index = windows.findIndex(window => window.address === address);
    const offset = direction % windows.length;
    const next = index < 0 ? (direction < 0 ? windows.length - 1 : 0)
        : (index + offset + windows.length) % windows.length;
    return windows[next].address;
}

function activationCommands(windows, address, usingLua) {
    if (!address || !windows.some(window => window.address === address)) return [];
    const selector = "address:" + (address.startsWith("0x") ? address : "0x" + address);
    if (!usingLua) return ["focuswindow " + selector];
    const window = 'window="' + selector + '"';
    return [
        "hl.dsp.focus({" + window + "})",
        'hl.dsp.window.fullscreen({' + window + ',mode=1,action="set"})'
    ];
}
