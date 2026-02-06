# PRD JSON Format Reference

Schema for `prd.json` files used by Ralph.

## Full Schema

```json
{
  "project": "string - Project name",
  "branchName": "string - Git branch name (e.g., 'ralph/feature-name')",
  "description": "string - Short feature description",
  "userStories": [
    {
      "id": "string - Unique identifier (e.g., 'US-001')",
      "title": "string - Short story title",
      "description": "string - User story format (As a X, I want Y...)",
      "acceptanceCriteria": ["string array - Specific verifiable criteria"],
      "priority": "number - Lower = higher priority (1, 2, 3...)",
      "passes": "boolean - Ralph sets true when complete",
      "notes": "string - Optional implementation notes"
    }
  ]
}
```

## Field Details

### Top Level

| Field | Required | Description |
|-------|----------|-------------|
| `project` | Yes | Project identifier |
| `branchName` | Yes | Git branch for work. Prefix with `ralph/` for organization |
| `description` | Yes | One-line feature summary |
| `userStories` | Yes | Array of story objects |

### User Story Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique ID, format: `US-###` or feature prefix |
| `title` | Yes | Concise action-oriented title |
| `description` | Yes | User story format recommended |
| `acceptanceCriteria` | Yes | Verifiable checklist for completion |
| `priority` | Yes | Execution order (1 = first) |
| `passes` | Yes | Start as `false`, Ralph updates to `true` |
| `notes` | No | Implementation hints or context |

## Best Practices

### Story Sizing
- Stories should be completable in one agent context window
- Break large features into 3-7 stories
- Each story should produce a working, commitable state

### Priority Ordering
- Priority 1: Foundation/infrastructure (database, models)
- Priority 2: Core functionality
- Priority 3: UI/UX improvements
- Priority 4+: Polish, edge cases, extras

### Acceptance Criteria
- Be specific and verifiable
- Include quality gates: "Typecheck passes", "Tests pass"
- For UI: "Verify in browser using dev-browser skill"

### Branch Naming
- Use `ralph/` prefix: `ralph/task-priority`
- Use kebab-case: `ralph/add-auth-flow`
- Include issue numbers if applicable: `ralph/feat-123-login`

## Example

```json
{
  "project": "TaskManager",
  "branchName": "ralph/task-priority",
  "description": "Add priority levels to tasks",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add priority field to database",
      "description": "As a developer, I need to store task priority.",
      "acceptanceCriteria": [
        "Add priority column: 'high' | 'medium' | 'low'",
        "Generate and run migration",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": "Use enum type"
    },
    {
      "id": "US-002",
      "title": "Display priority on task cards",
      "description": "As a user, I want to see task priority.",
      "acceptanceCriteria": [
        "Colored badge per priority level",
        "Visible without interaction",
        "Typecheck passes",
        "Verify in browser"
      ],
      "priority": 2,
      "passes": false,
      "notes": "Red=high, yellow=medium, gray=low"
    }
  ]
}
```

## Validation

Before running Ralph, verify your PRD:

```bash
# Check JSON is valid
jq . prd.json > /dev/null && echo "Valid JSON"

# List incomplete stories by priority
jq -r '.userStories | sort_by(.priority) | .[] | select(.passes != true) | "\(.priority): \(.id) - \(.title)"' prd.json

# Verify all required fields present
jq 'if has("project") and has("branchName") and has("userStories") then "Valid" else "Missing required fields" end' prd.json
```
