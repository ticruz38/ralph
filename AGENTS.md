# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs Amp repeatedly until all PRD items are complete. Each iteration is a fresh Amp instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph (from your project that has prd.json)
./ralph.sh [max_iterations]
```

## Key Files

- `ralph.sh` - The bash loop that spawns fresh Amp instances
- `prompt.md` - Instructions given to each Amp instance during implementation
- `retrospective.md` - Instructions for the final retrospective analysis
- `prd.json.example` - Example PRD format
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh Amp instance with clean context
- Memory persists via git history, `progress.txt`, and `prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations

## Retrospective Analysis

When Ralph completes (or reaches max iterations), it automatically runs a **retrospective analysis** before closing:

1. Spawns one final agent iteration with `retrospective.md` prompt
2. The agent reads all logs from `logs/` and analyzes `progress.txt`
3. Surfaces findings to `RETROSPECTIVE.md`:
   - **Impossible/deferred items** - Features that couldn't be implemented
   - **Challenging implementations** - Stories that took multiple attempts
   - **Difficult compromises** - Trade-offs and workarounds made
   - **Key design decisions** - Important architectural choices
   - **Critical patterns & gotchas** - Recurring issues discovered

This gives you a high-level summary of what happened under the hood across all iterations.
