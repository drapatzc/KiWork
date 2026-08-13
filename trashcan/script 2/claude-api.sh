#!/bin/sh
# Claude Code with Anthropic cloud (Claude 3.5 / 4)
# Compatible with zsh and bash

# Make sure no local proxy is active
unset ANTHROPIC_BASE_URL

# Check the Anthropic API key
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "ERROR: ANTHROPIC_API_KEY is not set."
  echo "Set it with: export ANTHROPIC_API_KEY=\"sk-ant-...\""
  exit 1
fi

echo "----------------------------------------------"
echo " Claude Code -> Anthropic Cloud"
echo " Model:    Claude 3.5 / 4 (Anthropic)"
echo " Privacy:  cloud - data leaves the Mac"
echo "----------------------------------------------"
echo ""

# Start Claude Code, pass through arguments
claude "$@"
