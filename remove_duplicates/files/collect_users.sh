#!/bin/bash

set +e

# ============================================
# CONFIGURATION
# ============================================
INSTANCE_ID=""
START_USER=1              # First user position to collect
END_USER=10000            # Last user position to collect
PARALLEL_PROCESSES=8      # Number of parallel workers
OUTPUT_FOLDER="./duplicate_users_output"
MASTER_FILE="$OUTPUT_FOLDER/all_users_master.json"
COLLECTION_LOG="$OUTPUT_FOLDER/collection_log_$(date +%Y%m%d_%H%M%S).log"
SKIP_EXISTING=true        # Skip users already in master file

# ============================================
# FUNCTIONS
# ============================================

mkdir -p "$OUTPUT_FOLDER" 2>/dev/null

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$COLLECTION_LOG"
}

error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# Initialize master file if it doesn't exist
initialize_master_file() {
    if [ ! -f "$MASTER_FILE" ]; then
        echo "[]" > "$MASTER_FILE"
        log_message "✓ Created new master file: $MASTER_FILE"
    else
        EXISTING_COUNT=$(jq '. | length' "$MASTER_FILE" 2>/dev/null || echo "0")
        log_message "✓ Master file exists with $EXISTING_COUNT users"
    fi
}

# Check if user ID already exists in master file
user_exists_in_master() {
    local USER_ID=$1
    if [ "$SKIP_EXISTING" = true ]; then
        jq -e --arg id "$USER_ID" '.[] | select(.Id == $id)' "$MASTER_FILE" &>/dev/null
        return $?
    else
        return 1
    fi
}

# ============================================
# MAIN EXECUTION
# ============================================

log_message "=========================================="
log_message "Amazon Connect User Data Collection"
log_message "=========================================="
log_message "Range: Users $START_USER to $END_USER"
log_message "Workers: $PARALLEL_PROCESSES"
log_message "Instance ID: $INSTANCE_ID"

# Validate range
if [ $START_USER -lt 1 ]; then
    error_exit "START_USER must be >= 1"
fi

if [ $END_USER -lt $START_USER ]; then
    error_exit "END_USER must be >= START_USER"
fi

log_message "Step 1: Checking prerequisites"
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed"
fi
if ! command -v jq &> /dev/null; then
    error_exit "jq is not installed"
fi
log_message "✓ Prerequisites verified"

log_message "Step 2: Verifying AWS credentials"
aws sts get-caller-identity &> /dev/null || error_exit "AWS credentials not configured or invalid"
log_message "✓ AWS credentials verified"

log_message "Step 3: Initializing master file"
initialize_master_file

log_message "Step 4: Fetching user list from instance: $INSTANCE_ID"
USERS_JSON=$(aws connect list-users --instance-id "$INSTANCE_ID" --output json 2>&1)
if [ $? -ne 0 ]; then
    error_exit "Failed to fetch users: $USERS_JSON"
fi

TOTAL_USERS=$(echo "$USERS_JSON" | jq -r '.UserSummaryList | length')
log_message "✓ Total users in instance: $TOTAL_USERS"

# Validate range against total users
if [ $END_USER -gt $TOTAL_USERS ]; then
    log_message "⚠ Warning: END_USER ($END_USER) exceeds total users ($TOTAL_USERS)"
    END_USER=$TOTAL_USERS
    log_message "✓ Adjusted END_USER to $END_USER"
fi

USERS_TO_COLLECT=$((END_USER - START_USER + 1))
log_message "✓ Will collect $USERS_TO_COLLECT users (positions $START_USER to $END_USER)"

ESTIMATED_TIME=$((USERS_TO_COLLECT / PARALLEL_PROCESSES / 60))
log_message "✓ Estimated time: ~$ESTIMATED_TIME minutes"

log_message "Step 5: Creating temporary working directory"
TEMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
    error_exit "Failed to create temporary directory"
fi
log_message "✓ Temporary directory: $TEMP_DIR"

# Extract the range of users we want to collect
echo "$USERS_JSON" | jq ".UserSummaryList[$((START_USER - 1)):$END_USER]" > "$TEMP_DIR/target_users.json"

TARGET_COUNT=$(jq '. | length' "$TEMP_DIR/target_users.json")
log_message "✓ Extracted $TARGET_COUNT users for this range"

# Split into chunks for parallel processing
CHUNK_SIZE=$((TARGET_COUNT / PARALLEL_PROCESSES))
if [ $CHUNK_SIZE -lt 1 ]; then
    CHUNK_SIZE=1
    PARALLEL_PROCESSES=$TARGET_COUNT
    log_message "⚠ Adjusted workers to $PARALLEL_PROCESSES (not enough users for more)"
fi

log_message "Step 6: Splitting into $PARALLEL_PROCESSES chunks"
log_message "  Chunk size: ~$CHUNK_SIZE users per worker"

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    CHUNK_START=$((i * CHUNK_SIZE))
    
    if [ $i -eq $((PARALLEL_PROCESSES - 1)) ]; then
        CHUNK_END=$((TARGET_COUNT))
    else
        CHUNK_END=$(((i + 1) * CHUNK_SIZE))
    fi
    
    CHUNK_FILE="$TEMP_DIR/chunk_${i}.json"
    jq ".[$CHUNK_START:$CHUNK_END]" "$TEMP_DIR/target_users.json" > "$CHUNK_FILE"
    
    CHUNK_COUNT=$(jq '. | length' "$CHUNK_FILE")
    log_message "  Chunk $((i + 1)): $CHUNK_COUNT users"
done

log_message "Step 7: Launching $PARALLEL_PROCESSES parallel workers"

WORKER_PIDS=()

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    WORKER_LOG="$OUTPUT_FOLDER/collection_worker_${i}_$(date +%Y%m%d_%H%M%S).log"
    WORKER_OUTPUT="$TEMP_DIR/worker_${i}_output.json"
    
    # Initialize empty JSON array for worker
    echo "[]" > "$WORKER_OUTPUT"
    
    (
        CHUNK_FILE="$TEMP_DIR/chunk_${i}.json"
        WORKER_TEMP="$TEMP_DIR/worker_${i}_temp.json"
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Started" >> "$WORKER_LOG"
        
        CHUNK_USERS=$(jq '. | length' "$CHUNK_FILE")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Processing $CHUNK_USERS users" >> "$WORKER_LOG"
        
        PROCESSED=0
        SKIPPED=0
        FAILED=0
        
        jq -r '.[].Id' "$CHUNK_FILE" 2>/dev/null | while read USER_ID; do
            PROCESSED=$((PROCESSED + 1))
            
            # Check if user already exists in master file
            if user_exists_in_master "$USER_ID"; then
                SKIPPED=$((SKIPPED + 1))
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ⊗ User $PROCESSED/$CHUNK_USERS - Skipped (already exists: $USER_ID)" >> "$WORKER_LOG"
                continue
            fi
            
            # Fetch user details
            USER_DETAIL=$(aws connect describe-user --user-id "$USER_ID" --instance-id "$INSTANCE_ID" --output json 2>&1)
            if [ $? -eq 0 ]; then
                # Extract username and email for better logging
                USERNAME=$(echo "$USER_DETAIL" | jq -r '.User.Username // "N/A"')
                EMAIL=$(echo "$USER_DETAIL" | jq -r '.User.IdentityInfo.Email // "N/A"')
                
                echo "$USER_DETAIL" | jq -c '.User' >> "$WORKER_TEMP" 2>/dev/null
                
                # Log progress for EVERY user with details
                PERCENT=$((PROCESSED * 100 / CHUNK_USERS))
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ✓ User $PROCESSED/$CHUNK_USERS ($PERCENT%) - $USERNAME ($EMAIL)" >> "$WORKER_LOG"
            else
                FAILED=$((FAILED + 1))
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ✗ User $PROCESSED/$CHUNK_USERS - FAILED (ID: $USER_ID)" >> "$WORKER_LOG"
            fi
        done
        
        # Convert temp file to proper JSON array
        if [ -f "$WORKER_TEMP" ]; then
            jq -s '.' "$WORKER_TEMP" > "$WORKER_OUTPUT" 2>/dev/null
            rm -f "$WORKER_TEMP"
        fi
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Completed - Processed: $PROCESSED, Skipped: $SKIPPED, Failed: $FAILED" >> "$WORKER_LOG"
    ) &
    
    WORKER_PIDS+=($!)
    log_message "  Worker $((i + 1)) launched (PID: ${WORKER_PIDS[$i]})"
done

log_message "Step 8: Monitoring workers"
log_message "  Workers are collecting user data in parallel..."
log_message "  Progress logged for EVERY user extracted"
log_message "  Check worker logs: $OUTPUT_FOLDER/collection_worker_*.log"

FAILED_WORKERS=0

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    wait ${WORKER_PIDS[$i]}
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        log_message "  ✓ Worker $((i + 1)) completed successfully"
    else
        log_message "  ⚠ Worker $((i + 1)) failed with exit code $EXIT_CODE"
        FAILED_WORKERS=$((FAILED_WORKERS + 1))
    fi
done

if [ $FAILED_WORKERS -gt 0 ]; then
    log_message "⚠ Warning: $FAILED_WORKERS worker(s) encountered errors"
fi

log_message "Step 9: Merging worker results"
MERGED_FILE="$TEMP_DIR/merged_new_users.json"

# Merge all worker outputs
jq -s 'add | map(select(. != null))' "$TEMP_DIR"/worker_*_output.json > "$MERGED_FILE" 2>&1
if [ $? -ne 0 ]; then
    error_exit "Failed to merge worker results"
fi

NEW_USERS_COUNT=$(jq '. | length' "$MERGED_FILE")
log_message "✓ Successfully collected $NEW_USERS_COUNT new users"

log_message "Step 10: Appending to master file"

# Read existing master file
EXISTING_USERS=$(cat "$MASTER_FILE")

# Merge with new users
echo "$EXISTING_USERS" | jq --slurpfile new "$MERGED_FILE" '. + $new[0]' > "$TEMP_DIR/updated_master.json"

if [ $? -eq 0 ]; then
    # Verify the updated file is valid JSON
    UPDATED_COUNT=$(jq '. | length' "$TEMP_DIR/updated_master.json" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Create backup of old master file
        if [ -f "$MASTER_FILE" ]; then
            cp "$MASTER_FILE" "$MASTER_FILE.backup" 2>/dev/null
        fi
        
        # Replace master file with updated version
        mv "$TEMP_DIR/updated_master.json" "$MASTER_FILE"
        log_message "✓ Master file updated successfully"
        log_message "✓ Total users in master file: $UPDATED_COUNT"
    else
        error_exit "Updated master file is not valid JSON"
    fi
else
    error_exit "Failed to merge with master file"
fi

log_message "Step 11: Generating collection summary"

SUMMARY_FILE="$OUTPUT_FOLDER/collection_summary.txt"

cat > "$SUMMARY_FILE" << EOF
========================================
Collection Summary
========================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Instance ID: $INSTANCE_ID
Range Collected: Users $START_USER to $END_USER
Total Users in Instance: $TOTAL_USERS
New Users Collected: $NEW_USERS_COUNT
Total Users in Master File: $UPDATED_COUNT

Master File: $MASTER_FILE
Collection Log: $COLLECTION_LOG
========================================

Progress:
Total Users: $TOTAL_USERS
Collected: $UPDATED_COUNT ($((UPDATED_COUNT * 100 / TOTAL_USERS))%)
Remaining: $((TOTAL_USERS - UPDATED_COUNT))

Next Steps:
- To collect more users, adjust START_USER and END_USER
- To analyze for duplicates, run: ./analyze_duplicates.sh
========================================
EOF

cat "$SUMMARY_FILE" | tee -a "$COLLECTION_LOG"

log_message "Step 12: Cleaning up temporary files"
rm -rf "$TEMP_DIR" 2>/dev/null
log_message "✓ Temporary files removed"

log_message "=========================================="
log_message "Collection Complete!"
log_message "=========================================="
log_message "Range processed: $START_USER to $END_USER"
log_message "New users collected: $NEW_USERS_COUNT"
log_message "Total in master file: $UPDATED_COUNT"
log_message "Progress: $((UPDATED_COUNT * 100 / TOTAL_USERS))% of $TOTAL_USERS users"
log_message "Master file: $MASTER_FILE"
log_message "Summary: $SUMMARY_FILE"
log_message "=========================================="

exit 0
