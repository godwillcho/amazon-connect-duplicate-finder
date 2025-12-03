#!/bin/bash

set +e

# ============================================
# CONFIGURATION
# ============================================
OUTPUT_FOLDER="./duplicate_users_output"
MASTER_FILE="$OUTPUT_FOLDER/all_users_master.json"
ANALYSIS_LOG="$OUTPUT_FOLDER/analysis_log_$(date +%Y%m%d_%H%M%S).log"

# Analysis Options
CHECK_EMAILS=true         # Check for duplicate emails
CHECK_USERNAMES=true      # Check for duplicate usernames
CHECK_NAMES=true          # Check for duplicate names (first + last)
MIN_USERS=1              # Minimum users required before analysis

# ============================================
# FUNCTIONS
# ============================================

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ANALYSIS_LOG"
}

error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# ============================================
# MAIN EXECUTION
# ============================================

log_message "=========================================="
log_message "Amazon Connect Duplicate Analysis"
log_message "=========================================="

log_message "Step 1: Checking prerequisites"
if ! command -v jq &> /dev/null; then
    error_exit "jq is not installed"
fi
log_message "✓ Prerequisites verified"

log_message "Step 2: Validating master file"
if [ ! -f "$MASTER_FILE" ]; then
    error_exit "Master file not found: $MASTER_FILE. Run collect_users.sh first."
fi

# Verify file is valid JSON
USER_COUNT=$(jq '. | length' "$MASTER_FILE" 2>/dev/null)
if [ $? -ne 0 ]; then
    error_exit "Master file is not valid JSON: $MASTER_FILE"
fi

log_message "✓ Master file found: $MASTER_FILE"
log_message "✓ Total users in master file: $USER_COUNT"

# Check minimum users requirement
if [ $USER_COUNT -lt $MIN_USERS ]; then
    error_exit "Not enough users for analysis. Have: $USER_COUNT, Need: $MIN_USERS"
fi

log_message "Step 3: Creating output files"
DUPLICATES_CSV="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).csv"
DUPLICATES_JSON="$OUTPUT_FOLDER/duplicate_users_$(date +%Y%m%d_%H%M%S).json"
ALL_USERS_CSV="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).csv"

# Create CSV header
echo "User1_ID,User1_Username,User1_Email,User1_FirstName,User1_LastName,User2_ID,User2_Username,User2_Email,User2_FirstName,User2_LastName,Reason" > "$DUPLICATES_CSV"
log_message "✓ Output files prepared"

log_message "Step 4: Generating all users CSV"
echo "Username,Email,FirstName,LastName,User_ID,ARN" > "$ALL_USERS_CSV"

jq -r '.[] | 
       [
         .Username // "",
         .IdentityInfo.Email // "",
         .IdentityInfo.FirstName // "",
         .IdentityInfo.LastName // "",
         .Id // "",
         .Arn // ""
       ] | @csv' "$MASTER_FILE" >> "$ALL_USERS_CSV" 2>&1

ALL_USERS_COUNT=$(($(wc -l < "$ALL_USERS_CSV") - 1))
log_message "✓ All users CSV created with $ALL_USERS_COUNT users"

EMAIL_DUPLICATES=0
USERNAME_DUPLICATES=0
NAME_DUPLICATES=0

# ============================================
# DUPLICATE EMAIL DETECTION
# ============================================

if [ "$CHECK_EMAILS" = true ]; then
    log_message "Step 5: Finding duplicate emails (case-insensitive)"
    
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
           ] | @csv' "$MASTER_FILE" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$EMAIL_RESULT" ]; then
        echo "$EMAIL_RESULT" >> "$DUPLICATES_CSV"
        EMAIL_DUPLICATES=$(echo "$EMAIL_RESULT" | wc -l)
    else
        EMAIL_DUPLICATES=0
    fi
    log_message "✓ Found $EMAIL_DUPLICATES duplicate email pairs"
else
    log_message "Step 5: Skipping email duplicate check (disabled)"
fi

# ============================================
# DUPLICATE USERNAME DETECTION
# ============================================

if [ "$CHECK_USERNAMES" = true ]; then
    log_message "Step 6: Finding duplicate usernames (case-insensitive)"
    
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
           ] | @csv' "$MASTER_FILE" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$USERNAME_RESULT" ]; then
        echo "$USERNAME_RESULT" >> "$DUPLICATES_CSV"
        USERNAME_DUPLICATES=$(echo "$USERNAME_RESULT" | wc -l)
    else
        USERNAME_DUPLICATES=0
    fi
    log_message "✓ Found $USERNAME_DUPLICATES duplicate username pairs"
else
    log_message "Step 6: Skipping username duplicate check (disabled)"
fi

# ============================================
# DUPLICATE NAME DETECTION
# ============================================

if [ "$CHECK_NAMES" = true ]; then
    log_message "Step 7: Finding duplicate names (case-insensitive)"
    
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
           ] | @csv' "$MASTER_FILE" 2>&1)
    
    if [ $? -eq 0 ] && [ -n "$NAME_RESULT" ]; then
        echo "$NAME_RESULT" >> "$DUPLICATES_CSV"
        NAME_DUPLICATES=$(echo "$NAME_RESULT" | wc -l)
    else
        NAME_DUPLICATES=0
    fi
    log_message "✓ Found $NAME_DUPLICATES duplicate name pairs"
else
    log_message "Step 7: Skipping name duplicate check (disabled)"
fi

DUPLICATE_COUNT=$((EMAIL_DUPLICATES + USERNAME_DUPLICATES + NAME_DUPLICATES))

# ============================================
# GENERATE JSON REPORT
# ============================================

log_message "Step 8: Creating duplicates JSON report"

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
       ] | flatten' "$MASTER_FILE")" \
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
       ] | flatten' "$MASTER_FILE")" \
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
       ] | flatten' "$MASTER_FILE")" \
   '{
      analysis_date: "'$(date -Iseconds)'",
      total_users_analyzed: '$USER_COUNT',
      duplicate_emails: $email_dups,
      duplicate_usernames: $username_dups,
      duplicate_names: $name_dups,
      summary: {
        total_duplicates: '$DUPLICATE_COUNT',
        email_duplicates: '$EMAIL_DUPLICATES',
        username_duplicates: '$USERNAME_DUPLICATES',
        name_duplicates: '$NAME_DUPLICATES'
      }
    }' > "$DUPLICATES_JSON" 2>&1

log_message "✓ Duplicates JSON report created"

# ============================================
# GENERATE SUMMARY
# ============================================

log_message "Step 9: Generating analysis summary"

SUMMARY_FILE="$OUTPUT_FOLDER/analysis_summary.txt"

cat > "$SUMMARY_FILE" << EOF
========================================
Duplicate Analysis Summary
========================================
Analysis Date: $(date '+%Y-%m-%d %H:%M:%S')
Master File: $MASTER_FILE

Users Analyzed: $USER_COUNT
Total Duplicate Pairs: $DUPLICATE_COUNT

Breakdown:
  - Duplicate Emails: $EMAIL_DUPLICATES
  - Duplicate Usernames: $USERNAME_DUPLICATES
  - Duplicate Names: $NAME_DUPLICATES

Output Files:
  - All Users CSV: $ALL_USERS_CSV
  - Duplicates CSV: $DUPLICATES_CSV
  - Duplicates JSON: $DUPLICATES_JSON
  - Analysis Log: $ANALYSIS_LOG

========================================
EOF

cat "$SUMMARY_FILE" | tee -a "$ANALYSIS_LOG"

log_message "=========================================="
log_message "Analysis Complete!"
log_message "=========================================="
log_message "Users analyzed: $USER_COUNT"
log_message "Total duplicates: $DUPLICATE_COUNT"
log_message "  - Email duplicates: $EMAIL_DUPLICATES"
log_message "  - Username duplicates: $USERNAME_DUPLICATES"
log_message "  - Name duplicates: $NAME_DUPLICATES"
log_message "CSV report: $DUPLICATES_CSV"
log_message "JSON report: $DUPLICATES_JSON"
log_message "=========================================="

# Return exit code based on duplicates found
if [ $DUPLICATE_COUNT -gt 0 ]; then
    exit 0  # Success - duplicates found
else
    exit 0  # Success - no duplicates found
fi
