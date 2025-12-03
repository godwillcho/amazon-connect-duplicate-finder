# Amazon Connect Duplicate User Finder

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell_Script-%23121011.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/connect/)

A production-ready bash script for Amazon Connect administrators to identify and report duplicate user accounts. The tool performs comprehensive duplicate detection across emails, usernames, and full names with case-insensitive matching, generating detailed reports in both CSV and JSON formats.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Output Files](#output-files)
- [How It Works](#how-it-works)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

## Features

### Core Capabilities

- ✅ **Multi-Criteria Duplicate Detection**
  - Email addresses (case-insensitive)
  - Usernames (case-insensitive)
  - Full names - first and last name combinations (case-insensitive)

- 📊 **Flexible Output Formats**
  - CSV reports for spreadsheet analysis
  - JSON files for programmatic integration
  - Detailed execution logs with timestamps

- 🛡️ **Enterprise-Grade Reliability**
  - Comprehensive error handling and validation
  - Graceful degradation on individual user fetch failures
  - Automatic cleanup of temporary resources
  - Progress tracking with real-time updates

- 🚀 **Production Ready**
  - Validates all prerequisites before execution
  - Detailed logging for audit trails
  - Safe read-only operations on Amazon Connect
  - No external dependencies beyond AWS CLI and jq

## Prerequisites

- **AWS CLI** - Installed and configured with appropriate credentials
- **jq** - JSON processor for parsing AWS responses
- **Amazon Connect Instance** - Valid instance ID with read permissions

### AWS Permissions Required

The AWS credentials must have the following Amazon Connect permissions:
- `connect:ListUsers`
- `connect:DescribeUser`

## Configuration

Before running the script, you must configure your Amazon Connect instance ID.

### Required Configuration

Open the script and set your instance ID:

```bash
# Edit the script
nano find_duplicate_users.sh

# Update this line with your Amazon Connect instance ID
INSTANCE_ID="a8fab42a-42a6-446d-b8fc-31ea25332f07"
```

### Optional Configuration

You can also customize the output directory:

```bash
# Default: ./duplicate_users_output
OUTPUT_FOLDER="./duplicate_users_output"

# Example: Use absolute path
OUTPUT_FOLDER="/var/log/connect-audits"

# Example: Use home directory
OUTPUT_FOLDER="$HOME/connect-reports"
```

### Finding Your Amazon Connect Instance ID

1. Sign in to the AWS Management Console
2. Navigate to Amazon Connect
3. Select your instance
4. The Instance ID is displayed in the instance details (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

Alternatively, use AWS CLI:
```bash
aws connect list-instances --query 'InstanceSummaryList[*].[InstanceAlias,Id]' --output table
```

## Installation

### Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/amazon-connect-duplicate-finder.git

# Navigate to the directory
cd amazon-connect-duplicate-finder

# Make the script executable
chmod +x find_duplicate_users.sh

# Configure your instance ID (see Configuration section)
nano find_duplicate_users.sh

# Run the script
./find_duplicate_users.sh
```

### System Requirements

| Requirement | Version | Installation |
|------------|---------|--------------|
| AWS CLI | 2.x or later | [Install Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |
| jq | 1.5 or later | See platform-specific instructions below |
| Bash | 4.0 or later | Pre-installed on most Unix systems |

#### Installing jq

**Ubuntu/Debian:**
```bash
sudo apt-get update && sudo apt-get install -y jq
```

**macOS:**
```bash
brew install jq
```

**CentOS/RHEL:**
```bash
sudo yum install -y jq
```

**Amazon Linux 2:**
```bash
sudo yum install -y jq
```

## Usage

### Basic Usage

```bash
./find_duplicate_users.sh
```

### What the Script Does

The script executes the following workflow:

1. ✓ **Pre-flight Checks** - Validates AWS CLI, jq, credentials, and configuration
2. ✓ **Data Collection** - Fetches all users from Amazon Connect instance
3. ✓ **Detail Retrieval** - Retrieves comprehensive information for each user
4. ✓ **Duplicate Analysis** - Performs case-insensitive comparison across:
   - Email addresses
   - Usernames  
   - Full names (first + last)
5. ✓ **Report Generation** - Creates CSV and JSON reports
6. ✓ **Cleanup** - Removes temporary files

### Execution Time

Processing time scales linearly with user count:
- **~1 second per user** for data retrieval
- **Example**: 100 users ≈ 2 minutes total execution time

### Running in Background

For large user bases, run in background:

```bash
# Run in background with output to log
nohup ./find_duplicate_users.sh > execution.log 2>&1 &

# Check progress
tail -f execution.log

# Or check the generated log file
tail -f ./duplicate_users_output/duplicate_users_log_*.log
```

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

## Examples

### Example 1: Duplicate Email Detection

**Scenario**: Two users with same email but different cases

```
User 1: john.smith@company.com
User 2: JOHN.SMITH@COMPANY.COM
```

**Result**: Identified as duplicates with reason: `Duplicate email: john.smith@company.com`

### Example 2: Duplicate Username Detection

**Scenario**: Two users with same username but different emails

```
User 1: jsmith123 (john.smith@company.com)
User 2: JSmith123 (j.smith@company.com)
```

**Result**: Identified as duplicates with reason: `Duplicate username: jsmith123`

### Example 3: Duplicate Name Detection

**Scenario**: Two users with same first and last name but different emails

```
User 1: John Smith (john.smith@company.com)
User 2: JOHN SMITH (jsmith@company.com)
```

**Result**: Identified as duplicates with reason: `Duplicate name: john smith`

### Sample CSV Output

```csv
User1_ID,User1_Username,User1_Email,User1_FirstName,User1_LastName,User2_ID,User2_Username,User2_Email,User2_FirstName,User2_LastName,Reason
abc-123,jsmith,john.smith@company.com,John,Smith,def-456,jsmith2,JOHN.SMITH@COMPANY.COM,John,Smith,"Duplicate email: john.smith@company.com"
```

### Sample JSON Output

```json
{
  "duplicate_emails": [
    {
      "user1": {
        "Id": "abc-123",
        "Username": "jsmith",
        "IdentityInfo": {
          "Email": "john.smith@company.com",
          "FirstName": "John",
          "LastName": "Smith"
        }
      },
      "user2": {
        "Id": "def-456",
        "Username": "jsmith2",
        "IdentityInfo": {
          "Email": "john.smith@company.com",
          "FirstName": "John",
          "LastName": "Smith"
        }
      },
      "reason": "Duplicate email: john.smith@company.com"
    }
  ],
  "duplicate_usernames": [],
  "duplicate_names": []
}
```

## Troubleshooting

### Common Issues

<details>
<summary><b>AWS Credentials Error</b></summary>

**Error Message:**
```
ERROR: AWS credentials not configured or invalid
```

**Solution:**
```bash
# Configure AWS CLI with your credentials
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-1"

# Verify credentials
aws sts get-caller-identity
```
</details>

<details>
<summary><b>Instance ID Not Configured</b></summary>

**Error Message:**
```
ERROR: Instance ID not configured. Please set INSTANCE_ID variable in the script.
```

**Solution:**
Edit the script and update the INSTANCE_ID variable:
```bash
nano find_duplicate_users.sh
# Change: INSTANCE_ID="your-instance-id-here"
# To: INSTANCE_ID="a8fab42a-42a6-446d-b8fc-31ea25332f07"
```
</details>

<details>
<summary><b>Permission Denied</b></summary>

**Error Message:**
```
bash: ./find_duplicate_users.sh: Permission denied
```

**Solution:**
```bash
chmod +x find_duplicate_users.sh
```
</details>

<details>
<summary><b>jq Not Found</b></summary>

**Error Message:**
```
ERROR: jq is not installed or not in PATH
```

**Solution:**
Install jq for your platform:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# CentOS/RHEL
sudo yum install jq
```
</details>

<details>
<summary><b>Insufficient Permissions</b></summary>

**Error Message:**
```
An error occurred (AccessDeniedException) when calling the ListUsers operation
```

**Solution:**
Ensure your IAM user/role has these permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "connect:ListUsers",
        "connect:DescribeUser"
      ],
      "Resource": "arn:aws:connect:*:*:instance/*"
    }
  ]
}
```
</details>

### Getting Help

If you encounter issues not covered here:

1. Check the execution log in `./duplicate_users_output/duplicate_users_log_*.log`
2. Run with verbose output: `bash -x ./find_duplicate_users.sh`
3. Open an issue on GitHub with:
   - Error message
   - Log file excerpt
   - AWS CLI version: `aws --version`
   - jq version: `jq --version`

## Use Cases

This tool is valuable for various Amazon Connect administration scenarios:

| Use Case | Description | Frequency |
|----------|-------------|-----------|
| **User Cleanup** | Identify and remove duplicate user accounts to maintain data integrity | Monthly |
| **Data Quality Audit** | Ensure user data integrity in Amazon Connect for compliance | Quarterly |
| **Migration Validation** | Verify no duplicates were created during data migration or system integration | After each migration |
| **Access Management** | Identify users with multiple accounts for consolidation | As needed |
| **Onboarding Review** | Detect duplicate accounts created during bulk user imports | After bulk operations |
| **Security Audit** | Identify potential security risks from duplicate accounts | Quarterly |

## Best Practices

### Regular Audits

```bash
# Schedule monthly audits with cron
0 2 1 * * /path/to/find_duplicate_users.sh >> /var/log/connect-audit.log 2>&1
```

### Archive Reports

```bash
# Create dated archive directory
mkdir -p archives/$(date +%Y-%m)
mv duplicate_users_output/*.{csv,json,log} archives/$(date +%Y-%m)/
```

### Integration with CI/CD

```bash
# Add to deployment validation
./find_duplicate_users.sh
DUPLICATES=$(tail -1 duplicate_users_output/duplicate_users_log_*.log | grep -oP 'Total duplicate pairs found: \K\d+')
if [ "$DUPLICATES" -gt 0 ]; then
    echo "Warning: $DUPLICATES duplicate pairs detected"
    exit 1
fi
```

### Team Collaboration

1. Commit output files to a separate audit repository
2. Review duplicates with team before cleanup
3. Document cleanup actions in tickets
4. Maintain historical records for compliance

## Limitations

- Script requires read access to all users in the Amazon Connect instance
- Processing time increases with the number of users (approximately 1 second per user)
- Temporary files are created during execution but cleaned up automatically
- Network connectivity to AWS is required throughout execution

## Contributing

We welcome contributions from the community! Here's how you can help:

### Ways to Contribute

- 🐛 **Report bugs** - Open an issue with detailed reproduction steps
- 💡 **Suggest features** - Share ideas for improvements
- 📖 **Improve documentation** - Fix typos, add examples, clarify instructions
- 🔧 **Submit pull requests** - Fix bugs or implement new features

### Development Guidelines

1. **Fork the repository**
   ```bash
   git clone https://github.com/yourusername/amazon-connect-duplicate-finder.git
   cd amazon-connect-duplicate-finder
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation as needed

3. **Test thoroughly**
   - Test with various user counts
   - Verify error handling
   - Check output file formats

4. **Submit a pull request**
   - Describe your changes clearly
   - Reference any related issues
   - Include test results

### Code of Conduct

- Be respectful and inclusive
- Provide constructive feedback
- Focus on the issue, not the person
- Help create a welcoming environment

### Reporting Issues

When reporting issues, please include:

- **Environment details**: OS, Bash version, AWS CLI version, jq version
- **Error messages**: Complete error output
- **Steps to reproduce**: Clear reproduction steps
- **Expected vs actual behavior**: What you expected and what happened
- **Log files**: Relevant portions of log files (sanitized of sensitive data)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built for Amazon Connect administrators and DevOps teams
- Uses AWS CLI and jq for reliable data processing
- Inspired by the need for clean user management in enterprise contact centers

## Roadmap

Future enhancements under consideration:

- [ ] Support for multiple Amazon Connect instances in one run
- [ ] Automatic duplicate remediation with user confirmation
- [ ] Email notifications for duplicate detection
- [ ] HTML report generation
- [ ] Integration with AWS Lambda for scheduled execution
- [ ] Duplicate scoring based on multiple factors
- [ ] Export to additional formats (Excel, PDF)

## Support

### Documentation

- [Amazon Connect Documentation](https://docs.aws.amazon.com/connect/)
- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [jq Manual](https://stedolan.github.io/jq/manual/)

### Getting Help

- 📖 Check the [Troubleshooting](#troubleshooting) section
- 🐛 [Open an issue](https://github.com/yourusername/amazon-connect-duplicate-finder/issues) for bugs
- 💬 [Start a discussion](https://github.com/yourusername/amazon-connect-duplicate-finder/discussions) for questions
- 📧 Contact the maintainers for security concerns

### Community

- ⭐ Star this repository if you find it useful
- 🔄 Share with your team and network
- 🤝 Contribute improvements

---

**Made with ❤️ for Amazon Connect administrators**

*Maintained by the community • Last updated: December 2025*
