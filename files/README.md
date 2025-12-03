# Amazon Connect Duplicate User Finder

A bash script that identifies duplicate users in Amazon Connect by comparing emails, usernames, and full names (case-insensitive). The script generates detailed reports in both CSV and JSON formats.

## Features

- **Comprehensive Duplicate Detection**
  - Duplicate email addresses (case-insensitive)
  - Duplicate usernames (case-insensitive)
  - Duplicate names (first name + last name, case-insensitive)

- **Multiple Output Formats**
  - CSV reports for easy viewing in spreadsheet applications
  - JSON files for programmatic processing
  - Detailed execution logs

- **Robust Error Handling**
  - Validates all prerequisites before execution
  - Continues processing even if individual user fetches fail
  - Detailed logging of each step

- **Progress Tracking**
  - Real-time progress updates for each user processed
  - Timestamped log entries
  - Summary statistics at completion

## Prerequisites

- **AWS CLI** - Installed and configured with appropriate credentials
- **jq** - JSON processor for parsing AWS responses
- **Amazon Connect Instance** - Valid instance ID with read permissions

### AWS Permissions Required

The AWS credentials must have the following Amazon Connect permissions:
- `connect:ListUsers`
- `connect:DescribeUser`

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/amazon-connect-duplicate-finder.git
cd amazon-connect-duplicate-finder
```

2. Make the script executable:
```bash
chmod +x find_duplicate_users.sh
```

3. Configure the script by editing the following variables:
```bash
INSTANCE_ID="your-amazon-connect-instance-id"
OUTPUT_FOLDER="./duplicate_users_output"  # Optional: change output directory
```

## Usage

Run the script:
```bash
./find_duplicate_users.sh
```

The script will:
1. Validate all prerequisites (AWS CLI, jq, credentials)
2. Fetch all users from your Amazon Connect instance
3. Retrieve detailed information for each user
4. Analyze users for duplicates based on:
   - Email addresses (case-insensitive)
   - Usernames (case-insensitive)
   - Full names (first + last name, case-insensitive)
5. Generate comprehensive reports

## Output Files

The script creates a timestamped output directory with the following files:

### 1. All Users CSV (`all_users_YYYYMMDD_HHMMSS.csv`)
Contains all users with the following columns:
- Username
- Email
- FirstName
- LastName
- User_ID
- ARN

### 2. All Users JSON (`all_users_YYYYMMDD_HHMMSS.json`)
Complete user details in JSON format with all fields from Amazon Connect API.

### 3. Duplicates CSV (`duplicate_users_YYYYMMDD_HHMMSS.csv`)
Lists all duplicate pairs with columns:
- User1_ID, User1_Username, User1_Email, User1_FirstName, User1_LastName
- User2_ID, User2_Username, User2_Email, User2_FirstName, User2_LastName
- Reason (why they're considered duplicates)

### 4. Duplicates JSON (`duplicate_users_YYYYMMDD_HHMMSS.json`)
Structured JSON containing three arrays:
```json
{
  "duplicate_emails": [...],
  "duplicate_usernames": [...],
  "duplicate_names": [...]
}
```

Each entry contains:
- `user1`: Complete user object
- `user2`: Complete user object
- `reason`: Explanation of why they're duplicates

### 5. Execution Log (`duplicate_users_log_YYYYMMDD_HHMMSS.log`)
Detailed timestamped log of all operations performed.

## Example Output

```
==========================================
Starting Amazon Connect Duplicate User Finder
==========================================
Step 1: Verifying output folder
✓ Output folder ready: ./duplicate_users_output
Step 2: Checking AWS CLI availability
✓ AWS CLI found
Step 3: Checking jq availability
✓ jq found
Step 4: Verifying AWS credentials
✓ AWS credentials verified
Step 5: Fetching users from Amazon Connect instance
✓ Successfully fetched 14 users
Step 6: Creating temporary working directory
✓ Temporary directory created
Step 7: Fetching detailed user information for all users
  ✓ Processed user 1 of 14
  ✓ Processed user 2 of 14
  ...
Step 8: Processing user data
✓ Successfully processed 14 user records
Step 9: Creating all users CSV file
✓ All users CSV created with 14 users
Step 9b: Creating all users JSON file
✓ All users JSON file created
Step 10: Creating duplicates CSV file
✓ CSV header created
Step 11: Finding duplicate emails (case-insensitive)
✓ Found 7 duplicate email pairs
Step 12: Finding duplicate usernames (case-insensitive)
✓ Found 0 duplicate username pairs
Step 12c: Finding duplicate names (case-insensitive)
✓ Found 2 duplicate name pairs
Step 12b: Creating duplicates JSON file
✓ Duplicates JSON file created
Step 13: Cleaning up temporary files
✓ Temporary files removed
==========================================
Analysis Complete!
==========================================
Total users analyzed: 14
Successfully processed: 14 users
Total duplicate pairs found: 9
  - Duplicate emails: 7
  - Duplicate usernames: 0
  - Duplicate names: 2
All users CSV saved to: ./duplicate_users_output/all_users_20251203_153830.csv
All users JSON saved to: ./duplicate_users_output/all_users_20251203_153830.json
Duplicates CSV saved to: ./duplicate_users_output/duplicate_users_20251203_153817.csv
Duplicates JSON saved to: ./duplicate_users_output/duplicate_users_20251203_153830.json
Log saved to: ./duplicate_users_output/duplicate_users_log_20251203_153817.log
==========================================
```

## How It Works

### Duplicate Detection Logic

1. **Email Duplicates**
   - Converts all email addresses to lowercase
   - Compares every user's email with every other user's email
   - Example: `JOHN.DOE@EXAMPLE.COM` matches `john.doe@example.com`

2. **Username Duplicates**
   - Converts all usernames to lowercase
   - Finds users with identical usernames but different emails
   - Example: `JohnDoe123` matches `johndoe123`

3. **Name Duplicates**
   - Converts first and last names to lowercase
   - Finds users with identical first AND last names but different emails
   - Both first and last names must be present and match
   - Example: `John Smith` matches `JOHN SMITH`

### Case Sensitivity

All comparisons are **case-insensitive**. The script normalizes all text to lowercase before comparison to ensure that variations in capitalization are properly detected as duplicates.

## Troubleshooting

### AWS Credentials Error
```
ERROR: AWS credentials not configured or invalid
```
**Solution**: Configure AWS CLI with valid credentials:
```bash
aws configure
```

### Instance ID Error
```
ERROR: Instance ID not configured
```
**Solution**: Edit the script and set your Amazon Connect instance ID:
```bash
INSTANCE_ID="your-instance-id-here"
```

### Permission Denied
```
bash: ./find_duplicate_users.sh: Permission denied
```
**Solution**: Make the script executable:
```bash
chmod +x find_duplicate_users.sh
```

### jq Not Found
```
ERROR: jq is not installed or not in PATH
```
**Solution**: Install jq:
- **Ubuntu/Debian**: `sudo apt-get install jq`
- **macOS**: `brew install jq`
- **CentOS/RHEL**: `sudo yum install jq`

## Configuration Options

You can customize the following variables in the script:

```bash
# Amazon Connect Instance ID (required)
INSTANCE_ID="a8fab42a-42a6-446d-b8fc-31ea25332f07"

# Output folder location (optional)
OUTPUT_FOLDER="./duplicate_users_output"
```

## Use Cases

- **User Cleanup**: Identify and remove duplicate user accounts
- **Data Quality Audit**: Ensure user data integrity in Amazon Connect
- **Migration Validation**: Verify no duplicates were created during data migration
- **Compliance**: Maintain clean user records for audit purposes
- **Access Management**: Identify users with multiple accounts for consolidation

## Limitations

- Script requires read access to all users in the Amazon Connect instance
- Processing time increases with the number of users (approximately 1 second per user)
- Temporary files are created during execution but cleaned up automatically
- Network connectivity to AWS is required throughout execution

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Author

Created for Amazon Connect administrators to maintain clean user databases.

## Support

For issues, questions, or contributions, please open an issue in the GitHub repository.
