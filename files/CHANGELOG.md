# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
