#!/usr/bin/env bash
# review.sh — Weekly team timesheet review for direct reports
#
# Required env vars:
#   BAMBOOHR_API_KEY          — API key for authentication
#   BAMBOOHR_COMPANY_DOMAIN   — Company subdomain
#   BAMBOOHR_EMPLOYEE_ID      — Manager's employee ID
#
# Reads validation rules from ../config.json (project names, ticket patterns, mandatory tasks).
#
# Usage:
#   bash review.sh                    # Review previous week (Mon–Sun)
#   bash review.sh --week 2026-05-25  # Review specific week (provide Monday date)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SKILL_DIR}/config.json"

# --- Validate config ---
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: config.json not found at ${CONFIG_FILE}" >&2
  echo "Run /timesheet-review to complete the first-time setup." >&2
  exit 1
fi
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "Error: config.json is not valid JSON." >&2
  exit 1
fi

# --- Validate env vars ---
missing=()
[[ -z "${BAMBOOHR_API_KEY:-}" ]]        && missing+=("BAMBOOHR_API_KEY")
[[ -z "${BAMBOOHR_COMPANY_DOMAIN:-}" ]] && missing+=("BAMBOOHR_COMPANY_DOMAIN")
[[ -z "${BAMBOOHR_EMPLOYEE_ID:-}" ]]    && missing+=("BAMBOOHR_EMPLOYEE_ID")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Missing required environment variables: ${missing[*]}" >&2
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

CONFIG=$(cat "$CONFIG_FILE")
HOURS_TARGET=$(echo "$CONFIG" | jq '.weeklyHoursTarget // 40')

BASE_URL="https://${BAMBOOHR_COMPANY_DOMAIN}.bamboohr.com/api/v1"
GATEWAY_URL="https://${BAMBOOHR_COMPANY_DOMAIN}.bamboohr.com/api/gateway.php/${BAMBOOHR_COMPANY_DOMAIN}/v1"
AUTH="${BAMBOOHR_API_KEY}:x"

# --- Parse arguments ---
WEEK_START=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --week) WEEK_START="$2"; shift 2 ;;
    *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Compute date range (Mon–Sun of target week) ---
if [[ -z "$WEEK_START" ]]; then
  dow=$(date +%u)           # 1=Mon … 7=Sun
  prev_mon=$(( dow + 6 ))   # days back to previous Monday
  prev_sun=$(( dow ))       # days back to previous Sunday
  WEEK_START=$(date -v-"${prev_mon}"d +%Y-%m-%d 2>/dev/null || date -d "-${prev_mon} days" +%Y-%m-%d)
  WEEK_END=$(date   -v-"${prev_sun}"d +%Y-%m-%d 2>/dev/null || date -d "-${prev_sun} days" +%Y-%m-%d)
else
  WEEK_END=$(date -j -v+6d -f "%Y-%m-%d" "$WEEK_START" "+%Y-%m-%d" 2>/dev/null \
          || date -d "$WEEK_START + 6 days" +%Y-%m-%d)
fi

# --- Fetch employee directory ---
echo "Fetching employee directory..." >&2
dir_resp=$(curl -s -w "\n%{http_code}" -u "$AUTH" -H "Accept: application/json" \
  "${GATEWAY_URL}/employees/directory")
dir_code=$(echo "$dir_resp" | tail -1)
dir_body=$(echo "$dir_resp" | sed '$d')

if [[ "$dir_code" != "200" ]]; then
  echo "Error: Directory API returned HTTP ${dir_code}" >&2
  exit 1
fi

# Resolve manager's display name by employee ID
manager_name=$(echo "$dir_body" | jq -r \
  --argjson mid "$BAMBOOHR_EMPLOYEE_ID" \
  '.employees[] | select(.id == ($mid | tostring)) | .displayName')

if [[ -z "$manager_name" ]]; then
  echo "Error: Employee ID ${BAMBOOHR_EMPLOYEE_ID} not found in directory" >&2
  exit 1
fi

# Collect direct reports (supervisor field matches manager's name)
direct_reports=$(echo "$dir_body" | jq \
  --arg mgr "$manager_name" \
  '[.employees[] | select(.supervisor == $mgr) | {id: .id, name: .displayName, jobTitle: (.jobTitle // "")}]')

report_count=$(echo "$direct_reports" | jq 'length')
if [[ "$report_count" == "0" ]]; then
  echo "No direct reports found for ${manager_name}." >&2
  exit 0
fi
echo "Found ${report_count} direct report(s) for ${manager_name}." >&2

# --- Fetch timesheet entries for all direct reports ---
emp_ids=$(echo "$direct_reports" | jq -r '[.[].id] | join(",")')
echo "Fetching timesheet entries (${WEEK_START} to ${WEEK_END})..." >&2

ts_resp=$(curl -s -w "\n%{http_code}" -u "$AUTH" -H "Accept: application/json" \
  "${BASE_URL}/time_tracking/timesheet_entries?employeeIds=${emp_ids}&start=${WEEK_START}&end=${WEEK_END}")
ts_code=$(echo "$ts_resp" | tail -1)
ts_body=$(echo "$ts_resp" | sed '$d')

if [[ "$ts_code" != "200" ]]; then
  echo "Error: Timesheet API returned HTTP ${ts_code}" >&2
  echo "$ts_body" >&2
  exit 1
fi

# --- Validate entries and build report data ---
REPORT=$(echo "$ts_body" | jq \
  --argjson reports "$direct_reports" \
  --argjson config "$CONFIG" \
  --argjson target "$HOURS_TARGET" \
  '
  . as $entries |
  [$reports[] as $emp |
    [$entries[] | select(.employeeId == ($emp.id | tonumber))] as $emp_entries |
    ($emp_entries | map(.hours) | add // 0) as $total |
    (($total * 100 | round) == ($target * 100 | round)) as $hours_ok |
    [$emp_entries[] |
      (.projectInfo.project.name // "") as $proj |
      (.projectInfo.task.name // "") as $task |
      (.note // "") as $note |
      ($config.projects | map(select(.name == $proj)) | .[0]) as $proj_config |
      ($proj_config != null and ($proj_config.mandatoryTasks | contains([$task]))) as $needs_id |
      {
        date: .date,
        project: (if $proj == "" then "-" else $proj end),
        task: (if $task == "" then "-" else $task end),
        note: $note,
        hours: .hours,
        needs_id: $needs_id,
        ticket_pattern: (if $proj_config != null then $proj_config.ticketPattern else "" end),
        ok: (if $needs_id then ($note | test($proj_config.ticketPattern)) else true end)
      }
    ] | sort_by(.date) as $validated |
    {
      name: $emp.name,
      jobTitle: $emp.jobTitle,
      total: $total,
      hours_ok: $hours_ok,
      target: $target,
      entries: $validated,
      id_errors: [$validated[] | select(.needs_id and (.ok | not))]
    }
  ]
')

# --- Print report ---
echo ""
echo "# Weekly Timesheet Review — ${WEEK_START} to ${WEEK_END}"
echo ""
echo "## Summary"
echo ""
echo "| Employee | Hours | Horas | IDs | Estado |"
echo "|----------|-------|-------|-----|--------|"
echo "$REPORT" | jq -r --argjson target "$HOURS_TARGET" '.[] |
  "| \(.name) | \(.total)/\($target) | \(if .hours_ok then "✅" else "❌" end) | \(if (.id_errors | length) == 0 then "✅" else "❌" end) | \(if .hours_ok and ((.id_errors | length) == 0) then "✅ OK" else "❌ Issues" end) |"'
echo ""

echo "$REPORT" | jq -c '.[]' | while IFS= read -r emp; do
  name=$(echo "$emp" | jq -r '.name')
  total=$(echo "$emp" | jq -r '.total')
  target=$(echo "$emp" | jq -r '.target')
  hours_ok=$(echo "$emp" | jq -r '.hours_ok')
  id_count=$(echo "$emp" | jq '.id_errors | length')

  hours_icon="✅"; [[ "$hours_ok" == "false" ]] && hours_icon="❌"
  all_ok="false"
  [[ "$hours_ok" == "true" && "$id_count" == "0" ]] && all_ok="true"

  echo "---"
  echo ""
  echo "## ${name} — ${total}h ${hours_icon}"
  echo ""
  echo "| Date | Project | Task | Description | Hours | ✓ |"
  echo "|------|---------|------|-------------|-------|---|"
  echo "$emp" | jq -r '.entries[] |
    "| \(.date) | \(.project | .[0:20]) | \(.task | .[0:26]) | \(.note | split("\n") | join(" ") | .[0:38]) | \(.hours) | \(if .ok then "✅" else "❌" end) |"'
  echo ""

  if [[ "$hours_ok" == "false" ]]; then
    if [[ $(echo "$emp" | jq -r "if .total < ${target} then \"yes\" else \"no\" end") == "yes" ]]; then
      missing=$(echo "$emp" | jq -r "${target} - .total")
      echo "  ❌ Horas insuficientes: ${total}/${target} (faltan ${missing}h)"
    else
      excess=$(echo "$emp" | jq -r ".total - ${target}")
      echo "  ❌ Horas excedidas: ${total}/${target} (exceso: ${excess}h)"
    fi
  fi

  echo "$emp" | jq -r '.id_errors[] |
    "  ❌ \(.date) — \(.task): falta \(.ticket_pattern) en descripción: \"\(.note | .[0:60])\""'

  if [[ "$all_ok" == "true" ]]; then
    echo "  ✅ Todo correcto"
  fi

  echo ""
done
