# Quick Start Guide - AWS CloudShell

This guide will get you running the duplicate user finder in AWS CloudShell in under 5 minutes.

## Prerequisites

✅ AWS Account with Amazon Connect access
✅ IAM permissions: `connect:ListUsers` and `connect:DescribeUser`
✅ Amazon Connect instance ID

## Step 1: Open AWS CloudShell

1. Log in to AWS Console
2. Click the CloudShell icon (>_) in the top navigation bar
3. Wait for CloudShell to initialize (~30 seconds)

## Step 2: Get Your Instance ID

If you don't have your instance ID handy:

```bash
# List all Amazon Connect instances
aws connect list-instances --query 'InstanceSummaryList[*].[InstanceAlias,Id]' --output table

# Output will show:
# --------------------------------
# |        ListInstances         |
# +----------------+-------------+
# |  my-connect    | abc-123-... |
# +----------------+-------------+
```

Copy the Instance ID (format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

## Step 3: Clone Repository

```bash
git clone https://github.com/yourusername/amazon-connect-duplicate-finder.git
cd amazon-connect-duplicate-finder
```

## Step 4: Configure Instance ID

```bash
# Open the parallel script
nano find_duplicate_users_parallel.sh

# Find this line (near the top):
INSTANCE_ID="a8fab42a-42a6-446d-b8fc-31ea25332f07"

# Replace with your instance ID:
INSTANCE_ID="your-instance-id-here"

# Save: Ctrl+O, Enter, Ctrl+X
```

## Step 5: Make Executable

```bash
chmod +x find_duplicate_users_parallel.sh
```

## Step 6: Run

```bash
./find_duplicate_users_parallel.sh
```

You'll see output like:

```
[2025-12-03 15:00:00] ==========================================
[2025-12-03 15:00:00] Amazon Connect Duplicate User Finder - Parallel Mode
[2025-12-03 15:00:00] ==========================================
[2025-12-03 15:00:00] Configuration: 8 parallel workers
[2025-12-03 15:00:01] ✓ Keep-alive started (PID: 12345)
[2025-12-03 15:00:02] ✓ Found 44000 users
[2025-12-03 15:00:02] ✓ Estimated processing time: ~90 minutes
```

## Step 7: Monitor Progress (Optional)

### Option A: Watch Main Log
```bash
# Open a new CloudShell tab (Actions > New tab)
cd amazon-connect-duplicate-finder
tail -f ./duplicate_users_output/parallel_main_log_*.log
```

### Option B: Check Worker Progress
```bash
# In a new tab
cd amazon-connect-duplicate-finder
watch -n 10 'grep "Processed" ./duplicate_users_output/worker_*_log_*.log | tail -8'
```

## Step 8: Download Results

When complete (you'll see "Parallel Processing Complete!"), download your files:

```bash
# List generated files
ls -lh ./duplicate_users_output/

# Files generated:
# - all_users_YYYYMMDD_HHMMSS.csv       (All users list)
# - all_users_YYYYMMDD_HHMMSS.json      (All users JSON)
# - duplicate_users_YYYYMMDD_HHMMSS.csv (Duplicates list)
# - duplicate_users_YYYYMMDD_HHMMSS.json (Duplicates JSON)
# - parallel_main_log_YYYYMMDD_HHMMSS.log (Execution log)
# - worker_N_log_YYYYMMDD_HHMMSS.log    (Worker logs)
```

### Download Files from CloudShell

**Method 1: CloudShell Actions**
1. Click "Actions" in CloudShell
2. Select "Download file"
3. Enter path: `./duplicate_users_output/duplicate_users_*.csv`
4. Repeat for other files

**Method 2: Upload to S3**
```bash
# Create S3 bucket (if needed)
aws s3 mb s3://my-connect-audit-reports

# Upload all output files
aws s3 cp ./duplicate_users_output/ s3://my-connect-audit-reports/ --recursive

# Get download URLs (valid for 1 hour)
aws s3 presign s3://my-connect-audit-reports/duplicate_users_20251203_150000.csv
```

## Expected Timelines

| User Count | Processing Time | When Complete |
|-----------|----------------|---------------|
| 1,000 | ~2 minutes | Coffee break ☕ |
| 5,000 | ~10 minutes | Short meeting 📊 |
| 10,000 | ~20 minutes | Lunch time 🍔 |
| 25,000 | ~50 minutes | Focus work session 💻 |
| 44,000 | ~90 minutes | Long meeting 📞 |
| 100,000 | ~3 hours | End of day 🌅 |

## Troubleshooting Quick Fixes

### "Permission denied"
```bash
chmod +x find_duplicate_users_parallel.sh
```

### "Instance ID not configured"
```bash
nano find_duplicate_users_parallel.sh
# Update INSTANCE_ID line
```

### "Access Denied"
Your IAM user needs these permissions:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "connect:ListUsers",
      "connect:DescribeUser"
    ],
    "Resource": "*"
  }]
}
```

### CloudShell Disconnected
- The script continues running even if you disconnect
- Reconnect and check logs:
```bash
cd amazon-connect-duplicate-finder
tail -20 ./duplicate_users_output/parallel_main_log_*.log
```

## Next Steps

1. **Review duplicates**: Open CSV in Excel/Google Sheets
2. **Analyze patterns**: Check why duplicates exist
3. **Plan cleanup**: Coordinate with team before deletion
4. **Schedule regular audits**: Run monthly or quarterly

## Tips for Large Instances (10,000+ Users)

1. **Run during off-peak hours** (nights/weekends)
2. **Monitor the first run** to ensure everything works
3. **Keep CloudShell tab open** (or use nohup for very long runs)
4. **Archive results** to S3 for historical tracking

## Common Questions

**Q: Will this affect my production Connect instance?**
A: No, it's read-only and doesn't impact active calls or agents.

**Q: Can I run this multiple times?**
A: Yes, run as often as needed. Each run creates new timestamped files.

**Q: What if I have more than 100,000 users?**
A: Consider splitting by organizational unit or running over multiple days.

**Q: Is this free?**
A: CloudShell is free. You only pay for standard Connect API calls (minimal cost).

## Success Checklist

- [ ] CloudShell opened
- [ ] Repository cloned
- [ ] Instance ID configured
- [ ] Script made executable
- [ ] Script running
- [ ] Logs showing progress
- [ ] Results downloaded
- [ ] Duplicates reviewed

---

**Need help?** Open an issue on GitHub or check the [full documentation](README.md).

**Time to complete**: 5 minutes setup + processing time based on user count
