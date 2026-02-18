# nes.nu - Next Edit Suggestion for Nushell

A transparent, permissionless natural language to shell command system for Nushell.

## Features

- **Natural language to commands**: Type what you want in plain English, get Nushell commands
- **Smart detection**: Automatically distinguishes between valid commands and natural language
- **Multiple providers**: Claude CLI (default), Anthropic API, OpenAI, Ollama
- **Permissionless**: Returns suggestions only, never auto-executes without explicit flag
- **Graceful degradation**: Falls back silently on errors

## Installation

```nushell
# Clone to your modules directory
git clone https://github.com/danielbodnar/nes.nu ~/.config/nushell/modules/nes.nu

# Add to your config.nu
use ~/.config/nushell/modules/nes.nu
```

## Usage

```nushell
# Natural language → command suggestion
nes list all rust files
# Output: glob **/*.rs

# Valid command → pass through
nes ls -la
# Output: ls -la

# Piped input
"find files larger than 100mb" | nes
# Output: ls | where size > 100mb

# Execute the suggestion directly
nes show disk usage --execute
```

## How It Works

1. **Input detection**: Uses heuristic-based detection to determine if input is:
   - A valid Nushell command (has flags, known first word)
   - Natural language (common English words, unknown first word)

2. **Routing**:
   - Valid commands pass through unchanged
   - Natural language is sent to the configured LLM provider

3. **Provider selection**: Configurable backend (defaults to Claude CLI)

## Configuration

Create `~/.config/nes.nu/config.nu`:

```nushell
$env.NES_CONFIG = {
    provider: {
        # Options: claude-cli, anthropic, openai, ollama
        default: claude-cli

        anthropic: {
            model: claude-3-5-haiku-20241022
            max_tokens: 128
        }
    }

    completer: {
        enabled: true
        min_chars: 5
        cache_ttl_ms: 500
    }

    debug: false
}
```

## Providers

| Provider | Setup | Latency |
|----------|-------|---------|
| `claude-cli` | Requires `claude` CLI installed | ~1-2s |
| `anthropic` | Requires `ANTHROPIC_API_KEY` | ~500ms |
| `openai` | Requires `OPENAI_API_KEY` | ~500ms |
| `ollama` | Requires local Ollama server | ~200ms |

## Tab Completion Integration

Add to your `config.nu`:

```nushell
# Load nes.nu
use ~/.config/nushell/modules/nes.nu

# Add to your external completer
let nes_completer = {|spans|
    if ($spans | first) != "nes" { return null }

    let input = $spans | skip 1 | str join " " | str trim
    if ($input | str length) < 5 { return null }

    let suggestion = try { nes $input } catch { "" }
    if ($suggestion | is-empty) { return null }

    [{value: $suggestion, description: "AI suggestion"}]
}
```

## Commands

| Command | Description |
|---------|-------------|
| `nes <input>` | Generate command from natural language |
| `nes <input> -x` | Generate and execute command |
| `nes status` | Show configuration and provider status |

## Testing

```nushell
nu tests/test_nes.nu
```

## Project Structure

```
nes.nu/
├── mod.nu              # Main entry point
├── src/
│   ├── validate.nu     # Input validation heuristics
│   ├── prompt.nu       # LLM system prompts
│   └── providers/
│       └── mod.nu      # Provider implementations
├── config/
│   └── default.nu      # Default configuration
├── completions/
│   └── nes-completer.nu  # Tab completion examples
└── tests/
    └── test_nes.nu     # Test suite
```

## License

MIT
