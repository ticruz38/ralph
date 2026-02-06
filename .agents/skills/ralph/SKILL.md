---
name: ralph
description: Use Ralph autonomous AI agent loop to execute PRDs. Ralph runs Kimi Code CLI repeatedly until all PRD user stories are complete. Use when you need to break down a complex feature into incremental stories, execute them autonomously, and track progress across multiple agent iterations. Triggers on phrases like "ralph this", "use ralph", "run ralph", "convert to ralph format", or when working with prd.json files.
---

# Ralph Autonomous Agent Loop

Ralph is a bash loop that spawns fresh Kimi Code CLI instances to work through a PRD iteratively until all stories are complete.

## Quick Start

```bash
# Create a PRD and convert to ralph format first
# Then run ralph:
./ralph.sh --worktree 20
```

## How Ralph Works

1. Reads `prd.json` for user stories and branch name
2. Spawns Kimi with `prompt.md` instructions
3. Each iteration works on ONE incomplete story
4. Updates `prd.json` to mark stories as `passes: true`
5. Appends learnings to `progress.txt`
6. Repeats until all stories complete or max iterations reached

## Key Files

| File | Purpose |
|------|---------|
| `prd.json` | Input - defines stories, priorities, branch name |
| `progress.txt` | Persistent memory - learnings for future iterations |
| `logs/` | Detailed logs per iteration |
| `.last-branch` | Tracks current branch to detect PRD switches |

## Running Ralph

### Basic Usage

```bash
# Run in current directory (modifies working directory)
./ralph.sh 15

# Run in git worktree (recommended - isolated workspace)
./ralph.sh --worktree 15

# Force recreate worktree (start fresh)
./ralph.sh --worktree --force 15
```

Arguments:
- `[number]` - Max iterations (default: 10)
- `--worktree` - Run in isolated git worktree under `~/worktrees/`
- `--force` - With `--worktree`: delete existing worktree and branch

### Worktree Mode (Recommended)

Worktree mode creates an isolated workspace:
- Creates branch from `prd.json` `branchName` field
- Sets up worktree at `~/worktrees/{project}-{branch}/`
- Copies `prd.json` to worktree
- All work happens in worktree, original repo untouched

After completion:
```bash
# Review work
cd ~/worktrees/{project}-{branch}
cat progress.txt

# Push branch
git push origin {branch-name}

# Clean up
git worktree remove ~/worktrees/{project}-{branch}
```

## Creating PRDs for Ralph

Ralph requires `prd.json` format. See [references/prd-format.md](references/prd-format.md) for full schema and examples.

### Converting Existing PRDs

To convert a markdown PRD to ralph format, use the user-level `ralph` skill:
```
User: Convert this PRD to ralph format: [paste PRD]
```
This loads `~/.config/agents/skills/ralph/` (the PRD converter skill) to generate `prd.json`.

### Quick prd.json Example

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Feature description",
  "userStories": [
    {
      "id": "US-001",
      "title": "Story title",
      "description": "As a user...",
      "acceptanceCriteria": ["Criteria 1", "Criteria 2"],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Monitoring Progress

Check progress without stopping Ralph:
```bash
# View current status
tail -f progress.txt

# Check which stories remain
jq '.userStories[] | select(.passes != true) | .id' prd.json

# View latest log
ls -t logs/ | head -1 | xargs cat
```

## Iteration Lifecycle

Each Ralph iteration:
1. Reads `prd.json` and `progress.txt`
2. Identifies highest priority incomplete story
3. Runs Kimi with `prompt.md` instructions
4. Kimi implements ONE story, runs quality checks
5. Commits with message: `feat: [Story ID] - [Story Title]`
6. Updates `prd.json` → `passes: true` for that story
7. Appends learnings to `progress.txt`
8. Logs saved to `logs/{story-id}-{timestamp}.log`

## When Ralph Stops

**Success**: All stories have `passes: true`
**Max iterations**: Hit iteration limit with incomplete stories
**Error**: Kimi exits with error (check logs)

## Common Patterns

### Resume after interruption
```bash
# Ralph detects incomplete stories and continues
./ralph.sh --worktree 10
```

### Switch to different PRD
Change `branchName` in `prd.json`. Ralph archives previous run and starts fresh.

### Debug failed iteration
```bash
# Find the failing story log
ls -t logs/ | head -5

# Check what went wrong
cat logs/US-001-143022.log
```

## Requirements

- `kimi` CLI installed and in PATH
- `jq` installed (for JSON processing)
- Git repository (for worktree mode)
- `prd.json` in working directory
