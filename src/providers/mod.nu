# nes.nu - Provider Dispatcher
#
# Routes suggestion requests to the configured provider.
# Supports: claude-cli (default), anthropic, openai, ollama, gemini

# ============================================================================
# Shared utilities
# ============================================================================

# System prompt for command generation
def get-system-prompt []: nothing -> string {
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

# Build a prompt with context for the LLM
def build-prompt [input: string, ctx: record]: nothing -> string {
    let pwd = $ctx.pwd? | default (pwd | path expand)
    $"Current directory: ($pwd)\n\nGenerate a nushell command for: ($input)"
}

# Clean up LLM response (remove markdown code blocks)
def clean-response []: string -> string {
    $in
    | str trim
    | lines
    | where {|line| not ($line | str starts-with "```")}
    | str join "\n"
    | str trim
}

# Get the configured provider name (without overrides; used as fallback)
def get-provider []: nothing -> string {
    $env.NES_CONFIG?.provider?.default? | default claude-cli
}

# Check if debug is enabled (with override support)
def is-debug [ovr: record]: nothing -> bool {
    $ovr.debug? | default ($env.NES_CONFIG?.debug? | default false)
}

# Build context record for providers
def build-context []: nothing -> record {
    { pwd: (pwd | path expand) }
}

# ============================================================================
# Claude CLI Provider
# ============================================================================

# Generate a command suggestion using Claude CLI
def claude-cli-suggest [input: string, opts: record]: nothing -> string {
    let prompt = build-prompt $input $opts
    let system = get-system-prompt
    let model = $opts.model? | default null

    try {
        if $model != null {
            ^claude --print --model $model --system-prompt $system $prompt | clean-response
        } else {
            ^claude --print --system-prompt $system $prompt | clean-response
        }
    } catch {|err|
        if (is-debug $opts) {
            print -e $"nes: claude-cli error: ($err.msg)"
        }
        ""
    }
}

# ============================================================================
# Anthropic API Provider
# ============================================================================

# Generate a command suggestion using Anthropic API
def anthropic-suggest [input: string, opts: record]: nothing -> string {
    let api_key = $env.ANTHROPIC_API_KEY? | default ""

    if ($api_key | is-empty) {
        if (is-debug $opts) {
            print -e "nes: ANTHROPIC_API_KEY not set"
        }
        return ""
    }

    let config = $env.NES_CONFIG?.provider?.anthropic? | default {
        model: claude-3-5-haiku-20241022
        max_tokens: 128
    }

    let prompt = build-prompt $input $opts
    let body = {
        model: ($opts.model? | default ($config.model? | default claude-3-5-haiku-20241022))
        max_tokens: ($opts.max_tokens? | default ($config.max_tokens? | default 128))
        system: (get-system-prompt)
        messages: [{role: user, content: $prompt}]
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
        | clean-response
    } catch {|err|
        if (is-debug $opts) {
            print -e $"nes: anthropic API error: ($err.msg)"
        }
        ""
    }
}

# ============================================================================
# OpenAI API Provider
# ============================================================================

def openai-suggest [input: string, opts: record]: nothing -> string {
    let api_key = $env.OPENAI_API_KEY? | default ""

    if ($api_key | is-empty) {
        if (is-debug $opts) {
            print -e "nes: OPENAI_API_KEY not set"
        }
        return ""
    }

    let config = $env.NES_CONFIG?.provider?.openai? | default {
        model: gpt-4o-mini
        max_tokens: 128
    }

    let prompt = build-prompt $input $opts
    let body = {
        model: ($opts.model? | default ($config.model? | default gpt-4o-mini))
        max_tokens: ($opts.max_tokens? | default ($config.max_tokens? | default 128))
        messages: [
            {role: system, content: (get-system-prompt)}
            {role: user, content: $prompt}
        ]
    }

    try {
        (http post "https://api.openai.com/v1/chat/completions"
            --content-type "application/json"
            --headers { Authorization: $"Bearer ($api_key)" }
            $body)
        | get choices.0.message.content
        | clean-response
    } catch {|err|
        if (is-debug $opts) {
            print -e $"nes: openai API error: ($err.msg)"
        }
        ""
    }
}

# ============================================================================
# Ollama Provider
# ============================================================================

def ollama-suggest [input: string, opts: record]: nothing -> string {
    let config = $env.NES_CONFIG?.provider?.ollama? | default {
        model: llama3.2
        base_url: "http://localhost:11434"
    }

    let prompt = build-prompt $input $opts
    let url = $"($config.base_url? | default 'http://localhost:11434')/api/generate"

    let body = {
        model: ($opts.model? | default ($config.model? | default llama3.2))
        prompt: $prompt
        system: (get-system-prompt)
        stream: false
    }

    try {
        (http post $url --content-type "application/json" $body)
        | get response
        | clean-response
    } catch {|err|
        if (is-debug $opts) {
            print -e $"nes: ollama error: ($err.msg)"
        }
        ""
    }
}

# ============================================================================
# Main dispatcher
# ============================================================================

# Generate a command suggestion using the configured provider
#
# Routes to the appropriate provider based on overrides or NES_CONFIG.provider.default.
# Falls back to empty string on error.
#
# The --overrides record supports: provider, model, max_tokens, debug, pwd.
# These values take precedence over NES_CONFIG when set (non-null).
#
# Examples:
#   suggest "list all rust files"
#   suggest "find files modified today" --context {pwd: "/home/user"}
#   suggest "large files" --overrides {provider: anthropic, model: claude-sonnet-4-5-20250514}
export def suggest [
    input: string         # Natural language input
    --context: record     # Optional context override
    --overrides: record   # Optional flag/env overrides {provider, model, max_tokens, debug}
]: nothing -> string {
    let ovr = if ($overrides != null) { $overrides } else { {} }
    let provider = $ovr.provider? | default (get-provider)

    # Merge context into opts so providers get both overrides and context in one record
    let ctx = if ($context != null) { $context } else { build-context }
    let opts = $ovr | merge $ctx

    match $provider {
        claude-cli => { claude-cli-suggest $input $opts }
        anthropic => { anthropic-suggest $input $opts }
        openai => { openai-suggest $input $opts }
        ollama => { ollama-suggest $input $opts }
        gemini => {
            if (is-debug $opts) {
                print -e "nes: gemini not implemented, using claude-cli"
            }
            claude-cli-suggest $input $opts
        }
        _ => {
            if (is-debug $opts) {
                print -e $"nes: unknown provider '($provider)', using claude-cli"
            }
            claude-cli-suggest $input $opts
        }
    }
}
