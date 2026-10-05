#!/usr/bin/env nu
# nes.nu - Test Suite
#
# Run with: nu tests/test_nes.nu
#
# Tests the core functionality of nes.nu

use std/assert

# ============================================================================
# Validation Tests (inline implementation for standalone testing)
# ============================================================================

const NATURAL_LANGUAGE_INDICATORS = [
    all the that which please me show
    big large small new old recent
    today yesterday modified created with
    containing named called like similar matching
    and or but for of by every any some
]

const NATURAL_LANGUAGE_STARTERS = [
    list show find get display give tell
    what how why when where who
]

def test-is-natural-language [input: string]: nothing -> bool {
    let trimmed = $input | str trim
    if ($trimmed | is-empty) { return false }

    let words = $trimmed | split words
    if ($words | length) == 1 {
        let found = which ($words | first) | length
        return ($found == 0)
    }

    let first = $words | first
    let first_lower = $first | str lowercase
    let is_known_command = (which $first | length) > 0

    if ($trimmed =~ ' -[a-zA-Z]') { return false }

    if not $is_known_command {
        if $first_lower in $NATURAL_LANGUAGE_STARTERS { return true }
        return true
    }

    let remaining_words = $words | skip 1
    let indicator_count = $remaining_words | where {|w|
        ($w | str lowercase) in $NATURAL_LANGUAGE_INDICATORS
    } | length

    $indicator_count >= 2
}

# ============================================================================
# Test Cases
# ============================================================================

def "test commands" [] {
    assert equal false (test-is-natural-language "ls -la") "ls -la should be a command"
    assert equal false (test-is-natural-language "git status") "git status should be a command"
    assert equal false (test-is-natural-language "du --summarize") "du --summarize should be a command"
    assert equal false (test-is-natural-language "http get url") "http get url should be a command"
}

def "test natural-language" [] {
    assert equal true (test-is-natural-language "list all files") "list all files is natural language"
    assert equal true (test-is-natural-language "find big files please") "find big files please is natural language"
    assert equal true (test-is-natural-language "show me disk usage") "show me disk usage is natural language"
}

def "test edge-cases" [] {
    assert equal false (test-is-natural-language "ls") "ls is a command"
    assert equal false (test-is-natural-language "du") "du is a command"
    assert equal true (test-is-natural-language "asdfasdf") "asdfasdf is natural language"
    assert equal false (test-is-natural-language "") "empty is not natural language"
    assert equal true (test-is-natural-language "ls all the files") "ls all the files is natural language"
}

# ============================================================================
# Test Runner
# ============================================================================

def run-test [name: string, test_fn: closure]: nothing -> record {
    print -n $"  test ($name)... "
    let result = try {
        do $test_fn
        print "PASS"
        { passed: 1, failed: 0 }
    } catch {|e|
        print $"FAIL: ($e.msg)"
        { passed: 0, failed: 1 }
    }
    $result
}

def "test all" [] {
    print "Running nes.nu tests...\n"

    let results = [
        (run-test "commands" { test commands })
        (run-test "natural-language" { test natural-language })
        (run-test "edge-cases" { test edge-cases })
    ]

    let passed = $results | get passed | math sum
    let failed = $results | get failed | math sum

    print $"\n($passed) passed, ($failed) failed"

    if $failed > 0 { exit 1 }
}

def main [] {
    test all
}
