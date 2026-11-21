const categoryTokens = {
    Internet: ["Network"],
    Development: ["Development"],
    Multimedia: ["AudioVideo", "Audio", "Video", "Graphics"],
    System: ["System", "Utility"],
    Settings: ["Settings"]
};

function normalize(text) {
    return (text || "").toLowerCase().normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "").replace(/\u0111/g, "d")
        .trim().replace(/\s+/g, " ");
}

function matchesCategory(app, category) {
    if (!category || category === "All") return true;
    const tokens = categoryTokens[category];
    return Array.isArray(tokens) && !!app?.categories?.some(token => tokens.includes(token));
}

function indexApps(apps) {
    const records = apps.filter(app => app && app.name && !app.noDisplay).map(app => {
        const name = normalize(app.name);
        return {
            app: app,
            name: name,
            words: name.split(/[^\p{L}\p{N}]+/u),
            metadata: [app.id, app.genericName, app.comment]
                .concat(Array.from(app.keywords || [])).map(normalize)
        };
    });
    const alphabetical = records.slice().sort((a, b) => a.name.localeCompare(b.name)
        || (a.app.id || "").localeCompare(b.app.id || ""));
    alphabetical.forEach((record, index) => { record.order = index; });
    return records;
}

function oneEditAway(a, b) {
    if (Math.abs(a.length - b.length) > 1) return false;
    let left = 0;
    while (left < a.length && left < b.length && a[left] === b[left]) left++;
    if (a.length === b.length) return a.slice(left + 1) === b.slice(left + 1);
    return a.length > b.length ? a.slice(left + 1) === b.slice(left)
                               : a.slice(left) === b.slice(left + 1);
}

function matchTerm(record, term) {
    if (record.name.startsWith(term)) return 4;
    for (let i = 0; i < record.words.length; i++) {
        if (record.words[i].startsWith(term)) return 8;
    }
    if (record.name.includes(term)) return 12;
    if (term.length >= 3) {
        let index = -1;
        for (const character of term) {
            index = record.name.indexOf(character, index + 1);
            if (index < 0) break;
        }
        if (index >= 0) return 16 + Math.min(index + 1 - term.length, 15);
        if (term.length >= 4 && record.words.some(word => oneEditAway(word, term))) return 32;
    }
    for (let i = 0; i < record.metadata.length; i++) {
        if (record.metadata[i].includes(term)) return 40;
    }
    return Infinity;
}

function searchApps(records, query, favorites = [], recents = [], frequency = {}) {
    const normalized = normalize(query);
    const terms = normalized.split(" ");
    const matches = [];
    for (const record of records) {
        let score = 0;
        if (record.name === normalized) {
            score = 0;
        } else if (record.name.startsWith(normalized)) {
            score = 1;
        } else {
            for (const term of terms) {
                score += matchTerm(record, term);
                if (!Number.isFinite(score)) break;
            }
        }
        if (Number.isFinite(score)) {
            const id = record.app.id;
            const recent = recents.indexOf(id);
            const boost = (favorites.includes(id) ? 0.4 : 0)
                + Math.min(Number.isInteger(frequency[id]) ? frequency[id] : 0, 10) * 0.03
                + (recent >= 0 ? 0.2 / (1 + recent) : 0);
            matches.push({ record, score: score - boost });
        }
    }
    matches.sort((a, b) => a.score - b.score || a.record.order - b.record.order);
    return matches.slice(0, 40).map(match => match.record.app);
}
