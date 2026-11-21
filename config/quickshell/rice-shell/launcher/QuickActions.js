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
    {action: "dnd", name: "Toggle Do Not Disturb", aliases: "dnd silence khong lam phien", icon: "󰂛"},
    {action: "dnd-on", name: "Turn Do Not Disturb on", aliases: "bat khong lam phien", icon: "󰂛"},
    {action: "dnd-off", name: "Turn Do Not Disturb off", aliases: "tat khong lam phien", icon: "󰂚"},
    {action: "volume-up", name: "Volume up", aliases: "vol louder", comment: "+5 percentage points"},
    {action: "volume-down", name: "Volume down", aliases: "vol quieter", comment: "-5 percentage points"},
    {action: "volume-mute", name: "Toggle output mute", aliases: "volume speaker audio mute"},
    {action: "mic-mute", name: "Toggle microphone mute", aliases: "mic input"},
    {action: "brightness-up", name: "Brightness up", aliases: "backlight brighter", comment: "+10 percentage points"},
    {action: "brightness-down", name: "Brightness down", aliases: "backlight dimmer", comment: "-10 percentage points"},
    {action: "night-light", name: "Toggle Night Light", aliases: "redshift warm"},
    {action: "night-light-on", name: "Turn Night Light on", aliases: "night light"},
    {action: "night-light-off", name: "Turn Night Light off", aliases: "night light"},
    {action: "awake", name: "Toggle Awake", aliases: "caffeine idle inhibit"},
    {action: "awake-on", name: "Turn Awake on", aliases: "caffeine"},
    {action: "awake-off", name: "Turn Awake off", aliases: "caffeine"},
    {action: "system", name: "Open System", aliases: "system controls", comment: "Control Center"},
    {action: "power", name: "Open Power", aliases: "battery profiles", comment: "Control Center"},
    {action: "audio", name: "Open Audio", aliases: "speaker sound devices", comment: "Control Center"},
    {action: "notifications", name: "Open Notifications", aliases: "notification history", comment: "Control Center"},
    {action: "home", name: "Open Home", aliases: "dashboard", comment: "Control Center"},
    {action: "config", name: "Open Shell Settings", aliases: "config session preferences", comment: "Control Center"},
    {action: "clipboard", name: "Open Clipboard History", aliases: "clipboard paste", icon: "󰅇"},
    {action: "screenshot", name: "Capture Screen Region", aliases: "screenshot print screen", icon: "󰹑"},
    {action: "windows", name: "Switch Windows", aliases: "window switcher tasks", icon: "󰖲"},
    {action: "wallpaper", name: "Open Wallpaper Switcher", aliases: "background wallpaper", icon: "󰸉"},
    {action: "clear-recents", name: "Clear Recent Apps", aliases: "clear usage history"},
    {action: "clear-calculations", name: "Clear Calculator History", aliases: "clear math history"},
    {action: "reload", name: "Reload Rice Shell", aliases: "refresh shell", comment: "Apply shell configuration"}
];

function findActions(query, statuses, availability) {
    const key = query.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/\u0111/g, "d").trim().replace(/\s+/g, " ")
        .replace(/^am luong\b/, "volume").replace(/^do sang\b/, "brightness")
        .replace(/^(?:dnd|do not disturb) (on|off)$/, "dnd-$1")
        .replace(/^night light (on|off)$/, "night-light-$1")
        .replace(/^(?:awake|caffeine) (on|off)$/, "awake-$1");
    const terms = key.split(" ");
    const volume = ["vol", "volume"].includes(terms[0]);
    const brightness = ["brightness", "backlight"].includes(terms[0]);
    if ((volume || brightness) && terms.length > 1 && /^[+-]?(?:\d|\.)/.test(terms[1])) {
        const label = volume ? "volume" : "brightness";
        const min = volume ? 0 : 5;
        const max = volume ? 150 : 100;
        const percent = Number(terms[1].replace(/%$/, ""));
        if (terms.length !== 2 || !/^\d+(?:\.\d+)?%?$/.test(terms[1]) || percent < min || percent > max)
            return [{name: "Invalid " + label, comment: "Enter " + min + "-" + max + "%", disabled: true}];
        return [{kind: "quick-action", action: label + "-set", argument: percent, name: "Set " + label + " to " + percent + "%",
                 comment: statuses?.[label + "-up"] || statuses?.[label] || "", disabled: availability?.[label + "-up"] === false,
                 glyph: volume ? "󰕾" : "󰃠"}];
    }

    const matches = actions.filter(item => item.action === key || terms.every(term =>
        (item.name + " " + item.aliases + " " + (item.comment || "")).toLowerCase().includes(term)))
        .sort((a, b) => Number(b.action === key) - Number(a.action === key))
        .map(item => {
            const status = statuses?.[item.action] || statuses?.[item.action.replace(/-(?:on|off)$/, "")];
            const toggle = item.action === "dnd" || item.action === "night-light" || item.action === "awake";
            const name = toggle && (status === "On" || status === "Off")
                ? "Turn " + item.name.slice(7) + (status === "On" ? " off" : " on") : item.name;
            const glyph = item.icon || (item.action.startsWith("volume") ? "󰕾"
                : item.action.startsWith("brightness") ? "󰃠" : "›");
            return {kind: "quick-action", action: item.action, name, glyph,
                    confirm: item.action === "reload" || item.action.startsWith("clear-"),
                    disabled: availability?.[item.action] === false,
                    comment: [status, item.comment].filter(Boolean).join(" · ")};
        });
    if (terms.length === 1 && (volume || brightness)) {
        const label = volume ? "volume" : "brightness";
        matches.push({name: "Set " + label, comment: "Type :" + label + " 50", disabled: true});
    }
    return matches;
}
