#!/usr/bin/env bash
# review.sh — Weekly team timesheet review for direct reports
#
# Required env vars:
#   BAMBOOHR_API_KEY          — API key for authentication
#   BAMBOOHR_COMPANY_DOMAIN   — Company subdomain
#   BAMBOOHR_EMPLOYEE_ID      — Manager's employee ID
#
# Reads validation rules from ../review-config.json (project names, ticket patterns, mandatory tasks).
# Note: review-config.json is separate from config.json, which init.sh auto-generates.
#
# Usage:
#   bash review.sh                    # Review previous week (Mon–Sun)
#   bash review.sh --week 2026-05-25  # Review specific week (provide Monday date)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${SKILL_DIR}/review-config.json"

# --- Validate config ---
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Error: review-config.json not found at ${CONFIG_FILE}" >&2
  echo "Run /timesheet review to complete the first-time setup." >&2
  exit 1
fi
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "Error: review-config.json is not valid JSON." >&2
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

# --- Fetch approved time off for all direct reports (single request) ---
echo "Fetching time off data..." >&2
# Day-based time off converts to hours assuming a 5-day work week
DAILY_HOURS=$(jq -n --argjson t "$HOURS_TARGET" '$t / 5')
timeoff_json="{}"
to_resp=$(curl -s -w "\n%{http_code}" -u "$AUTH" -H "Accept: application/json" \
  "${BASE_URL}/time_off/requests?start=${WEEK_START}&end=${WEEK_END}&status=approved")
to_code=$(echo "$to_resp" | tail -1)
to_body=$(echo "$to_resp" | sed '$d')

if [[ "$to_code" == "200" ]]; then
  timeoff_json=$(echo "$to_body" | jq \
    --arg start "$WEEK_START" --arg end "$WEEK_END" \
    --argjson daily "$DAILY_HOURS" \
    --argjson reports "$direct_reports" '
    [$reports[].id | tostring] as $ids |
    (if type == "array" then . else [] end) |
    map(
      select((.employeeId | tostring) as $eid | $ids | index($eid)) |
      select(
        (.status | if type == "object" then .status else . end) == "approved"
      ) |
      (.amount.unit // "days") as $unit |
      (if $unit == "hours" then 1 else $daily end) as $mult |
      {
        id: (.employeeId | tostring),
        hours: ([
          .dates | to_entries[] |
          select(.key >= $start and .key <= $end) |
          (.value | tonumber) * $mult
        ] | add // 0)
      }
    ) |
    group_by(.id) | map({key: .[0].id, value: (map(.hours) | add)}) | from_entries
  ')
else
  echo "Warning: Time off API returned HTTP ${to_code} — assuming no time off." >&2
fi

# --- Validate entries and build report data ---
REPORT=$(echo "$ts_body" | jq \
  --argjson reports "$direct_reports" \
  --argjson config "$CONFIG" \
  --argjson target "$HOURS_TARGET" \
  --argjson timeoff "$timeoff_json" \
  '
  . as $entries |
  [$reports[] as $emp |
    [$entries[] | select(.employeeId == ($emp.id | tonumber))] as $emp_entries |
    ($emp_entries | map(.hours) | add // 0) as $total |
    ($timeoff[($emp.id | tostring)] // 0) as $timeoff_h |
    ($target - $timeoff_h) as $effective_target |
    (($total * 100 | round) == ($effective_target * 100 | round)) as $hours_ok |
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
      timeoff_hours: $timeoff_h,
      effective_target: $effective_target,
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
echo "| Employee | Work | Time Off | Target | Horas | IDs | Estado |"
echo "|----------|------|----------|--------|-------|-----|--------|"
echo "$REPORT" | jq -r '.[] |
  "| \(.name) | \(.total)h | \(if .timeoff_hours > 0 then "\(.timeoff_hours)h" else "—" end) | \(.effective_target)h | \(if .hours_ok then "✅" else "❌" end) | \(if (.id_errors | length) == 0 then "✅" else "❌" end) | \(if .hours_ok and ((.id_errors | length) == 0) then "✅ OK" else "❌ Issues" end) |"'
echo ""

echo "$REPORT" | jq -c '.[]' | while IFS= read -r emp; do
  name=$(echo "$emp" | jq -r '.name')
  total=$(echo "$emp" | jq -r '.total')
  target=$(echo "$emp" | jq -r '.target')
  effective_target=$(echo "$emp" | jq -r '.effective_target')
  timeoff_h=$(echo "$emp" | jq -r '.timeoff_hours')
  hours_ok=$(echo "$emp" | jq -r '.hours_ok')
  id_count=$(echo "$emp" | jq '.id_errors | length')

  hours_icon="✅"; [[ "$hours_ok" == "false" ]] && hours_icon="❌"
  all_ok="false"
  [[ "$hours_ok" == "true" && "$id_count" == "0" ]] && all_ok="true"

  timeoff_label=""
  if [[ "$timeoff_h" != "0" ]]; then
    timeoff_label=" (${timeoff_h}h time off)"
  fi

  echo "---"
  echo ""
  echo "## ${name} — ${total}h trabajadas${timeoff_label} ${hours_icon}"
  echo ""
  echo "| Date | Project | Task | Description | Hours | ✓ |"
  echo "|------|---------|------|-------------|-------|---|"

  if [[ "$timeoff_h" != "0" ]]; then
    echo "| — | — | Time Off (approved) | — | ${timeoff_h} | ✅ |"
  fi

  echo "$emp" | jq -r '.entries[] |
    "| \(.date) | \(.project | .[0:20]) | \(.task | .[0:26]) | \(.note | split("\n") | join(" ") | .[0:38]) | \(.hours) | \(if .ok then "✅" else "❌" end) |"'
  echo ""

  if [[ "$hours_ok" == "false" ]]; then
    if [[ $(echo "$emp" | jq -r "if .total < ${effective_target} then \"yes\" else \"no\" end") == "yes" ]]; then
      missing=$(echo "$emp" | jq -r "${effective_target} - .total")
      echo "  ❌ Horas insuficientes: ${total}h trabajadas + ${timeoff_h}h time off = $(echo "$emp" | jq -r '.total + .timeoff_hours')/${target} (faltan ${missing}h)"
    else
      excess=$(echo "$emp" | jq -r ".total - ${effective_target}")
      echo "  ❌ Horas excedidas: ${total}/${effective_target} (exceso: ${excess}h)"
    fi
  fi

  echo "$emp" | jq -r '.id_errors[] |
    "  ❌ \(.date) — \(.task): falta \(.ticket_pattern) en descripción: \"\(.note | .[0:60])\""'

  if [[ "$all_ok" == "true" ]]; then
    echo "  ✅ Todo correcto"
  fi

  echo ""
done
