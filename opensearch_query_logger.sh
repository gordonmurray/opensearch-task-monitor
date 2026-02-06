#!/usr/bin/env bash

# Requirements: curl, jq
# Usage: ./opensearch_query_logger.sh

# Load configuration
if [ -f "config.sh" ]; then
    source config.sh
else
    echo "Error: config.sh not found. Copy config.sh.example to config.sh and update with your credentials."
    exit 1
fi

HOST="${OPENSEARCH_HOST:-https://localhost:8443}"
USER="${OPENSEARCH_USER:-admin}"
PASS="${OPENSEARCH_PASS}"
LOG_DIR="query_logs"
CHECK_INTERVAL=${CHECK_INTERVAL:-2}  # seconds between checks

# Create log directory
mkdir -p "$LOG_DIR"

# Generate log filename with date
LOG_FILE="$LOG_DIR/queries_$(date +%Y%m%d).jsonl"
SUMMARY_LOG="$LOG_DIR/queries_$(date +%Y%m%d)_summary.log"

# Track seen tasks to avoid duplicate logging
declare -A seen_tasks

echo "Starting OpenSearch query logger..."
echo "Logging to: $LOG_FILE"
echo "Summary: $SUMMARY_LOG"
echo "========================================="

log_task() {
    local task_id="$1"
    local task_json="$2"
    local timestamp="$3"
    
    # Log full JSON (JSONL format for easy parsing)
    echo "{\"timestamp\":\"$timestamp\",\"task_id\":\"$task_id\",\"task\":$task_json}" >> "$LOG_FILE"
    
    # Log human-readable summary
    local action=$(echo "$task_json" | jq -r '.action // "unknown"')
    local running_ms=$(echo "$task_json" | jq -r '(.running_time_in_nanos // 0) / 1000000 | floor')
    local description=$(echo "$task_json" | jq -r '.description // "no description"')
    local cancellable=$(echo "$task_json" | jq -r '.cancellable // false')
    local node=$(echo "$task_json" | jq -r '.node // "unknown"')
    
    echo "[$timestamp] Task: $task_id | Action: $action | Runtime: ${running_ms}ms | Cancellable: $cancellable | Node: $node | Desc: $description" >> "$SUMMARY_LOG"
    
    # Also output to console for real-time monitoring
    if [[ "$action" != "cluster:monitor/tasks/lists"* ]]; then
        printf "[%s] %-20s | %-40s | %8sms | %s\n" \
            "$(date +%H:%M:%S)" \
            "${action:0:20}" \
            "${task_id:0:40}" \
            "$running_ms" \
            "${description:0:50}"
    fi
}

# Print header
printf "\n%-9s %-20s | %-40s | %10s | %s\n" "TIME" "ACTION" "TASK_ID" "RUNTIME" "DESCRIPTION"
echo "-----------------------------------------------------------------------------------------------------------"

while true; do
    # Fetch current tasks
    response=$(curl -sk -u "$USER:$PASS" "$HOST/_tasks?detailed=true" 2>/dev/null)
    
    if [ -z "$response" ]; then
        echo "[$(date +%H:%M:%S)] ERROR: Failed to connect to OpenSearch" >&2
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    timestamp=$(date -Iseconds)
    
    # Process each task
    while IFS= read -r line; do
        if [ -n "$line" ]; then
            task_id=$(echo "$line" | jq -r '.key')
            task_json=$(echo "$line" | jq -c '.value')
            
            # Skip only our own monitoring tasks
            action=$(echo "$task_json" | jq -r '.action // ""')
            if [[ "$action" == "cluster:monitor/tasks/lists"* ]]; then
                continue
            fi
            
            # Check if we've seen this task before
            if [ -z "${seen_tasks[$task_id]}" ]; then
                seen_tasks[$task_id]=1
                log_task "$task_id" "$task_json" "$timestamp"
            fi
        fi
    done < <(echo "$response" | jq -c '.nodes[].tasks | to_entries[]' 2>/dev/null)
    
    # Clean up old entries from seen_tasks (older than 5 minutes)
    # This prevents memory growth but allows re-logging of recurring task IDs
    current_epoch=$(date +%s)
    for task in "${!seen_tasks[@]}"; do
        if (( current_epoch - seen_tasks[$task] > 300 )); then
            unset seen_tasks[$task]
        fi
    done
    
    # Update seen tasks with current timestamp
    for task in "${!seen_tasks[@]}"; do
        if [ "${seen_tasks[$task]}" = "1" ]; then
            seen_tasks[$task]=$current_epoch
        fi
    done
    
    sleep "$CHECK_INTERVAL"
done