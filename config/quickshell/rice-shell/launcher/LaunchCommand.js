.pragma library

// Keep apps outside the shell/IDE cgroup. A failed service
// registration falls back to exec; positional arguments never become shell code.
function launchContext(app, terminal, home) {
    if (!app || !app.command || app.command.length === 0) return null;
    var command = Array.from(app.command);
    if (app.runInTerminal)
        command = [(terminal || "").trim() || "kitty", "-e"].concat(command);
    return {
        command: ["sh", "-c",
            'systemd-run --user --quiet --collect --slice=app.slice --service-type=exec --expand-environment=no '
            + '--property=ExitType=cgroup --property=OOMPolicy=continue '
            + '--working-directory="$PWD" -- "$@" && exit 0; exec "$@"',
            "rice-launch"].concat(command),
        workingDirectory: app.workingDirectory || home
    };
}
