#!/usr/bin/env bash
# init.sh — Bootstrap timesheet skill configuration from BambooHR API
# Discovers projects and tasks available to the employee, writes config.json.
#
# Required env vars:
#   BAMBOOHR_API_KEY          — API key for authentication
#   BAMBOOHR_COMPANY_DOMAIN   — Company subdomain (e.g., "acme" for acme.bamboohr.com)
#   BAMBOOHR_EMPLOYEE_ID      — Employee ID number
#
# Usage:
#   ./scripts/init.sh             # First-time setup
#   ./scripts/init.sh --refresh   # Overwrite existing config.json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$SKILL_DIR/config.json"

# --- Validate env vars ---
missing=()
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

# --- Check for existing config ---
if [[ -f "$CONFIG_FILE" && "${1:-}" != "--refresh" ]]; then
  echo "config.json already exists at: $CONFIG_FILE"
  echo "Use --refresh to overwrite."
  exit 0
fi

# --- Check dependencies ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  echo "Install with: brew install jq" >&2
  exit 1
fi

# --- API base URL ---
BASE_URL="https://${BAMBOOHR_COMPANY_DOMAIN}.bamboohr.com/api/v1"
AUTH="${BAMBOOHR_API_KEY}:x"

echo "Fetching projects and tasks for employee ${BAMBOOHR_EMPLOYEE_ID}..."

# --- Fetch projects/tasks ---
response=$(curl -s -w "\n%{http_code}" \
  -u "$AUTH" \
  -H "Accept: application/json" \
  "${BASE_URL}/time_tracking/employees/${BAMBOOHR_EMPLOYEE_ID}/projects")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" != "200" ]]; then
  echo "Error: BambooHR API returned HTTP ${http_code}" >&2
  echo "Response: $body" >&2
  exit 1
fi

# --- Build config.json ---
# The API returns an array of projects, each with a tasks array.
# Transform into our config format.
config=$(echo "$body" | jq --arg eid "$BAMBOOHR_EMPLOYEE_ID" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
  employeeId: ($eid | tonumber),
  projects: [.[] | {
    id: .id,
    name: .name,
    tasks: [.tasks[]? | {
      id: .id,
      name: .name
    }]
  }],
  generatedAt: $ts
}')

echo "$config" > "$CONFIG_FILE"

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
