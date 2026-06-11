# Project Context

This repository is the `timesheet` skill itself: SKILL.md at the root holds the
agent instructions, and `scripts/` holds the BambooHR API scripts. Team review
for managers is part of the same skill (`/timesheet review`, scripts/review.sh).

## Environment

BambooHR integration requires BAMBOOHR_API_KEY, BAMBOOHR_COMPANY_DOMAIN, and
BAMBOOHR_EMPLOYEE_ID to be set in your shell environment.
