---
name: timesheet-review
description: |
  Weekly team timesheet review for managers. Fetches direct reports from BambooHR,
  validates that each person logged the required hours and that technical entries
  include a ticket ID in the description. Configurable per project via config.json.
  Triggers on: "review del equipo", "reporte semanal", "timesheet del equipo",
  "check team hours", "revisá las horas", "review team timesheets".
argument-hint: [--week YYYY-MM-DD]
allowed-tools: Read, Bash, Write, AskUserQuestion
---

# Timesheet Review

> Weekly validation of your team's BambooHR timesheets.

## Purpose

Help managers verify every Monday that their direct reports:
1. Logged the required hours for the previous week
2. Included a ticket ID (e.g., `TD-11615`) in the description of technical entries

The skill reads validation rules from `config.json` — each project can have its own ticket ID pattern and list of task types that require one.

---

## First-Time Setup

Before the first review, check if `config.json` exists at `.claude/skills/timesheet-review/config.json`.

If it does NOT exist, run the setup flow:

1. Ask the user (via AskUserQuestion):
   - How many hours per week should each person log? (default: 40)
   - Which project(s) does their team work on?

2. For each project, ask:
   - What is the ticket ID pattern? (e.g., `TD-[0-9]+`, `JIRA-[0-9]+`, `PTA-[0-9]+`)
   - Which task types require a ticket ID in the description? (let the user select from their BambooHR tasks or type them)

3. Write `config.json` using this structure:
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

If `config.json` already exists, skip setup and go directly to **Running the Review**.

---

## Running the Review

Run the script for the **previous week** (default):
```bash
bash .claude/skills/timesheet-review/scripts/review.sh
```

For a **specific week** (provide the Monday date):
```bash
bash .claude/skills/timesheet-review/scripts/review.sh --week 2026-05-25
```

The script:
1. Reads `config.json` for validation rules
2. Fetches the manager's direct reports from BambooHR directory
3. Retrieves their timesheet entries for the week
4. Validates hours total and ticket IDs
5. Prints a markdown report to stdout

Display the output directly to the user — no additional formatting needed.

---

## Argument Handling

| Argument | Action |
|----------|--------|
| `--week YYYY-MM-DD` | Review the week starting on that Monday |
| No argument | Review the previous week (auto-detected) |

---

## Error Handling

| Error | Action |
|-------|--------|
| `config.json` missing | Run the setup flow |
| Missing env vars | Tell the user which vars to set (`BAMBOOHR_API_KEY`, `BAMBOOHR_COMPANY_DOMAIN`, `BAMBOOHR_EMPLOYEE_ID`) |
| No direct reports found | Inform the user — they may not be set as supervisor in BambooHR |
| API error | Show HTTP status and response body |

---

## File Structure

```
.claude/skills/timesheet-review/
├── SKILL.md              # This file (AI instructions)
├── config.json           # Validation rules per project (gitignored, created on setup)
└── scripts/
    └── review.sh         # Fetches entries, validates, prints report
```
