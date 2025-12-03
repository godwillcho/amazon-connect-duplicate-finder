# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-12-03

### Added
- **Parallel processing mode** for large-scale deployments
  - Configurable worker processes (default: 8 workers)
  - Automatic workload distribution across workers
  - Individual worker progress tracking
  - Optimized for 10,000+ users
- **AWS CloudShell integration**
  - Automatic keep-alive mechanism to prevent timeout
  - Pre-configured for CloudShell environment
  - Quick start guide for CloudShell users
- **Enhanced progress reporting**
  - Progress updates every 100 users per worker
  - Percentage completion tracking
  - Estimated processing time calculation
- **Large-scale optimization**
  - Tested with 44,000 users
  - ~90 minute processing time for 44K users with 8 workers
  - 8x speed improvement over sequential processing

### Changed
- Default parallel worker count increased from 2 to 8
- Progress logging now batched (every 100 users instead of every user)
- Improved time estimation for large user bases

### Documentation
- Added QUICKSTART_CLOUDSHELL.md for quick start in CloudShell
- Updated PARALLEL_PROCESSING.md with large-scale deployment guidance
- Added performance benchmarks for various user counts
- Enhanced README with CloudShell quick start section

## [1.0.0] - 2025-12-03

### Added
- Initial release of Amazon Connect Duplicate User Finder
- Duplicate detection for email addresses (case-insensitive)
- Duplicate detection for usernames (case-insensitive)
- Duplicate detection for full names (first + last name, case-insensitive)
- CSV export for all users
- JSON export for all users
- CSV export for duplicate users
- JSON export for duplicate users
- Detailed execution logging with timestamps
- Real-time progress tracking for user processing
- Comprehensive error handling and validation
- Automatic output directory creation
- Prerequisites validation (AWS CLI, jq, credentials)
- Temporary file cleanup after execution

### Features
- Case-insensitive comparison for all duplicate detection
- Multiple output formats (CSV and JSON)
- Detailed duplicate reasoning in reports
- Support for large user bases
- Robust error recovery

### Technical Details
- Uses AWS CLI for Amazon Connect API interaction
- Uses jq for JSON processing
- Bash script compatible with Linux and macOS
- No external dependencies beyond AWS CLI and jq
