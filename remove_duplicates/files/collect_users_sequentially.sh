#!/bin/bash

set +e

# ============================================
# CONFIGURATION
# ============================================
INSTANCE_ID="a8fab42a-42a6-446d-b8fc-31ea25332f07"
START_USER=1              # First user position to collect
END_USER=100              # Last user position to collect
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
log_message "Amazon Connect User Data Collection (Sequential)"
log_message "=========================================="
log_message "Range: Users $START_USER to $END_USER"
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

ESTIMATED_TIME=$((USERS_TO_COLLECT))
log_message "✓ Estimated time: ~$((ESTIMATED_TIME / 60)) minutes $((ESTIMATED_TIME % 60)) seconds"

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

log_message "Step 6: Fetching detailed user information"
log_message "  Progress will be logged for EVERY user"

PROCESSED=0
SKIPPED=0
FAILED=0

# Read user IDs into array
mapfile -t USER_IDS < <(jq -r '.[].Id' "$TEMP_DIR/target_users.json" 2>/dev/null)

for USER_ID in "${USER_IDS[@]}"; do
    PROCESSED=$((PROCESSED + 1))
    
    # Check if user already exists in master file
    if user_exists_in_master "$USER_ID"; then
        SKIPPED=$((SKIPPED + 1))
        log_message "  ⊗ User $PROCESSED/$TARGET_COUNT - Skipped (already exists: $USER_ID)"
        continue
    fi
    
    # Fetch user details
    USER_DETAIL=$(aws connect describe-user --user-id "$USER_ID" --instance-id "$INSTANCE_ID" --output json 2>&1)
    if [ $? -eq 0 ]; then
        # Extract username and email for better logging
        USERNAME=$(echo "$USER_DETAIL" | jq -r '.User.Username // "N/A"')
        EMAIL=$(echo "$USER_DETAIL" | jq -r '.User.IdentityInfo.Email // "N/A"')
        
        echo "$USER_DETAIL" | jq -c '.User' >> "$TEMP_DIR/user_details.jsonl" 2>/dev/null
        
        # Log progress for EVERY user with details
        PERCENT=$((PROCESSED * 100 / TARGET_COUNT))
        log_message "  ✓ User $PROCESSED/$TARGET_COUNT ($PERCENT%) - $USERNAME ($EMAIL)"
    else
        FAILED=$((FAILED + 1))
        log_message "  ✗ User $PROCESSED/$TARGET_COUNT - FAILED (ID: $USER_ID)"
    fi
done

log_message "✓ User details fetching complete"
log_message "  Processed: $PROCESSED, Skipped: $SKIPPED, Failed: $FAILED"

log_message "Step 7: Processing collected user data"

NEW_USERS_FILE="$TEMP_DIR/new_users.json"

if [ -f "$TEMP_DIR/user_details.jsonl" ] && [ -s "$TEMP_DIR/user_details.jsonl" ]; then
    # Convert JSONL to JSON array
    jq -s '.' "$TEMP_DIR/user_details.jsonl" > "$NEW_USERS_FILE" 2>&1
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to process user data into JSON array"
    fi
    
    NEW_USERS_COUNT=$(jq '. | length' "$NEW_USERS_FILE")
    log_message "✓ Successfully processed $NEW_USERS_COUNT new user records"
else
    log_message "⚠ No new users to add (all were skipped or failed)"
    NEW_USERS_COUNT=0
    echo "[]" > "$NEW_USERS_FILE"
fi

log_message "Step 8: Appending to master file"

if [ $NEW_USERS_COUNT -gt 0 ]; then
    # Read existing master file
    EXISTING_USERS=$(cat "$MASTER_FILE")
    
    # Merge with new users
    echo "$EXISTING_USERS" | jq --slurpfile new "$NEW_USERS_FILE" '. + $new[0]' > "$TEMP_DIR/updated_master.json"
    
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
else
    UPDATED_COUNT=$(jq '. | length' "$MASTER_FILE")
    log_message "✓ Master file unchanged (no new users added)"
    log_message "✓ Total users in master file: $UPDATED_COUNT"
fi

log_message "Step 9: Generating collection summary"

SUMMARY_FILE="$OUTPUT_FOLDER/collection_summary.txt"

cat > "$SUMMARY_FILE" << EOF
========================================
Collection Summary
========================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Instance ID: $INSTANCE_ID
Range Collected: Users $START_USER to $END_USER
Processing Mode: Sequential (1 user at a time)

Results:
  Total Users in Instance: $TOTAL_USERS
  Users Targeted: $TARGET_COUNT
  New Users Collected: $NEW_USERS_COUNT
  Users Skipped: $SKIPPED
  Users Failed: $FAILED

Master File Status:
  Location: $MASTER_FILE
  Total Users: $UPDATED_COUNT
  Progress: $((UPDATED_COUNT * 100 / TOTAL_USERS))% complete
  Remaining: $((TOTAL_USERS - UPDATED_COUNT))

Output Files:
  Master File: $MASTER_FILE
  Collection Log: $COLLECTION_LOG
  Summary: $SUMMARY_FILE

Next Steps:
  - To collect more users, adjust START_USER and END_USER
  - To analyze for duplicates, run: ./analyze_duplicates.sh
========================================
EOF

cat "$SUMMARY_FILE" | tee -a "$COLLECTION_LOG"

log_message "Step 10: Cleaning up temporary files"
rm -rf "$TEMP_DIR" 2>/dev/null
log_message "✓ Temporary files removed"

log_message "=========================================="
log_message "Collection Complete!"
log_message "=========================================="
log_message "Range processed: $START_USER to $END_USER"
log_message "New users collected: $NEW_USERS_COUNT"
log_message "Users skipped: $SKIPPED"
log_message "Users failed: $FAILED"
log_message "Total in master file: $UPDATED_COUNT"
log_message "Progress: $((UPDATED_COUNT * 100 / TOTAL_USERS))% of $TOTAL_USERS users"
log_message "Master file: $MASTER_FILE"
log_message "Summary: $SUMMARY_FILE"
log_message "=========================================="

exit 0