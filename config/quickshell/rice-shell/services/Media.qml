pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris

QtObject {
    id: root

    // Determine active player dynamically: prioritize playing players
    readonly property MprisPlayer activePlayer: {
        var players = Mpris.players.values;
        if (!players || players.length === 0) return null;
        for (var i = 0; i < players.length; i++) {
            if (players[i].isPlaying) return players[i];
        }
        return players[0];
    }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool isPlaying: activePlayer ? activePlayer.isPlaying : false
    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle || "Unknown Track") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string trackAlbum: activePlayer ? (activePlayer.trackAlbum || "") : ""
    readonly property string trackArtUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""

    readonly property bool canToggle: activePlayer ? (activePlayer.canTogglePlaying || activePlayer.canPlay || activePlayer.canPause) : false
    readonly property bool canNext: activePlayer ? activePlayer.canGoNext : false
    readonly property bool canPrev: activePlayer ? activePlayer.canGoPrevious : false
    readonly property real position: activePlayer && isFinite(activePlayer.position)
        ? Math.max(0, activePlayer.position) : 0
    readonly property real length: activePlayer && isFinite(activePlayer.length)
        ? Math.max(0, activePlayer.length) : 0
    readonly property real progress: length > 0 && isFinite(position / length)
        ? Math.max(0.0, Math.min(1.0, position / length)) : 0.0

    function formatTime(seconds: real): string {
        if (!seconds || !isFinite(seconds) || seconds <= 0) return "0:00";
        var m = Math.floor(seconds / 60);
        var s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" + s : s);
    }

    function setPosition(targetSeconds: real): void {
        if (root.activePlayer && root.activePlayer.canSeek && root.length > 0
            && isFinite(targetSeconds)) {
            root.activePlayer.position = Math.max(0, Math.min(root.length, targetSeconds));
        }
    }

    function togglePlaying(): void {
        if (root.activePlayer) {
            if (root.activePlayer.canTogglePlaying) {
                root.activePlayer.togglePlaying();
            } else if (root.activePlayer.isPlaying && root.activePlayer.canPause) {
                root.activePlayer.pause();
            } else if (!root.activePlayer.isPlaying && root.activePlayer.canPlay) {
                root.activePlayer.play();
            }
        }
    }

    function next(): void {
        if (root.activePlayer && root.activePlayer.canGoNext) {
            root.activePlayer.next();
        }
    }

    function previous(): void {
        if (root.activePlayer && root.activePlayer.canGoPrevious) {
            root.activePlayer.previous();
        }
    }
}

