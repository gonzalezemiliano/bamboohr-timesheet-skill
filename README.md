# BambooHR Timesheets Skill

Conversational BambooHR timesheet builder. Describe your day in natural language, curate entries with projects/tasks/hours, then submit after approval.

Works with any AI agent (Claude Code, Gemini, Codex, OpenCode) or standalone via shell scripts.

## Quick Start

```bash
# 1. Set environment variables (add to ~/.zshrc or ~/.bashrc)
export BAMBOOHR_API_KEY="your-api-key"
export BAMBOOHR_COMPANY_DOMAIN="your-company"
export BAMBOOHR_EMPLOYEE_ID="123"
source ~/.zshrc

# 2. Run first-time setup (auto-discovers projects and tasks)
.claude/skills/timesheet/scripts/init.sh

# 3. Use the skill (in Claude Code)
/timesheet                    # Start conversational flow
/timesheet show               # Show current week's entries
/timesheet 4h feature dev     # Pre-populate with description
```

## Setup

### Prerequisites

- **bash**, **curl**, **jq** — standard CLI tools (no Python, no npm)
- A BambooHR account with API access and time tracking enabled

### Step 1: Get Your BambooHR API Key

1. Log in to BambooHR (`https://your-company.bamboohr.com`)
2. Click your profile photo (top right) > **API Keys**
3. Click **Add New Key**, give it a name (e.g., "Timesheet CLI"), and copy the key

### Step 2: Find Your Employee ID

Your employee ID is the number in the URL when you view your BambooHR profile:

```
https://your-company.bamboohr.com/employees/121/...
                                              ^^^
                                              This is your employee ID
```

### Step 3: Set Environment Variables

Add the following to your shell profile (`~/.zshrc` for macOS, `~/.bashrc` for Linux):

```bash
# BambooHR Timesheet Skill
export BAMBOOHR_API_KEY="your-api-key-here"
export BAMBOOHR_COMPANY_DOMAIN="your-company"       # just the subdomain, not the full URL
export BAMBOOHR_EMPLOYEE_ID="121"                    # your numeric employee ID
```

Then reload your shell:

```bash
# If using zsh (macOS default)
source ~/.zshrc

# If using bash
source ~/.bashrc
```

Verify the variables are set:

```bash
echo $BAMBOOHR_API_KEY        # should print your key
echo $BAMBOOHR_COMPANY_DOMAIN # should print your subdomain
echo $BAMBOOHR_EMPLOYEE_ID    # should print your ID
```

### Step 4: Run First-Time Setup

From your workspace root, run `init.sh` to auto-discover your available projects and tasks:

```bash
.claude/skills/timesheet/scripts/init.sh
```

This queries the BambooHR API and writes `config.json` with your projects and tasks. Example output:

```
Fetching projects and tasks for employee 121...

config.json written to: .claude/skills/timesheet/config.json
  Employee ID: 121
  Projects:    6
  Tasks:       68

Available projects:
  - Project X (23 tasks)
  - Modelit - General (10 tasks)
  ...
```

To refresh after projects or tasks change in BambooHR:

```bash
.claude/skills/timesheet/scripts/init.sh --refresh
```

## Installing in an AI Agent

### Claude Code

Copy the `timesheet/` directory into your Claude Code skills folder:

```bash
# If you already have .claude/skills/ in your project
cp -r timesheet/ /path/to/your/project/.claude/skills/timesheet/

# Or if setting up from scratch
mkdir -p /path/to/your/project/.claude/skills/
cp -r timesheet/ /path/to/your/project/.claude/skills/timesheet/
```

Claude Code automatically discovers skills in `.claude/skills/*/SKILL.md`. Once the directory is in place, you can use it immediately:

```
/timesheet              # log hours
/timesheet show         # view current week
```

### Gemini CLI

Gemini CLI natively supports the same `SKILL.md` format via the [Agent Skills](https://geminicli.com/docs/cli/skills/) standard.

**1. Install Gemini CLI:**

```bash
brew install gemini-cli
```

**2. Authenticate:**

```bash
gemini
# Follow the browser prompt to sign in with your Google account
# Free tier: 60 requests/min, 1,000 requests/day with Gemini 2.5 Pro
```

**3. Create the `GEMINI.md` file (optional but recommended):**

Create a `GEMINI.md` file in your project root to give Gemini persistent context. This is the equivalent of Claude Code's `CLAUDE.md`:

```bash
cat > GEMINI.md << 'EOF'
# Project Context

## Available Skills

This project includes custom skills in `.gemini/skills/`. Use them when relevant.

## Environment

BambooHR integration is available via the `timesheet` skill.
Ensure BAMBOOHR_API_KEY, BAMBOOHR_COMPANY_DOMAIN, and BAMBOOHR_EMPLOYEE_ID
are set in your shell environment before using it.
EOF
```

**4. Install the skill:**

Gemini CLI discovers skills in `.gemini/skills/` (project-scoped) or `~/.gemini/skills/` (global). Copy the timesheet skill:

```bash
# Project-scoped (for this project only)
mkdir -p .gemini/skills/timesheet/scripts
cp .claude/skills/timesheet/SKILL.md .gemini/skills/timesheet/SKILL.md
cp .claude/skills/timesheet/scripts/*.sh .gemini/skills/timesheet/scripts/
cp .claude/skills/timesheet/config.json .gemini/skills/timesheet/config.json
chmod +x .gemini/skills/timesheet/scripts/*.sh

# Or global (available in all projects)
mkdir -p ~/.gemini/skills/timesheet/scripts
cp .claude/skills/timesheet/SKILL.md ~/.gemini/skills/timesheet/SKILL.md
cp .claude/skills/timesheet/scripts/*.sh ~/.gemini/skills/timesheet/scripts/
cp .claude/skills/timesheet/config.json ~/.gemini/skills/timesheet/config.json
chmod +x ~/.gemini/skills/timesheet/scripts/*.sh
```

**5. Use it:**

```bash
gemini
> log my timesheet for today
> show my timesheet
```

Gemini CLI auto-discovers the skill by its `name` and `description` in the SKILL.md frontmatter. When it detects a matching task, it activates the skill and loads the full instructions.

### Other AI Agents (Codex, OpenCode, etc.)

The skill instructions are in `SKILL.md` — a plain markdown file any AI agent can read. To use it with any agent that supports shell commands:

1. Copy the `timesheet/` directory to wherever your agent reads skill/tool definitions
2. Point your agent to `SKILL.md` as a system prompt or instruction file
3. Ensure the agent can run `bash` commands (needed to execute the scripts)
4. Ensure the 3 environment variables are set in the agent's shell environment

The `SKILL.md` file follows the [Agent Skills](https://agentskills.io) open standard, which is supported by Claude Code, Gemini CLI, and other compatible agents. It contains all the instructions the agent needs: conversational flow, project/task mapping logic, submission steps, and error handling.

### No AI Agent (Standalone)

The scripts work without any AI agent at all:

```bash
# Show this week's entries
.claude/skills/timesheet/scripts/submit.sh --show

# Show a specific date range
.claude/skills/timesheet/scripts/submit.sh --show --start 2026-02-10 --end 2026-02-14

# Dry run (validate without submitting)
.claude/skills/timesheet/scripts/submit.sh --dry-run /tmp/entries.json

# Submit entries from a JSON file
.claude/skills/timesheet/scripts/submit.sh /tmp/entries.json
```

**JSON input format:**
```json
{
  "hours": [
    {
      "employeeId": 121,
      "date": "2026-02-13",
      "hours": 4.0,
      "projectId": 15,
      "taskId": 121,
      "note": "PTA-2300 feature development"
    }
  ]
}
```

Project and task IDs can be found in `config.json` after running `init.sh`.

## Usage Examples

### Conversational Flow (with AI agent)

```
You: /timesheet
Agent: What did you work on today?

You: 4 hours on JIRA-1234 code review, 2 hours troubleshooting with engineers,
     1.5 hours feature dev, 30 min DSU

Agent: Here's what I mapped:
| # | Date       | Project              | Task                        | Hours | Note              |
|---|------------|----------------------|-----------------------------|-------|-------------------|
| 1 | 2026-02-13 | Project X | Code Review                 | 4.0   | JIRA-1234          |
| 2 | 2026-02-13 | Project X | Troubleshooting Meeting     | 2.0   | Engineer support   |
| 3 | 2026-02-13 | Project X | Feature Development         | 1.5   | Feature dev        |
| 4 | 2026-02-13 | Project X | Project Meetings - Internal | 0.5   | DSU                |
Total: 8.0 hours

Want to change anything, add more, or submit?

You: change #2 to 1.5 hours
Agent: (updates table, shows new total of 7.5 hours)

You: submit
Agent: Submitted 4 entries (7.5 hours) to BambooHR.
```

### Show Current Week

```
You: /timesheet show
Agent: (fetches and displays your entries for Mon-Fri of the current week)
```

### Add a Single Entry

```
You: log another hour as Troubleshooting with this description: "JIRA-1234 investigation"
Agent: (submits a single 1.0h entry)
```

## File Structure

```
.claude/skills/timesheet/
├── SKILL.md              # AI agent instructions (any agent can read this)
├── README.md             # This file
├── config.json           # Auto-generated by init.sh (not committed to git)
└── scripts/
    ├── init.sh           # Bootstrap: discover projects/tasks from BambooHR API
    └── submit.sh         # Submit entries or show existing ones
```

## API Reference

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/v1/time_tracking/employees/{id}/projects` | Discover available projects and tasks |
| GET | `/api/v1/time_tracking/timesheet_entries?employeeIds=X&start=Y&end=Z` | Fetch existing entries |
| POST | `/api/v1/time_tracking/hour_entries/store` | Submit new hour entries |

All endpoints use Basic auth (`$BAMBOOHR_API_KEY:x`) at `https://{BAMBOOHR_COMPANY_DOMAIN}.bamboohr.com`.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Error: Missing required environment variables` | Set all 3 env vars in `~/.zshrc` and run `source ~/.zshrc` |
| `Error: jq is required but not installed` | Install with `brew install jq` (macOS) or `apt install jq` (Linux) |
| `Error: BambooHR API returned HTTP 401` | Check your API key is correct and not expired |
| `Error: BambooHR API returned HTTP 403` | Your account may not have time tracking permissions |
| `config.json already exists` | Use `--refresh` flag: `./scripts/init.sh --refresh` |
| Skill not appearing in Claude Code | Ensure `SKILL.md` is at `.claude/skills/timesheet/SKILL.md` |
| Scripts not executable | Run `chmod +x scripts/init.sh scripts/submit.sh` |

## Google Calendar Integration (Optional)

The `/timesheet calendar` command imports events from Google Calendar and maps them to timesheet entries automatically. This requires the [Google Calendar MCP server](https://github.com/nspady/google-calendar-mcp) (`@cocal/google-calendar-mcp` on [npm](https://www.npmjs.com/package/@cocal/google-calendar-mcp)).

### Step 1: Create Google Cloud OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com) and create a new project (e.g., "Calendar MCP")
2. Navigate to **APIs & Services > Library**, search for **Google Calendar API**, and click **Enable**
3. Go to **APIs & Services > OAuth consent screen**:
   - Select **Internal** user type
   - Fill in the required fields (app name, support email, developer contact)
   - Add scope: `https://www.googleapis.com/auth/calendar.events`
   - Add your Google email as a test user
   - Wait 2-3 minutes for propagation
4. Go to **APIs & Services > Credentials**:
   - Click **Create Credentials > OAuth client ID**
   - Select **Desktop app** as the application type
   - Download the credentials JSON file

### Step 2: Save the Credentials File

Save the downloaded JSON file to a known location. Recommended path:

```bash
# macOS / Linux
~/.config/gcp-oauth.keys.json
```

The file should look like this:

```json
{
  "installed": {
    "client_id": "YOUR_CLIENT_ID.apps.googleusercontent.com",
    "client_secret": "YOUR_CLIENT_SECRET",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "redirect_uris": ["http://localhost"]
  }
}
```

### Step 3: Set the Environment Variable

Add the following to your shell profile (`~/.zshrc` for macOS, `~/.bashrc` for Linux):

```bash
# Google Calendar MCP
export GOOGLE_OAUTH_CREDENTIALS="$HOME/.config/gcp-oauth.keys.json"
```

Then reload your shell:

```bash
source ~/.zshrc   # macOS
source ~/.bashrc  # Linux
```

### Step 4: Authenticate

Run the auth command to complete the OAuth flow. This opens a browser where you sign in with your Google account:

```bash
npx @cocal/google-calendar-mcp auth
```

This saves authentication tokens to `~/.config/google-calendar-mcp/tokens.json`.

> **Note:** If you're using Google Cloud in "test" mode (not published), tokens expire after 7 days. You'll need to re-run the auth command when they expire.

### Step 5: Add to Your MCP Configuration

Add the Google Calendar MCP server to your `.mcp.json`:

```json
{
  "mcpServers": {
    "google-calendar": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@cocal/google-calendar-mcp"],
      "env": {
        "GOOGLE_OAUTH_CREDENTIALS": "/path/to/gcp-oauth.keys.json"
      }
    }
  }
}
```

> **Tip:** You can omit the `env` block if you already have `GOOGLE_OAUTH_CREDENTIALS` set in your shell profile (Step 3). The MCP server inherits environment variables from the parent shell.

### Step 6: Use It

```bash
/timesheet calendar              # Import today's events
/timesheet calendar yesterday    # Import yesterday's events
/timesheet calendar 2026-02-10   # Import events for a specific date
```

The agent fetches your calendar events, maps them to BambooHR projects/tasks based on event titles, and presents a table for you to review and edit before submitting.

### Troubleshooting

| Problem | Solution |
|---------|----------|
| `Authentication tokens are no longer valid` | Re-run `npx @cocal/google-calendar-mcp auth` |
| Auth command fails with missing credentials | Ensure `GOOGLE_OAUTH_CREDENTIALS` env var is set and points to your `gcp-oauth.keys.json` |
| Google Calendar MCP tools not found | Verify the `google-calendar` entry exists in `.mcp.json` and restart your AI agent |
| No events returned | Check you're querying the correct calendar (defaults to `primary`) |
| Token expires every 7 days | Your Google Cloud app is in test mode. Publish it for longer-lived tokens, or just re-auth weekly |

## Why a Skill?

This is implemented as a **skill** (`.claude/skills/`) rather than a **command** (`.claude/commands/`) because:

- **Agent-agnostic**: Works with Claude Code, Gemini, Codex, OpenCode, or any AI that reads markdown
- **Standalone scripts**: The bash scripts work without any AI agent at all
- **No framework dependencies**: Pure bash + curl + jq — runs anywhere
- **Bypasses broken MCP**: The BambooHR MCP server's time tracking tools have incorrect URL patterns; this skill calls the API directly via curl
