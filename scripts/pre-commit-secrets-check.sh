#!/usr/bin/env bash
# Pre-commit hook: block commits containing private key material or secrets.
# Install: cp scripts/pre-commit-secrets-check.sh .git/hooks/pre-commit
set -euo pipefail

# This script's own path (excluded from scanning to avoid self-detection)
SELF_PATH="scripts/pre-commit-secrets-check.sh"

# Patterns that should NEVER appear in a commit
FORBIDDEN_PATTERNS=(
    'BEGIN[[:space:]].*PRIV'
    'PRIV.*KEY-----'
    'eddsa_priv'
    'secret_key[[:space:]]*='
    'password[[:space:]]*='
    'app\.specific\.pass'
)

STAGED=$(git diff --cached --name-only --diff-filter=ACMR)
if [[ -z "$STAGED" ]]; then
    exit 0
fi

FOUND=0
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    # Search staged content, excluding this script
    MATCHES=$(git diff --cached -U0 -- . ":(exclude)${SELF_PATH}" | grep -iE "$pattern" || true)
    if [[ -n "$MATCHES" ]]; then
        echo "❌ BLOCKED: Staged changes contain forbidden pattern: $pattern"
        echo "$MATCHES"
        FOUND=1
    fi
done

# Block .env files that aren't gitignored (exclude this script)
for file in $STAGED; do
    [[ "$file" == "$SELF_PATH" ]] && continue
    if [[ "$file" == *.env* || "$file" == *secret* || "$file" == *credential* ]]; then
        echo "❌ BLOCKED: Sensitive file staged: $file"
        echo "   If intentional, use: git commit --no-verify"
        FOUND=1
    fi
done

if [[ $FOUND -ne 0 ]]; then
    echo ""
    echo "Commit blocked to prevent secret leaks."
    echo "If this is a false positive, use: git commit --no-verify"
    exit 1
fi
