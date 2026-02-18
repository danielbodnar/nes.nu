# nes.nu - Input validation
#
# Provides heuristic-based detection to distinguish between
# valid Nushell commands and natural language input.
#
# Note: nu-check only validates syntax, not command existence.
# "list all files" passes nu-check because it's syntactically valid
# (external command `list` with args). We need smarter detection.

# Words that strongly indicate natural language intent
# Excludes words that are also common in commands (get, find, list)
const NATURAL_LANGUAGE_INDICATORS = [
    all the that which please me show
    big large small new old recent
    today yesterday modified created with
    containing named called like similar matching
    and or but for of by every any some
]

# Words that when appearing as FIRST word indicate natural language
# (these look like commands but aren't standard nushell/unix commands)
const NATURAL_LANGUAGE_STARTERS = [
    list show find get display give tell
    what how why when where who
]

# Determines if the input looks like natural language rather than a command
#
# Returns true if the input appears to be natural language that should
# be sent to an LLM for command generation.
#
# Detection logic:
# 1. If first word is not a known command → check if it's a natural language starter
# 2. If input has flags (-x, --flag) → likely a real command
# 3. If known command + natural language indicators → natural language
#
# Examples:
#   "ls -la" | is-natural-language           # false (has flags)
#   "list all files" | is-natural-language   # true (common words)
#   "git status" | is-natural-language       # false (known command)
#   "find big files please" | is-natural-language  # true (common words)
export def is-natural-language []: string -> bool {
    let input = $in | str trim

    # Empty input is not natural language (nothing to process)
    if ($input | is-empty) {
        return false
    }

    let words = $input | split words

    # Single word - check if it's a known command
    if ($words | length) == 1 {
        let first = $words | first
        let found = which $first | length
        # Unknown single word = natural language
        # Known command = not natural language
        return ($found == 0)
    }

    let first = $words | first
    let first_lower = $first | str downcase

    # Check if first word is a known command
    let is_known_command = (which $first | length) > 0

    # If input has flags (-x, --flag) → definitely a command
    if ($input =~ ' -[a-zA-Z]') {
        return false
    }

    # If first word is NOT a known command
    if not $is_known_command {
        # Check if it's a natural language starter
        if $first_lower in $NATURAL_LANGUAGE_STARTERS {
            return true
        }
        # Unknown first word = likely natural language
        return true
    }

    # First word IS a known command - be more conservative
    # Only treat as natural language if there are strong indicators
    let remaining_words = $words | skip 1
    let indicator_count = $remaining_words | where {|w|
        let lower = $w | str downcase
        $lower in $NATURAL_LANGUAGE_INDICATORS
    } | length

    # Need at least 2 indicator words to override a known command
    $indicator_count >= 2
}

# Alternative: check if input is a valid command (inverse of is-natural-language)
#
# Examples:
#   "ls -la" | is-valid-command           # true
#   "list all files" | is-valid-command   # false
export def is-valid-command []: string -> bool {
    not ($in | is-natural-language)
}
