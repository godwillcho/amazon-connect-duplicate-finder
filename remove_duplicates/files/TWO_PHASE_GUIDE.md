# Two-Phase Duplicate Detection System

Complete guide for the collection and analysis approach for Amazon Connect duplicate user detection.

## 📋 Overview

This system uses a **two-phase approach**:

1. **Phase 1: Data Collection** - Fetch user data and save to master file (can run multiple times)
2. **Phase 2: Duplicate Analysis** - Analyze master file for duplicates (run once after collection)

## 🎯 Why Two-Phase?

### ✅ Advantages:
- **Resumable** - Stop and continue collection anytime
- **Flexible** - Collect in chunks over days/weeks
- **Distributed** - Run multiple collection sessions simultaneously
- **Fast Analysis** - No API calls during duplicate detection
- **Reusable** - Analyze data multiple times with different criteria
- **Safe** - Separate data collection from analysis

### 📊 Perfect for 44,000 Users:
```
Day 1: collect_users.sh (users 1-11,000)      → 22 min
Day 2: collect_users.sh (users 11,001-22,000) → 22 min
Day 3: collect_users.sh (users 22,001-33,000) → 22 min
Day 4: collect_users.sh (users 33,001-44,000) → 22 min
Then:  analyze_duplicates.sh                  → 10 sec

Total: ~90 minutes split over 4 days + instant analysis
```

---

## 🔧 Script 1: collect_users.sh

### Purpose
Collects detailed user information from Amazon Connect and appends to a master file.

### Configuration

```bash
# Edit at top of script
INSTANCE_ID="a8fab42a-42a6-446d-b8fc-31ea25332f07"
START_USER=1              # Where to start (position in list)
END_USER=10000            # Where to end (position in list)
PARALLEL_PROCESSES=8      # Number of workers
SKIP_EXISTING=true        # Skip already collected users
```

### Usage Examples

#### Example 1: First Collection (Test)
```bash
# Collect first 1,000 users as a test
nano collect_users.sh
# Set: START_USER=1, END_USER=1000

./collect_users.sh
```

#### Example 2: Full Collection in Batches
```bash
# Batch 1 (Day 1)
START_USER=1
END_USER=11000
./collect_users.sh

# Batch 2 (Day 2)
START_USER=11001
END_USER=22000
./collect_users.sh

# Batch 3 (Day 3)
START_USER=22001
END_USER=33000
./collect_users.sh

# Batch 4 (Day 4)
START_USER=33001
END_USER=44000
./collect_users.sh
```

#### Example 3: Resume After Interruption
```bash
# If script fails at user 15,234
START_USER=15234
END_USER=44000
./collect_users.sh
```

#### Example 4: Parallel Collection (Multiple Sessions)
```bash
# CloudShell Session 1:
START_USER=1
END_USER=11000
./collect_users.sh

# CloudShell Session 2 (simultaneously):
START_USER=11001
END_USER=22000
./collect_users.sh

# CloudShell Session 3 (simultaneously):
START_USER=22001
END_USER=33000
./collect_users.sh

# CloudShell Session 4 (simultaneously):
START_USER=33001
END_USER=44000
./collect_users.sh

# All write to same master file!
# Total time: ~22 minutes instead of 90!
```

### What It Does

1. ✅ Validates prerequisites (AWS CLI, jq, credentials)
2. ✅ Fetches user list from Amazon Connect
3. ✅ Extracts the specified range (START_USER to END_USER)
4. ✅ Splits range into chunks for parallel processing
5. ✅ Launches workers to fetch detailed user info
6. ✅ Each worker checks if user already exists (if SKIP_EXISTING=true)
7. ✅ Merges worker results
8. ✅ **Appends** new users to master file (doesn't overwrite)
9. ✅ Generates collection summary

### Output Files

```
duplicate_users_output/
├── all_users_master.json              ← Master file (all collected users)
├── collection_log_YYYYMMDD.log        ← Collection execution log
├── collection_worker_N_YYYYMMDD.log   ← Individual worker logs
└── collection_summary.txt             ← Summary of what was collected
```

### Progress Tracking

The script shows:
- Range being collected
- Number of users in master file before collection
- New users collected in this session
- Total users after collection
- Percentage complete

---

## 🔍 Script 2: analyze_duplicates.sh

### Purpose
Analyzes the master file for duplicate users (emails, usernames, names).

### Configuration

```bash
# Edit at top of script
MASTER_FILE="./duplicate_users_output/all_users_master.json"
CHECK_EMAILS=true         # Check for duplicate emails
CHECK_USERNAMES=true      # Check for duplicate usernames
CHECK_NAMES=true          # Check for duplicate names
MIN_USERS=1              # Minimum users required before analysis
```

### Usage

```bash
# Simply run after collection is complete
./analyze_duplicates.sh
```

### What It Does

1. ✅ Validates master file exists and is valid JSON
2. ✅ Checks minimum user requirement
3. ✅ Generates all users CSV (for reference)
4. ✅ Finds duplicate emails (case-insensitive)
5. ✅ Finds duplicate usernames (case-insensitive)
6. ✅ Finds duplicate names (case-insensitive first+last)
7. ✅ Generates CSV and JSON duplicate reports
8. ✅ Creates analysis summary

### Output Files

```
duplicate_users_output/
├── all_users_YYYYMMDD.csv             ← All users list
├── duplicate_users_YYYYMMDD.csv       ← Duplicate pairs
├── duplicate_users_YYYYMMDD.json      ← Duplicate pairs (JSON)
├── analysis_log_YYYYMMDD.log          ← Analysis log
└── analysis_summary.txt               ← Summary
```

### Performance

- **44,000 users**: ~10 seconds
- **No API calls** - reads from file only
- **Can run multiple times** - doesn't modify master file

---

## 🚀 Complete Workflow

### For 44,000 Users

#### Option A: Collect Over Multiple Days (Safest)

**Day 1:**
```bash
nano collect_users.sh
# Set: START_USER=1, END_USER=11000
./collect_users.sh
# Time: ~22 minutes
```

**Day 2:**
```bash
nano collect_users.sh
# Set: START_USER=11001, END_USER=22000
./collect_users.sh
# Time: ~22 minutes
```

**Day 3:**
```bash
nano collect_users.sh
# Set: START_USER=22001, END_USER=33000
./collect_users.sh
# Time: ~22 minutes
```

**Day 4:**
```bash
nano collect_users.sh
# Set: START_USER=33001, END_USER=44000
./collect_users.sh
# Time: ~22 minutes
```

**Then Analyze:**
```bash
./analyze_duplicates.sh
# Time: ~10 seconds
```

#### Option B: Parallel Collection (Fastest)

**Open 4 CloudShell tabs simultaneously:**

**Tab 1:**
```bash
nano collect_users.sh
# Set: START_USER=1, END_USER=11000
./collect_users.sh
```

**Tab 2:**
```bash
nano collect_users.sh
# Set: START_USER=11001, END_USER=22000
./collect_users.sh
```

**Tab 3:**
```bash
nano collect_users.sh
# Set: START_USER=22001, END_USER=33000
./collect_users.sh
```

**Tab 4:**
```bash
nano collect_users.sh
# Set: START_USER=33001, END_USER=44000
./collect_users.sh
```

**All complete in ~22 minutes! Then analyze:**
```bash
./analyze_duplicates.sh
# Time: ~10 seconds
```

**Total Time: ~23 minutes** (vs 90 minutes with single session)

---

## 📊 Master File Structure

### all_users_master.json

```json
[
  {
    "Id": "user-id-1",
    "Arn": "arn:aws:connect:...",
    "Username": "john.doe",
    "IdentityInfo": {
      "FirstName": "John",
      "LastName": "Doe",
      "Email": "john.doe@company.com"
    },
    "PhoneConfig": {...},
    "SecurityProfileIds": [...]
  },
  {
    "Id": "user-id-2",
    ...
  },
  ...
  {
    "Id": "user-id-44000",
    ...
  }
]
```

### Features:
- ✅ Single JSON array
- ✅ One entry per user
- ✅ Complete user details
- ✅ Append-only (preserves existing data)
- ✅ Duplicate-safe (skips existing users)

---

## 🛡️ Safety Features

### 1. Duplicate Prevention
```bash
SKIP_EXISTING=true  # Automatically skips already collected users
```

### 2. Backup Creation
```bash
# Automatically creates backup before updating master file
all_users_master.json.backup
```

### 3. JSON Validation
```bash
# Validates JSON before overwriting master file
# Rollback to backup if validation fails
```

### 4. Worker Independence
```bash
# Each worker has separate log file
# Workers can fail independently without affecting others
```

---

## 📈 Performance Metrics

### Collection Performance

| Users | Workers | Single Session | 4 Parallel Sessions |
|-------|---------|---------------|---------------------|
| 1,000 | 8 | ~2 min | ~0.5 min |
| 11,000 | 8 | ~22 min | ~22 min (per session) |
| 44,000 | 8 | ~90 min | ~22 min (all run together) |

### Analysis Performance

| Users | Analysis Time |
|-------|--------------|
| 1,000 | < 1 second |
| 11,000 | ~2 seconds |
| 44,000 | ~10 seconds |
| 100,000 | ~30 seconds |

---

## 🔄 Common Workflows

### Workflow 1: Incremental Collection
```bash
# Week 1: Collect first 10,000
START_USER=1, END_USER=10000

# Week 2: Collect next 10,000
START_USER=10001, END_USER=20000

# Week 3: Collect next 10,000
START_USER=20001, END_USER=30000

# Week 4: Collect remaining
START_USER=30001, END_USER=44000

# Week 5: Analyze all
./analyze_duplicates.sh
```

### Workflow 2: Test First, Then Full Run
```bash
# Step 1: Test with 100 users
START_USER=1, END_USER=100
./collect_users.sh

# Step 2: Analyze test data
./analyze_duplicates.sh

# Step 3: If good, collect the rest
START_USER=101, END_USER=44000
./collect_users.sh

# Step 4: Final analysis
./analyze_duplicates.sh
```

### Workflow 3: Resume After Failure
```bash
# Step 1: Start collection
START_USER=1, END_USER=44000
./collect_users.sh

# ❌ Fails at user 15,234

# Step 2: Check where it stopped
cat collection_summary.txt
# Shows: 15,234 users collected

# Step 3: Resume
START_USER=15235, END_USER=44000
./collect_users.sh

# Step 4: Analyze
./analyze_duplicates.sh
```

---

## 🎯 Best Practices

### 1. Always Test First
```bash
# Collect first 100-1,000 users
START_USER=1, END_USER=100
./collect_users.sh
./analyze_duplicates.sh
```

### 2. Use Reasonable Chunks
```bash
# Good chunk sizes:
- 10,000 users per session (22 min)
- 5,000 users per session (11 min)

# Avoid:
- 100,000 users in one session (too long)
- 100 users per session (too many sessions)
```

### 3. Monitor Progress
```bash
# Check collection summary
cat duplicate_users_output/collection_summary.txt

# Check worker logs for issues
tail -20 duplicate_users_output/collection_worker_*.log
```

### 4. Backup Master File
```bash
# Before major operations
cp duplicate_users_output/all_users_master.json \
   duplicate_users_output/all_users_master_backup_$(date +%Y%m%d).json
```

### 5. Run Analysis Multiple Times
```bash
# Analysis is fast and doesn't modify data
# Run it whenever you want updated reports
./analyze_duplicates.sh
```

---

## 🐛 Troubleshooting

### Issue: "Master file not found"
**Solution:**
```bash
# Run collection first
./collect_users.sh
```

### Issue: "Not enough users for analysis"
**Solution:**
```bash
# Collect more users or adjust MIN_USERS
nano analyze_duplicates.sh
# Set: MIN_USERS=1
```

### Issue: Collection seems stuck
**Solution:**
```bash
# Check worker logs
tail -f duplicate_users_output/collection_worker_*.log

# Workers log progress every 100 users
```

### Issue: Want to recollect specific users
**Solution:**
```bash
# Delete master file and start over
rm duplicate_users_output/all_users_master.json
./collect_users.sh

# Or set SKIP_EXISTING=false to recollect
```

---

## 📝 Quick Reference

### Collection Commands
```bash
# Edit range
nano collect_users.sh

# Run collection
./collect_users.sh

# Check progress
cat duplicate_users_output/collection_summary.txt
```

### Analysis Commands
```bash
# Run analysis
./analyze_duplicates.sh

# View results
cat duplicate_users_output/analysis_summary.txt
cat duplicate_users_output/duplicate_users_*.csv
```

### File Locations
```bash
# Master file (all users)
duplicate_users_output/all_users_master.json

# Duplicate reports
duplicate_users_output/duplicate_users_*.csv
duplicate_users_output/duplicate_users_*.json

# Logs
duplicate_users_output/collection_log_*.log
duplicate_users_output/analysis_log_*.log
```

---

**Time to collect 44,000 users:**
- Single session: ~90 minutes
- 4 parallel sessions: ~22 minutes
- Analysis: ~10 seconds

**Total: 23-90 minutes depending on approach!** 🚀
