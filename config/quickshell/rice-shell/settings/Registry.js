var pages = [
    { id: "appearance", label: qsTr("Appearance"), group: qsTr("Personalization"), icon: "appearance", summary: qsTr("Choose a color mode, wallpaper, and adaptive palette."), rows: [
        ["color-mode", qsTr("Color mode"), "light dark theme giao diện sáng tối"],
        ["wallpaper", qsTr("Wallpaper"), "background hình nền"],
        ["palette", qsTr("Adaptive palette"), "accent colors matugen bảng màu"],
        ["reduce-motion", qsTr("Reduce motion"), "animation transitions accessibility motion giảm chuyển động hiệu ứng"],
        ["compact-rows", qsTr("Compact layout"), "density spacing giao diện gọn khoảng cách"],
        ["fonts", qsTr("Interface font"), "typography font phông chữ"],
        ["icons", qsTr("GTK icon theme"), "icons glyphs biểu tượng"]
    ] },
    { id: "desktop", label: qsTr("Windows & workspaces"), group: qsTr("Personalization"), icon: "windows", summary: qsTr("Set window spacing and inspect workspaces and rules."), rows: [
        ["workspaces", qsTr("Workspaces"), "virtual desktops không gian làm việc"],
        ["gaps", qsTr("Window spacing"), "gaps border tiling inner outer viền khoảng cách cửa sổ"],
        ["window-effects", qsTr("Window effects"), "rounding blur shadows animation bo góc bóng mờ hiệu ứng"],
        ["window-rules", qsTr("Window rules"), "windowrule floating fullscreen rules quy tắc cửa sổ"]
    ] },
    { id: "shell", label: qsTr("Desktop shell"), group: qsTr("Personalization"), icon: "shell", summary: qsTr("Customize the Control Center, bar, Dynamic Island, and on-screen feedback."), rows: [
        ["control-center", qsTr("Control Center"), "opening tab quick settings dashboard trung tâm điều khiển"],
        ["top-bar", qsTr("Top Bar"), "system tray network status battery clock seconds thanh trên đồng hồ khay hệ thống"],
        ["dynamic-island", qsTr("Dynamic Island"), "music media preview nhạc trình phát"],
        ["osd", qsTr("On-screen feedback"), "osd popup volume brightness microphone phản hồi trên màn hình"]
    ] },
    { id: "launcher", label: qsTr("Launcher"), group: qsTr("Personalization"), icon: "launcher", summary: qsTr("Choose which results and quick actions appear in Launcher."), rows: [
        ["launcher", qsTr("Launcher"), "app search quick actions trình khởi chạy ứng dụng"]
    ] },
    { id: "network", label: qsTr("Wi-Fi & Hotspot"), group: qsTr("Connectivity"), icon: "wifi", summary: qsTr("Connect to a wireless network or share your connection."), rows: [
        ["wifi", qsTr("Wi-Fi"), "wifi wi-fi wireless internet network mạng không dây"],
        ["hotspot", qsTr("Hotspot"), "tethering chia sẻ mạng"]
    ] },
    { id: "bluetooth", label: qsTr("Bluetooth"), group: qsTr("Connectivity"), icon: "bluetooth", summary: qsTr("Pair, connect, and manage nearby devices."), rows: [
        ["bluetooth", qsTr("Bluetooth"), "pairing ghép đôi"]
    ] },
    { id: "display", label: qsTr("Displays"), group: qsTr("Devices"), icon: "display", summary: qsTr("Configure your screens, backlight, and Night Light."), rows: [
        ["displays", qsTr("Displays"), "monitor resolution refresh rate hz scale screen màn hình độ phân giải tần số quét"],
        ["night-light", qsTr("Night Light"), "blue light warm color ánh sáng đêm"],
        ["brightness", qsTr("Brightness"), "backlight độ sáng"]
    ] },
    { id: "sound", label: qsTr("Sound"), group: qsTr("Devices"), icon: "sound", summary: qsTr("Manage playback and recording devices."), rows: [
        ["output-volume", qsTr("Output volume"), "audio sound amplification âm lượng"],
        ["output-mute", qsTr("Output mute"), "audio sound unmute tắt tiếng"],
        ["output-device", qsTr("Output device"), "audio speakers headphones loa tai nghe"],
        ["microphone", qsTr("Microphone"), "audio input mute mic âm lượng"]
    ] },
    { id: "keyboard", label: qsTr("Keyboard"), group: qsTr("Devices"), icon: "keyboard", summary: qsTr("Check keyboard layouts and look up system shortcuts."), rows: [
        ["keyboard-layout", qsTr("Keyboard layout"), "input language bàn phím ngôn ngữ"],
        ["shortcuts", qsTr("Keyboard shortcuts"), "keybinds hotkeys phím tắt"]
    ] },
    { id: "power-input", label: qsTr("Power & sleep"), group: qsTr("System"), icon: "power", summary: qsTr("Manage power modes, battery, and idle behavior."), rows: [
        ["battery", qsTr("Battery"), "charge energy pin sạc"],
        ["power-profile", qsTr("Power mode"), "battery saver balanced performance tiết kiệm hiệu năng"],
        ["awake", qsTr("Keep awake"), "caffeine idle sleep thức tắt ngủ"],
        ["lock-idle", qsTr("Lock and idle"), "screen timeout sleep khóa ngủ"]
    ] },
    { id: "notifications", label: qsTr("Notifications"), group: qsTr("System"), icon: "notifications", summary: qsTr("Choose when notification popups appear."), rows: [
        ["do-not-disturb", qsTr("Do Not Disturb"), "dnd notifications popups không làm phiền thông báo"]
    ] },
    { id: "maintenance", label: qsTr("Maintenance"), group: qsTr("System"), icon: "maintenance", summary: qsTr("Check shell health and manage settings backups."), rows: [
        ["diagnostics", qsTr("Diagnostics"), "capabilities version logs chẩn đoán phiên bản"],
        ["regenerate-theme", qsTr("Regenerate adaptive palette"), "matugen colors tạo lại bảng màu"],
        ["reload-compositor", qsTr("Reload Hyprland"), "compositor reload configuration nạp lại hyprland"],
        ["reload-shell", qsTr("Reload Rice Shell"), "quickshell shell reload nạp lại rice shell"],
        ["settings-preferences", qsTr("Settings preferences"), "restore preferences recovery khôi phục tùy chọn"],
        ["preference-copies", qsTr("Import and export preferences"), "backup json copy sao lưu nhập xuất tùy chọn"]
    ] }
];

// These are real controls nested inside the page sections, not additional sidebar pages.
var extraRows = {
    shell: [
        ["shell-showTray", qsTr("System tray"), "top bar background app icons khay hệ thống"],
        ["shell-showConnectivity", qsTr("Connection status"), "top bar network online offline kết nối"],
        ["shell-showBattery", qsTr("Battery indicator"), "top bar battery pin"],
        ["shell-showClockSeconds", qsTr("Clock seconds"), "top bar time clock seconds giây đồng hồ"],
        ["shell-showMediaPreview", qsTr("Media preview"), "dynamic island music track artwork nhạc"],
        ["shell-volumeOsd", qsTr("Volume feedback"), "osd popup sound volume âm lượng"],
        ["shell-brightnessOsd", qsTr("Brightness feedback"), "osd popup backlight độ sáng"],
        ["shell-microphoneOsd", qsTr("Microphone feedback"), "osd popup microphone mute mic"]
    ],
    launcher: [
        ["launcher-apps", qsTr("Recently used apps"), "history recent applications lịch sử ứng dụng"],
        ["launcher-calculations", qsTr("Calculator history"), "calculator calculation clear history máy tính lịch sử"],
        ["launcher-favorites", qsTr("Favorites"), "pin unpin pinned apps yêu thích ghim ứng dụng"]
    ]
};

function rowsFor(page) {
    return page.rows.concat(extraRows[page.id] || []);
}

function canonicalRoute(route) {
    if (typeof route !== "string") return "";
    const aliases = {
        devices: "sound",
        "power-input#keyboard-layout": "keyboard#keyboard-layout",
        "power-input#shortcuts": "keyboard#shortcuts",
        "devices#output-volume": "sound#output-volume",
        "devices#output-mute": "sound#output-mute",
        "devices#output-device": "sound#output-device",
        "devices#microphone": "sound#microphone",
        "devices#brightness": "display#brightness",
        "desktop#displays": "display#displays",
        "desktop#night-light": "display#night-light",
        connectivity: "network",
        "connectivity#wifi": "network#wifi",
        "connectivity#hotspot": "network#hotspot",
        "connectivity#bluetooth": "bluetooth",
        "shell#do-not-disturb": "notifications#do-not-disturb",
        "shell#notification-center": "notifications",
        "notifications#notification-center": "notifications",
        "shell#launcher": "launcher"
    };
    return Object.prototype.hasOwnProperty.call(aliases, route) ? aliases[route] : route;
}

function pageFor(route) {
    return pages.find(page => page.id === canonicalRoute(route).split("#", 1)[0]);
}

function validRoute(route) {
    const next = canonicalRoute(route);
    const page = pageFor(next);
    return !!page && (next === page.id || rowsFor(page).some(row => next === page.id + "#" + row[0]));
}

function normalize(text) {
    return text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/đ/g, "d").replace(/[^a-z0-9\u0080-\uffff]+/g, " ").trim();
}

function displayLayouts(outputs) {
    return Array.from(outputs).filter(output => output && typeof output.name === "string"
        && [output.width, output.height, output.scale].every(value => Number.isFinite(value) && value > 0)
        && Number.isFinite(output.x) && Number.isFinite(output.y)).map(output => {
        const rotated = (output.transform & 1) === 1;
        return { output: output, x: output.x, y: output.y,
            w: (rotated ? output.height : output.width) / output.scale,
            h: (rotated ? output.width : output.height) / output.scale };
    });
}

function activeDisplayMode(output, mode) {
    const match = /^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz$/.exec(mode);
    return !!match && Number(match[1]) === output.width && Number(match[2]) === output.height
        && Math.abs(Number(match[3]) - output.refreshRate) < 0.08;
}

// A small local catalog: rank exact labels first, then prefixes and aliases.
// One edit (including a swapped adjacent pair) is tolerated for longer words.
function nearWord(a, b) {
    if (a.length < 4 || Math.abs(a.length - b.length) > 1) return false;
    if (a.length === b.length) {
        const diff = [];
        for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) diff.push(i);
        return diff.length === 1 || (diff.length === 2 && diff[1] === diff[0] + 1
            && a[diff[0]] === b[diff[1]] && a[diff[1]] === b[diff[0]]);
    }
    const shorter = a.length < b.length ? a : b;
    const longer = a.length < b.length ? b : a;
    for (let i = 0; i < longer.length; i++)
        if (longer.slice(0, i) + longer.slice(i + 1) === shorter) return true;
    return false;
}

function search(text) {
    const query = normalize(text);
    if (!query) return [];
    const terms = query.split(" ");
    const matches = [];
    function rank(label, aliases, context) {
        const title = normalize(label);
        if (title === query) return 0;
        if (title.startsWith(query)) return 1;
        if (query.length === 1) return -1;
        const words = title.split(" ");
        const keywords = normalize(aliases).split(" ");
        const parents = normalize(context).split(" ");
        let score = 3;
        let ownMatch = false;
        for (const term of terms) {
            if (words.includes(term)) { ownMatch = true; continue; }
            if (words.some(word => word.startsWith(term))) { score += 1; ownMatch = true; }
            else if (keywords.includes(term)) { score += 2; ownMatch = true; }
            else if (keywords.some(word => word.startsWith(term))) { score += 3; ownMatch = true; }
            else if (parents.some(word => word.startsWith(term))) score += 4;
            else if (words.some(word => word.includes(term))) { score += 5; ownMatch = true; }
            else if (words.concat(keywords).some(word => nearWord(term, word))) { score += 8; ownMatch = true; }
            else return -1;
        }
        return ownMatch ? score : -1;
    }
    for (const page of pages) {
        const pageRank = rank(page.label, page.id + " " + page.summary, "");
        if (pageRank >= 0)
            matches.push({ route: page.id, label: page.label, page: page.group, icon: page.icon,
                rank: pageRank === 0 ? -1 : pageRank + 1 });
        for (const row of rowsFor(page)) {
            if (normalize(row[1]) === normalize(page.label) && pageRank >= 0) continue;
            const score = rank(row[1], row[2], page.label);
            if (score >= 0)
                matches.push({ route: page.id + "#" + row[0], label: row[1], page: page.label, icon: page.icon, rank: score + (score >= 3 && (extraRows[page.id] || []).some(extra => extra[0] === row[0]) ? 1 : 0) });
        }
    }
    return matches.sort((a, b) => a.rank - b.rank);
}

function luminance(color) {
    const linear = value => value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
}

function readable(color, background, minimum) {
    const a = luminance(color) + 0.05;
    const b = luminance(background) + 0.05;
    return Math.max(a, b) / Math.min(a, b) >= minimum ? color
        : b > Math.sqrt(0.0525) ? "#000000" : "#ffffff";
}
