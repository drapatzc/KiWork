#!/bin/sh
# Claude Code with Claude subscription (OAuth login)
# Compatible with zsh and bash

# Unambiguous auth: remove API key and proxy -> only the OAuth login counts.
# (Prevents the "two auth methods" confirmation dialog.)
unset ANTHROPIC_API_KEY
unset ANTHROPIC_BASE_URL

# Check whether a subscription login exists in the keychain
if ! security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
  echo "ERROR: No Claude subscription login found."
  echo "Log in with:  claude   -> then /login"
  exit 1
fi

echo "----------------------------------------------"
echo " Claude Code -> Claude subscription"
echo " Auth:     OAuth login (keychain)"
echo " Billing:  via your subscription, no API cost"
echo "----------------------------------------------"
echo ""

# Start Claude Code, pass through arguments
claude "$@"
