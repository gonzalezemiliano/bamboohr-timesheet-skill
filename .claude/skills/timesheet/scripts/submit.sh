#!/usr/bin/env bash
# submit.sh — Submit timesheet entries to BambooHR or show existing entries
#
# Required env vars:
#   BAMBOOHR_API_KEY          — API key for authentication
#   BAMBOOHR_COMPANY_DOMAIN   — Company subdomain
#   BAMBOOHR_EMPLOYEE_ID      — Employee ID number
#
# Usage:
#   ./scripts/submit.sh /tmp/entries.json                    # Submit entries
#   ./scripts/submit.sh --dry-run /tmp/entries.json          # Validate only
#   ./scripts/submit.sh --show                               # Show current week
#   ./scripts/submit.sh --show --start 2026-02-10 --end 2026-02-14  # Show date range

set -euo pipefail

# --- Validate env vars ---
missing=()
[[ -z "${BAMBOOHR_API_KEY:-}" ]] && missing+=("BAMBOOHR_API_KEY")
[[ -z "${BAMBOOHR_COMPANY_DOMAIN:-}" ]] && missing+=("BAMBOOHR_COMPANY_DOMAIN")
[[ -z "${BAMBOOHR_EMPLOYEE_ID:-}" ]] && missing+=("BAMBOOHR_EMPLOYEE_ID")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Missing required environment variables: ${missing[*]}" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed." >&2
  exit 1
fi

BASE_URL="https://${BAMBOOHR_COMPANY_DOMAIN}.bamboohr.com/api/v1"
AUTH="${BAMBOOHR_API_KEY}:x"

# --- Parse arguments ---
MODE="submit"
DRY_RUN=false
INPUT_FILE=""
START_DATE=""
END_DATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --show)
      MODE="show"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --start)
      START_DATE="$2"
      shift 2
      ;;
    --end)
      END_DATE="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
    *)
      INPUT_FILE="$1"
      shift
      ;;
  esac
done

# ============================================================
# SHOW MODE — Fetch and display existing timesheet entries
# ============================================================
if [[ "$MODE" == "show" ]]; then
  # Default to current week (Monday to Friday)
  if [[ -z "$START_DATE" ]]; then
    # Get Monday of current week
    day_of_week=$(date +%u)  # 1=Monday, 7=Sunday
    days_since_monday=$((day_of_week - 1))
    START_DATE=$(date -v-"${days_since_monday}"d +%Y-%m-%d 2>/dev/null || date -d "-${days_since_monday} days" +%Y-%m-%d)
  fi
  if [[ -z "$END_DATE" ]]; then
    # Get Friday of current week
    day_of_week=$(date +%u)
    days_to_friday=$((5 - day_of_week))
    if [[ $days_to_friday -lt 0 ]]; then days_to_friday=0; fi
    END_DATE=$(date -v+"${days_to_friday}"d +%Y-%m-%d 2>/dev/null || date -d "+${days_to_friday} days" +%Y-%m-%d)
  fi

  echo "Fetching timesheet entries: ${START_DATE} to ${END_DATE}"
  echo ""

  response=$(curl -s -w "\n%{http_code}" \
    -u "$AUTH" \
    -H "Accept: application/json" \
    "${BASE_URL}/time_tracking/timesheet_entries?employeeIds=${BAMBOOHR_EMPLOYEE_ID}&start=${START_DATE}&end=${END_DATE}")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    echo "Error: BambooHR API returned HTTP ${http_code}" >&2
    echo "Response: $body" >&2
    exit 1
  fi

  # Format and display entries
  entry_count=$(echo "$body" | jq 'length')

  if [[ "$entry_count" == "0" || "$entry_count" == "null" ]]; then
    echo "No entries found for ${START_DATE} to ${END_DATE}."
    exit 0
  fi

  echo "| Date       | Hours | Project                | Task                     | Note                          |"
  echo "|------------|-------|------------------------|--------------------------|-------------------------------|"

  echo "$body" | jq -r '.[] | "| \(.date) | \(.hours | tostring | .[0:5] | if length < 5 then . + "  " else . end) | \(.projectName // "-" | .[0:22] | if length < 22 then . + (" " * (22 - length)) else . end) | \(.taskName // "-" | .[0:24] | if length < 24 then . + (" " * (24 - length)) else . end) | \(.note // "-" | .[0:29] | if length < 29 then . + (" " * (29 - length)) else . end) |"' 2>/dev/null || \
  echo "$body" | jq -r '.[] | "| \(.date) | \(.hours) | \(.projectName // "-") | \(.taskName // "-") | \(.note // "-") |"'

  total=$(echo "$body" | jq '[.[].hours | tonumber] | add')
  echo ""
  echo "Total: ${total} hours (${entry_count} entries)"
  exit 0
fi

# ============================================================
# SUBMIT MODE — POST timesheet entries to BambooHR
# ============================================================
if [[ -z "$INPUT_FILE" ]]; then
  echo "Error: No input file specified." >&2
  echo "Usage: ./scripts/submit.sh [--dry-run] <entries.json>" >&2
  exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "Error: File not found: $INPUT_FILE" >&2
  exit 1
fi

# Validate JSON structure
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
  echo "Error: Invalid JSON in $INPUT_FILE" >&2
  exit 1
fi

entry_count=$(jq '.hours | length' "$INPUT_FILE")
total_hours=$(jq '[.hours[].hours] | add' "$INPUT_FILE")

if [[ "$entry_count" == "0" || "$entry_count" == "null" ]]; then
  echo "Error: No entries found in JSON payload." >&2
  exit 1
fi

echo "Entries to submit: ${entry_count} (${total_hours} hours total)"
echo ""

# Display what will be submitted
echo "| # | Date       | Hours | Project ID | Task ID | Note                          |"
echo "|---|------------|-------|------------|---------|-------------------------------|"
jq -r '.hours | to_entries[] | "| \(.key + 1) | \(.value.date) | \(.value.hours) | \(.value.projectId) | \(.value.taskId) | \(.value.note // "-") |"' "$INPUT_FILE"
echo ""

# Dry run — stop here
if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] Validation passed. No entries submitted."
  exit 0
fi

# Submit to BambooHR
echo "Submitting to BambooHR..."

response=$(curl -s -w "\n%{http_code}" \
  -X POST \
  -u "$AUTH" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d @"$INPUT_FILE" \
  "${BASE_URL}/time_tracking/hour_entries/store")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" == "201" || "$http_code" == "200" ]]; then
  echo "Success: ${entry_count} entries (${total_hours} hours) submitted to BambooHR."
  exit 0
else
  echo "Error: BambooHR API returned HTTP ${http_code}" >&2
  echo "Response: $body" >&2
  exit 1
fi
