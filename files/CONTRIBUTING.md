# Contributing to Amazon Connect Duplicate User Finder

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to this project.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

### Our Standards

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

## How to Contribute

### Reporting Bugs

Before creating a bug report, please check existing issues to avoid duplicates.

When reporting a bug, include:

- **Clear title** - Descriptive summary of the issue
- **Environment details**:
  - OS and version
  - Bash version (`bash --version`)
  - AWS CLI version (`aws --version`)
  - jq version (`jq --version`)
- **Reproduction steps** - Detailed steps to reproduce the issue
- **Expected behavior** - What you expected to happen
- **Actual behavior** - What actually happened
- **Log output** - Relevant log excerpts (sanitize sensitive data)
- **Screenshots** - If applicable

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:

- **Use case** - Why is this enhancement needed?
- **Proposed solution** - How should it work?
- **Alternatives considered** - Other approaches you've thought about
- **Additional context** - Any other relevant information

### Pull Requests

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/yourusername/amazon-connect-duplicate-finder.git
   cd amazon-connect-duplicate-finder
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```

3. **Make your changes**
   - Follow the coding standards below
   - Test thoroughly
   - Update documentation

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Add amazing feature"
   ```
   
   Use clear commit messages:
   - `feat:` - New feature
   - `fix:` - Bug fix
   - `docs:` - Documentation changes
   - `refactor:` - Code refactoring
   - `test:` - Adding tests
   - `chore:` - Maintenance tasks

5. **Push to your fork**
   ```bash
   git push origin feature/amazing-feature
   ```

6. **Open a Pull Request**
   - Describe your changes clearly
   - Reference related issues
   - Include test results
   - Update CHANGELOG.md

## Coding Standards

### Shell Script Style

- Use 4 spaces for indentation (no tabs)
- Maximum line length: 120 characters
- Use meaningful variable names in UPPERCASE for constants
- Use lowercase for local variables
- Always quote variables: `"$VARIABLE"`
- Use `[[` instead of `[` for conditionals
- Include comments for complex logic

### Example

```bash
# Good
INSTANCE_ID="abc-123"
user_count=$(echo "$USERS_JSON" | jq -r '.UserSummaryList | length')

if [[ "$user_count" -gt 0 ]]; then
    log_message "✓ Successfully fetched $user_count users"
fi

# Avoid
instanceid=abc-123
usercount=$(echo $USERS_JSON|jq -r '.UserSummaryList|length')

if [ $usercount -gt 0 ]
then
    echo "Successfully fetched $usercount users"
fi
```

### Error Handling

- Always check command exit codes
- Use meaningful error messages
- Log errors appropriately
- Clean up resources on failure

```bash
if ! aws connect list-users --instance-id "$INSTANCE_ID" > /dev/null 2>&1; then
    error_exit "Failed to connect to Amazon Connect instance"
fi
```

### Documentation

- Update README.md for user-facing changes
- Add inline comments for complex logic
- Update CHANGELOG.md with your changes
- Include examples where helpful

## Testing

### Manual Testing

Before submitting, test your changes:

1. **Basic functionality**
   ```bash
   ./find_duplicate_users.sh
   ```

2. **Error conditions**
   - Invalid instance ID
   - No AWS credentials
   - Missing jq
   - No users in instance

3. **Edge cases**
   - Empty user data
   - Special characters in names/emails
   - Very large user counts

4. **Output validation**
   - CSV format correctness
   - JSON structure validity
   - Log completeness

### Test Checklist

- [ ] Script executes without errors
- [ ] All output files are created
- [ ] CSV files open correctly in spreadsheet software
- [ ] JSON files are valid (use `jq . file.json`)
- [ ] Logs contain all expected information
- [ ] Error handling works as expected
- [ ] Temporary files are cleaned up

## Release Process

For maintainers:

1. Update version in CHANGELOG.md
2. Create release notes
3. Tag the release: `git tag -a v1.0.0 -m "Release v1.0.0"`
4. Push tags: `git push origin --tags`

## Questions?

If you have questions about contributing:

- Check existing documentation
- Search closed issues
- Open a discussion on GitHub
- Contact the maintainers

## Recognition

Contributors will be acknowledged in:
- README.md (for significant contributions)
- Release notes
- CHANGELOG.md

Thank you for contributing to making this tool better!
