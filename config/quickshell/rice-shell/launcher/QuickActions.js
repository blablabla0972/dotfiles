.pragma library

function calculate(expression) {
    if (expression.length > 512)
        return {error: "Expression is too long"};

    let rest = expression;

    function take(pattern) {
        rest = rest.replace(/^\s+/, "");
        const match = rest.match(pattern);
        if (!match) return "";
        rest = rest.slice(match[0].length);
        return match[0];
    }

    function finite(value) {
        if (!Number.isFinite(value)) throw new Error("Number out of range");
        return value;
    }

    function primary() {
        const sign = take(/^[+-]/);
        if (sign) return sign === "-" ? -primary() : primary();

        if (take(/^\(/)) {
            const value = sum();
            if (!take(/^\)/)) throw new Error("Expected a closing parenthesis");
            return value;
        }

        const number = take(/^(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?/i);
        if (!number) throw new Error("Expected a number or parenthesis");
        return finite(Number(number));
    }

    function product() {
        let value = primary();
        for (let op; (op = take(/^[*/]/)); ) {
            const next = primary();
            if (op === "/" && next === 0) throw new Error("Cannot divide by zero");
            value = finite(op === "*" ? value * next : value / next);
        }
        return value;
    }

    function sum() {
        let value = product();
        for (let op; (op = take(/^[+-]/)); ) {
            const next = product();
            value = finite(op === "+" ? value + next : value - next);
        }
        return value;
    }

    try {
        if (!rest.trim()) return {error: "Enter an expression"};
        const value = sum();
        if (rest.trim()) return {error: "Unexpected input"};
        // Hide floating-point noise while retaining the digits of safe integers.
        const rounded = Number(value.toPrecision(15));
        return {value: String(Number.isSafeInteger(value) || !Number.isFinite(rounded) ? value : rounded)};
    } catch (error) {
        return {error: error.message};
    }
}

const actions = [
    {action: "volume-up", name: "Volume up", aliases: "vol louder tang am luong", comment: "+5 percentage points", icon: "󰎈", category: "Audio & media"},
    {action: "volume-down", name: "Volume down", aliases: "vol quieter giam am luong", comment: "-5 percentage points", icon: "󰎈", category: "Audio & media"},
    {action: "volume-mute", name: "Toggle output mute", aliases: "volume speaker audio mute", icon: "󰎈", category: "Audio & media"},
    {action: "mic-mute", name: "Toggle microphone mute", aliases: "mic input", icon: "󰎈", category: "Audio & media"},
    {action: "audio", name: "Open Audio", aliases: "speaker sound devices", comment: "Control Center", icon: "󰎈", category: "Audio & media"},
    {"action": "volume-mute-on", "name": "Mute output", "aliases": "silence speaker audio tat tieng", "icon": "󰝟", "category": "Audio & media"},
    {"action": "volume-mute-off", "name": "Unmute output", "aliases": "speaker audio bat tieng", "icon": "󰕾", "category": "Audio & media"},
    {"action": "mic-mute-on", "name": "Mute microphone", "aliases": "mic input tat mic", "icon": "󰍭", "category": "Audio & media"},
    {"action": "mic-mute-off", "name": "Unmute microphone", "aliases": "mic input bat mic", "icon": "󰍬", "category": "Audio & media"},
    {"action": "mic-up", "name": "Microphone louder", "aliases": "mic input gain tang am luong mic", "icon": "󰍬", "category": "Audio & media"},
    {"action": "mic-down", "name": "Microphone quieter", "aliases": "mic input gain giam am luong mic", "icon": "󰍬", "category": "Audio & media"},
    {"action": "media-toggle", "name": "Play / pause media", "aliases": "music play pause toggle nhac phat dung", "icon": "󰐎", "category": "Audio & media"},
    {"action": "media-play", "name": "Play media", "aliases": "resume music phat nhac", "icon": "󰐊", "category": "Audio & media"},
    {"action": "media-pause", "name": "Pause media", "aliases": "stop playing music dung nhac", "icon": "󰏤", "category": "Audio & media"},
    {"action": "media-next", "name": "Next track", "aliases": "next song skip bai tiep", "icon": "󰒭", "category": "Audio & media"},
    {"action": "media-prev", "name": "Previous track", "aliases": "previous song back bai truoc", "icon": "󰒮", "category": "Audio & media"},
    {"action": "media-loop", "name": "Cycle repeat mode", "aliases": "music loop repeat lap lai", "icon": "󰑖", "category": "Audio & media"},
    {action: "brightness-up", name: "Brightness up", aliases: "backlight brighter", comment: "+10 percentage points", icon: "󰃠", category: "Display & appearance"},
    {action: "brightness-down", name: "Brightness down", aliases: "backlight dimmer", comment: "-10 percentage points", icon: "󰃠", category: "Display & appearance"},
    {action: "night-light", name: "Toggle Night Light", aliases: "redshift warm", icon: "󰃠", category: "Display & appearance"},
    {action: "night-light-on", name: "Turn Night Light on", aliases: "night light", icon: "󰃠", category: "Display & appearance"},
    {action: "night-light-off", name: "Turn Night Light off", aliases: "night light", icon: "󰃠", category: "Display & appearance"},
    {action: "wallpaper", name: "Open Wallpaper Switcher", aliases: "background wallpaper hinh nen", icon: "󰸉", category: "Display & appearance"},
    {"action": "theme-dark", "name": "Use dark theme", "aliases": "dark mode theme toi giao dien toi", "icon": "󰖔", "category": "Display & appearance"},
    {"action": "theme-light", "name": "Use light theme", "aliases": "light mode theme sang giao dien sang", "icon": "󰖨", "category": "Display & appearance"},
    {"action": "wifi", "name": "Open Wi-Fi", "aliases": "wireless internet mang ket noi", "icon": "󰖩", "category": "Connectivity"},
    {"action": "wifi-on", "name": "Turn Wi-Fi on", "aliases": "wifi wireless bat wifi", "icon": "󰖩", "category": "Connectivity"},
    {"action": "wifi-off", "name": "Turn Wi-Fi off", "aliases": "wifi wireless tat wifi", "icon": "󰖪", "category": "Connectivity", "confirm": true},
    {"action": "bluetooth", "name": "Open Bluetooth", "aliases": "pair devices ghep doi", "icon": "󰂯", "category": "Connectivity"},
    {"action": "bluetooth-on", "name": "Turn Bluetooth on", "aliases": "bluetooth bat bluetooth", "icon": "󰂯", "category": "Connectivity"},
    {"action": "bluetooth-off", "name": "Turn Bluetooth off", "aliases": "bluetooth tat bluetooth", "icon": "󰂲", "category": "Connectivity", "confirm": true},
    {"action": "hotspot", "name": "Open Hotspot", "aliases": "tethering share internet chia se mang", "icon": "󰀂", "category": "Connectivity"},
    {action: "awake", name: "Toggle Awake", aliases: "caffeine idle inhibit", icon: "󰐥", category: "Power & session"},
    {action: "awake-on", name: "Turn Awake on", aliases: "caffeine", icon: "󰐥", category: "Power & session"},
    {action: "awake-off", name: "Turn Awake off", aliases: "caffeine", icon: "󰐥", category: "Power & session"},
    {action: "power", name: "Open Power", aliases: "battery profiles", comment: "Control Center", icon: "󰐥", category: "Power & session"},
    {"action": "profile-saver", "name": "Use power saver", "aliases": "battery power profile tiet kiem pin", "icon": "󰁹", "category": "Power & session"},
    {"action": "profile-balanced", "name": "Use balanced power mode", "aliases": "battery power profile can bang", "icon": "󰾅", "category": "Power & session"},
    {"action": "profile-performance", "name": "Use performance mode", "aliases": "power profile high performance hieu nang", "icon": "󰓅", "category": "Power & session"},
    {"action": "session", "name": "Open Power Menu", "aliases": "session shutdown reboot restart logout sign out suspend sleep tat may khoi dong lai dang xuat", "icon": "󰐥", "category": "Power & session"},
    {"action": "lock", "name": "Lock screen", "aliases": "lock session khoa man hinh", "icon": "󰌾", "category": "Power & session"},
    {action: "home", name: "Open Home", aliases: "dashboard", comment: "Control Center", icon: "󰕰", category: "Desktop & tools"},
    {action: "system", name: "Open System", aliases: "system controls", comment: "Control Center", icon: "󰕰", category: "Desktop & tools"},
    {action: "notifications", name: "Open Notifications", aliases: "notification history", comment: "Control Center", icon: "󰕰", category: "Desktop & tools"},
    {action: "config", name: "Open Shell Settings", aliases: "config session preferences", comment: "Control Center", icon: "󰕰", category: "Desktop & tools"},
    {action: "clipboard", name: "Open Clipboard History", aliases: "clipboard paste bo nho tam", icon: "󰅇", category: "Desktop & tools"},
    {action: "screenshot", name: "Capture Screen Region", aliases: "screenshot print screen chup man hinh", icon: "󰹑", category: "Desktop & tools"},
    {action: "windows", name: "Switch Windows", aliases: "window switcher tasks", icon: "󰖲", category: "Desktop & tools"},
    {action: "open-settings", name: "Open Settings", aliases: "rice settings preferences system cai dat", comment: "Rice Settings", icon: "󰕰", category: "Desktop & tools"},
    {"action": "screenshot-full", "name": "Capture full screen", "aliases": "fullscreen screenshot print screen chup toan man hinh", "icon": "󰹑", "category": "Desktop & tools"},
    {"action": "workspace-next", "name": "Next workspace", "aliases": "desktop workspace tiep theo", "icon": "󰒭", "category": "Desktop & tools"},
    {"action": "workspace-prev", "name": "Previous workspace", "aliases": "desktop workspace truoc", "icon": "󰒮", "category": "Desktop & tools"},
    {"action": "workspace-empty", "name": "Open empty workspace", "aliases": "desktop workspace trong", "icon": "󰝦", "category": "Desktop & tools"},
    {"action": "scratchpad", "name": "Toggle special workspace", "aliases": "scratchpad special desktop", "icon": "󰘔", "category": "Desktop & tools"},
    {action: "dnd", name: "Toggle Do Not Disturb", aliases: "dnd silence khong lam phien", icon: "󰂛", category: "Notifications"},
    {action: "dnd-on", name: "Turn Do Not Disturb on", aliases: "bat khong lam phien", icon: "󰂛", category: "Notifications"},
    {action: "dnd-off", name: "Turn Do Not Disturb off", aliases: "tat khong lam phien", icon: "󰂚", category: "Notifications"},
    {"action": "clear-notifications", "name": "Clear notification history", "aliases": "delete notifications xoa thong bao", "icon": "󰂚", "category": "Notifications", "confirm": true},
    {"action": "settings-appearance", "name": "Appearance settings", "aliases": "wallpaper color theme font giao dien", "icon": "󰏘", "category": "Settings"},
    {"action": "settings-desktop", "name": "Windows & workspaces settings", "aliases": "gaps border tiling cua so", "icon": "󰖲", "category": "Settings"},
    {"action": "settings-shell", "name": "Desktop shell settings", "aliases": "dynamic island top bar control center", "icon": "󰒓", "category": "Settings"},
    {"action": "settings-launcher", "name": "Launcher settings", "aliases": "calculator favorites history launcher", "icon": "󰕰", "category": "Settings"},
    {"action": "settings-network", "name": "Wi-Fi & hotspot settings", "aliases": "network wireless internet mang", "icon": "󰖩", "category": "Settings"},
    {"action": "settings-bluetooth", "name": "Bluetooth settings", "aliases": "pair devices ghep doi", "icon": "󰂯", "category": "Settings"},
    {"action": "settings-display", "name": "Display settings", "aliases": "monitor resolution refresh scale man hinh", "icon": "󰍹", "category": "Settings"},
    {"action": "settings-sound", "name": "Sound settings", "aliases": "audio output input speaker am luong", "icon": "󰕾", "category": "Settings"},
    {"action": "settings-keyboard", "name": "Keyboard settings", "aliases": "shortcuts keybinds layout phim tat", "icon": "󰌌", "category": "Settings"},
    {"action": "settings-power-input", "name": "Power & sleep settings", "aliases": "battery idle lock pin", "icon": "󰐥", "category": "Settings"},
    {"action": "settings-notifications", "name": "Notification settings", "aliases": "alerts dnd thong bao", "icon": "󰂚", "category": "Settings"},
    {"action": "settings-maintenance", "name": "Maintenance settings", "aliases": "diagnostics backups recovery", "icon": "󰒔", "category": "Settings"},
    {action: "clear-recents", name: "Clear Recent Apps", aliases: "clear usage history", icon: "󰒔", category: "Maintenance"},
    {action: "clear-calculations", name: "Clear Calculator History", aliases: "clear math history", icon: "󰒔", category: "Maintenance"},
    {action: "reload", name: "Reload Rice Shell", aliases: "refresh shell", comment: "Apply shell configuration", icon: "󰒔", category: "Maintenance"},
    {"action": "regenerate-theme", "name": "Regenerate adaptive palette", "aliases": "matugen wallpaper colors bang mau", "icon": "󰏘", "category": "Maintenance", "confirm": true},
    {"action": "reload-hyprland", "name": "Reload Hyprland", "aliases": "compositor refresh reload config", "icon": "󰒔", "category": "Maintenance", "confirm": true}
];

function normalizeAction(text) {
    return text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/\u0111/g, "d").trim().replace(/\s+/g, " ");
}

function findActions(query, statuses, availability) {
    const key = normalizeAction(query)
        .replace(/^am luong\b/, "volume").replace(/^do sang\b/, "brightness")
        .replace(/^(?:dnd|do not disturb) (on|off)$/, "dnd-$1")
        .replace(/^night light (on|off)$/, "night-light-$1")
        .replace(/^(?:awake|caffeine) (on|off)$/, "awake-$1")
        .replace(/^wi-fi\b/, "wifi")
        .replace(/^microphone (?=\d)/, "mic ");
    const terms = key.split(" ");
    const volume = ["vol", "volume"].includes(terms[0]);
    const brightness = ["brightness", "backlight"].includes(terms[0]);
    const mic = ["mic", "microphone"].includes(terms[0]);
    if ((volume || brightness || mic) && terms.length > 1 && /^[+-]?(?:\d|\.)/.test(terms[1])) {
        const label = volume ? "volume" : brightness ? "brightness" : "mic";
        const min = brightness ? 5 : 0;
        const max = volume ? 150 : 100;
        const percent = Number(terms[1].replace(/%$/, ""));
        if (terms.length !== 2 || !/^\d+(?:\.\d+)?%?$/.test(terms[1]) || !Number.isFinite(percent) || percent < min || percent > max)
            return [{kind: "message", name: "Invalid " + label, comment: "Enter " + min + "-" + max + "%", disabled: true}];
        return [{kind: "quick-action", action: label + "-set", argument: percent, name: "Set " + (mic ? "microphone" : label) + " to " + percent + "%",
                 comment: statuses?.[label + "-up"] || statuses?.[label] || "", disabled: availability?.[label + "-up"] === false,
                 glyph: volume ? "󰕾" : brightness ? "󰃠" : "󰍬"}];
    }

    const exact = actions.find(item => item.action === key || item.action === key.replace(/ /g, "-"));
    function score(item) {
        if (!key) return 0;
        const name = normalizeAction(item.name);
        const aliases = normalizeAction(item.aliases);
        const id = item.action.replace(/-/g, " ");
        if (name === key) return 0;
        if (name.startsWith(key)) return 1;
        if (aliases.split(" ").includes(key)) return 2;
        const haystack = name + " " + aliases + " " + id + " " + normalizeAction(item.comment || "");
        if (terms.every(term => haystack.includes(term))) return 3;
        return -1;
    }
    const candidates = exact ? [exact] : actions.map(item => ({item, score: score(item)}))
        .filter(entry => entry.score >= 0).sort((a, b) => a.score - b.score).map(entry => entry.item);
    const matches = candidates.map(item => {
        const status = statuses?.[item.action] || statuses?.[item.action.replace(/-(?:on|off)$/, "")];
        const toggle = item.action === "dnd" || item.action === "night-light" || item.action === "awake";
        const name = toggle && (status === "On" || status === "Off")
            ? "Turn " + item.name.slice(7) + (status === "On" ? " off" : " on") : item.name;
        return {kind: "quick-action", action: item.action, name, glyph: item.icon || "›",
                category: key ? "" : item.category,
                confirm: !!item.confirm || item.action === "reload" || item.action.startsWith("clear-"),
                disabled: availability?.[item.action] === false,
                comment: [status, item.comment || item.category].filter(Boolean).join(" · ")};
    });
    if (terms.length === 1 && (volume || brightness || mic)) {
        const label = volume ? "volume" : brightness ? "brightness" : "mic";
        matches.push({kind: "message", name: "Set " + label, comment: "Type :" + label + " 50", disabled: true,
            glyph: volume ? "󰕾" : brightness ? "󰃠" : "󰍬"});
    }
    return matches;
}
