# nes.nu - System prompts for LLM
#
# Provides the system prompt that instructs the LLM how to generate
# Nushell commands from natural language input.

# Returns the system prompt for command generation
#
# The prompt instructs the LLM to output only valid Nushell commands
# without any markdown, explanations, or code blocks.
#
# Examples:
#   system-prompt
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
