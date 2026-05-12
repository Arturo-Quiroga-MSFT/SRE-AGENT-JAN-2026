#!/usr/bin/env bash
# Wave B fixture creator — creates F1..F4 in SCRUM project using default Story type.
# Requires: JIRA_AUTH env var like "email:token"
set -u
: "${JIRA_AUTH:?Set JIRA_AUTH=email:token before running}"

BASE="https://aq-r2d2.atlassian.net/rest/api/3"
PROJECT_KEY="SCRUM"
ISSUE_TYPE_NAME="Story"
CURL_OPTS=(--max-time 20 -sS -H "Accept: application/json" -H "Content-Type: application/json" -u "$JIRA_AUTH")

create_issue() {
  local summary="$1"
  local body
  body=$(cat <<JSON
{"fields":{"project":{"key":"${PROJECT_KEY}"},"summary":"${summary}","issuetype":{"name":"${ISSUE_TYPE_NAME}"}}}
JSON
)
  curl "${CURL_OPTS[@]}" -X POST "${BASE}/issue" --data "$body"
}

transition() {
  local key="$1" tid="$2"
  curl "${CURL_OPTS[@]}" -X POST "${BASE}/issue/${key}/transitions" --data "{\"transition\":{\"id\":\"${tid}\"}}"
  echo "  -> transitioned ${key} via ${tid}"
}

echo "=== Discovering transitions for SCRUM-25 ==="
curl "${CURL_OPTS[@]}" "${BASE}/issue/SCRUM-25/transitions" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(t['id'], t['name'], '->', t['to']['name']) for t in d['transitions']]"

echo
echo "=== Creating F2 (R001c FAIL: Story -> In Progress -> Done) ==="
F2=$(create_issue "Wave B fixture F2: ticket closed before activation (R001c FAIL)")
echo "$F2"
F2_KEY=$(echo "$F2" | python3 -c "import sys,json;print(json.load(sys.stdin)['key'])")
echo "F2_KEY=${F2_KEY}"

echo
echo "=== Creating F3 (R003 FAIL: Story -> In Progress, requester not linked) ==="
F3=$(create_issue "Wave B fixture F3: requester not linked to ticket (R003 FAIL)")
echo "$F3"
F3_KEY=$(echo "$F3" | python3 -c "import sys,json;print(json.load(sys.stdin)['key'])")
echo "F3_KEY=${F3_KEY}"

echo
echo "=== Creating F4 (R002 FAIL placeholder: needs YAML override at smoke time) ==="
F4=$(create_issue "Wave B fixture F4: ticket older than 72h (R002 FAIL, requires R002.value override at smoke time)")
echo "$F4"
F4_KEY=$(echo "$F4" | python3 -c "import sys,json;print(json.load(sys.stdin)['key'])")
echo "F4_KEY=${F4_KEY}"

echo
echo "=== Transitions (using IDs discovered above; defaults 21=In Progress, 31=Done for team-managed Scrum) ==="
# We will read IDs dynamically per-issue to be safe.
get_tid() {
  local key="$1" want="$2"
  curl "${CURL_OPTS[@]}" "${BASE}/issue/${key}/transitions" \
    | python3 -c "import sys,json,os; d=json.load(sys.stdin); want=os.environ['WANT'].lower(); m=[t for t in d['transitions'] if t['to']['name'].lower()==want]; print(m[0]['id'] if m else '')" \
    WANT="$want"
}

for K in "$F2_KEY" "$F3_KEY" "$F4_KEY"; do
  WANT="In Progress"
  TID=$(curl "${CURL_OPTS[@]}" "${BASE}/issue/${K}/transitions" | WANT="$WANT" python3 -c "import sys,json,os; d=json.load(sys.stdin); want=os.environ['WANT'].lower(); m=[t for t in d['transitions'] if t['to']['name'].lower()==want]; print(m[0]['id'] if m else '')")
  if [ -n "$TID" ]; then transition "$K" "$TID"; else echo "WARN: no In Progress transition for $K"; fi
done

# F2 -> Done
WANT="Done"
TID=$(curl "${CURL_OPTS[@]}" "${BASE}/issue/${F2_KEY}/transitions" | WANT="$WANT" python3 -c "import sys,json,os; d=json.load(sys.stdin); want=os.environ['WANT'].lower(); m=[t for t in d['transitions'] if t['to']['name'].lower()==want]; print(m[0]['id'] if m else '')")
if [ -n "$TID" ]; then transition "$F2_KEY" "$TID"; else echo "WARN: no Done transition for $F2_KEY"; fi

echo
echo "=== Final summary ==="
for K in SCRUM-25 "$F2_KEY" "$F3_KEY" "$F4_KEY"; do
  curl "${CURL_OPTS[@]}" "${BASE}/issue/${K}?fields=summary,status,reporter,assignee" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); f=d['fields']; print(f\"{d['key']:10s} status={f['status']['name']:12s} reporter={(f['reporter'] or {}).get('displayName','?')}  | {f['summary']}\")"
done
