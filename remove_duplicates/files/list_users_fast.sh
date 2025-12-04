#!/bin/bash

set +e

# ============================================
# CONFIGURATION
# ============================================
INSTANCE_ID=""
START_USER=1              # First user position to collect
END_USER=50000            # Last user position to collect (will auto-adjust to actual count)
OUTPUT_FOLDER="./duplicate_users_output"
MASTER_FILE="$OUTPUT_FOLDER/all_users_master.json"
COLLECTION_LOG="$OUTPUT_FOLDER/list_users_log_$(date +%Y%m%d_%H%M%S).log"
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
log_message "Amazon Connect User List Collection (Lightweight)"
log_message "=========================================="
log_message "Range: Users $START_USER to $END_USER"
log_message "Instance ID: $INSTANCE_ID"
log_message "Method: list-users only (no describe-user calls)"

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
log_message "  This is a SINGLE API call (very fast!)"

USERS_JSON=$(aws connect list-users --instance-id "$INSTANCE_ID" --output json 2>&1)
if [ $? -ne 0 ]; then
    error_exit "Failed to fetch users: $USERS_JSON"
fi

TOTAL_USERS=$(echo "$USERS_JSON" | jq -r '.UserSummaryList | length')
log_message "✓ Total users in instance: $TOTAL_USERS"
log_message "✓ API call completed in < 5 seconds"

# Validate range against total users
if [ $END_USER -gt $TOTAL_USERS ]; then
    log_message "⚠ Warning: END_USER ($END_USER) exceeds total users ($TOTAL_USERS)"
    END_USER=$TOTAL_USERS
    log_message "✓ Adjusted END_USER to $END_USER"
fi

USERS_TO_COLLECT=$((END_USER - START_USER + 1))
log_message "✓ Will collect $USERS_TO_COLLECT users (positions $START_USER to $END_USER)"

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

log_message "Step 6: Processing users from list-users response"
log_message "  Progress will be logged for EVERY user"

PROCESSED=0
NEW_USERS_FILE="$TEMP_DIR/new_users.jsonl"

# Process each user from the list using array to avoid subshell
mapfile -t USER_SUMMARIES < <(jq -c '.[]' "$TEMP_DIR/target_users.json")

for USER_SUMMARY in "${USER_SUMMARIES[@]}"; do
    PROCESSED=$((PROCESSED + 1))
    
    # Extract fields from UserSummaryList
    USER_ID=$(echo "$USER_SUMMARY" | jq -r '.Id')
    USERNAME=$(echo "$USER_SUMMARY" | jq -r '.Username // "N/A"')
    
    # Check if user already exists in master file
    if user_exists_in_master "$USER_ID"; then
        log_message "  ⊗ User $PROCESSED/$TARGET_COUNT - Skipped (already exists: $USERNAME)"
        continue
    fi
    
    # Convert UserSummary to User format (matching Amazon Connect describe-user structure)
    # list-users provides: Id, Arn, Username, IdentityInfo (FirstName, LastName, Email)
    # We keep the same structure for compatibility
    USER_RECORD=$(echo "$USER_SUMMARY" | jq '{
        Id: .Id,
        Arn: .Arn,
        Username: .Username,
        IdentityInfo: {
            FirstName: (.IdentityInfo.FirstName // ""),
            LastName: (.IdentityInfo.LastName // ""),
            Email: (.IdentityInfo.Email // "")
        }
    }')
    
    echo "$USER_RECORD" >> "$NEW_USERS_FILE"
    
    # Log progress for EVERY user with details
    PERCENT=$((PROCESSED * 100 / TARGET_COUNT))
    EMAIL=$(echo "$USER_SUMMARY" | jq -r '.IdentityInfo.Email // "N/A"')
    log_message "  ✓ User $PROCESSED/$TARGET_COUNT ($PERCENT%) - $USERNAME ($EMAIL)"
done

# Count results
if [ -f "$NEW_USERS_FILE" ]; then
    NEW_USERS_COUNT=$(wc -l < "$NEW_USERS_FILE")
else
    NEW_USERS_COUNT=0
fi
SKIPPED=$((TARGET_COUNT - NEW_USERS_COUNT))

log_message "✓ User processing complete"
log_message "  New users: $NEW_USERS_COUNT, Skipped: $SKIPPED"

log_message "Step 7: Processing collected user data"

if [ -f "$NEW_USERS_FILE" ] && [ -s "$NEW_USERS_FILE" ]; then
    # Convert JSONL to JSON array
    jq -s '.' "$NEW_USERS_FILE" > "$TEMP_DIR/new_users.json" 2>&1
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to process user data into JSON array"
    fi
    
    log_message "✓ Successfully processed $NEW_USERS_COUNT new user records"
else
    log_message "⚠ No new users to add (all were skipped)"
    NEW_USERS_COUNT=0
    echo "[]" > "$TEMP_DIR/new_users.json"
fi

log_message "Step 8: Appending to master file"

if [ $NEW_USERS_COUNT -gt 0 ]; then
    # Read existing master file
    EXISTING_USERS=$(cat "$MASTER_FILE")
    
    # Merge with new users
    echo "$EXISTING_USERS" | jq --slurpfile new "$TEMP_DIR/new_users.json" '. + $new[0]' > "$TEMP_DIR/updated_master.json"
    
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
Collection Summary (list-users method)
========================================
Date: $(date '+%Y-%m-%d %H:%M:%S')
Instance ID: $INSTANCE_ID
Range Collected: Users $START_USER to $END_USER
Processing Mode: list-users only (single API call)

Results:
  Total Users in Instance: $TOTAL_USERS
  Users Targeted: $TARGET_COUNT
  New Users Collected: $NEW_USERS_COUNT
  Users Skipped: $SKIPPED

Master File Status:
  Location: $MASTER_FILE
  Total Users: $UPDATED_COUNT
  Progress: $((UPDATED_COUNT * 100 / TOTAL_USERS))% complete
  Remaining: $((TOTAL_USERS - UPDATED_COUNT))

Data Available:
  - User ID
  - Username
  - ARN
  - First Name
  - Last Name
  - Email

Note: This method uses only list-users (no describe-user).
      Data collected is limited to basic user info.
      Much faster than describe-user method!

Output Files:
  Master File: $MASTER_FILE
  Collection Log: $COLLECTION_LOG
  Summary: $SUMMARY_FILE

Next Steps:
  - To collect more users, adjust START_USER and END_USER
  - To analyze for duplicates, run: ./analyze_duplicates_username.sh
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
log_message "Total in master file: $UPDATED_COUNT"
log_message "Progress: $((UPDATED_COUNT * 100 / TOTAL_USERS))% of $TOTAL_USERS users"
log_message "Master file: $MASTER_FILE"
log_message "Summary: $SUMMARY_FILE"
log_message "Collection time: < 10 seconds (single API call!)"
log_message "=========================================="

exit 0
