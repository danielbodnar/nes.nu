# nes.nu - Next Edit Suggestion for Nushell
#
# A transparent, permissionless natural language to shell command system.
# Works seamlessly with Nushell's existing completion system.
#
# Usage:
#   use nes.nu
#   nes list all rust files          # Natural language → command
#   nes ls -la                        # Valid command → pass through
#   "find big files" | nes            # Piped input
#   nes show disk usage --execute     # Execute the suggestion
#
# Author: Daniel Bodnar
# Version: 0.1.0

export use src/validate.nu [is-natural-language is-valid-command]
export use src/providers/mod.nu suggest

# Module version
export const VERSION = "0.1.0"

# Resolve effective configuration by merging: flag > env var > NES_CONFIG > default
#
# Returns a record with all resolved values ready for the provider dispatcher.
def resolve-config [
    opts: record   # {provider?, model?, max_tokens?, debug?} from CLI flags
]: nothing -> record {
    # Helper: first non-null value wins
    let provider = if ($opts.provider? != null) { $opts.provider } else {
        let ev = ($env | get -o NES_PROVIDER)
        if ($ev != null) { $ev } else {
            $env.NES_CONFIG?.provider?.default? | default claude-cli
        }
    }

    let model = if ($opts.model? != null) { $opts.model } else {
        let ev = ($env | get -o NES_MODEL)
        if ($ev != null) { $ev } else { null }
    }

    let max_tokens = if ($opts.max_tokens? != null) { $opts.max_tokens | into int } else {
        let ev = ($env | get -o NES_MAX_TOKENS)
        if ($ev != null) { $ev | into int } else { null }
    }

    let debug_flag = if ($opts.debug? | default false) { true } else {
        let ev = ($env | get -o NES_DEBUG)
        if ($ev != null) { $ev in [true 1 yes] } else {
            $env.NES_CONFIG?.debug? | default false
        }
    }

    {
        provider: $provider
        model: $model
        max_tokens: $max_tokens
        debug: $debug_flag
    }
}

# Main entry point - accepts rest args or stdin
#
# Routes input to either pass-through (valid commands) or LLM suggestion
# (natural language). Uses heuristic detection to determine intent.
#
# Flags override NES_CONFIG; env vars (NES_PROVIDER, NES_MODEL, NES_MAX_TOKENS,
# NES_DEBUG) sit between flags and config. Precedence: flag > env > config > default.
#
# Examples:
#   nes ls -la                                  # Pass through (valid command)
#   nes list all rust files                     # LLM suggestion
#   "find big files" | nes                      # Piped natural language
#   nes show disk usage -x                      # Execute the suggestion
#   nes -p anthropic -m claude-sonnet-4-5-20250514 list files   # Override provider + model
#   NES_PROVIDER=ollama nes find big files      # Env var override
export def main [
    ...rest: string           # Natural language or valid command
    --execute (-x)            # Execute result instead of returning
    --provider (-p): string   # Provider: claude-cli, anthropic, openai, ollama
    --model (-m): string      # Model name to use for the provider
    --max-tokens (-t): int    # Max tokens for LLM response
    --debug (-d)              # Enable debug output
]: [nothing -> string, string -> string] {
    # Get input from args or stdin
    let input = if ($rest | is-empty) {
        $in | default "" | into string | str trim
    } else {
        $rest | str join " "
    }

    # Empty input returns empty
    if ($input | is-empty) {
        return ""
    }

    # Resolve effective config: flag > env > NES_CONFIG > default
    # Null-check typed flags before passing to resolver
    let overrides = resolve-config {
        provider: (if ($provider != null) { $provider } else { null })
        model: (if ($model != null) { $model } else { null })
        max_tokens: (if ($max_tokens != null) { $max_tokens } else { null })
        debug: $debug
    }

    if $overrides.debug {
        print -e $"nes: provider=($overrides.provider) model=($overrides.model) max_tokens=($overrides.max_tokens)"
    }

    # Check if this looks like natural language
    if ($input | is-natural-language) {
        # Send to LLM for suggestion
        let suggestion = suggest $input --overrides $overrides

        if $execute {
            if ($suggestion | is-not-empty) {
                # nu-lint:ignore(redundant_nu_subprocess) - Required for dynamic execution
                nu -c $suggestion
            }
        } else {
            $suggestion
        }
    } else {
        # Valid command - pass through or execute
        if $execute {
            # nu-lint:ignore(redundant_nu_subprocess) - Required for dynamic execution
            nu -c $input
        } else {
            $input
        }
    }
}

# Show nes.nu status and configuration
#
# Displays effective config (after resolving flag > env > config > default).
# Shows which source each value came from.
#
# Examples:
#   nes status
export def status []: nothing -> record {
    let resolved = resolve-config { provider: null, model: null, max_tokens: null, debug: false }

    let claude_available = (which claude | length) > 0
    let api_key_set = ($env.ANTHROPIC_API_KEY? | default "" | is-not-empty)

    let env_overrides = {
        NES_PROVIDER: ($env | get -o NES_PROVIDER | default null)
        NES_MODEL: ($env | get -o NES_MODEL | default null)
        NES_MAX_TOKENS: ($env | get -o NES_MAX_TOKENS | default null)
        NES_DEBUG: ($env | get -o NES_DEBUG | default null)
    }

    {
        version: $VERSION
        provider: $resolved.provider
        model: $resolved.model
        debug: $resolved.debug
        max_tokens: $resolved.max_tokens
        claude_cli_available: $claude_available
        anthropic_api_key_set: $api_key_set
        env_overrides: $env_overrides
        config_path: ([$env.XDG_CONFIG_HOME? $env.HOME] | where {|v| $v != null } | first | path join nes.nu config.nu)
    }
}
