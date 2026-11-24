var pages = [
    { id: "appearance", label: qsTr("Appearance"), group: qsTr("Desktop"), icon: "appearance", summary: qsTr("Choose a color mode, wallpaper, and adaptive palette."), rows: [
        ["color-mode", qsTr("Color mode"), "light dark theme giao diện sáng tối"],
        ["wallpaper", qsTr("Wallpaper"), "background hình nền"],
        ["palette", qsTr("Palette"), "accent colors bảng màu"],
        ["reduce-motion", qsTr("Reduce motion"), "animation transitions accessibility giảm chuyển động"],
        ["compact-rows", qsTr("Compact layout"), "density spacing giao diện gọn khoảng cách"],
        ["fonts", qsTr("Interface font"), "typography font phông chữ"],
        ["icons", qsTr("Icon theme"), "icons glyphs biểu tượng"]
    ] },
    { id: "desktop", label: qsTr("Windows & workspaces"), group: qsTr("Desktop"), icon: "windows", summary: qsTr("Set window spacing and inspect workspaces and rules."), rows: [
        ["workspaces", qsTr("Workspaces"), "virtual desktops không gian làm việc"],
        ["gaps", qsTr("Window spacing"), "gaps border tiling viền khoảng cách cửa sổ"],
        ["window-effects", qsTr("Window effects"), "rounding blur shadows animation bo góc bóng mờ hiệu ứng"],
        ["window-rules", qsTr("Window rules"), "windowrule floating fullscreen rules quy tắc cửa sổ"]
    ] },
    { id: "shell", label: qsTr("Shell"), group: qsTr("Desktop"), icon: "shell", summary: qsTr("Customize the Control Center, bar, Dynamic Island, and on-screen feedback."), rows: [
        ["control-center", qsTr("Control Center"), "quick settings dashboard trung tâm điều khiển"],
        ["top-bar", qsTr("Top Bar"), "system tray network status battery clock seconds thanh trên đồng hồ khay hệ thống"],
        ["dynamic-island", qsTr("Dynamic Island"), "music media preview nhạc trình phát"],
        ["osd", qsTr("On-screen feedback"), "osd popup volume brightness microphone phản hồi trên màn hình"]
    ] },
    { id: "launcher", label: qsTr("Launcher"), group: qsTr("Desktop"), icon: "launcher", summary: qsTr("Choose which results and quick actions appear in Launcher."), rows: [
        ["launcher", qsTr("Launcher"), "app search quick actions trình khởi chạy ứng dụng"]
    ] },
    { id: "network", label: qsTr("Wi-Fi & Hotspot"), group: qsTr("Connections"), icon: "wifi", summary: qsTr("Connect to a wireless network or share your connection."), rows: [
        ["wifi", qsTr("Wi-Fi"), "wifi wireless mạng không dây"],
        ["hotspot", qsTr("Hotspot"), "tethering chia sẻ mạng"]
    ] },
    { id: "bluetooth", label: qsTr("Bluetooth"), group: qsTr("Connections"), icon: "bluetooth", summary: qsTr("Pair, connect, and manage nearby devices."), rows: [
        ["bluetooth", qsTr("Bluetooth"), "pairing ghép đôi"]
    ] },
    { id: "sound", label: qsTr("Sound"), group: qsTr("Hardware"), icon: "sound", summary: qsTr("Manage playback and recording devices."), rows: [
        ["output-volume", qsTr("Output volume"), "audio sound amplification âm lượng"],
        ["output-mute", qsTr("Output mute"), "audio sound unmute tắt tiếng"],
        ["output-device", qsTr("Output device"), "audio speakers headphones loa tai nghe"],
        ["microphone", qsTr("Microphone"), "audio input mute mic âm lượng"]
    ] },
    { id: "display", label: qsTr("Displays"), group: qsTr("Hardware"), icon: "display", summary: qsTr("Configure your screens, backlight, and Night Light."), rows: [
        ["displays", qsTr("Displays"), "monitor resolution refresh scale màn hình độ phân giải"],
        ["night-light", qsTr("Night Light"), "blue light warm color ánh sáng đêm"],
        ["brightness", qsTr("Brightness"), "backlight độ sáng"]
    ] },
    { id: "power-input", label: qsTr("Power & sleep"), group: qsTr("Hardware"), icon: "power", summary: qsTr("Manage power modes, battery, and idle behavior."), rows: [
        ["battery", qsTr("Battery"), "charge energy pin sạc"],
        ["power-profile", qsTr("Power mode"), "battery saver balanced performance tiết kiệm hiệu năng"],
        ["awake", qsTr("Keep awake"), "caffeine idle sleep thức tắt ngủ"],
        ["lock-idle", qsTr("Lock and idle"), "screen timeout sleep khóa ngủ"]
    ] },
    { id: "keyboard", label: qsTr("Keyboard"), group: qsTr("Hardware"), icon: "keyboard", summary: qsTr("Check keyboard layouts and look up system shortcuts."), rows: [
        ["keyboard-layout", qsTr("Keyboard layout"), "input language bàn phím ngôn ngữ"],
        ["shortcuts", qsTr("Keyboard shortcuts"), "keybinds hotkeys phím tắt"]
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
    return !!page && (next === page.id || page.rows.some(row => next === page.id + "#" + row[0]));
}

function normalize(text) {
    return text.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
        .replace(/đ/g, "d").trim().replace(/\s+/g, " ");
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

function search(text) {
    const query = normalize(text);
    if (query.length < 2) return [];
    const matches = [];
    for (const page of pages) {
        const title = normalize(page.label);
        const matchesTitle = title.includes(query);
        if (matchesTitle)
            matches.push({ route: page.id, label: page.label, page: page.group, icon: page.icon, rank: title === query ? -1 : 3 });
        for (const row of page.rows) {
            const label = normalize(row[1]);
            if (matchesTitle && label === title) continue;
            const aliases = normalize(row[2]);
            const rank = label === query ? 0 : (" " + label).includes(" " + query) ? 1
                : (" " + aliases).includes(" " + query) ? 2
                : (label + " " + aliases).includes(query) ? 3 : -1;
            if (rank >= 0) matches.push({ route: page.id + "#" + row[0], label: row[1], page: page.label, icon: page.icon, rank });
        }
    }
    return matches.sort((a, b) => a.rank - b.rank).slice(0, 12);
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
