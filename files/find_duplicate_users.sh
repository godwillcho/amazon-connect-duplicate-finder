#!/bin/bash

set +e

INSTANCE_ID=""
OUTPUT_FOLDER="./duplicate_users_output"

mkdir -p "$OUTPUT_FOLDER" 2>/dev/null

OUTPUT_FILE="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).csv"
LOG_FILE="$OUTPUT_FOLDER/duplicate_users_log_$(date +%Y%m%d_%H%M%S).log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log_message "ERROR: $1"
    log_message "Script terminated with errors"
    exit 1
}

log_message "=========================================="
log_message "Starting Amazon Connect Duplicate User Finder"
log_message "=========================================="

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" == "your-instance-id-here" ]; then
    error_exit "Instance ID not configured. Please set INSTANCE_ID variable in the script."
fi

log_message "Step 1: Verifying output folder"
if [ ! -d "$OUTPUT_FOLDER" ]; then
    mkdir -p "$OUTPUT_FOLDER" 2>/dev/null
    if [ ! -d "$OUTPUT_FOLDER" ]; then
        error_exit "Failed to create output folder: $OUTPUT_FOLDER"
    fi
fi
log_message "✓ Output folder ready: $OUTPUT_FOLDER"

log_message "Step 2: Checking AWS CLI availability"
if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI is not installed or not in PATH"
fi
log_message "✓ AWS CLI found"

log_message "Step 3: Checking jq availability"
if ! command -v jq &> /dev/null; then
    error_exit "jq is not installed or not in PATH"
fi
log_message "✓ jq found"

log_message "Step 4: Verifying AWS credentials"
CREDS_CHECK=$(aws sts get-caller-identity 2>&1)
if [ $? -ne 0 ]; then
    error_exit "AWS credentials not configured or invalid: $CREDS_CHECK"
fi
log_message "✓ AWS credentials verified"

log_message "Step 5: Fetching users from Amazon Connect instance: $INSTANCE_ID"
USERS_JSON=$(aws connect list-users --instance-id "$INSTANCE_ID" --output json 2>&1)

if [ $? -ne 0 ]; then
    error_exit "Failed to fetch users from Amazon Connect. Error: $USERS_JSON"
fi

USER_COUNT=$(echo "$USERS_JSON" | jq -r '.UserSummaryList | length' 2>/dev/null)
if [ -z "$USER_COUNT" ] || [ "$USER_COUNT" == "null" ]; then
    error_exit "Failed to parse user count from API response"
fi
log_message "✓ Successfully fetched $USER_COUNT users"

log_message "Step 6: Creating temporary working directory"
TEMP_DIR=$(mktemp -d 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$TEMP_DIR" ]; then
    error_exit "Failed to create temporary directory"
fi
log_message "✓ Temporary directory created: $TEMP_DIR"

USERS_FILE="$TEMP_DIR/users.json"
DETAILS_FILE="$TEMP_DIR/user_details.json"

echo "$USERS_JSON" > "$USERS_FILE"

log_message "Step 7: Fetching detailed user information for all users"
CURRENT_USER=0

echo "$USERS_JSON" | jq -r '.UserSummaryList[].Id' 2>/dev/null | while read USER_ID; do
    CURRENT_USER=$((CURRENT_USER + 1))
    
    USER_DETAIL=$(aws connect describe-user --user-id "$USER_ID" --instance-id "$INSTANCE_ID" --output json 2>&1)
    if [ $? -eq 0 ]; then
        echo "$USER_DETAIL" | jq -c '.User' >> "$TEMP_DIR/user_detail_temp.json" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ✓ Processed user $CURRENT_USER of $USER_COUNT (ID: $USER_ID)" | tee -a "$LOG_FILE"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ⚠ Warning: Could not parse user $CURRENT_USER (ID: $USER_ID)" | tee -a "$LOG_FILE"
        fi
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')]   ⚠ Warning: Failed to fetch details for user $CURRENT_USER (ID: $USER_ID)" | tee -a "$LOG_FILE"
    fi
done

log_message "✓ User details fetching complete"

log_message "Step 8: Processing user data"
if [ ! -f "$TEMP_DIR/user_detail_temp.json" ] || [ ! -s "$TEMP_DIR/user_detail_temp.json" ]; then
    error_exit "No user details were fetched successfully"
fi

jq -s '.' "$TEMP_DIR/user_detail_temp.json" > "$DETAILS_FILE" 2>/dev/null
if [ $? -ne 0 ]; then
    error_exit "Failed to process user data into JSON array"
fi

PROCESSED_COUNT=$(jq '. | length' "$DETAILS_FILE" 2>/dev/null)
log_message "✓ Successfully processed $PROCESSED_COUNT user records"

log_message "Step 9: Creating all users CSV file"
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
       ] | @csv' "$DETAILS_FILE" >> "$ALL_USERS_FILE" 2>&1

if [ $? -eq 0 ]; then
    ALL_USERS_COUNT=$(($(wc -l < "$ALL_USERS_FILE") - 1))
    log_message "✓ All users CSV created with $ALL_USERS_COUNT users"
else
    log_message "⚠ Warning: Error while creating all users CSV"
fi

log_message "Step 9b: Creating all users JSON file"
ALL_USERS_JSON_FILE="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).json"
cp "$DETAILS_FILE" "$ALL_USERS_JSON_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "✓ All users JSON file created"
else
    log_message "⚠ Warning: Error while creating all users JSON file"
fi

log_message "Step 10: Creating duplicates CSV file"
echo "User1_ID,User1_Username,User1_Email,User1_FirstName,User1_LastName,User2_ID,User2_Username,User2_Email,User2_FirstName,User2_LastName,Reason" > "$OUTPUT_FILE"
if [ $? -ne 0 ]; then
    error_exit "Failed to create output CSV file"
fi
log_message "✓ CSV header created"

log_message "Step 11: Finding duplicate emails (case-insensitive)"
EMAIL_RESULT=$(jq -r '
       # Normalize all emails to lowercase first
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
       ] | @csv' "$DETAILS_FILE" 2>&1)

if [ $? -eq 0 ]; then
    if [ -n "$EMAIL_RESULT" ]; then
        echo "$EMAIL_RESULT" >> "$OUTPUT_FILE"
        EMAIL_DUPLICATES=$(echo "$EMAIL_RESULT" | wc -l)
    else
        EMAIL_DUPLICATES=0
    fi
    log_message "✓ Found $EMAIL_DUPLICATES duplicate email pairs"
else
    log_message "⚠ Warning: Error while finding duplicate emails"
    EMAIL_DUPLICATES=0
fi

log_message "Step 12: Finding duplicate usernames (case-insensitive)"
USERNAME_RESULT=$(jq -r '
       # Normalize all usernames and emails to lowercase first
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
       ] | @csv' "$DETAILS_FILE" 2>&1)

if [ $? -eq 0 ]; then
    if [ -n "$USERNAME_RESULT" ]; then
        echo "$USERNAME_RESULT" >> "$OUTPUT_FILE"
        USERNAME_DUPLICATES=$(echo "$USERNAME_RESULT" | wc -l)
    else
        USERNAME_DUPLICATES=0
    fi
    log_message "✓ Found $USERNAME_DUPLICATES duplicate username pairs"
else
    log_message "⚠ Warning: Error while finding duplicate usernames"
    USERNAME_DUPLICATES=0
fi

log_message "Step 12c: Finding duplicate names (case-insensitive first and last name)"
NAME_RESULT=$(jq -r '
       # Normalize all names and emails to lowercase first
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
       ] | @csv' "$DETAILS_FILE" 2>&1)

if [ $? -eq 0 ]; then
    if [ -n "$NAME_RESULT" ]; then
        echo "$NAME_RESULT" >> "$OUTPUT_FILE"
        NAME_DUPLICATES=$(echo "$NAME_RESULT" | wc -l)
    else
        NAME_DUPLICATES=0
    fi
    log_message "✓ Found $NAME_DUPLICATES duplicate name pairs"
else
    log_message "⚠ Warning: Error while finding duplicate names"
    NAME_DUPLICATES=0
fi

DUPLICATE_COUNT=$((EMAIL_DUPLICATES + USERNAME_DUPLICATES + NAME_DUPLICATES))

log_message "Step 12b: Creating duplicates JSON file"
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
       ] | flatten' "$DETAILS_FILE")" \
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
       ] | flatten' "$DETAILS_FILE")" \
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
       ] | flatten' "$DETAILS_FILE")" \
   '{duplicate_emails: $email_dups, duplicate_usernames: $username_dups, duplicate_names: $name_dups}' > "$DUPLICATES_JSON_FILE" 2>&1

if [ $? -eq 0 ]; then
    log_message "✓ Duplicates JSON file created"
else
    log_message "⚠ Warning: Error while creating duplicates JSON file"
fi

log_message "Step 13: Cleaning up temporary files"
rm -rf "$TEMP_DIR" 2>/dev/null
log_message "✓ Temporary files removed"

log_message "=========================================="
log_message "Analysis Complete!"
log_message "=========================================="
log_message "Total users analyzed: $USER_COUNT"
log_message "Successfully processed: $PROCESSED_COUNT users"
log_message "Total duplicate pairs found: $DUPLICATE_COUNT"
log_message "  - Duplicate emails: $EMAIL_DUPLICATES"
log_message "  - Duplicate usernames: $USERNAME_DUPLICATES"
log_message "  - Duplicate names: $NAME_DUPLICATES"
log_message "All users CSV saved to: $ALL_USERS_FILE"
log_message "All users JSON saved to: $ALL_USERS_JSON_FILE"
log_message "Duplicates CSV saved to: $OUTPUT_FILE"
log_message "Duplicates JSON saved to: $DUPLICATES_JSON_FILE"
log_message "Log saved to: $LOG_FILE"
log_message "=========================================="

exit 0
