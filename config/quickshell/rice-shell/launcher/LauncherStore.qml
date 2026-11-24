pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: store
    visible: false

    property alias path: stateFile.path
    property var favorites: []
    property var savedRecents: []
    property var savedFrequency: ({})
    property var savedCalculations: []
    property bool recordApps: true
    property bool recordCalculations: true
    readonly property bool appsAllowed: Quickshell.env("RICE_LAUNCHER_MRU") !== "0"
    readonly property bool calculationsAllowed: Quickshell.env("RICE_LAUNCHER_CALC_HISTORY") !== "0"
    readonly property var recents: appsAllowed ? savedRecents : []
    readonly property var frequency: appsAllowed ? savedFrequency : ({})
    readonly property var calculations: calculationsAllowed ? savedCalculations : []
    readonly property bool rememberApps: appsAllowed && recordApps
    readonly property bool rememberCalculations: calculationsAllowed && recordCalculations
    property bool ready: false
    property bool writable: true
    property bool saveFailed: false
    property bool saving: false
    property bool dirty: false
    property var beforeLoad: []

    function load(contents: string): void {
        if (ready) return;
        try {
            const data = JSON.parse(contents);
            if (!Array.isArray(data.favorites) || !Array.isArray(data.recents)
                    || !Array.isArray(data.calculations)) throw new Error("Invalid fields");
            favorites = Array.from(new Set(data.favorites.filter(value => typeof value === "string")));
            recordApps = data.history?.apps !== false;
            recordCalculations = data.history?.calculations !== false;
            savedRecents = Array.from(new Set(data.recents.filter(value => typeof value === "string"))).slice(0, 32);
            const counts = Object.create(null);
            for (const id of savedRecents) {
                const count = data.frequency?.[id];
                if (Number.isInteger(count) && count > 0) counts[id] = Math.min(count, 10000);
            }
            savedFrequency = counts;
            savedCalculations = data.calculations.filter(entry => entry
                && typeof entry.expression === "string" && typeof entry.value === "string").slice(0, 20);
        } catch (error) {
            writable = false;
            console.warn("Could not read launcher state:", error.message);
        }
        ready = true;
        for (const operation of beforeLoad) update(operation);
        beforeLoad = [];
    }

    function update(operation): void {
        if (!ready) {
            beforeLoad.push(operation);
            return;
        }
        operation();
        dirty = true;
        save();
    }

    function save(): void {
        if (!writable || !dirty || saving) return;
        saving = true;
        dirty = false;
        stateFile.setText(JSON.stringify({
            favorites, recents: savedRecents, frequency: savedFrequency, calculations: savedCalculations,
            history: { apps: recordApps, calculations: recordCalculations }
        }));
    }

    function setHistoryRecording(kind: string, enabled: bool): void {
        if (!ready || !writable) return;
        if (kind === "apps" && appsAllowed && enabled !== recordApps)
            update(() => { recordApps = enabled; });
        else if (kind === "calculations" && calculationsAllowed && enabled !== recordCalculations)
            update(() => { recordCalculations = enabled; });
    }

    function toggleFavorite(id: string): void {
        if (id) update(() => {
            favorites = favorites.includes(id) ? favorites.filter(value => value !== id) : favorites.concat(id);
        });
    }

    function recordLaunch(id: string): void {
        if (id && rememberApps) update(() => {
            if (!rememberApps) return;
            savedRecents = [id].concat(savedRecents.filter(value => value !== id)).slice(0, 32);
            const counts = Object.create(null);
            for (const recent of savedRecents) counts[recent] = savedFrequency[recent] || 0;
            counts[id] = Math.min(10000, counts[id] + 1);
            savedFrequency = counts;
        });
    }

    function clearHistory(calculator: bool): void {
        update(() => {
            if (calculator) savedCalculations = [];
            else {
                savedRecents = [];
                savedFrequency = Object.create(null);
            }
        });
    }

    function recordCalculation(expression: string, value: string): void {
        if (!rememberCalculations || !expression || !value) return;
        update(() => {
            if (!rememberCalculations) return;
            savedCalculations = [{expression, value}].concat(
                savedCalculations.filter(entry => entry.expression !== expression)).slice(0, 20);
        });
    }

    FileView {
        id: stateFile
        path: Quickshell.stateDir + "/launcher.json"
        printErrors: false
        onLoaded: store.load(text())
        onLoadFailed: (error) => {
            store.writable = error === FileViewError.FileNotFound;
            if (!store.writable) console.warn("Could not load launcher state:", error);
            store.load('{"favorites":[],"recents":[],"calculations":[]}');
        }
        onSaved: {
            store.saveFailed = false;
            store.saving = false;
            store.save();
        }
        onSaveFailed: (error) => {
            console.warn("Could not save launcher state:", error);
            store.saveFailed = true;
            store.saving = false;
            store.dirty = true;
        }
    }
}
