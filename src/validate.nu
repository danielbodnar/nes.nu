# nes.nu - Input validation
#
# Provides heuristic-based detection to distinguish between
# valid Nushell commands and natural language input.
#
# Strategy: Check first word against static lists of nushell commands and
# curated external tools. No `which` or `scope commands` calls — both are
# slow (16ms+) and `which` returns false positives like /usr/bin/example.

# Nushell builtin commands (first word only — subcommands like "str trim"
# are handled by checking the first word "str").
# Generated from: scope commands | where type not-in [external custom plugin]
const NU_COMMANDS = [
    alias all ansi any append ast attr
    bits break bytes
    cal cd char chunk-by chunks clear collect columns commandline compact
    complete config const continue cp
    date debug decode def default describe detect do drop du
    each echo encode enumerate error every exec exit explain explore export
    extern
    fill filter find first flatten for format from
    generate get glob grid group-by
    hash headers help hide histogram history http
    if ignore input insert inspect interleave into is-admin is-empty
    is-not-empty is-terminal items
    job join
    keybindings kill
    last length let lines load-env loop
    match math merge metadata mkdir mktemp module move mut mv
    nu-check nu-highlight
    open overlay
    panic par-each parse path plugin port prepend print ps
    query
    random reduce reject rename return reverse rm roll rotate run-external
    save schema scope select seq shuffle skip sleep slice sort source split
    start stor str sys
    table take tee term timeit to touch transpose try tutor
    ulimit uname uniq unlet update upsert url use
    values version view
    watch where which while whoami window with-env wrap
    zip
]

# Common external commands that users actually invoke intentionally.
const KNOWN_EXTERNALS = [
    git cargo docker podman kubectl ssh scp rsync curl wget
    tar zip unzip chmod chown ln
    cat head tail grep rg fd sd awk sed jq yq
    vim nvim nano code zed hx
    bun npm yarn node deno
    rustup rustc gcc clang cmake make just task
    mise brew pacman apt dnf flatpak snap nix guix
    systemctl journalctl
    tmux zellij screen
    htop btop top ps kill
    ping traceroute dig nslookup ip ss lsof strace
    diff patch wc sort uniq tee xargs
    env echo printf date cal bc man file stat
    lsblk mount umount df dust dua tree
    bat eza exa less more
    wrangler gh glab claude ollama
    go zig
]

# Words that strongly indicate natural language intent
const NATURAL_LANGUAGE_INDICATORS = [
    all the that which please me show
    big large small new old recent
    today yesterday modified created with
    containing named called like similar matching
    and or but for of by every any some
]

# Check if a word is a known nushell or external command (pure const lookup)
def is-known-command [name: string]: nothing -> bool {
    ($name in $NU_COMMANDS) or ($name in $KNOWN_EXTERNALS)
}

# Determines if the input looks like natural language rather than a command
#
# Returns true if the input appears to be natural language that should
# be sent to an LLM for command generation.
#
# Examples:
#   "ls -la" | is-natural-language                # false (has flags)
#   "list all files" | is-natural-language         # true (not a known command)
#   "git status" | is-natural-language             # false (known command)
#   "find big files please" | is-natural-language  # true (indicators override)
#   "natural language" | is-natural-language        # true (not a known command)
#   "example instructions" | is-natural-language    # true (not a known command)
export def is-natural-language []: string -> bool {
    let input = $in | str trim

    if ($input | is-empty) {
        return false
    }

    let words = $input | split words

    if ($words | length) == 1 {
        return (not (is-known-command ($words | first)))
    }

    let first = $words | first

    # Flags (-x, --flag) → definitely a command
    if ($input =~ ' -[a-zA-Z]') {
        return false
    }

    # Unknown first word → natural language
    if not (is-known-command $first) {
        return true
    }

    # Known command + indicator words → might be natural language
    let indicator_count = $words | skip 1 | where {|w|
        ($w | str lowercase) in $NATURAL_LANGUAGE_INDICATORS
    } | length

    $indicator_count >= 2
}

# Check if input is a valid command (inverse of is-natural-language)
#
# Examples:
#   "ls -la" | is-valid-command           # true
#   "list all files" | is-valid-command   # false
export def is-valid-command []: string -> bool {
    not ($in | is-natural-language)
}
