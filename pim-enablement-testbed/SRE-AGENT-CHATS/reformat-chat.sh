#!/usr/bin/env bash
# Helper for the recurring "reformat N.md like the others" ask.
#
# Usage:
#   ./reformat-chat.sh <N>            # prepares a Copilot prompt for N.md
#   ./reformat-chat.sh <N> --new      # scaffolds a brand-new N.md skeleton
#
# What it does:
#   - Validates the target file (or creates a skeleton with --new).
#   - Emits a ready-to-paste Copilot Chat prompt that references the canonical
#     format files (1.md, 7.md) and the target file, then pipes it to pbcopy
#     so you can just Cmd+V it into Copilot Chat.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-}"
MODE="${2:-}"

if [[ -z "$N" ]]; then
  echo "Usage: $0 <N> [--new]" >&2
  exit 1
fi

TARGET="$SCRIPT_DIR/${N}.md"

if [[ "$MODE" == "--new" ]]; then
  if [[ -e "$TARGET" ]]; then
    echo "Refusing to overwrite existing $TARGET" >&2
    exit 1
  fi
  cat > "$TARGET" <<'EOF'
> **Prompt:** <PASTE THE EXACT PROMPT HERE>

| Tool call | Server | Result |
|---|---|---|
| `<tool_name>` | <server> | Completed |

<one-line summary of what the agent did>

---

## <Section heading>

| Column | Column |
|---|---|
| value | value |

---

## Bottom line

<closing recommendation or follow-up>
EOF
  echo "Scaffolded $TARGET" >&2
  exit 0
fi

if [[ ! -f "$TARGET" ]]; then
  echo "$TARGET does not exist. Create it first (paste raw agent output) or run with --new." >&2
  exit 1
fi

PROMPT=$(cat <<EOF
Reformat pim-enablement-testbed/SRE-AGENT-CHATS/${N}.md to match the shared
format used by 1.md, 6.md, and 7.md in the same directory. Specifically:

  1. Start with a blockquote prompt: \`> **Prompt:** <the question>\`
  2. Follow with a "Tool call | Server | Result" markdown table.
  3. Use \`---\` separators between sections and \`##\` headings.
  4. Convert any plaintext column-listed data into proper markdown tables.
  5. Wrap IDs, emails, scopes, role names, Graph endpoints, and rule
     references (R001..R008) in inline backticks.
  6. Preserve all factual content verbatim — do not invent, drop, or
     reinterpret data. Only restructure for readability.
  7. End with a "## Bottom line" or "## Recommendation" section if the
     original output had a closing recommendation.

Do not touch any other file. After editing, do not create a summary
markdown doc — just confirm the file was reformatted.
EOF
)

echo "$PROMPT"

if command -v pbcopy >/dev/null 2>&1; then
  printf '%s' "$PROMPT" | pbcopy
  echo
  echo "[copied to clipboard via pbcopy]" >&2
fi
