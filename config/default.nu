# nes.nu - Default Configuration
#
# Copy this file to your config directory:
#   cp default.nu $"($env.XDG_CONFIG_HOME | default '~/.config')/nes.nu/config.nu"
#
# Then source it in your nushell config.nu:
#   source ~/.config/nes.nu/config.nu

$env.NES_CONFIG = {
    # Provider configuration
    # Supports: claude-cli (default), anthropic, openai, ollama, gemini
    provider: {
        # Which provider to use
        # "claude-cli" - Uses the claude CLI (default, no API key needed)
        # "anthropic" - Direct Anthropic API (requires ANTHROPIC_API_KEY)
        # "openai" - OpenAI API (requires OPENAI_API_KEY)
        # "ollama" - Local Ollama (requires running ollama server)
        default: claude-cli

        # Provider-specific settings
        anthropic: {
            model: claude-3-5-haiku-20241022
            max_tokens: 128
        }

        openai: {
            model: gpt-4o-mini
            max_tokens: 128
        }

        ollama: {
            model: llama3.2
            base_url: "http://localhost:11434"
        }
    }

    # Completer settings (for tab completion integration)
    completer: {
        enabled: true
        min_chars: 5        # Minimum characters before triggering
        cache_ttl_ms: 500   # Cache results for this duration
    }

    # Output settings
    output: {
        include_explanation: false
    }

    # Enable debug output
    debug: false
}
