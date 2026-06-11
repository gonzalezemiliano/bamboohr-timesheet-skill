---
name: timesheet
description: |
  Interactive BambooHR timesheet entry builder. Chat about your day,
  curate entries with projects/tasks/hours, then submit after approval.
  Also reviews your team's weekly timesheets (managers): validates hours
  and ticket IDs for direct reports, accounting for approved time off.
  Triggers on: "timesheet", "log hours", "log time", "track time",
  "bamboohr", "submit timesheet", "what did I work on", "review del equipo",
  "timesheet del equipo", "check team hours", "review team timesheets".
argument-hint: "[add|show|calendar|review] [natural language description] — use init --refresh to update projects"
allowed-tools: Read, Bash, Write, AskUserQuestion, ToolSearch
---

# Timesheet

> Conversational BambooHR timesheet builder.

## Purpose

Help the user log their daily work to BambooHR through natural conversation. The user describes what they worked on, you curate entries with correct projects, tasks, and hours, then submit after explicit approval.

This skill works with any AI agent that can read markdown and run shell commands.

## First-Time Setup

Before first use, check if `config.json` exists in the skill directory (`.claude/skills/timesheet/config.json`).

If it does NOT exist:
1. Verify the 3 required env vars are set: `BAMBOOHR_API_KEY`, `BAMBOOHR_COMPANY_DOMAIN`, `BAMBOOHR_EMPLOYEE_ID`
2. Run: `bash .claude/skills/timesheet/scripts/init.sh`
3. This auto-discovers projects and tasks from the BambooHR API and writes `config.json`

If any env var is missing, tell the user which ones they need to set and stop.

After setup (or if `config.json` already exists), read it to load the available projects and tasks. Check the `generatedAt` field — if it is older than 30 days, suggest running `init.sh --refresh` to pick up any new projects or tasks.

To refresh the project/task list: `bash .claude/skills/timesheet/scripts/init.sh --refresh`

## Argument Handling

| Argument | Action |
|----------|--------|
| `show` or `--show` | Jump to **Show Entries** (skip conversational flow) |
| `calendar` or `cal` | Jump to **Calendar Import** — fetch today's events from Google Calendar and map to entries |
| `calendar yesterday` | Import yesterday's calendar events |
| `calendar 2026-02-10` | Import events for a specific date |
| `add <text>` | Pre-populate Step 1 with the provided text |
| `review` or `--review` | Jump to **Team Review** — validate direct reports' timesheets for the previous week |
| `review --week 2026-05-25` | Team review for a specific week (Monday date) |
| `review --start 2026-06-01 --end 2026-06-10` | Team review for an arbitrary date range |
| `review --all` | Team review of every employee in the company (senior managers without direct reports) |
| `review --employees "Ana López, Juan Pérez"` | Team review of specific employees by name |
| No argument | Start the conversational flow from Step 1 |
| Natural language (e.g., "4h feature dev") | Treat as `add <text>` |

## Conversational Flow

### Step 1: Understand the Day

Ask the user what they worked on today (unless text was provided as an argument). Accept natural language descriptions like:

- "I spent 4 hours on PTA-2300 feature dev, 2 hours reviewing PRs, and had a 30 min DSU"
- "Mostly code reviews today, about 3 hours. Rest was meetings."
- "Feature development all day, 8 hours"

Parse the description into candidate entries with estimated hours, likely project, task category, and a short note.

### Step 2: Map to Projects and Tasks

For each candidate entry, match it to a project and task from `config.json`. Use keyword matching:

| User says | Likely task match |
|-----------|-------------------|
| "feature dev", "coding", "implementation" | Feature Development |
| "code review", "PR review", "reviewing" | Code Review |
| "meeting", "DSU", "standup", "sync" | Project Meetings - Internal |
| "bug fix", "debugging" | Bug Fixes |
| "testing", "unit tests" | Testing / QA |
| "documentation", "docs" | Documentation |
| "deployment", "release" | Deployment / Release |
| "planning", "grooming", "refinement" | Planning / Grooming |

If there's ambiguity, ask the user using AskUserQuestion.

When the same task name exists under multiple projects (e.g. "Project Meetings - Internal"), use the project that matches the work context. For client work, use the client's project. For internal Modelit activities, use the relevant Modelit project.

Use today's date unless the user specifies otherwise.

### Step 3: Build the Entries Table

Display a markdown table of all entries:

```
| # | Date       | Project              | Task                        | Hours | Note                    |
|---|------------|----------------------|-----------------------------|-------|-------------------------|
| 1 | 2026-02-13 | PeerNova - Cuneiform | Feature Development         | 4.0   | PTA-2300 implementation |
| 2 | 2026-02-13 | PeerNova - Cuneiform | Code Review                 | 2.0   | PR reviews              |
| 3 | 2026-02-13 | PeerNova - Cuneiform | Project Meetings - Internal | 0.5   | DSU                     |

Total: 6.5 hours
```

Ask: "Want to change anything, add more entries, or submit?"

### Step 4: Iterate

The user can refine entries conversationally:

- "Change #2 to 1.5 hours" — update hours on entry 2
- "Remove #3" — delete entry 3
- "Add 1 hour for interviews" — add a new entry
- "Change the note on #1 to 'API adapter work'" — update a note
- "That should be under Bug Fixes, not Feature Dev" — change task

After each change, redisplay the full table with updated totals.

If the user says "cancel", "start over", or "clear all", discard all entries and return to Step 1.

### Step 5: Submit

**Only submit after explicit user approval.** Trigger words: "submit", "looks good", "send it", "yes", "go ahead", "ship it", "lgtm".

To submit:

1. Read the employee ID from `config.json`
2. Build the JSON payload:
```json
{
  "hours": [
    {"employeeId": 121, "date": "2026-02-13", "hours": 4.0, "projectId": 15, "taskId": 121, "note": "PTA-2300 implementation"},
    {"employeeId": 121, "date": "2026-02-13", "hours": 2.0, "projectId": 15, "taskId": 119, "note": "PR reviews"}
  ]
}
```
3. Write the JSON to a temp file
4. Run: `bash .claude/skills/timesheet/scripts/submit.sh /tmp/timesheet-YYYY-MM-DD.json`
5. Report the result (success count, total hours)
6. Clean up the temp file — the AI is responsible for cleanup after submission (successful or failed). The script also cleans up via trap as a safety net.

## Calendar Import

When the user says "calendar", "cal", or uses the `calendar` argument, fetch events from Google Calendar and convert them into timesheet entries.

**Requires:** The `google-calendar` MCP server must be configured. Use `ToolSearch` to find and load the calendar tools (search for "google calendar").

### How It Works

1. **Load MCP tools:** Use `ToolSearch` with query `+google-calendar list` to discover the `list-events` tool.
2. **Determine the date:** Default to today. If the user says "yesterday", use yesterday's date. If they provide a specific date (e.g., "2026-02-10"), use that.
3. **Fetch events:** Call the `list-events` MCP tool with the target date as both start and end (full day range). Use the user's primary calendar.
4. **Filter events:** Exclude:
   - All-day events (these are usually reminders/OOO, not work tasks)
   - Declined events
   - Events shorter than 5 minutes
5. **Calculate hours:** For each event, compute duration from start/end times. Round to nearest 0.25h (15 min increments).
6. **Map to tasks:** Use the event title to guess the project/task from `config.json`:

   | Calendar event title contains | Likely task |
   |-------------------------------|-------------|
   | "DSU", "standup", "daily", "scrum" | Project Meetings - Internal |
   | "1:1", "one on one", "check-in" | Project Meetings - Internal |
   | "sprint", "planning", "grooming", "refinement", "retro" | Project Meetings - Internal |
   | "interview" | Interview (Modelit - General) |
   | "review", "PR" | Code Review |
   | "demo", "showcase" | Project Meetings - Client |
   | "leadership", "management", "directors" | Leadership Activities |
   | "pit stop", "all hands" | Project Meetings - Internal |
   | "sync", "alignment", "PO check" | Project Meetings - Internal |
   | "troubleshooting", "debugging", "investigation" | Troubleshooting Meeting |

   For events that don't match any pattern, default to "Project Meetings - Internal" and flag for user review.

7. **Merge similar events:** If multiple events map to the same project + task, offer to merge them into a single entry with combined hours.
8. **Present the table:** Show the entries table (same as Step 3 of Conversational Flow) with a note indicating these came from the calendar.
9. **Let the user edit:** The user can adjust, add non-calendar work (coding, reviews, etc.), remove entries, or change mappings before submitting. This flows into Step 4 (Iterate) of the normal conversational flow.

### Example

```
You: /timesheet calendar

Agent: Fetching your Google Calendar events for 2026-02-13...

Found 5 events:

| # | Date       | Project              | Task                        | Hours | Note (from calendar)         |
|---|------------|----------------------|-----------------------------|-------|------------------------------|
| 1 | 2026-02-13 | PeerNova - Cuneiform | Project Meetings - Internal | 0.5   | DSU                          |
| 2 | 2026-02-13 | PeerNova - Cuneiform | Project Meetings - Internal | 0.5   | PO Check                     |
| 3 | 2026-02-13 | PeerNova - Cuneiform | Troubleshooting Meeting     | 1.0   | ISV-6071 Troubleshooting     |
| 4 | 2026-02-13 | Modelit - General    | Interview                   | 1.0   | Technical Interview - Lucas  |
| 5 | 2026-02-13 | Modelit - General    | Interview                   | 1.0   | Technical Interview - Maxi   |

Calendar total: 4.0 hours

This only includes meetings. You probably also did coding, reviews, etc.
Want to add more entries, change anything, or submit as-is?
```

### Calendar Not Available

If the Google Calendar MCP tools are not found via ToolSearch, tell the user:

> Google Calendar MCP server is not configured. To enable calendar import, add the `google-calendar` MCP server to your `.mcp.json`. See the README for setup instructions.

Then fall back to the normal conversational flow (Step 1).

## Show Entries

When the user says "show", "show timesheet", or uses the `show` argument:

Run: `bash .claude/skills/timesheet/scripts/submit.sh --show`

This fetches and displays the current week's entries from BambooHR.

For a specific date range:
`bash .claude/skills/timesheet/scripts/submit.sh --show --start 2026-02-10 --end 2026-02-14`

## Team Review (Managers)

When the user says "review", "--review", "review del equipo", "check team hours", or similar, run the team timesheet review. It fetches the manager's direct reports from the BambooHR directory and validates that each person:

1. Logged the required hours for the period (approved time off is subtracted from the target)
2. Included a ticket ID (e.g., `TD-11615`) in the description of technical entries

The review covers the previous week by default, a specific week (`--week`), or an arbitrary date range (`--start`/`--end`). The hours target scales to the business days (Mon–Fri) in the range: `business days × weeklyHoursTarget / 5`.

**Scope:** by default only the manager's direct reports are reviewed. If the user is a senior manager with no direct reports (they manage managers), or explicitly asks to review the whole company, add `--all` to review every employee in the directory. If the user names specific people ("revisá las horas de Ana y Juan"), pass them as `--employees "Ana López, Juan Pérez"` — comma-separated display names as they appear in BambooHR (first and last name; case-insensitive, partial names work if unambiguous). If the script reports "No direct reports found", offer the user the `--all` option before rerunning. If it reports unmatched or ambiguous names, show the script's message and ask the user for the corrected names.

Validation rules live in `review-config.json` — separate from `config.json`, which init.sh auto-generates and overwrites on `--refresh`.

### Review Setup (first time only)

Check if `review-config.json` exists in the skill directory. If it does NOT exist, run the setup flow:

1. Ask the user (via AskUserQuestion):
   - How many hours per week should each person log? (default: 40)
   - Which project(s) does their team work on?
2. For each project, ask:
   - What is the ticket ID pattern? (e.g., `TD-[0-9]+`, `JIRA-[0-9]+`, `PTA-[0-9]+`)
   - Which task types require a ticket ID in the description? (let the user select from their BambooHR tasks or type them)
3. Write `review-config.json` using this structure:
```json
{
  "weeklyHoursTarget": 40,
  "projects": [
    {
      "name": "Project Name",
      "ticketPattern": "TD-[0-9]+",
      "mandatoryTasks": ["Bug Fixing", "Feature Development", "QA Testing"]
    }
  ]
}
```
4. Confirm the config with the user before saving.

If `review-config.json` already exists, skip setup and run the review directly.

### Running the Review

For the **previous week** (default):
```bash
bash .claude/skills/timesheet/scripts/review.sh
```

For a **specific week** (provide the Monday date):
```bash
bash .claude/skills/timesheet/scripts/review.sh --week 2026-05-25
```

For an **arbitrary date range**:
```bash
bash .claude/skills/timesheet/scripts/review.sh --start 2026-06-01 --end 2026-06-10
```

For **all employees in the company** (combinable with any date option):
```bash
bash .claude/skills/timesheet/scripts/review.sh --all --start 2026-06-01 --end 2026-06-10
```

For **specific employees by name** (combinable with any date option):
```bash
bash .claude/skills/timesheet/scripts/review.sh --employees "Ana López, Juan Pérez" --week 2026-05-25
```

The script prints a markdown report to stdout: the hours target for the range, a summary table (worked hours, time off, effective target, status per employee), and a per-employee entry detail. Display the output directly to the user — no additional formatting needed.

### Review Errors

| Error | Action |
|-------|--------|
| `review-config.json` missing | Run the Review Setup flow |
| No direct reports found | Offer to rerun with `--all` (reviews every employee) — confirm with the user first |
| Unmatched or ambiguous `--employees` name | Show the script's message and ask the user for the corrected full name |
| Invalid date range (`--start` after `--end`, bad format, no business days) | Show the script's error and ask for corrected dates |
| API error | Show HTTP status and response body |

## Error Handling

| Error | Action |
|-------|--------|
| Missing env vars | Tell the user which vars to set. Do not proceed. |
| `config.json` missing | Run `init.sh`. If that fails, report the API error. |
| Project/task not found in config | Ask the user to pick from available options using AskUserQuestion. |
| API returns non-201 on submit | Show the HTTP status and response body. Suggest retrying or checking entries. |
| Duplicate entries warning | If the user already has entries for the same date, warn before submitting. Use `--show` to check first. |
| Hours exceed 24 for a single day | Warn the user and ask for confirmation. |
| Hours are 0 or negative | Reject and ask for correction. |

## Critical Rules

1. **NEVER submit without explicit user approval** — always show the table and wait for confirmation
2. **NEVER hardcode employee IDs or project/task IDs** — always read from `config.json`
3. **NEVER guess projects or tasks** — if unsure, ask the user
4. **ALWAYS show a running total** — the user should see their daily total at a glance
5. **ALWAYS use the scripts** — `init.sh` for setup, `submit.sh` for API calls. Do not craft raw curl commands.

## File Structure

```
.claude/skills/timesheet/
├── SKILL.md              # This file (AI instructions)
├── config.json           # Auto-generated by init.sh (gitignored)
├── review-config.json    # Team review rules, created on review setup (gitignored)
└── scripts/
    ├── init.sh           # Bootstrap: discover projects/tasks from BambooHR API
    ├── submit.sh         # Standalone: submit entries or show existing
    └── review.sh         # Team review: validate direct reports' weekly entries
```
