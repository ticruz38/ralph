#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [options] [max_iterations]
#
# Options:
#   --worktree    Run Ralph in a git worktree under ~/worktrees/
#   --force       With --worktree: delete existing worktree and branch, start fresh

set -e

# Parse arguments
USE_WORKTREE=false
FORCE_WORKTREE=false
MAX_ITERATIONS=10

for arg in "$@"; do
  case $arg in
    --worktree)
      USE_WORKTREE=true
      shift
      ;;
    --force)
      FORCE_WORKTREE=true
      shift
      ;;
    -*)
      echo "Unknown option: $arg"
      exit 1
      ;;
    *)
      # Assume it's the max_iterations
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS=$arg
      fi
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGINAL_DIR="$(pwd)"
PRD_FILE="$ORIGINAL_DIR/prd.json"
BRANCH_NAME=""

# Worktree mode: create worktree and switch to it
if [ "$USE_WORKTREE" = true ]; then
  # Check prd.json exists
  if [ ! -f "$PRD_FILE" ]; then
    echo "Error: prd.json not found in $ORIGINAL_DIR"
    exit 1
  fi
  
  # Get branch name from prd.json
  BRANCH_NAME=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -z "$BRANCH_NAME" ] || [ "$BRANCH_NAME" = "null" ]; then
    echo "Error: branchName not found in prd.json"
    exit 1
  fi
  
  # Get project name from directory
  PROJECT_NAME=$(basename "$ORIGINAL_DIR")
  
  # Sanitize branch name for folder (replace / with -)
  BRANCH_FOLDER=$(echo "$BRANCH_NAME" | sed 's|/|-|g')
  WORKTREE_FOLDER="${PROJECT_NAME}-${BRANCH_FOLDER}"
  WORKTREE_DIR="$HOME/worktrees/$WORKTREE_FOLDER"
  
  echo "Worktree mode enabled"
  echo "  Branch: $BRANCH_NAME"
  echo "  Worktree: $WORKTREE_DIR"
  
  # Create worktrees directory
  mkdir -p "$HOME/worktrees"
  
  # Handle force mode: delete existing worktree and branch
  if [ "$FORCE_WORKTREE" = true ] && [ -d "$WORKTREE_DIR" ]; then
    echo "  Force mode: removing existing worktree..."
    git worktree remove "$WORKTREE_DIR" 2>/dev/null || rm -rf "$WORKTREE_DIR"
    git worktree prune
    # Also delete the branch to start fresh
    if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
      echo "  Force mode: deleting branch $BRANCH_NAME..."
      git branch -D "$BRANCH_NAME" 2>/dev/null || true
    fi
  fi
  
  # Create worktree if it doesn't exist
  if [ -d "$WORKTREE_DIR" ]; then
    echo "  Worktree already exists, reusing..."
  else
    # Ensure branch exists (create from current branch if needed)
    if ! git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
      echo "  Creating branch $BRANCH_NAME..."
      git branch "$BRANCH_NAME"
    fi
    
    echo "  Creating worktree..."
    git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
  fi
  
  # Copy prd.json to worktree if needed
  # If prd.json exists, only keep it if branch names match
  if [ -f "$WORKTREE_DIR/prd.json" ]; then
    WORKTREE_BRANCH=$(jq -r '.branchName // empty' "$WORKTREE_DIR/prd.json" 2>/dev/null || echo "")
    if [ "$WORKTREE_BRANCH" = "$BRANCH_NAME" ]; then
      echo "  Reusing existing prd.json (branch matches: $BRANCH_NAME)"
    else
      echo "  Branch mismatch! Worktree has: $WORKTREE_BRANCH, need: $BRANCH_NAME"
      echo "  Copying new prd.json..."
      cp "$PRD_FILE" "$WORKTREE_DIR/"
    fi
  else
    echo "  Copying prd.json to worktree..."
    cp "$PRD_FILE" "$WORKTREE_DIR/"
  fi
  
  # Change to worktree directory
  cd "$WORKTREE_DIR"
  echo "  Switched to worktree"
  echo ""
fi

# From here, WORK_DIR is the current directory (either original or worktree)
WORK_DIR="$(pwd)"
PRD_FILE="$WORK_DIR/prd.json"
PROGRESS_FILE="$WORK_DIR/progress.txt"
ARCHIVE_DIR="$WORK_DIR/archive"
LAST_BRANCH_FILE="$WORK_DIR/.last-branch"
LOG_DIR="$WORK_DIR/logs"

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

# Create logs directory
mkdir -p "$LOG_DIR" || {
  echo "Error: Failed to create logs directory: $LOG_DIR"
  exit 1
}

echo "Starting Ralph (Kimi Code CLI) - Max iterations: $MAX_ITERATIONS"
echo "Working directory: $WORK_DIR"
echo "Logs directory: $LOG_DIR"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS (Kimi)"
  echo "═══════════════════════════════════════════════════════"
  
  # Determine which story will be worked on (first incomplete)
  STORY_ID=$(jq -r '[.userStories[] | select(.passes != true)] | first | .id' "$PRD_FILE" 2>/dev/null || echo "unknown")
  if [ -z "$STORY_ID" ] || [ "$STORY_ID" = "null" ]; then
    STORY_ID="cleanup"
  fi
  
  TIMESTAMP=$(date +%H%M%S)
  LOG_FILE="$LOG_DIR/${STORY_ID}-${TIMESTAMP}.log"
  
  # Run kimi with the ralph prompt
  # Full output saved to log file, only status shown in console
  echo "  Story: $STORY_ID"
  echo "  Log: $LOG_FILE"
  if kimi --yolo --thinking --work-dir "$WORK_DIR" --prompt "$(cat "$SCRIPT_DIR/prompt.md")" > "$LOG_FILE" 2>&1; then
    echo "  ✓ Story $STORY_ID completed successfully"
  else
    echo "  ✗ Story $STORY_ID exited with error (check $LOG_FILE)"
  fi
  # Verify log file was created
  if [ ! -f "$LOG_FILE" ]; then
    echo "  ⚠ Warning: Log file was not created"
  fi
  
  # Verify actual completion by checking prd.json
  if [ -f "$PRD_FILE" ]; then
    INCOMPLETE=$(jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE" 2>/dev/null || echo "1")
    if [ "$INCOMPLETE" -eq 0 ]; then
      echo ""
      echo "✅ All stories complete! ($i iterations)"
      
      if [ "$USE_WORKTREE" = true ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════"
        echo "  Worktree Summary"
        echo "═══════════════════════════════════════════════════════"
        echo "  Location: $WORK_DIR"
        echo "  Branch:   $BRANCH_NAME"
        echo ""
        echo "  Files available:"
        echo "    - prd.json      (story status)"
        echo "    - progress.txt  (learnings from each iteration)"
        echo "    - logs/         (detailed logs from each story)"
        echo ""
        echo "  Next steps:"
        echo "    1. Review the work:"
        echo "       cd $WORK_DIR"
        echo "       cat progress.txt"
        echo ""
        echo "    2. Push the branch:"
        echo "       git -C $WORK_DIR push origin $BRANCH_NAME"
        echo ""
        echo "    3. Or merge locally:"
        echo "       cd $ORIGINAL_DIR"
        echo "       git merge $BRANCH_NAME"
        echo ""
        echo "    4. Clean up when done:"
        echo "       git worktree remove $WORK_DIR"
        echo "       rm -rf $WORK_DIR"
        echo "═══════════════════════════════════════════════════════"
      fi
      
      exit 0
    fi
  fi
  
  echo "  Waiting 2 seconds before next iteration..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."

if [ "$USE_WORKTREE" = true ]; then
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Worktree Summary (Incomplete)"
  echo "═══════════════════════════════════════════════════════"
  echo "  Location: $WORK_DIR"
  echo "  Branch:   $BRANCH_NAME"
  echo ""
  echo "  The work is incomplete but progress has been made."
  echo "  Check the worktree for details."
  echo ""
  echo "  Files available:"
  echo "    - prd.json      (check which stories are incomplete)"
  echo "    - progress.txt  (learnings and blockers)"
  echo "    - logs/         (detailed error logs)"
  echo ""
  echo "  Next steps:"
  echo "    1. Investigate the worktree:"
  echo "       cd $WORK_DIR"
  echo "       cat progress.txt"
  echo "       ls logs/"
  echo ""
  echo "    2. Continue working in the worktree:"
  echo "       cd $WORK_DIR"
  echo "       # make fixes, then commit"
  echo ""
  echo "    3. Or run ralph again with more iterations:"
  echo "       cd $ORIGINAL_DIR"
  echo "       ralph --worktree [higher_number]"
  echo ""
  echo "    4. Push partial progress:"
  echo "       git -C $WORK_DIR push origin $BRANCH_NAME"
  echo ""
  echo "    5. Clean up when done:"
  echo "       git worktree remove $WORK_DIR"
  echo "       rm -rf $WORK_DIR"
  echo "═══════════════════════════════════════════════════════"
fi

exit 1
