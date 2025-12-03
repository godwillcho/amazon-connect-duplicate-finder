# GitHub Repository Structure

This document provides a complete overview of the repository structure and all files included.

## Repository: amazon-connect-duplicate-finder

### Description
A production-ready tool for Amazon Connect administrators to identify and report duplicate user accounts through case-insensitive comparison of emails, usernames, and full names. Supports both sequential and parallel processing modes, optimized for CloudShell.

### Topics/Tags
`amazon-connect` `aws` `duplicate-detection` `user-management` `bash-script` `cloudshell` `parallel-processing` `contact-center` `devops` `automation`

---

## 📁 Repository Structure

```
amazon-connect-duplicate-finder/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── find_duplicate_users.sh              # Sequential processing script
├── find_duplicate_users_parallel.sh     # Parallel processing script (8 workers)
├── README.md                            # Main documentation
├── QUICKSTART_CLOUDSHELL.md            # CloudShell quick start guide
├── PARALLEL_PROCESSING.md              # Detailed parallel processing guide
├── CONTRIBUTING.md                      # Contribution guidelines
├── SECURITY.md                          # Security policy
├── CHANGELOG.md                         # Version history
├── LICENSE                              # MIT License
└── .gitignore                           # Git ignore rules
```

---

## 📄 File Descriptions

### Core Scripts

#### `find_duplicate_users.sh`
- **Purpose**: Sequential processing for small to medium instances
- **Best for**: < 1,000 users
- **Processing**: One user at a time
- **Time**: ~1 second per user
- **Features**: Simple, reliable, detailed progress logging

#### `find_duplicate_users_parallel.sh`
- **Purpose**: Parallel processing for large instances
- **Best for**: 1,000+ users (optimized for 44,000 users)
- **Processing**: 8 parallel workers by default
- **Time**: ~0.125 seconds per user (8x faster)
- **Features**: Worker management, CloudShell optimized, progress batching

### Documentation Files

#### `README.md`
Main documentation covering:
- Features overview
- Quick start for CloudShell
- Installation instructions
- Configuration guide
- Usage examples
- Output file descriptions
- How duplicate detection works
- Troubleshooting
- Use cases and best practices

#### `QUICKSTART_CLOUDSHELL.md`
Step-by-step guide for AWS CloudShell:
- 5-minute setup process
- Instance ID configuration
- Execution and monitoring
- File download instructions
- Expected timelines by user count
- Common issues and quick fixes
- Tips for large instances (10,000+ users)

#### `PARALLEL_PROCESSING.md`
Comprehensive parallel processing guide:
- Performance comparisons
- CloudShell integration details
- Worker configuration recommendations
- Large-scale deployment (44,000 users)
- Monitoring and progress tracking
- AWS rate limits and optimization
- Real-world examples
- Performance tuning

#### `CONTRIBUTING.md`
Contribution guidelines covering:
- Code of conduct
- How to report bugs
- How to suggest features
- Pull request process
- Coding standards and style
- Testing requirements
- Documentation requirements

#### `SECURITY.md`
Security policy including:
- Vulnerability reporting process
- Security best practices
- Credential management
- Data protection guidelines
- Known security considerations
- Disclosure timeline

#### `CHANGELOG.md`
Version history:
- v1.1.0 - Parallel processing, CloudShell support
- v1.0.0 - Initial release

#### `LICENSE`
MIT License - Open source, permissive license

---

## 🔧 GitHub Templates

### `.github/ISSUE_TEMPLATE/bug_report.md`
Structured bug report template with:
- Environment details
- Reproduction steps
- Expected vs actual behavior
- Log output sections
- Screenshots

### `.github/ISSUE_TEMPLATE/feature_request.md`
Feature request template with:
- Feature description
- Problem statement
- Use case explanation
- Alternatives considered
- Priority level
- Willingness to contribute

### `.github/PULL_REQUEST_TEMPLATE.md`
Pull request template with:
- Change description
- Type of change checklist
- Related issues
- Testing checklist
- Documentation updates
- Breaking changes section

---

## ⚙️ Configuration Files

### `.gitignore`
Excludes:
- Output directory (`duplicate_users_output/`)
- Temporary files
- Log files
- Editor files
- AWS credentials
- System files

---

## 🚀 Quick Reference

### For First-Time Users
1. Start with **QUICKSTART_CLOUDSHELL.md**
2. Read **README.md** for full features
3. Use `find_duplicate_users_parallel.sh` for 1,000+ users

### For Contributors
1. Read **CONTRIBUTING.md**
2. Check **SECURITY.md** for security guidelines
3. Follow templates in `.github/`

### For Large Deployments
1. Read **PARALLEL_PROCESSING.md**
2. Configure 8-10 workers for 44,000+ users
3. Monitor via worker logs

---

## 📊 Output Files Generated

When running the scripts, the following files are created in `./duplicate_users_output/`:

### CSV Files
- `all_users_YYYYMMDD_HHMMSS.csv` - Complete user list
- `duplicate_users_YYYYMMDD_HHMMSS.csv` - Duplicate pairs with reasons

### JSON Files
- `all_users_YYYYMMDD_HHMMSS.json` - Complete user data
- `duplicate_users_YYYYMMDD_HHMMSS.json` - Structured duplicate data

### Log Files
- `duplicate_users_log_YYYYMMDD_HHMMSS.log` (sequential)
- `parallel_main_log_YYYYMMDD_HHMMSS.log` (parallel)
- `worker_N_log_YYYYMMDD_HHMMSS.log` (parallel workers)

---

## 🎯 Key Features Summary

### Duplicate Detection
- ✅ Email addresses (case-insensitive)
- ✅ Usernames (case-insensitive)
- ✅ Full names - first + last (case-insensitive)

### Processing Modes
- ✅ Sequential (1-1,000 users)
- ✅ Parallel (1,000+ users, up to 8 workers)

### Output Formats
- ✅ CSV (spreadsheet-friendly)
- ✅ JSON (programmatic access)
- ✅ Detailed logs (audit trail)

### Environment Support
- ✅ AWS CloudShell (optimized)
- ✅ Linux/macOS local
- ✅ EC2 instances
- ✅ CI/CD pipelines

---

## 📈 Performance Metrics

| User Count | Sequential | Parallel (8 workers) | Improvement |
|-----------|-----------|---------------------|-------------|
| 100 | 2 min | 15 sec | 8x |
| 1,000 | 20 min | 2.5 min | 8x |
| 10,000 | 3 hours | 20 min | 9x |
| 44,000 | 12 hours | 90 min | 8x |

---

## 🔗 Important Links

- **Repository**: https://github.com/yourusername/amazon-connect-duplicate-finder
- **Issues**: https://github.com/yourusername/amazon-connect-duplicate-finder/issues
- **Discussions**: https://github.com/yourusername/amazon-connect-duplicate-finder/discussions
- **AWS Connect Docs**: https://docs.aws.amazon.com/connect/
- **CloudShell Guide**: https://docs.aws.amazon.com/cloudshell/

---

## 📝 Version Information

- **Current Version**: 1.1.0
- **Release Date**: December 3, 2025
- **License**: MIT
- **Bash Version Required**: 4.0+
- **AWS CLI Version**: 2.x recommended
- **jq Version**: 1.5+

---

## 🤝 Community

### Contributing
We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Support
- 🐛 Report bugs via [GitHub Issues](https://github.com/yourusername/amazon-connect-duplicate-finder/issues)
- 💡 Request features via [GitHub Issues](https://github.com/yourusername/amazon-connect-duplicate-finder/issues)
- 💬 Ask questions via [GitHub Discussions](https://github.com/yourusername/amazon-connect-duplicate-finder/discussions)
- 🔒 Report security issues via [Security Policy](SECURITY.md)

### Recognition
Contributors are acknowledged in release notes and CHANGELOG.md.

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Last Updated**: December 3, 2025
**Maintained By**: Community
**Status**: Active Development
