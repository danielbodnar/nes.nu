# nes.nu - Next Edit Suggestion for Nushell

## Overview

A transparent, permissionless natural language to shell command system for Nushell. Works seamlessly with Nushell's existing completion system.

## Core Design Principle

```
nes [input]  →  if is_valid_command(input) → execute directly
             →  else                       → send to LLM → return suggestion
```

**No subcommands for the main use case.** The command intelligently routes based on input validity.

## Input Validation Strategy

**Important:** `nu-check` only validates *syntax*, not command existence. `"list all files"` passes `nu-check` because it's syntactically valid (external command `list` with args).

We use **heuristic-based detection** instead:

```nushell
def is-natural-language [input: string]: nothing -> bool {
    let words = $input | split words
    if ($words | is-empty) { return true }

    let first = $words | first

    # If first word is not a known command → natural language
    if (which $first | is-empty) { return true }

    # If has flags (-x, --flag) → likely a real command
    let has_flags = ($input =~ " -")
    if $has_flags { return false }

    # Multiple words without flags + common English words → natural language
    let common_words = ["all" "the" "files" "that" "which" "please" "show" "me" "list" "find" "get" "big" "large" "small" "new" "old" "recent" "today" "yesterday"]
    let has_common = $words | skip 1 | any {|w| $w in $common_words}

    ($words | length) > 2 and $has_common
}
```

## Input Flow

```
┌─────────────────────────────────────────────────────────────┐
│                        nes [input]                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │  Input source?  │
                    └─────────────────┘
                     │              │
            has args │              │ no args
                     ▼              ▼
              use $rest        check stdin
                     │              │
                     └──────┬───────┘
                            ▼
               ┌─────────────────────────┐
               │ is-natural-language?    │
               │ (heuristic detection)   │
               └─────────────────────────┘
                   │              │
              true │              │ false
                   ▼              ▼
         ┌──────────────┐  ┌──────────────┐
         │  Send to LLM │  │   Pass       │
         │  for suggest │  │   through    │
         └──────────────┘  └──────────────┘
                 │
                 ▼
       ┌──────────────────┐
       │ Return suggestion │
       └──────────────────┘
```

## Usage Examples

```nushell
# Valid nushell command - passes through
nes ls -la
# → ls -la

# Natural language - sends to LLM, returns command
nes list all rust files modified today
# stdout: ls **/*.rs | where modified > (date now) - 1day

# Piped input
"find files larger than 100mb" | nes
# stdout: ls | where size > 100mb

# Execute the suggestion directly
nes list all rust files --execute

# As external completer (integrated into tab completion)
# User types: "nes list files<TAB>"
# Completer returns suggestions from LLM
```

## Command Signature

```nushell
# Main entry point - accepts rest args or stdin
export def main [
    ...rest: string      # Natural language or valid command
    --execute (-x)       # Execute result instead of returning
]: [nothing -> string, string -> string] {
    # Get input from args or stdin
    let input = if ($rest | is-empty) {
        $in | default "" | into string | str trim
    } else {
        $rest | str join " "
    }

    if ($input | is-empty) {
        return ""
    }

    # Check if this looks like natural language
    if (is-natural-language $input) {
        # Send to LLM
        let suggestion = suggest $input

        if $execute {
            nu -c $suggestion
        } else {
            $suggestion
        }
    } else {
        # Valid command - pass through or execute
        if $execute {
            nu -c $input
        } else {
            $input
        }
    }
}
```

## Configuration

Location: `$env.XDG_CONFIG_HOME/nes.nu/config.nu` (default: `~/.config/nes.nu/config.nu`)

```nushell
# nes.nu configuration
$env.NES_CONFIG = {
    # Provider configuration (models.dev / ai-sdk pattern)
    # Supports: claude-cli, anthropic, openai, ollama, gemini
    provider: {
        # Default: claude-cli (uses existing claude code CLI)
        default: "claude-cli"

        # Provider-specific settings
        claude-cli: {
            # Uses existing claude CLI auth - no config needed
        }

        anthropic: {
            model: "claude-3-5-haiku-20241022"  # fast, cheap default
            max_tokens: 128
            # api_key from $env.ANTHROPIC_API_KEY
        }

        openai: {
            model: "gpt-4o-mini"
            max_tokens: 128
            # api_key from $env.OPENAI_API_KEY
        }

        ollama: {
            model: "llama3.2"
            base_url: "http://localhost:11434"
        }

        gemini: {
            model: "gemini-2.0-flash-lite"
            # api_key from $env.GOOGLE_API_KEY
        }
    }

    # Completer settings
    completer: {
        enabled: true
        min_chars: 5           # Min chars before suggesting
        cache_ttl_ms: 500      # Cache results for this long
    }

    # Output settings
    output: {
        include_explanation: false
    }

    debug: false
}
```

## Provider Interface

All providers implement the same interface:

```nushell
# src/providers/mod.nu

# Get the configured provider name
def get-provider []: nothing -> string {
    $env.NES_CONFIG?.provider?.default? | default "claude-cli"
}

# Main suggest function - dispatches to the right provider
export def suggest [
    input: string       # Natural language input
    --context: record   # Optional context (pwd, history, etc.)
]: nothing -> string {
    let provider = get-provider
    let ctx = $context | default {}

    let result = match $provider {
        "claude-cli" => { claude-cli-suggest $input $ctx }
        "anthropic" => { anthropic-suggest $input $ctx }
        "openai" => { openai-suggest $input $ctx }
        "ollama" => { ollama-suggest $input $ctx }
        "gemini" => { gemini-suggest $input $ctx }
        _ => { error make { msg: $"Unknown provider: ($provider)" } }
    }

    $result
}
```

### Claude CLI Provider (Default)

```nushell
# src/providers/claude-cli.nu

# Build the prompt with context
def build-prompt [input: string, context: record]: nothing -> string {
    let pwd = $context.pwd? | default (pwd)
    $"Current directory: ($pwd)\n\nGenerate a nushell command for: ($input)"
}

# Suggest using Claude CLI
export def claude-cli-suggest [input: string, context: record]: nothing -> string {
    let prompt = build-prompt $input $context
    let system = system-prompt

    try {
        ^claude --print --system $system $prompt | str trim
    } catch {
        ""  # Graceful degradation
    }
}
```

### Anthropic API Provider

```nushell
# src/providers/anthropic.nu

export def anthropic-suggest [input: string, context: record]: nothing -> string {
    let config = $env.NES_CONFIG?.provider?.anthropic? | default {
        model: "claude-3-5-haiku-20241022"
        max_tokens: 128
    }

    let api_key = $env.ANTHROPIC_API_KEY? | default ""
    if ($api_key | is-empty) {
        error make { msg: "ANTHROPIC_API_KEY not set" }
    }

    let prompt = build-prompt $input $context

    let body = {
        model: $config.model
        max_tokens: $config.max_tokens
        system: (system-prompt)
        messages: [{role: "user", content: $prompt}]
    }

    try {
        (http post "https://api.anthropic.com/v1/messages"
            --content-type "application/json"
            --headers {
                x-api-key: $api_key
                anthropic-version: "2023-06-01"
            }
            $body)
        | get content.0.text
        | str trim
    } catch {|err|
        if $env.NES_CONFIG?.debug? == true {
            print -e $"nes: API error: ($err.msg)"
        }
        ""
    }
}
```

## System Prompt

```nushell
# src/prompt.nu

export def system-prompt []: nothing -> string {
    r#'You are a Nushell command generator. Output ONLY the command, nothing else.

Rules:
- Output the nushell command only, no markdown, no explanation, no code blocks
- Use nushell syntax (not bash)
- Prefer built-in commands: ls, where, select, open, http, glob
- Use pipelines and structured data
- Use glob patterns: **/*.rs instead of find

Examples:
"list files" → ls
"find rust files" → glob **/*.rs
"large files over 100mb" → ls | where size > 100mb
"disk usage sorted" → du | sort-by size --reverse
"fetch json from url" → http get https://example.com | from json
"files modified today" → ls | where modified > (date now) - 1day
"count lines in file" → open file.txt | lines | length'#
}
```

## External Completer Integration

```nushell
# completions/nes-completer.nu
# Add to your config.nu external_completer chain

# Simple cache to avoid repeated LLM calls
mut nes_cache = { input: "", result: [], ts: 0 }

export def nes-completer [spans: list<string>]: nothing -> list<record> {
    # Only trigger for 'nes' command
    if ($spans | first) != "nes" { return null }

    # Get the natural language input (everything after 'nes')
    let input = $spans | skip 1 | str join " " | str trim

    # Skip if too short
    let min_chars = $env.NES_CONFIG?.completer?.min_chars? | default 5
    if ($input | str length) < $min_chars { return null }

    # Check cache
    let cache_ttl = $env.NES_CONFIG?.completer?.cache_ttl_ms? | default 500
    let now = date now | into int
    if $nes_cache.input == $input and ($now - $nes_cache.ts) < ($cache_ttl * 1_000_000) {
        return $nes_cache.result
    }

    # Get suggestion from LLM
    let suggestion = try { nes $input } catch { "" }

    if ($suggestion | is-empty) { return null }

    # Update cache
    $nes_cache = { input: $input, result: [{value: $suggestion, description: "AI suggestion"}], ts: $now }

    $nes_cache.result
}

# Integration example for config.nu:
# let external_completer = {|spans|
#     match ($spans | first) {
#         "nes" => { nes-completer $spans }
#         _ => { $your_existing_completer | do $in $spans }
#     }
# }
```

## Project Structure

```
nes.nu/
├── mod.nu                    # Main module entry (export def main)
├── src/
│   ├── validate.nu           # is-natural-language heuristic
│   ├── prompt.nu             # System prompts for LLM
│   └── providers/
│       ├── mod.nu            # Provider dispatcher + suggest
│       ├── claude-cli.nu     # Claude CLI backend (default)
│       ├── anthropic.nu      # Anthropic API
│       ├── openai.nu         # OpenAI API
│       ├── ollama.nu         # Ollama (local)
│       └── gemini.nu         # Google Gemini
├── config/
│   └── default.nu            # Default configuration
├── completions/
│   └── nes-completer.nu      # External completer integration
├── tests/
│   └── test_nes.nu           # Test suite
└── README.md
```

## Installation

```nushell
# Clone to modules directory
git clone https://github.com/danielbodnar/nes.nu ~/.config/nushell/modules/nes.nu

# Add to config.nu
use ~/.config/nushell/modules/nes.nu

# Or for full integration with completer
source ~/.config/nushell/modules/nes.nu/init.nu
```

## Implementation Order

1. [x] Project structure + mod.nu skeleton
2. [ ] Input validation (is-natural-language heuristic)
3. [ ] System prompt
4. [ ] Claude CLI provider (default, works out of box)
5. [ ] Configuration loading
6. [ ] Main command logic
7. [ ] Anthropic API provider
8. [ ] Other providers (openai, ollama, gemini)
9. [ ] External completer integration
10. [ ] Tests
11. [ ] Documentation

## Key Decisions

1. **No subcommands** - `nes [input]` is the entire interface
2. **Heuristic validation** - Uses word patterns, not just syntax checking
3. **Claude CLI as default** - Works with existing `claude` auth, no API key needed
4. **Fast model defaults** - Haiku/mini models for speed in autocomplete context
5. **Provider abstraction** - Easy to add new providers following models.dev pattern
6. **Permissionless** - Suggestions only, never auto-execute without --execute flag
7. **Graceful degradation** - Returns empty string on errors, never crashes
8. **Simple caching** - Avoids duplicate LLM calls in completer context
