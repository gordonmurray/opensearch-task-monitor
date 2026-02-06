#!/usr/bin/env bash

# Requirements: curl, jq, fzf
# Usage: ./opensearch_task_manager.sh

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

cancel_tasks_loop() {
  while true; do
    # Fetch latest _tasks response (all tasks, not just search)
    response=$(curl -sk -u "$USER:$PASS" "$HOST/_tasks?detailed=true")
    
    # Show all running tasks for monitoring
    echo -e "\n=== All Running Tasks ==="
    echo "$response" | jq -r '.nodes[].tasks | to_entries[] | 
      select(.value.action != "cluster:monitor/tasks/lists" and .value.action != "cluster:monitor/tasks/lists[n]") |
      "[\(if .value.cancellable then "CANCELLABLE" else "PROTECTED  " end)] \(.value.action) | \(.value.running_time_in_nanos // 0 | . / 1000000 | floor)ms | \(.value.description // .key)"' 2>/dev/null
    
    task_count=$(echo "$response" | jq '[.nodes[].tasks | to_entries[] | select(.value.action != "cluster:monitor/tasks/lists" and .value.action != "cluster:monitor/tasks/lists[n]")] | length' 2>/dev/null)
    
    if [ "$task_count" = "0" ] || [ -z "$task_count" ]; then
      echo "No active tasks (cluster is idle)"
    fi
    echo "============================"

    mapfile -t tasks < <(echo "$response" | jq -r '
      .nodes[].tasks | to_entries[] | select(.value.cancellable == true) |
      "\(.key) | \(.value.action) | \(.value.description) | running: \(.value.running_time_in_nanos / 1000000 | floor) ms"
    ')

    if [ ${#tasks[@]} -eq 0 ]; then
      echo -e "\nNo cancellable tasks found."
      sleep 5
      return
    fi

    selected=$(printf "%s\n" "${tasks[@]}" | \
      fzf --multi \
          --preview='echo {} | fold -s -w $(tput cols)' \
          --preview-window=wrap \
          --header="Select tasks to cancel (Tab to select, Enter to confirm, Esc to skip)" \
          --bind ctrl-a:toggle-all)

    if [ -z "$selected" ]; then
      echo -e "\nNo tasks selected. Returning to main loop..."
      return
    fi

    timestamp=$(date +"%Y%m%d_%H%M%S")
    mkdir -p killed_tasks_logs

    fresh_response=$(curl -sk -u "$USER:$PASS" "$HOST/_tasks?detailed=true")

    while IFS= read -r line; do
      task_id=$(echo "$line" | cut -d'|' -f1 | xargs)
      echo "Cancelling task $task_id..."
      cancel_output=$(curl -sk -u "$USER:$PASS" -XPOST "$HOST/_tasks/$task_id/_cancel")

      if echo "$cancel_output" | jq -e '.node_failures[]? | select(.caused_by.reason | test("not found"))' > /dev/null; then
        echo "Task $task_id already completed. Skipping."
      else
        echo "$cancel_output" | jq
        full_task=$(echo "$fresh_response" | jq ".nodes[].tasks[\"$task_id\"]")
        echo "$full_task" | jq > "killed_tasks_logs/${timestamp}_$task_id.json"
      fi
      echo "---"
    done <<< "$selected"
  done
}

while true; do
  clear
  echo -e "\nCurrent search thread pool status:"
  curl -sk -u "$USER:$PASS" "$HOST/_cat/thread_pool/search?v&h=node,active,queue,rejected"

  cancel_tasks_loop

  echo -e "\nReloading ..."
  sleep 2

done
