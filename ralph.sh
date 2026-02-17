#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [options] [max_iterations|command]
#
# Options:
#   -a, --agent       Agent to use: pi, kimi (default: kimi)
#   --model           Model to use (e.g., gemini-2.5-flash, claude-sonnet-4)
#   --thinking        Thinking level: off, minimal, low, medium, high, xhigh (default: medium for pi)
#   -d, --daemon      Run Ralph in daemon mode (background process)
#   --worktree        Run Ralph in a git worktree under ~/worktrees/
#   --force           With --worktree: delete existing worktree and branch, start fresh
#
# Commands:
#   status        Check if daemon is running (for current branch's prd.json)
#   stop          Stop the running daemon (for current branch's prd.json)
#   list          List all running Ralph daemons across all projects/branches
#
# Multiple concurrent daemons:
#   You can run one daemon per branch. Ralph uses branchName from prd.json to
#   isolate PID files: /tmp/ralph-{project}-{branch}.pid
#
# Examples:
#   ./ralph.sh 20                    # Run 20 iterations in foreground
#   ./ralph.sh -d 50                 # Start daemon with 50 iterations
#   ./ralph.sh -d --worktree         # Daemon mode with worktree
#   ./ralph.sh status                # Check daemon status
#   ./ralph.sh stop                  # Stop the daemon
#   ./ralph.sh list                  # List all running daemons

set -e

# Parse arguments
USE_WORKTREE=false
FORCE_WORKTREE=false
DAEMON_MODE=false
MAX_ITERATIONS=10
COMMAND=""

for arg in "$@"; do
  case $arg in
    -h|--help)
      sed -n '/^#!/! { /^#/{ s/^# //; s/^#//; p; }; }' "$0" | head -n 26
      exit 0
      ;;
    -a|--agent)
      AGENT="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --thinking)
      THINKING="$2"
      shift 2
      ;;
    -d|--daemon)
      DAEMON_MODE=true
      shift
      ;;
    --worktree)
      USE_WORKTREE=true
      shift
      ;;
    --force)
      FORCE_WORKTREE=true
      shift
      ;;
    status|stop|list)
      COMMAND="$arg"
      shift
      ;;
    -*)
      echo "Unknown option: $arg"
      echo "Use -h or --help for usage"
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

# Set defaults
AGENT="${AGENT:-kimi}"
MODEL="${MODEL:-}"
THINKING="${THINKING:-}"

# Get project name for PID file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use current working directory for project name, not script location
# This allows running ralph from any project directory
PROJECT_NAME=$(basename "$(pwd)")

# For daemon mode, we need the branch name from prd.json to allow per-branch daemons
# This must happen early so status/stop commands know which daemon to target
BRANCH_FROM_PRD=""
if [ -f "prd.json" ]; then
  BRANCH_FROM_PRD=$(jq -r '.branchName // empty' prd.json 2>/dev/null || echo "")
fi

# Build PID/log file names - per-branch to allow multiple concurrent daemons
if [ -n "$BRANCH_FROM_PRD" ]; then
  # Sanitize branch name for filename (replace / with -)
  BRANCH_SAFE=$(echo "$BRANCH_FROM_PRD" | sed 's|/|-|g')
  PID_FILE="/tmp/ralph-${PROJECT_NAME}-${BRANCH_SAFE}.pid"
  DAEMON_LOG="/tmp/ralph-${PROJECT_NAME}-${BRANCH_SAFE}.log"
else
  # Fallback if no prd.json or no branchName
  PID_FILE="/tmp/ralph-${PROJECT_NAME}.pid"
  DAEMON_LOG="/tmp/ralph-${PROJECT_NAME}.log"
fi

# Handle daemon commands
if [ "$COMMAND" = "status" ]; then
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
      echo "Ralph daemon is running (PID: $PID)"
      echo "  Project: $PROJECT_NAME"
      [ -n "$BRANCH_FROM_PRD" ] && echo "  Branch: $BRANCH_FROM_PRD"
      echo "  Daemon output: $DAEMON_LOG"
      echo "  Story logs: logs/ (in project directory)"
      exit 0
    else
      echo "Ralph daemon is not running (stale PID file: $PID_FILE)"
      rm -f "$PID_FILE"
      exit 1
    fi
  else
    echo "Ralph daemon is not running"
    [ -n "$BRANCH_FROM_PRD" ] && echo "  Branch: $BRANCH_FROM_PRD"
    exit 1
  fi
fi

if [ "$COMMAND" = "stop" ]; then
  if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
      echo "Stopping Ralph daemon (PID: $PID)..."
      [ -n "$BRANCH_FROM_PRD" ] && echo "  Branch: $BRANCH_FROM_PRD"
      kill "$PID"
      # Wait for process to terminate
      for i in {1..10}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
          break
        fi
        sleep 1
      done
      rm -f "$PID_FILE"
      echo "Ralph daemon stopped"
      exit 0
    else
      echo "Ralph daemon is not running (removing stale PID file)"
      rm -f "$PID_FILE"
      exit 1
    fi
  else
    echo "Ralph daemon is not running"
    [ -n "$BRANCH_FROM_PRD" ] && echo "  Branch: $BRANCH_FROM_PRD"
    exit 1
  fi
fi

if [ "$COMMAND" = "list" ]; then
  echo "Running Ralph daemons:"
  echo ""
  
  FOUND=0
  for pid_file in /tmp/ralph-*.pid; do
    # Check if file exists (handles case where no matches)
    [ -e "$pid_file" ] || continue
    
    pid=$(cat "$pid_file" 2>/dev/null || echo "")
    if [ -n "$pid" ] && ps -p "$pid" > /dev/null 2>&1; then
      # Extract project and branch from filename
      # Format: /tmp/ralph-{project}-{branch-with-dashes}.pid or /tmp/ralph-{project}.pid
      # Branch always starts with 'ralph-' after the project name
      basename=$(basename "$pid_file" .pid)
      # Remove 'ralph-' prefix
      rest=${basename#ralph-}
      
      # Check if there's a branch component (contains 'ralph-')
      if [[ "$rest" == *-ralph-* ]]; then
        # Extract project (everything before the last '-ralph-')
        project=$(echo "$rest" | sed 's/-ralph-.*$//')
        # Extract branch (everything after project, with dashes converted to slashes)
        branch=$(echo "$rest" | sed "s/^${project}-//" | sed 's/-/\//')
      elif [[ "$rest" == ralph-* ]]; then
        # Format: ralph-{branch} (no project prefix)
        project="(unknown)"
        branch=$(echo "$rest" | sed 's/-/\//')
      elif [[ "$rest" == *-* ]]; then
        # Old format without ralph- prefix in branch: project-branch-name
        project=$(echo "$rest" | cut -d'-' -f1)
        branch=$(echo "$rest" | cut -d'-' -f2- | sed 's/-/\//')
      else
        # No branch component
        project="$rest"
        branch="(no branch)"
      fi
      
      echo "  Project: $project"
      echo "  Branch:  $branch"
      echo "  PID:     $pid"
      echo "  Log:     ${pid_file%.pid}.log"
      echo ""
      FOUND=$((FOUND + 1))
    else
      # Clean up stale PID file
      rm -f "$pid_file"
    fi
  done
  
  if [ "$FOUND" -eq 0 ]; then
    echo "  No running Ralph daemons found"
  else
    echo "Total: $FOUND daemon(s) running"
  fi
  exit 0
fi

# Daemon mode: fork to background
if [ "$DAEMON_MODE" = true ]; then
  # Check if already running
  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
      echo "Ralph daemon is already running (PID: $OLD_PID)"
      echo "Use '$0 stop' to stop it first"
      exit 1
    else
      rm -f "$PID_FILE"
    fi
  fi
  
  echo "Starting Ralph daemon..."
  echo "  Project: $PROJECT_NAME"
  [ -n "$BRANCH_FROM_PRD" ] && echo "  Branch: $BRANCH_FROM_PRD"
  echo "  Agent: $AGENT"
  [ -n "$MODEL" ] && echo "  Model: $MODEL"
  [ -n "$THINKING" ] && echo "  Thinking: $THINKING"
  echo "  Iterations: $MAX_ITERATIONS"
  echo "  Daemon log: $DAEMON_LOG (status output only)"
  echo "  Story logs: logs/ (per-iteration details, in project dir)"
  
  # Build argument list for the child process
  CHILD_ARGS=()
  [ -n "$AGENT" ] && [ "$AGENT" != "kimi" ] && CHILD_ARGS+=("--agent" "$AGENT")
  [ -n "$MODEL" ] && CHILD_ARGS+=("--model" "$MODEL")
  [ -n "$THINKING" ] && CHILD_ARGS+=("--thinking" "$THINKING")
  [ "$USE_WORKTREE" = true ] && CHILD_ARGS+=("--worktree")
  [ "$FORCE_WORKTREE" = true ] && CHILD_ARGS+=("--force")
  CHILD_ARGS+=("$MAX_ITERATIONS")
  
  # Fork to background with nohup, redirect output, and capture PID
  nohup "$0" "${CHILD_ARGS[@]}" > "$DAEMON_LOG" 2>&1 &
  CHILD_PID=$!
  
  # Write PID file immediately
  echo $CHILD_PID > "$PID_FILE"
  
  # Give it a moment to start and check for early exit
  sleep 1
  if ! ps -p "$CHILD_PID" > /dev/null 2>&1; then
    echo "Ralph daemon failed to start (check $DAEMON_LOG)"
    rm -f "$PID_FILE"
    exit 1
  fi
  
  echo "Ralph daemon started (PID: $CHILD_PID)"
  echo "Use '$0 status' to check status"
  echo "Use '$0 stop' to stop"
  exit 0
fi

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
    
    # Archive logs directory if it exists and has content
    if [ -d "$LOG_DIR" ] && [ "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
      mv "$LOG_DIR" "$ARCHIVE_FOLDER/logs"
      echo "   Logs archived to: $ARCHIVE_FOLDER/logs"
    fi
    
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

echo "Starting Ralph (${AGENT}) - Max iterations: $MAX_ITERATIONS"
[ -n "$MODEL" ] && echo "  Model: ${MODEL}"
[ -n "$THINKING" ] && echo "  Thinking: ${THINKING}"
echo "Working directory: $WORK_DIR"
echo "Logs directory: $LOG_DIR"

# Set agent-specific flags and command
if [ "$AGENT" = "pi" ]; then
  # pi: use -p for non-interactive, --no-session for ephemeral
  AGENT_FLAGS="-p --no-session"
  [ -n "$MODEL" ] && AGENT_FLAGS="$AGENT_FLAGS --model $MODEL"
  [ -n "$THINKING" ] && AGENT_FLAGS="$AGENT_FLAGS --thinking $THINKING"
  AGENT_CMD="pi"
else
  # kimi: needs --yolo --thinking
  AGENT_FLAGS="--yolo --thinking"
  AGENT_CMD="kimi"
fi

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "═══════════════════════════════════════════════════════"
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($AGENT)"
  echo "═══════════════════════════════════════════════════════"
  
  # Determine which story will be worked on (first incomplete)
  STORY_ID=$(jq -r '[.userStories[] | select(.passes != true)] | first | .id' "$PRD_FILE" 2>/dev/null || echo "unknown")
  if [ -z "$STORY_ID" ] || [ "$STORY_ID" = "null" ]; then
    STORY_ID="cleanup"
  fi
  
  TIMESTAMP=$(date +%H%M%S)
  LOG_FILE="$LOG_DIR/${STORY_ID}-${TIMESTAMP}.log"
  
  # Run agent with the ralph prompt
  # Full output saved to log file, only status shown in console
  echo "  Story: $STORY_ID"
  echo "  Log: $LOG_FILE"
  # Build agent command based on agent type
  if [ "$AGENT" = "pi" ]; then
    # pi: prompt as argument, -p for non-interactive
    if $AGENT_CMD $AGENT_FLAGS "$(cat "$SCRIPT_DIR/prompt.md")" > "$LOG_FILE" 2>&1; then
      echo "  ✓ Story $STORY_ID completed successfully"
    else
      echo "  ✗ Story $STORY_ID exited with error (check $LOG_FILE)"
    fi
  else
    # kimi: uses --prompt flag
    if $AGENT_CMD $AGENT_FLAGS --work-dir "$WORK_DIR" --prompt "$(cat "$SCRIPT_DIR/prompt.md")" > "$LOG_FILE" 2>&1; then
      echo "  ✓ Story $STORY_ID completed successfully"
    else
      echo "  ✗ Story $STORY_ID exited with error (check $LOG_FILE)"
    fi
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
      
      # Run retrospective analysis
      echo ""
      echo "═══════════════════════════════════════════════════════"
      echo "  Running Retrospective Analysis"
      echo "═══════════════════════════════════════════════════════"
      echo "  Analyzing logs to surface challenges and decisions..."
      
      RETRO_LOG="$LOG_DIR/retrospective-$(date +%H%M%S).log"
      if [ "$AGENT" = "pi" ]; then
        if $AGENT_CMD $AGENT_FLAGS "$(cat "$SCRIPT_DIR/retrospective.md")" > "$RETRO_LOG" 2>&1; then
          echo "  ✓ Retrospective complete: $RETRO_LOG"
          if [ -f "$WORK_DIR/RETROSPECTIVE.md" ]; then
            echo "  ✓ Report written to: RETROSPECTIVE.md"
          fi
        else
          echo "  ⚠ Retrospective exited with error (check $RETRO_LOG)"
        fi
      else
        if $AGENT_CMD $AGENT_FLAGS --work-dir "$WORK_DIR" --prompt "$(cat "$SCRIPT_DIR/retrospective.md")" > "$RETRO_LOG" 2>&1; then
          echo "  ✓ Retrospective complete: $RETRO_LOG"
          if [ -f "$WORK_DIR/RETROSPECTIVE.md" ]; then
            echo "  ✓ Report written to: RETROSPECTIVE.md"
          fi
        else
          echo "  ⚠ Retrospective exited with error (check $RETRO_LOG)"
        fi
      fi
      
      if [ "$USE_WORKTREE" = true ]; then
        echo ""
        echo "═══════════════════════════════════════════════════════"
        echo "  Worktree Summary"
        echo "═══════════════════════════════════════════════════════"
        echo "  Location: $WORK_DIR"
        echo "  Branch:   $BRANCH_NAME"
        echo ""
        echo "  Files available:"
        echo "    - prd.json          (story status)"
        echo "    - progress.txt      (learnings from each iteration)"
        echo "    - logs/             (detailed logs from each story)"
        if [ -f "$WORK_DIR/RETROSPECTIVE.md" ]; then
        echo "    - RETROSPECTIVE.md  (challenges, compromises, design decisions)"
        fi
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

# Run retrospective even on incomplete runs (partial analysis)
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Running Retrospective Analysis (Partial)"
echo "═══════════════════════════════════════════════════════"
echo "  Analyzing logs to surface challenges and decisions..."

RETRO_LOG="$LOG_DIR/retrospective-$(date +%H%M%S).log"
if [ "$AGENT" = "pi" ]; then
  if $AGENT_CMD $AGENT_FLAGS "$(cat "$SCRIPT_DIR/retrospective.md")" > "$RETRO_LOG" 2>&1; then
    echo "  ✓ Retrospective complete: $RETRO_LOG"
    if [ -f "$WORK_DIR/RETROSPECTIVE.md" ]; then
      echo "  ✓ Report written to: RETROSPECTIVE.md"
    fi
  else
    echo "  ⚠ Retrospective exited with error (check $RETRO_LOG)"
  fi
else
  if $AGENT_CMD $AGENT_FLAGS --work-dir "$WORK_DIR" --prompt "$(cat "$SCRIPT_DIR/retrospective.md")" > "$RETRO_LOG" 2>&1; then
    echo "  ✓ Retrospective complete: $RETRO_LOG"
    if [ -f "$WORK_DIR/RETROSPECTIVE.md" ]; then
      echo "  ✓ Report written to: RETROSPECTIVE.md"
    fi
  else
    echo "  ⚠ Retrospective exited with error (check $RETRO_LOG)"
  fi
fi

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
  echo "    - prd.json          (check which stories are incomplete)"
  echo "    - progress.txt      (learnings and blockers)"
  echo "    - logs/             (detailed error logs)"
  if [ -f "$WORK_DIR/RETROSPECTIVE.md" ]; then
  echo "    - RETROSPECTIVE.md  (challenges, compromises, design decisions)"
  fi
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
