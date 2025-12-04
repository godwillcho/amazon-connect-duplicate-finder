#!/bin/bash

set +e

# ============================================
# CONFIGURATION
# ============================================
MASTER_FILE="./duplicate_users_output/all_users_master.json"
OUTPUT_FOLDER="./duplicate_users_output"
ANALYSIS_LOG="$OUTPUT_FOLDER/username_only_log_$(date +%Y%m%d_%H%M%S).log"

# ============================================
# FUNCTIONS
# ============================================

mkdir -p "$OUTPUT_FOLDER" 2>/dev/null

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
log_message "Amazon Connect Username Duplicate Analysis"
log_message "=========================================="
log_message "Checking ONLY for duplicate usernames (emails)"

log_message "Step 1: Validating master file"
if [ ! -f "$MASTER_FILE" ]; then
    error_exit "Master file not found: $MASTER_FILE"
fi

if ! jq empty "$MASTER_FILE" 2>/dev/null; then
    error_exit "Master file is not valid JSON"
fi

TOTAL_USERS=$(jq '. | length' "$MASTER_FILE")
log_message "✓ Master file found: $MASTER_FILE"
log_message "✓ Total users in master file: $TOTAL_USERS"

log_message "Step 2: Extracting usernames to temp file"
TEMP_DIR=$(mktemp -d)
USER_DATA="$TEMP_DIR/users.txt"

# Extract: ID|USERNAME|EMAIL|FIRSTNAME|LASTNAME
jq -r '.[] | 
    [.Id, .Username, .IdentityInfo.Email // "", .IdentityInfo.FirstName // "", .IdentityInfo.LastName // ""] | 
    @tsv' "$MASTER_FILE" | tr '\t' '|' > "$USER_DATA"

log_message "✓ Extracted $TOTAL_USERS users"

DUPLICATES_CSV="$OUTPUT_FOLDER/duplicate_usernames_$(date +%Y%m%d_%H%M%S).csv"
echo "User1_ID,User1_Username,User1_Email,User1_FirstName,User1_LastName,User2_ID,User2_Username,User2_Email,User2_FirstName,User2_LastName,Reason" > "$DUPLICATES_CSV"

# ============================================
# DUPLICATE USERNAME DETECTION (SUPER FAST)
# ============================================

log_message "Step 3: Finding duplicate usernames (case-insensitive)"

awk -F'|' '
BEGIN {
    count = 0
}
{
    id = $1
    username = tolower($2)
    email = $3
    first = $4
    last = $5
    
    # Skip empty usernames
    if (username == "") next
    
    # Store: username -> id|original_username|email|first|last
    key = username
    if (key in seen) {
        # Found duplicate!
        split(seen[key], prev, "|")
        print prev[1] "," prev[2] "," prev[3] "," prev[4] "," prev[5] "," id "," $2 "," email "," first "," last ",\"Duplicate username/email: " username "\""
        count++
    } else {
        seen[key] = id "|" $2 "|" email "|" first "|" last
    }
}
END {
    print "DUPLICATE_COUNT=" count > "/dev/stderr"
}
' "$USER_DATA" 2>"$TEMP_DIR/count.txt" >> "$DUPLICATES_CSV"

USERNAME_DUPLICATES=$(grep "DUPLICATE_COUNT=" "$TEMP_DIR/count.txt" | cut -d= -f2)
log_message "✓ Found $USERNAME_DUPLICATES duplicate username/email pairs"

# ============================================
# GENERATE ALL USERS CSV
# ============================================

log_message "Step 4: Generating all users CSV"
ALL_USERS_CSV="$OUTPUT_FOLDER/all_users_$(date +%Y%m%d_%H%M%S).csv"
echo "Username,Email,FirstName,LastName,User_ID" > "$ALL_USERS_CSV"

awk -F'|' '{
    print $2 "," $3 "," $4 "," $5 "," $1
}' "$USER_DATA" >> "$ALL_USERS_CSV"

log_message "✓ All users CSV created with $TOTAL_USERS users"

# ============================================
# GENERATE SUMMARY
# ============================================

log_message "Step 5: Generating analysis summary"

SUMMARY_FILE="$OUTPUT_FOLDER/username_analysis_summary.txt"

cat > "$SUMMARY_FILE" << SUMMARY
========================================
Username Duplicate Analysis Summary
========================================
Analysis Date: $(date '+%Y-%m-%d %H:%M:%S')
Master File: $MASTER_FILE
Total Users Analyzed: $TOTAL_USERS

Results:
  Duplicate Username/Email Pairs Found: $USERNAME_DUPLICATES

Output Files:
  - All Users CSV: $ALL_USERS_CSV
  - Duplicates CSV: $DUPLICATES_CSV
  - Analysis Log: $ANALYSIS_LOG
  - Summary: $SUMMARY_FILE

Analysis Method:
  - Case-insensitive username comparison
  - Usernames treated as email addresses
  - Single-pass O(n) algorithm
  - Lightning fast for any dataset size

Next Steps:
  - Review duplicates in: $DUPLICATES_CSV
  - Decide which duplicate users to keep/remove
========================================
SUMMARY

cat "$SUMMARY_FILE" | tee -a "$ANALYSIS_LOG"

# ============================================
# SHOW DUPLICATE DETAILS
# ============================================

if [ $USERNAME_DUPLICATES -gt 0 ]; then
    log_message ""
    log_message "=========================================="
    log_message "DUPLICATE USERNAME/EMAIL DETAILS:"
    log_message "=========================================="
    
    # Show first 10 duplicates as examples
    SHOW_COUNT=10
    if [ $USERNAME_DUPLICATES -lt $SHOW_COUNT ]; then
        SHOW_COUNT=$USERNAME_DUPLICATES
    fi
    
    tail -n +2 "$DUPLICATES_CSV" | head -n $SHOW_COUNT | while IFS=',' read -r id1 user1 email1 first1 last1 id2 user2 email2 first2 last2 reason; do
        # Remove quotes from reason
        reason_clean=$(echo "$reason" | tr -d '"')
        log_message "  • $reason_clean"
        log_message "    User 1: $user1 ($first1 $last1)"
        log_message "    User 2: $user2 ($first2 $last2)"
        log_message ""
    done
    
    if [ $USERNAME_DUPLICATES -gt $SHOW_COUNT ]; then
        log_message "  ... and $((USERNAME_DUPLICATES - SHOW_COUNT)) more (see CSV file for all)"
    fi
else
    log_message ""
    log_message "=========================================="
    log_message "✓ NO DUPLICATE USERNAMES FOUND!"
    log_message "=========================================="
    log_message "All usernames are unique."
fi

# Cleanup
rm -rf "$TEMP_DIR"

log_message ""
log_message "=========================================="
log_message "Analysis Complete!"
log_message "=========================================="
log_message "Total users analyzed: $TOTAL_USERS"
log_message "Duplicate usernames found: $USERNAME_DUPLICATES"
log_message "CSV report: $DUPLICATES_CSV"
log_message "All users list: $ALL_USERS_CSV"
log_message "Summary: $SUMMARY_FILE"
log_message "=========================================="

exit 0