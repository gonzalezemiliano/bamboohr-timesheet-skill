#!/usr/bin/env bash
# init.sh — Bootstrap timesheet skill configuration from BambooHR API
# Discovers projects and tasks available to the employee, writes config.json.
#
# Required env vars (for API operations — NOT needed for --check, nor for
# --export when a local config.json already exists):
#   BAMBOOHR_API_KEY          — API key for authentication
#   BAMBOOHR_COMPANY_DOMAIN   — Company subdomain (e.g., "acme" for acme.bamboohr.com)
#   BAMBOOHR_EMPLOYEE_ID      — Employee ID number
#
# Usage:
#   ./scripts/init.sh                   # First-time setup (needs API key)
#   ./scripts/init.sh --refresh         # Overwrite existing config.json (needs API key)
#   ./scripts/init.sh --export [file]   # Write a shareable config (projects/tasks only,
#                                       #   no employeeId) for teammates without an API key.
#                                       #   Default output: config.shared.json
#   ./scripts/init.sh --check           # Print detected mode (online/offline) — no API call

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"

# --- Parse arguments ---
ACTION="init"
EXPORT_FILE="$SKILL_DIR/config.shared.json"

case "${1:-}" in
  --refresh) ACTION="refresh" ;;
  --check)   ACTION="check" ;;
  --export)
    ACTION="export"
    [[ -n "${2:-}" ]] && EXPORT_FILE="$2"
    ;;
  "") ;;
  *)
    echo "Error: Unknown option: $1" >&2
    echo "Usage: ./scripts/init.sh [--refresh | --export [file] | --check]" >&2
    exit 1
    ;;
esac

# --- Helpers ---
have_api_key() { [[ -n "${BAMBOOHR_API_KEY:-}" ]]; }

require_api() {
  local missing=()
  [[ -z "${BAMBOOHR_API_KEY:-}" ]] && missing+=("BAMBOOHR_API_KEY")
  [[ -z "${BAMBOOHR_COMPANY_DOMAIN:-}" ]] && missing+=("BAMBOOHR_COMPANY_DOMAIN")
  [[ -z "${BAMBOOHR_EMPLOYEE_ID:-}" ]] && missing+=("BAMBOOHR_EMPLOYEE_ID")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing required environment variables: ${missing[*]}" >&2
    echo "" >&2
    echo "Set them in your shell profile or export before running:" >&2
    echo "  export BAMBOOHR_API_KEY='your-api-key'" >&2
    echo "  export BAMBOOHR_COMPANY_DOMAIN='your-company'" >&2
    echo "  export BAMBOOHR_EMPLOYEE_ID='123'" >&2
    exit 1
  fi
}

# Fetch the raw projects/tasks array from the BambooHR API (stdout = JSON body).
# Errors go to stderr and exit non-zero; call as: body="$(fetch_projects)" || exit 1
fetch_projects() {
  local base_url="https://${BAMBOOHR_COMPANY_DOMAIN}.bamboohr.com/api/v1"
  local auth="${BAMBOOHR_API_KEY}:x"
  local response http_code body
  response=$(curl -s --connect-timeout 10 --max-time 30 \
    -w "\nHTTP_CODE:%{http_code}" \
    -u "$auth" \
    -H "Accept: application/json" \
    "${base_url}/time_tracking/employees/${BAMBOOHR_EMPLOYEE_ID}/projects")
  http_code="${response##*HTTP_CODE:}"
  body="${response%HTTP_CODE:*}"
  body="${body%$'\n'}"
  if [[ "$http_code" != "200" ]]; then
    echo "Error: BambooHR API returned HTTP ${http_code}" >&2
    echo "Response: $body" >&2
    return 1
  fi
  printf '%s' "$body"
}

# Transform an API body into our config format (stdout = config JSON).
#   $1 = API body
#   $2 = employeeId to embed ("" to omit — used for shareable configs)
#   $3 = shared flag (true/false) — adds "shared": true when true
build_config() {
  local body="$1" eid="$2" shared="$3" ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$body" | jq \
    --arg eid "$eid" \
    --arg ts "$ts" \
    --argjson shared "$shared" '
    {
      projects: [.[] | {
        id: .id,
        name: .name,
        tasks: [.tasks[]? | { id: .id, name: .name }]
      }],
      generatedAt: $ts,
      version: "1.0"
    }
    | (if $eid != "" then {employeeId: ($eid | tonumber)} + . else . end)
    | (if $shared then . + {shared: true} else . end)'
}

# ============================================================
# CHECK MODE — report detected mode without calling the API
# ============================================================
if [[ "$ACTION" == "check" ]]; then
  if have_api_key; then echo "api_key=set"; else echo "api_key=missing"; fi
  if [[ -f "$CONFIG_FILE" ]]; then echo "config=present"; else echo "config=missing"; fi
  if have_api_key; then echo "mode=online"; else echo "mode=offline"; fi
  exit 0
fi

# --- jq required for everything below ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  echo "Install with: brew install jq" >&2
  exit 1
fi

# ============================================================
# EXPORT MODE — write a shareable config (projects/tasks only)
# ============================================================
if [[ "$ACTION" == "export" ]]; then
  if [[ -f "$CONFIG_FILE" ]]; then
    # Reuse the existing config — just strip employee-specific data. No API call.
    jq 'del(.employeeId) | .shared = true' "$CONFIG_FILE" > "$EXPORT_FILE.tmp" \
      && mv "$EXPORT_FILE.tmp" "$EXPORT_FILE"
    src="existing config.json"
  else
    # No local config — fetch from the API, then omit employee-specific data.
    require_api
    echo "No local config.json found — fetching projects from BambooHR..."
    body="$(fetch_projects)" || exit 1
    build_config "$body" "" true > "$EXPORT_FILE.tmp" && mv "$EXPORT_FILE.tmp" "$EXPORT_FILE"
    src="BambooHR API"
  fi

  project_count=$(jq '.projects | length' "$EXPORT_FILE")
  task_count=$(jq '[.projects[].tasks | length] | add // 0' "$EXPORT_FILE")

  echo ""
  echo "Shareable config written to: $EXPORT_FILE"
  echo "  Source:     ${src}"
  echo "  Projects:   ${project_count}"
  echo "  Tasks:      ${task_count}"
  echo "  employeeId: omitted (safe to share)"
  echo ""
  echo "Share this file privately with teammates (Slack/Drive — do NOT commit it)."
  echo "They save it as:"
  echo "  ${CONFIG_FILE}"
  echo "then run the skill with no API key set (offline mode)."
  exit 0
fi

# ============================================================
# INIT / REFRESH — discover projects/tasks and write config.json
# ============================================================
if [[ -f "$CONFIG_FILE" && "$ACTION" != "refresh" ]]; then
  echo "config.json already exists at: $CONFIG_FILE"
  echo "Use --refresh to overwrite."
  exit 0
fi

require_api

echo "Fetching projects and tasks for employee ${BAMBOOHR_EMPLOYEE_ID}..."
body="$(fetch_projects)" || exit 1

config="$(build_config "$body" "$BAMBOOHR_EMPLOYEE_ID" false)"
echo "$config" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

# --- Summary ---
project_count=$(echo "$config" | jq '.projects | length')
task_count=$(echo "$config" | jq '[.projects[].tasks | length] | add // 0')

echo ""
echo "config.json written to: $CONFIG_FILE"
echo "  Employee ID: ${BAMBOOHR_EMPLOYEE_ID}"
echo "  Projects:    ${project_count}"
echo "  Tasks:       ${task_count}"
echo ""
echo "Available projects:"
echo "$config" | jq -r '.projects[] | "  - \(.name) (\(.tasks | length) tasks)"'
