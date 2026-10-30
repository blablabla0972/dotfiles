if status is-interactive
    source /usr/share/cachyos-fish-config/cachyos-config.fish
else
    # Keep the distro environment for scripts without loading terminal UI setup.
    set -gx MANROFFOPT "-c"
    set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"
    if test -f ~/.fish_profile
        source ~/.fish_profile
    end
    fish_add_path ~/.local/bin ~/.cargo/bin ~/Applications/depot_tools
end

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# Starship prompt
if status is-interactive
    starship init fish | source
end
