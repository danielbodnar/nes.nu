# nes.nu - External Completer Integration Example
#
# This file shows how to integrate nes.nu with Nushell's external completer.
# Copy and adapt this to your config.nu.
#
# SETUP INSTRUCTIONS:
# 1. First, ensure nes.nu is loaded in your config.nu:
#    use ~/.config/nushell/modules/nes.nu
#
# 2. Then add this completer to your external_completer chain

# Example: Simple nes completer
# Add this to your config.nu after loading nes.nu
#
# let nes_completer = {|spans: list<string>|
#     let first = $spans | first | default ""
#     if $first != "nes" { return null }
#
#     let input = $spans | skip 1 | str join " " | str trim
#     let min_chars = $env.NES_CONFIG?.completer?.min_chars? | default 5
#
#     if ($input | str length) < $min_chars { return null }
#
#     # Call nes to get suggestion
#     let suggestion = try { nes $input } catch { "" }
#     if ($suggestion | is-empty) { return null }
#
#     [{value: $suggestion, description: "AI suggestion", style: {fg: cyan}}]
# }

# Example: Combining with existing completer (e.g., carapace)
#
# let carapace_completer = {|spans| carapace $spans.0 nushell ...$spans | from json }
#
# let combined_completer = {|spans|
#     let first = $spans | first | default ""
#     match $first {
#         "nes" => {
#             let input = $spans | skip 1 | str join " " | str trim
#             if ($input | str length) < 5 { return null }
#             let suggestion = try { nes $input } catch { "" }
#             if ($suggestion | is-empty) { return null }
#             [{value: $suggestion, description: "AI suggestion"}]
#         }
#         _ => { do $carapace_completer $spans }
#     }
# }
#
# $env.config.completions.external = {
#     enable: true
#     completer: $combined_completer
# }

# This is a documentation-only file
# The actual integration happens in your config.nu
