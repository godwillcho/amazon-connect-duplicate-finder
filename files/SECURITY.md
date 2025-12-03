# Security Policy

## Supported Versions

We release patches for security vulnerabilities. Currently supported versions:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |

## Reporting a Vulnerability

We take the security of this project seriously. If you discover a security vulnerability, please follow these steps:

### 1. Do Not Open a Public Issue

Please **DO NOT** create a public GitHub issue for security vulnerabilities, as this could put users at risk.

### 2. Report Privately

Send your vulnerability report privately to the project maintainers:

- **Email**: [Create a security advisory](https://github.com/yourusername/amazon-connect-duplicate-finder/security/advisories/new)
- **Subject**: Include "[SECURITY]" in the subject line
- **Description**: Provide detailed information about the vulnerability

### 3. Include in Your Report

Please include the following information in your report:

- **Type of vulnerability**: What kind of security issue is it?
- **Location**: Which file(s) and line(s) are affected?
- **Impact**: What could an attacker do by exploiting this?
- **Reproduction steps**: How to reproduce the vulnerability
- **Proof of concept**: If possible, provide code or commands
- **Suggested fix**: If you have ideas for how to fix it

### 4. What to Expect

- **Acknowledgment**: Within 48 hours of your report
- **Initial assessment**: Within 5 business days
- **Regular updates**: Every 5 business days until resolved
- **Resolution**: We aim to patch critical vulnerabilities within 30 days

## Security Best Practices for Users

### Credential Management

1. **Never commit AWS credentials**
   - Use AWS CLI configuration (`aws configure`)
   - Use environment variables
   - Use IAM roles when running on EC2/ECS

2. **Use least privilege IAM policies**
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
         "Resource": "arn:aws:connect:REGION:ACCOUNT:instance/INSTANCE-ID"
       }
     ]
   }
   ```

3. **Rotate credentials regularly**
   - Follow your organization's credential rotation policy
   - Use temporary credentials when possible

### Data Protection

1. **Sanitize logs before sharing**
   - Remove user IDs, ARNs, and instance IDs
   - Redact email addresses and names
   - Don't share complete output files publicly

2. **Secure output files**
   ```bash
   # Set restrictive permissions
   chmod 600 duplicate_users_output/*.csv
   chmod 600 duplicate_users_output/*.json
   ```

3. **Store output securely**
   - Don't commit output files to public repositories
   - Use encrypted storage for sensitive reports
   - Delete old reports when no longer needed

### Script Execution

1. **Review before running**
   - Read the script before first use
   - Understand what it does
   - Verify the source

2. **Run with minimal permissions**
   - Use read-only AWS credentials if possible
   - Run as non-root user
   - Use dedicated IAM roles for automation

3. **Monitor execution**
   - Review logs for unexpected behavior
   - Check output files for anomalies
   - Report suspicious activity

## Known Security Considerations

### Read-Only Operations

This script performs **read-only** operations on Amazon Connect:
- ✅ `connect:ListUsers` - Lists users
- ✅ `connect:DescribeUser` - Retrieves user details
- ❌ No write, delete, or modify operations

### Data Exposure

Be aware that output files contain:
- User IDs and ARNs
- Email addresses
- First and last names
- Usernames

**Recommendation**: Treat output files as confidential and protect accordingly.

### Temporary Files

The script creates temporary files during execution:
- Location: `/tmp/tmp.XXXXXXXXXX`
- Content: User data from Amazon Connect
- Cleanup: Automatically deleted on completion

**Security**: Temporary files are created with default system permissions. Ensure your `/tmp` directory has appropriate security settings.

## Vulnerability Disclosure Timeline

We follow responsible disclosure practices:

1. **Day 0**: Vulnerability reported privately
2. **Day 1-5**: Initial assessment and triage
3. **Day 5-30**: Develop and test fix
4. **Day 30**: Release patched version
5. **Day 30+**: Public disclosure after users have had time to update

## Security Updates

Subscribe to security updates:
- Watch this repository for security advisories
- Enable GitHub security alerts
- Check CHANGELOG.md for security-related updates

## Acknowledgments

We appreciate security researchers who responsibly disclose vulnerabilities. Contributors will be acknowledged (with permission) in:
- Security advisory
- Release notes
- CHANGELOG.md

Thank you for helping keep this project secure!
