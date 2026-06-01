---
name: timesheet
description: |
  Interactive BambooHR timesheet entry builder. Chat about your day,
  curate entries with projects/tasks/hours, then submit after approval.
  Triggers on: "timesheet", "log hours", "log time", "track time",
  "bamboohr", "submit timesheet", "what did I work on".
argument-hint: [add|show|calendar|csv] [descripción o ruta de archivo]
allowed-tools: Read, Bash, AskUserQuestion, ToolSearch
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

After setup (or if `config.json` already exists), read it to load the available projects and tasks.

To refresh the project/task list: `bash .claude/skills/timesheet/scripts/init.sh --refresh`

## Argument Handling

| Argument | Action |
|----------|--------|
| `show` or `--show` | Jump to **Show Entries** (skip conversational flow) |
| `calendar` or `cal` | Jump to **Calendar Import** — fetch today's events from Google Calendar and map to entries |
| `calendar yesterday` | Import yesterday's calendar events |
| `calendar 2026-02-10` | Import events for a specific date |
| `add <text>` | Pre-populate Step 1 with the provided text |
| `csv /path/to/file.csv` | Read team weekly CSV → filter Fer's entries → show table for approval |
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
6. Clean up the temp file

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

## CSV Import

When the user says `csv /path/to/file.csv` or uses the `csv` argument followed by a file path, import timesheet entries from the team's weekly Google Sheets CSV export.

**Context:** The CSV is a shared team spreadsheet (Fernando, Omar, Nico). Only Fernando's entries must be imported — identified by `"Fer"` in column 13.

### Column Layout (0-indexed)

| Index | Name        | Use                       |
|-------|-------------|---------------------------|
| 3     | Total       | Hours in `H:MM:SS` format |
| 5     | Description | Note for BambooHR         |
| 6     | Pjt         | Project name              |
| 7     | Type        | Task name                 |
| 13    | Person      | Filter: only `Fer`        |

### Parsing Rules

1. **Skip the header row** (row index 0, containing "Time In", "Time Out", etc.)
2. **Filter by person:** Only process rows where column 13 = `"Fer"` (case-insensitive, trim whitespace)
3. **Skip incomplete rows:** Skip if Description (col 5), Pjt (col 6), or Type (col 7) is empty or blank
4. **Convert hours:** Parse column 3 from `H:MM:SS` to decimal:
   - Formula: `hours + minutes/60 + seconds/3600`
   - `1:00:00` → 1.0, `0:15:00` → 0.25, `1:15:00` → 1.25
   - Skip the row if result ≤ 0 or the value is unparseable
5. **Map project name:** Match column 6 to a project in `config.json` (case-insensitive, trim whitespace):
   - `"Fair Trade Usa"` → `"Fair Trade USA"` (ID 17)
   - `"Modelit - Research and Development"` → `"Modelit - Research and Development"` (ID 39)
   - For other names, find the closest match in `config.json`
6. **Map task name:** Match column 7 to a task under the matched project in `config.json` (case-insensitive, trim):
   - `"QA Testing"` → ID 149 (under Fair Trade USA)
   - `"Project Meetings - Internal"` → ID 148 (under Fair Trade USA)
   - `"Process Research and Improvement"` → ID 466 (under Modelit - Research and Development)
7. **Ambiguity:** If a project or task has no clear match in `config.json`, use `AskUserQuestion` to let the user pick from available options.

### How It Works

1. **Read the file:** Use the `Read` tool to load the CSV from the provided path.
2. **Parse and filter:** Apply all parsing rules above to extract Fernando's entries only.
3. **Confirm the date:** Ask: "¿Estas entradas son para hoy, {fecha}?" If not, ask for the correct date.
4. **Show entries table:** Display the same table format as Step 3 of the Conversational Flow.
5. **Iterate and submit:** Continue with Steps 4 and 5 of the normal conversational flow.

### Example

```
You: /timesheet csv /Users/fernando.masci/timesheet/TemplateSheet/Weekly time sheet - Today.csv

Agent: Leyendo CSV: Weekly time sheet - Today.csv
Entradas encontradas para Fer (2026-02-26):

| # | Fecha      | Proyecto                        | Tarea                       | Horas | Nota                              |
|---|------------|---------------------------------|-----------------------------|-------|-----------------------------------|
| 1 | 2026-02-26 | Fair Trade USA                  | QA Testing                  | 1.0   | Test Execution [TD-11253]...      |
| 2 | 2026-02-26 | Modelit - Research and Dev.     | Process Research and Imp.   | 1.25  | QA BambooHR - Gemini CLI by Emi   |

Total: 2.25 horas

¿Querés cambiar algo o lo enviamos?
```

## Show Entries

When the user says "show", "show timesheet", or uses the `show` argument:

Run: `bash .claude/skills/timesheet/scripts/submit.sh --show`

This fetches and displays the current week's entries from BambooHR.

For a specific date range:
`bash .claude/skills/timesheet/scripts/submit.sh --show --start 2026-02-10 --end 2026-02-14`

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
└── scripts/
    ├── init.sh           # Bootstrap: discover projects/tasks from BambooHR API
    └── submit.sh         # Standalone: submit entries or show existing
```
