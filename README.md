# OpenSearch Task Manager

Real-time monitoring and management toolkit for OpenSearch cluster operations - track queries, identify slow operations, and cancel problematic tasks interactively.

## Quick Start

1. Copy `config.sh.example` to `config.sh`
2. Update `config.sh` with your OpenSearch credentials
3. Run `./opensearch_task_manager.sh` for interactive monitoring

## Requirements
- curl
- jq  
- fzf (for interactive mode)

## Tools Included

### 1. Interactive Task Manager (`opensearch_task_manager.sh`)
Terminal UI to monitor all OpenSearch tasks with the option to cancel multiple tasks interactively.

**Features:**
- Shows all running tasks (not just search queries)
- Interactive selection with fzf
- Multi-select for bulk cancellation
- Displays thread pool status
- Logs cancelled tasks to `killed_tasks_logs/`

**Usage:**
```bash
./opensearch_task_manager.sh
```

![Task manager screenshot](images/task_manager.png)

### 2. Query Logger (`opensearch_query_logger.sh`)
Continuously logs all OpenSearch queries and tasks for monitoring and analysis.

**Features:**
- Non-intrusive monitoring (doesn't cancel tasks)
- Logs all application activity
- Daily log rotation
- Two output formats:
  - JSONL format for data analysis (`query_logs/queries_YYYYMMDD.jsonl`)
  - Human-readable summary (`query_logs/queries_YYYYMMDD_summary.log`)
- Real-time console output
- Automatic deduplication

**Usage:**
```bash
./opensearch_query_logger.sh
```

**Output Example:**
```
TIME      ACTION               | TASK_ID                                  |    RUNTIME | DESCRIPTION
-----------------------------------------------------------------------------------------------------------
[14:23:05] indices:data/read/se | bbVmgJC1RDmjFrgnx4zKMA:295128915        |       45ms | search on index[products]
```

### 3. Automated Task Killer (`automated_opensearch_task_manager.sh`)
Automatically cancels long-running tasks that exceed a configured threshold.

**Features:**
- Runs continuously in the background
- Configurable threshold (default: 10 seconds)
- Logs cancelled tasks with timestamps
- No user interaction required

**Usage:**
```bash
./automated_opensearch_task_manager.sh
```

## Configuration

1. Copy the example configuration:
```bash
cp config.sh.example config.sh
```

2. Edit `config.sh` with your OpenSearch connection details:
```bash
export OPENSEARCH_HOST="https://localhost:8443"
export OPENSEARCH_USER="admin"
export OPENSEARCH_PASS="your_password_here"
export CHECK_INTERVAL=2           # Optional: polling interval in seconds
export THRESHOLD_MS=10000         # Optional: auto-cancel threshold in milliseconds
```

## Log Files

- **Cancelled tasks**: `killed_tasks_logs/` - JSON files with full task details
- **Query logs**: `query_logs/` - Daily rotating logs of all queries
