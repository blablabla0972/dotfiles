pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: store
    visible: false

    property alias path: stateFile.path
    property var favorites: []
    property var recents: []
    property var frequency: ({})
    property var calculations: []
    readonly property bool rememberApps: Quickshell.env("RICE_LAUNCHER_MRU") !== "0"
    readonly property bool rememberCalculations: Quickshell.env("RICE_LAUNCHER_CALC_HISTORY") !== "0"
    property bool ready: false
    property bool writable: true
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
            if (rememberApps) {
                recents = Array.from(new Set(data.recents.filter(value => typeof value === "string"))).slice(0, 32);
                const counts = Object.create(null);
                for (const id of recents) {
                    const count = data.frequency?.[id];
                    if (Number.isInteger(count) && count > 0) counts[id] = Math.min(count, 10000);
                }
                frequency = counts;
            }
            if (rememberCalculations) calculations = data.calculations.filter(entry => entry
                && typeof entry.expression === "string" && typeof entry.value === "string").slice(0, 20);
        } catch (error) {
            writable = false;
            console.warn("Could not read launcher state:", error.message);
        }
        ready = true;
        for (const operation of beforeLoad) operation();
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
        stateFile.setText(JSON.stringify({favorites, recents, frequency, calculations}));
    }

    function toggleFavorite(id: string): void {
        if (id) update(() => {
            favorites = favorites.includes(id) ? favorites.filter(value => value !== id) : favorites.concat(id);
        });
    }

    function recordLaunch(id: string): void {
        if (id && rememberApps) update(() => {
            recents = [id].concat(recents.filter(value => value !== id)).slice(0, 32);
            const counts = Object.create(null);
            for (const recent of recents) counts[recent] = frequency[recent] || 0;
            counts[id] = Math.min(10000, counts[id] + 1);
            frequency = counts;
        });
    }

    function clearHistory(calculator: bool): void {
        update(() => {
            if (calculator) calculations = [];
            else {
                recents = [];
                frequency = Object.create(null);
            }
        });
    }

    function recordCalculation(expression: string, value: string): void {
        if (!rememberCalculations || !expression || !value) return;
        update(() => {
            calculations = [{expression, value}].concat(
                calculations.filter(entry => entry.expression !== expression)).slice(0, 20);
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
            store.saving = false;
            store.save();
        }
        onSaveFailed: (error) => {
            console.warn("Could not save launcher state:", error);
            store.saving = false;
            store.dirty = true;
        }
    }
}
