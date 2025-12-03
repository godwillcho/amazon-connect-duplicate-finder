#!/bin/bash

set +e

INSTANCE_ID=""
OUTPUT_FOLDER="./duplicate_users_output"
PARALLEL_PROCESSES=8

mkdir -p "$OUTPUT_FOLDER" 2>/dev/null

MAIN_LOG="$OUTPUT_FOLDER/parallel_main_log_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MAIN_LOG"
}

error_exit() {
    log_message "ERROR: $1"
    exit 1
}

log_message "=========================================="
log_message "Amazon Connect Duplicate User Finder - Parallel Mode"
log_message "=========================================="
log_message "Configuration: $PARALLEL_PROCESSES parallel workers"

log_message "Step 1: Checking prerequisites"
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed"
fi
if ! command -v jq &> /dev/null; then
    error_exit "jq is not installed"
fi
log_message "✓ Prerequisites verified"

log_message "Step 2: Fetching user list from instance: $INSTANCE_ID"
USERS_JSON=$(aws connect list-users --instance-id "$INSTANCE_ID" --output json 2>&1)
if [ $? -ne 0 ]; then
    error_exit "Failed to fetch users: $USERS_JSON"
fi

TOTAL_USERS=$(echo "$USERS_JSON" | jq -r '.UserSummaryList | length')
log_message "✓ Found $TOTAL_USERS users"

ESTIMATED_TIME=$((TOTAL_USERS / PARALLEL_PROCESSES))
log_message "✓ Estimated processing time: ~$((ESTIMATED_TIME / 60)) minutes"

log_message "Step 3: Creating temporary directory"
TEMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
    error_exit "Failed to create temporary directory"
fi
log_message "✓ Temporary directory: $TEMP_DIR"

echo "$USERS_JSON" > "$TEMP_DIR/all_users.json"

CHUNK_SIZE=$((TOTAL_USERS / PARALLEL_PROCESSES))
REMAINDER=$((TOTAL_USERS % PARALLEL_PROCESSES))

log_message "Step 4: Splitting users into $PARALLEL_PROCESSES chunks"
log_message "  Chunk size: ~$CHUNK_SIZE users per worker"

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    START_INDEX=$((i * CHUNK_SIZE))
    
    if [ $i -eq $((PARALLEL_PROCESSES - 1)) ]; then
        END_INDEX=$((TOTAL_USERS - 1))
    else
        END_INDEX=$(((i + 1) * CHUNK_SIZE - 1))
    fi
    
    CHUNK_FILE="$TEMP_DIR/chunk_${i}.json"
    jq ".UserSummaryList[$START_INDEX:$((END_INDEX + 1))]" "$TEMP_DIR/all_users.json" > "$CHUNK_FILE"
    
    CHUNK_COUNT=$(jq '. | length' "$CHUNK_FILE")
    log_message "  Chunk $((i + 1)): Users $((START_INDEX + 1)) to $((END_INDEX + 1)) ($CHUNK_COUNT users)"
done

log_message "Step 5: Launching parallel processing workers"

WORKER_PIDS=()

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    WORKER_LOG="$OUTPUT_FOLDER/worker_${i}_log_$(date +%Y%m%d_%H%M%S).log"
    WORKER_OUTPUT="$TEMP_DIR/worker_${i}_details.json"
    
    # Initialize empty JSON array for each worker
    echo "[]" > "$WORKER_OUTPUT"
    
    (
        CHUNK_FILE="$TEMP_DIR/chunk_${i}.json"
        WORKER_TEMP="$TEMP_DIR/worker_${i}_temp.json"
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Started" >> "$WORKER_LOG"
        
        CHUNK_USERS=$(jq '. | length' "$CHUNK_FILE")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Processing $CHUNK_USERS users" >> "$WORKER_LOG"
        
        CURRENT=0
        jq -r '.[].Id' "$CHUNK_FILE" 2>/dev/null | while read USER_ID; do
            CURRENT=$((CURRENT + 1))
            
            USER_DETAIL=$(aws connect describe-user --user-id "$USER_ID" --instance-id "$INSTANCE_ID" --output json 2>&1)
            if [ $? -eq 0 ]; then
                echo "$USER_DETAIL" | jq -c '.User' >> "$WORKER_TEMP" 2>/dev/null
                
                if [ $((CURRENT % 100)) -eq 0 ] || [ $CURRENT -eq $CHUNK_USERS ]; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ✓ Processed $CURRENT of $CHUNK_USERS users ($((CURRENT * 100 / CHUNK_USERS))%)" >> "$WORKER_LOG"
                fi
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ⚠ Failed to fetch user at position $CURRENT (ID: $USER_ID)" >> "$WORKER_LOG"
            fi
        done
        
        # Convert temp file to proper JSON array
        if [ -f "$WORKER_TEMP" ]; then
            jq -s '.' "$WORKER_TEMP" > "$WORKER_OUTPUT" 2>/dev/null
            rm -f "$WORKER_TEMP"
        fi
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Completed - processed $CURRENT users" >> "$WORKER_LOG"
    ) &
    
    WORKER_PIDS+=($!)
    log_message "  Worker $((i + 1)) launched (PID: ${WORKER_PIDS[$i]})"
done

log_message "Step 6: Monitoring workers (progress logged every 100 users per worker)"
log_message "  All $PARALLEL_PROCESSES workers are processing in parallel..."
log_message "  Check individual worker logs for detailed progress"

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

log_message "Step 7: Merging worker results"
MERGED_FILE="$TEMP_DIR/merged_users.json"

jq -s 'add | map(select(. != null))' "$TEMP_DIR"/worker_*_details.json > "$MERGED_FILE" 2>&1
if [ $? -ne 0 ]; then
    error_exit "Failed to merge worker results"
fi

PROCESSED_COUNT=$(jq '. | length' "$MERGED_FILE")
log_message "✓ Successfully merged $PROCESSED_COUNT user records"

log_message "Step 8: Creating all users CSV file"
ALL_USERS_FILE="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).csv"
echo "Username,Email,FirstName,LastName,User_ID,ARN" > "$ALL_USERS_FILE"

jq -r '.[] | 
       [
         .Username // "",
         .IdentityInfo.Email // "",
         .IdentityInfo.FirstName // "",
         .IdentityInfo.LastName // "",
         .Id // "",
         .Arn // ""
       ] | @csv' "$MERGED_FILE" >> "$ALL_USERS_FILE" 2>&1

ALL_USERS_COUNT=$(($(wc -l < "$ALL_USERS_FILE") - 1))
log_message "✓ All users CSV created with $ALL_USERS_COUNT users"

log_message "Step 9: Creating all users JSON file"
ALL_USERS_JSON_FILE="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).json"
cp "$MERGED_FILE" "$ALL_USERS_JSON_FILE" 2>&1
log_message "✓ All users JSON file created"

log_message "Step 10: Creating duplicates CSV file"
DUPLICATES_FILE="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).csv"
echo "User1_ID,User1_Username,User1_Email,User1_FirstName,User1_LastName,User2_ID,User2_Username,User2_Email,User2_FirstName,User2_LastName,Reason" > "$DUPLICATES_FILE"

log_message "Step 11: Finding duplicate emails (case-insensitive)"
EMAIL_RESULT=$(jq -r '
       map(.IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       $normalized | to_entries | .[] as $entry1 | 
       $normalized | to_entries | .[] as $entry2 | 
       select($entry1.key < $entry2.key) |
       select(
         ($entry1.value.IdentityInfo.Email // "") == ($entry2.value.IdentityInfo.Email // "") and
         ($entry1.value.IdentityInfo.Email // "") != ""
       ) |
       [
         $entry1.value.Id // "",
         $entry1.value.Username // "",
         $entry1.value.IdentityInfo.Email // "",
         $entry1.value.IdentityInfo.FirstName // "",
         $entry1.value.IdentityInfo.LastName // "",
         $entry2.value.Id // "",
         $entry2.value.Username // "",
         $entry2.value.IdentityInfo.Email // "",
         $entry2.value.IdentityInfo.FirstName // "",
         $entry2.value.IdentityInfo.LastName // "",
         "Duplicate email: " + ($entry1.value.IdentityInfo.Email // "")
       ] | @csv' "$MERGED_FILE" 2>&1)

if [ $? -eq 0 ] && [ -n "$EMAIL_RESULT" ]; then
    echo "$EMAIL_RESULT" >> "$DUPLICATES_FILE"
    EMAIL_DUPLICATES=$(echo "$EMAIL_RESULT" | wc -l)
else
    EMAIL_DUPLICATES=0
fi
log_message "✓ Found $EMAIL_DUPLICATES duplicate email pairs"

log_message "Step 12: Finding duplicate usernames (case-insensitive)"
USERNAME_RESULT=$(jq -r '
       map(.Username = (.Username // "" | ascii_downcase) | .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       $normalized | to_entries | .[] as $entry1 | 
       $normalized | to_entries | .[] as $entry2 | 
       select($entry1.key < $entry2.key) |
       select(
         ($entry1.value.Username // "") == ($entry2.value.Username // "") and
         ($entry1.value.Username // "") != "" and
         (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
          ($entry1.value.IdentityInfo.Email // "") == "")
       ) |
       [
         $entry1.value.Id // "",
         $entry1.value.Username // "",
         $entry1.value.IdentityInfo.Email // "",
         $entry1.value.IdentityInfo.FirstName // "",
         $entry1.value.IdentityInfo.LastName // "",
         $entry2.value.Id // "",
         $entry2.value.Username // "",
         $entry2.value.IdentityInfo.Email // "",
         $entry2.value.IdentityInfo.FirstName // "",
         $entry2.value.IdentityInfo.LastName // "",
         "Duplicate username: " + ($entry1.value.Username // "")
       ] | @csv' "$MERGED_FILE" 2>&1)

if [ $? -eq 0 ] && [ -n "$USERNAME_RESULT" ]; then
    echo "$USERNAME_RESULT" >> "$DUPLICATES_FILE"
    USERNAME_DUPLICATES=$(echo "$USERNAME_RESULT" | wc -l)
else
    USERNAME_DUPLICATES=0
fi
log_message "✓ Found $USERNAME_DUPLICATES duplicate username pairs"

log_message "Step 13: Finding duplicate names (case-insensitive)"
NAME_RESULT=$(jq -r '
       map(
         .IdentityInfo.FirstName = (.IdentityInfo.FirstName // "" | ascii_downcase) | 
         .IdentityInfo.LastName = (.IdentityInfo.LastName // "" | ascii_downcase) |
         .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)
       ) |
       . as $normalized |
       $normalized | to_entries | .[] as $entry1 | 
       $normalized | to_entries | .[] as $entry2 | 
       select($entry1.key < $entry2.key) |
       select(
         ($entry1.value.IdentityInfo.FirstName // "") == ($entry2.value.IdentityInfo.FirstName // "") and
         ($entry1.value.IdentityInfo.LastName // "") == ($entry2.value.IdentityInfo.LastName // "") and
         ($entry1.value.IdentityInfo.FirstName // "") != "" and
         ($entry1.value.IdentityInfo.LastName // "") != "" and
         (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
          ($entry1.value.IdentityInfo.Email // "") == "")
       ) |
       [
         $entry1.value.Id // "",
         $entry1.value.Username // "",
         $entry1.value.IdentityInfo.Email // "",
         $entry1.value.IdentityInfo.FirstName // "",
         $entry1.value.IdentityInfo.LastName // "",
         $entry2.value.Id // "",
         $entry2.value.Username // "",
         $entry2.value.IdentityInfo.Email // "",
         $entry2.value.IdentityInfo.FirstName // "",
         $entry2.value.IdentityInfo.LastName // "",
         "Duplicate name: " + ($entry1.value.IdentityInfo.FirstName // "") + " " + ($entry1.value.IdentityInfo.LastName // "")
       ] | @csv' "$MERGED_FILE" 2>&1)

if [ $? -eq 0 ] && [ -n "$NAME_RESULT" ]; then
    echo "$NAME_RESULT" >> "$DUPLICATES_FILE"
    NAME_DUPLICATES=$(echo "$NAME_RESULT" | wc -l)
else
    NAME_DUPLICATES=0
fi
log_message "✓ Found $NAME_DUPLICATES duplicate name pairs"

DUPLICATE_COUNT=$((EMAIL_DUPLICATES + USERNAME_DUPLICATES + NAME_DUPLICATES))

log_message "Step 14: Creating duplicates JSON file"
DUPLICATES_JSON_FILE="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).json"

jq -n --argjson email_dups "$(jq '
       map(.IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       [
         $normalized | to_entries | .[] as $entry1 | 
         $normalized | to_entries | .[] as $entry2 | 
         select($entry1.key < $entry2.key) |
         select(
           ($entry1.value.IdentityInfo.Email // "") == ($entry2.value.IdentityInfo.Email // "") and
           ($entry1.value.IdentityInfo.Email // "") != ""
         ) |
         {
           user1: $entry1.value,
           user2: $entry2.value,
           reason: ("Duplicate email: " + ($entry1.value.IdentityInfo.Email // ""))
         }
       ] | flatten' "$MERGED_FILE")" \
   --argjson username_dups "$(jq '
       map(.Username = (.Username // "" | ascii_downcase) | .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       [
         $normalized | to_entries | .[] as $entry1 | 
         $normalized | to_entries | .[] as $entry2 | 
         select($entry1.key < $entry2.key) |
         select(
           ($entry1.value.Username // "") == ($entry2.value.Username // "") and
           ($entry1.value.Username // "") != "" and
           (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
            ($entry1.value.IdentityInfo.Email // "") == "")
         ) |
         {
           user1: $entry1.value,
           user2: $entry2.value,
           reason: ("Duplicate username: " + ($entry1.value.Username // ""))
         }
       ] | flatten' "$MERGED_FILE")" \
   --argjson name_dups "$(jq '
       map(
         .IdentityInfo.FirstName = (.IdentityInfo.FirstName // "" | ascii_downcase) | 
         .IdentityInfo.LastName = (.IdentityInfo.LastName // "" | ascii_downcase) |
         .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)
       ) |
       . as $normalized |
       [
         $normalized | to_entries | .[] as $entry1 | 
         $normalized | to_entries | .[] as $entry2 | 
         select($entry1.key < $entry2.key) |
         select(
           ($entry1.value.IdentityInfo.FirstName // "") == ($entry2.value.IdentityInfo.FirstName // "") and
           ($entry1.value.IdentityInfo.LastName // "") == ($entry2.value.IdentityInfo.LastName // "") and
           ($entry1.value.IdentityInfo.FirstName // "") != "" and
           ($entry1.value.IdentityInfo.LastName // "") != "" and
           (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
            ($entry1.value.IdentityInfo.Email // "") == "")
         ) |
         {
           user1: $entry1.value,
           user2: $entry2.value,
           reason: ("Duplicate name: " + ($entry1.value.IdentityInfo.FirstName // "") + " " + ($entry1.value.IdentityInfo.LastName // ""))
         }
       ] | flatten' "$MERGED_FILE")" \
   '{duplicate_emails: $email_dups, duplicate_usernames: $username_dups, duplicate_names: $name_dups}' > "$DUPLICATES_JSON_FILE" 2>&1

log_message "✓ Duplicates JSON file created"

log_message "Step 15: Cleaning up temporary files"
rm -rf "$TEMP_DIR" 2>/dev/null
log_message "✓ Temporary files removed"

log_message "=========================================="
log_message "Parallel Processing Complete!"
log_message "=========================================="
log_message "Total users analyzed: $TOTAL_USERS"
log_message "Successfully processed: $PROCESSED_COUNT users"
log_message "Parallel workers: $PARALLEL_PROCESSES"
log_message "Failed workers: $FAILED_WORKERS"
log_message "Total duplicate pairs found: $DUPLICATE_COUNT"
log_message "  - Duplicate emails: $EMAIL_DUPLICATES"
log_message "  - Duplicate usernames: $USERNAME_DUPLICATES"
log_message "  - Duplicate names: $NAME_DUPLICATES"
log_message "All users CSV saved to: $ALL_USERS_FILE"
log_message "All users JSON saved to: $ALL_USERS_JSON_FILE"
log_message "Duplicates CSV saved to: $DUPLICATES_FILE"
log_message "Duplicates JSON saved to: $DUPLICATES_JSON_FILE"
log_message "Main log saved to: $MAIN_LOG"
log_message "Worker logs saved to: $OUTPUT_FOLDER/worker_*_log_*.log"
log_message "=========================================="

exit 0


mkdir -p "$OUTPUT_FOLDER" 2>/dev/null

MAIN_LOG="$OUTPUT_FOLDER/parallel_main_log_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$MAIN_LOG"
}

error_exit() {
    log_message "ERROR: $1"
    exit 1
}

log_message "=========================================="
log_message "Amazon Connect Duplicate User Finder - Parallel Mode"
log_message "=========================================="

log_message "Step 1: Checking prerequisites"
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed"
fi
if ! command -v jq &> /dev/null; then
    error_exit "jq is not installed"
fi
log_message "✓ Prerequisites verified"

log_message "Step 2: Fetching user list from instance: $INSTANCE_ID"
USERS_JSON=$(aws connect list-users --instance-id "$INSTANCE_ID" --output json 2>&1)
if [ $? -ne 0 ]; then
    error_exit "Failed to fetch users: $USERS_JSON"
fi

TOTAL_USERS=$(echo "$USERS_JSON" | jq -r '.UserSummaryList | length')
log_message "✓ Found $TOTAL_USERS users"

log_message "Step 3: Creating temporary directory"
TEMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
    error_exit "Failed to create temporary directory"
fi
log_message "✓ Temporary directory: $TEMP_DIR"

echo "$USERS_JSON" > "$TEMP_DIR/all_users.json"

CHUNK_SIZE=$((TOTAL_USERS / PARALLEL_PROCESSES))
REMAINDER=$((TOTAL_USERS % PARALLEL_PROCESSES))

log_message "Step 4: Splitting users into $PARALLEL_PROCESSES chunks"
log_message "  Chunk size: ~$CHUNK_SIZE users per process"

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    START_INDEX=$((i * CHUNK_SIZE))
    
    if [ $i -eq $((PARALLEL_PROCESSES - 1)) ]; then
        END_INDEX=$((TOTAL_USERS - 1))
    else
        END_INDEX=$(((i + 1) * CHUNK_SIZE - 1))
    fi
    
    CHUNK_FILE="$TEMP_DIR/chunk_${i}.json"
    jq ".UserSummaryList[$START_INDEX:$((END_INDEX + 1))]" "$TEMP_DIR/all_users.json" > "$CHUNK_FILE"
    
    CHUNK_COUNT=$(jq '. | length' "$CHUNK_FILE")
    log_message "  Chunk $((i + 1)): Users $((START_INDEX + 1)) to $((END_INDEX + 1)) ($CHUNK_COUNT users)"
done

log_message "Step 5: Launching parallel processing workers"

WORKER_PIDS=()

for i in $(seq 0 $((PARALLEL_PROCESSES - 1))); do
    WORKER_LOG="$OUTPUT_FOLDER/worker_${i}_log_$(date +%Y%m%d_%H%M%S).log"
    WORKER_OUTPUT="$TEMP_DIR/worker_${i}_details.json"
    
    (
        CHUNK_FILE="$TEMP_DIR/chunk_${i}.json"
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Started" >> "$WORKER_LOG"
        
        CHUNK_USERS=$(jq '. | length' "$CHUNK_FILE")
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Processing $CHUNK_USERS users" >> "$WORKER_LOG"
        
        CURRENT=0
        jq -r '.[].Id' "$CHUNK_FILE" 2>/dev/null | while read USER_ID; do
            CURRENT=$((CURRENT + 1))
            
            USER_DETAIL=$(aws connect describe-user --user-id "$USER_ID" --instance-id "$INSTANCE_ID" --output json 2>&1)
            if [ $? -eq 0 ]; then
                echo "$USER_DETAIL" | jq -c '.User' >> "$WORKER_OUTPUT" 2>/dev/null
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ✓ Processed user $CURRENT of $CHUNK_USERS (ID: $USER_ID)" >> "$WORKER_LOG"
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: ⚠ Failed to fetch user $CURRENT (ID: $USER_ID)" >> "$WORKER_LOG"
            fi
        done
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Worker $i: Completed" >> "$WORKER_LOG"
    ) &
    
    WORKER_PIDS+=($!)
    log_message "  Worker $((i + 1)) launched (PID: ${WORKER_PIDS[$i]})"
done

log_message "Step 6: Waiting for all workers to complete"
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

log_message "Step 7: Merging worker results"
MERGED_FILE="$TEMP_DIR/merged_users.json"

jq -s 'add' "$TEMP_DIR"/worker_*_details.json > "$MERGED_FILE" 2>&1
if [ $? -ne 0 ]; then
    error_exit "Failed to merge worker results"
fi

PROCESSED_COUNT=$(jq '. | length' "$MERGED_FILE")
log_message "✓ Successfully merged $PROCESSED_COUNT user records"

log_message "Step 8: Creating all users CSV file"
ALL_USERS_FILE="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).csv"
echo "Username,Email,FirstName,LastName,User_ID,ARN" > "$ALL_USERS_FILE"

jq -r '.[] | 
       [
         .Username // "",
         .IdentityInfo.Email // "",
         .IdentityInfo.FirstName // "",
         .IdentityInfo.LastName // "",
         .Id // "",
         .Arn // ""
       ] | @csv' "$MERGED_FILE" >> "$ALL_USERS_FILE" 2>&1

ALL_USERS_COUNT=$(($(wc -l < "$ALL_USERS_FILE") - 1))
log_message "✓ All users CSV created with $ALL_USERS_COUNT users"

log_message "Step 9: Creating all users JSON file"
ALL_USERS_JSON_FILE="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).json"
cp "$MERGED_FILE" "$ALL_USERS_JSON_FILE" 2>&1
log_message "✓ All users JSON file created"

log_message "Step 10: Creating duplicates CSV file"
DUPLICATES_FILE="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).csv"
echo "User1_ID,User1_Username,User1_Email,User1_FirstName,User1_LastName,User2_ID,User2_Username,User2_Email,User2_FirstName,User2_LastName,Reason" > "$DUPLICATES_FILE"

log_message "Step 11: Finding duplicate emails (case-insensitive)"
EMAIL_RESULT=$(jq -r '
       map(.IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       $normalized | to_entries | .[] as $entry1 | 
       $normalized | to_entries | .[] as $entry2 | 
       select($entry1.key < $entry2.key) |
       select(
         ($entry1.value.IdentityInfo.Email // "") == ($entry2.value.IdentityInfo.Email // "") and
         ($entry1.value.IdentityInfo.Email // "") != ""
       ) |
       [
         $entry1.value.Id // "",
         $entry1.value.Username // "",
         $entry1.value.IdentityInfo.Email // "",
         $entry1.value.IdentityInfo.FirstName // "",
         $entry1.value.IdentityInfo.LastName // "",
         $entry2.value.Id // "",
         $entry2.value.Username // "",
         $entry2.value.IdentityInfo.Email // "",
         $entry2.value.IdentityInfo.FirstName // "",
         $entry2.value.IdentityInfo.LastName // "",
         "Duplicate email: " + ($entry1.value.IdentityInfo.Email // "")
       ] | @csv' "$MERGED_FILE" 2>&1)

if [ $? -eq 0 ] && [ -n "$EMAIL_RESULT" ]; then
    echo "$EMAIL_RESULT" >> "$DUPLICATES_FILE"
    EMAIL_DUPLICATES=$(echo "$EMAIL_RESULT" | wc -l)
else
    EMAIL_DUPLICATES=0
fi
log_message "✓ Found $EMAIL_DUPLICATES duplicate email pairs"

log_message "Step 12: Finding duplicate usernames (case-insensitive)"
USERNAME_RESULT=$(jq -r '
       map(.Username = (.Username // "" | ascii_downcase) | .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       $normalized | to_entries | .[] as $entry1 | 
       $normalized | to_entries | .[] as $entry2 | 
       select($entry1.key < $entry2.key) |
       select(
         ($entry1.value.Username // "") == ($entry2.value.Username // "") and
         ($entry1.value.Username // "") != "" and
         (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
          ($entry1.value.IdentityInfo.Email // "") == "")
       ) |
       [
         $entry1.value.Id // "",
         $entry1.value.Username // "",
         $entry1.value.IdentityInfo.Email // "",
         $entry1.value.IdentityInfo.FirstName // "",
         $entry1.value.IdentityInfo.LastName // "",
         $entry2.value.Id // "",
         $entry2.value.Username // "",
         $entry2.value.IdentityInfo.Email // "",
         $entry2.value.IdentityInfo.FirstName // "",
         $entry2.value.IdentityInfo.LastName // "",
         "Duplicate username: " + ($entry1.value.Username // "")
       ] | @csv' "$MERGED_FILE" 2>&1)

if [ $? -eq 0 ] && [ -n "$USERNAME_RESULT" ]; then
    echo "$USERNAME_RESULT" >> "$DUPLICATES_FILE"
    USERNAME_DUPLICATES=$(echo "$USERNAME_RESULT" | wc -l)
else
    USERNAME_DUPLICATES=0
fi
log_message "✓ Found $USERNAME_DUPLICATES duplicate username pairs"

log_message "Step 13: Finding duplicate names (case-insensitive)"
NAME_RESULT=$(jq -r '
       map(
         .IdentityInfo.FirstName = (.IdentityInfo.FirstName // "" | ascii_downcase) | 
         .IdentityInfo.LastName = (.IdentityInfo.LastName // "" | ascii_downcase) |
         .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)
       ) |
       . as $normalized |
       $normalized | to_entries | .[] as $entry1 | 
       $normalized | to_entries | .[] as $entry2 | 
       select($entry1.key < $entry2.key) |
       select(
         ($entry1.value.IdentityInfo.FirstName // "") == ($entry2.value.IdentityInfo.FirstName // "") and
         ($entry1.value.IdentityInfo.LastName // "") == ($entry2.value.IdentityInfo.LastName // "") and
         ($entry1.value.IdentityInfo.FirstName // "") != "" and
         ($entry1.value.IdentityInfo.LastName // "") != "" and
         (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
          ($entry1.value.IdentityInfo.Email // "") == "")
       ) |
       [
         $entry1.value.Id // "",
         $entry1.value.Username // "",
         $entry1.value.IdentityInfo.Email // "",
         $entry1.value.IdentityInfo.FirstName // "",
         $entry1.value.IdentityInfo.LastName // "",
         $entry2.value.Id // "",
         $entry2.value.Username // "",
         $entry2.value.IdentityInfo.Email // "",
         $entry2.value.IdentityInfo.FirstName // "",
         $entry2.value.IdentityInfo.LastName // "",
         "Duplicate name: " + ($entry1.value.IdentityInfo.FirstName // "") + " " + ($entry1.value.IdentityInfo.LastName // "")
       ] | @csv' "$MERGED_FILE" 2>&1)

if [ $? -eq 0 ] && [ -n "$NAME_RESULT" ]; then
    echo "$NAME_RESULT" >> "$DUPLICATES_FILE"
    NAME_DUPLICATES=$(echo "$NAME_RESULT" | wc -l)
else
    NAME_DUPLICATES=0
fi
log_message "✓ Found $NAME_DUPLICATES duplicate name pairs"

DUPLICATE_COUNT=$((EMAIL_DUPLICATES + USERNAME_DUPLICATES + NAME_DUPLICATES))

log_message "Step 14: Creating duplicates JSON file"
DUPLICATES_JSON_FILE="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).json"

jq -n --argjson email_dups "$(jq '
       map(.IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       [
         $normalized | to_entries | .[] as $entry1 | 
         $normalized | to_entries | .[] as $entry2 | 
         select($entry1.key < $entry2.key) |
         select(
           ($entry1.value.IdentityInfo.Email // "") == ($entry2.value.IdentityInfo.Email // "") and
           ($entry1.value.IdentityInfo.Email // "") != ""
         ) |
         {
           user1: $entry1.value,
           user2: $entry2.value,
           reason: ("Duplicate email: " + ($entry1.value.IdentityInfo.Email // ""))
         }
       ] | flatten' "$MERGED_FILE")" \
   --argjson username_dups "$(jq '
       map(.Username = (.Username // "" | ascii_downcase) | .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)) |
       . as $normalized |
       [
         $normalized | to_entries | .[] as $entry1 | 
         $normalized | to_entries | .[] as $entry2 | 
         select($entry1.key < $entry2.key) |
         select(
           ($entry1.value.Username // "") == ($entry2.value.Username // "") and
           ($entry1.value.Username // "") != "" and
           (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
            ($entry1.value.IdentityInfo.Email // "") == "")
         ) |
         {
           user1: $entry1.value,
           user2: $entry2.value,
           reason: ("Duplicate username: " + ($entry1.value.Username // ""))
         }
       ] | flatten' "$MERGED_FILE")" \
   --argjson name_dups "$(jq '
       map(
         .IdentityInfo.FirstName = (.IdentityInfo.FirstName // "" | ascii_downcase) | 
         .IdentityInfo.LastName = (.IdentityInfo.LastName // "" | ascii_downcase) |
         .IdentityInfo.Email = (.IdentityInfo.Email // "" | ascii_downcase)
       ) |
       . as $normalized |
       [
         $normalized | to_entries | .[] as $entry1 | 
         $normalized | to_entries | .[] as $entry2 | 
         select($entry1.key < $entry2.key) |
         select(
           ($entry1.value.IdentityInfo.FirstName // "") == ($entry2.value.IdentityInfo.FirstName // "") and
           ($entry1.value.IdentityInfo.LastName // "") == ($entry2.value.IdentityInfo.LastName // "") and
           ($entry1.value.IdentityInfo.FirstName // "") != "" and
           ($entry1.value.IdentityInfo.LastName // "") != "" and
           (($entry1.value.IdentityInfo.Email // "") != ($entry2.value.IdentityInfo.Email // "") or
            ($entry1.value.IdentityInfo.Email // "") == "")
         ) |
         {
           user1: $entry1.value,
           user2: $entry2.value,
           reason: ("Duplicate name: " + ($entry1.value.IdentityInfo.FirstName // "") + " " + ($entry1.value.IdentityInfo.LastName // ""))
         }
       ] | flatten' "$MERGED_FILE")" \
   '{duplicate_emails: $email_dups, duplicate_usernames: $username_dups, duplicate_names: $name_dups}' > "$DUPLICATES_JSON_FILE" 2>&1

log_message "✓ Duplicates JSON file created"

log_message "Step 15: Cleaning up temporary files"
rm -rf "$TEMP_DIR" 2>/dev/null
log_message "✓ Temporary files removed"

log_message "=========================================="
log_message "Parallel Processing Complete!"
log_message "=========================================="
log_message "Total users analyzed: $TOTAL_USERS"
log_message "Successfully processed: $PROCESSED_COUNT users"
log_message "Parallel workers: $PARALLEL_PROCESSES"
log_message "Failed workers: $FAILED_WORKERS"
log_message "Total duplicate pairs found: $DUPLICATE_COUNT"
log_message "  - Duplicate emails: $EMAIL_DUPLICATES"
log_message "  - Duplicate usernames: $USERNAME_DUPLICATES"
log_message "  - Duplicate names: $NAME_DUPLICATES"
log_message "All users CSV saved to: $ALL_USERS_FILE"
log_message "All users JSON saved to: $ALL_USERS_JSON_FILE"
log_message "Duplicates CSV saved to: $DUPLICATES_FILE"
log_message "Duplicates JSON saved to: $DUPLICATES_JSON_FILE"
log_message "Main log saved to: $MAIN_LOG"
log_message "Worker logs saved to: $OUTPUT_FOLDER/worker_*_log_*.log"
log_message "=========================================="

exit 0
