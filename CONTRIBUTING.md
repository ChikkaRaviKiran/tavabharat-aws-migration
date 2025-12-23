# Contributing to TavaBharat AWS Migration Toolkit

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Issues

If you find a bug or have a suggestion:

1. **Search existing issues** to avoid duplicates
2. **Create a new issue** with:
   - Clear title and description
   - Steps to reproduce (for bugs)
   - Expected vs actual behavior
   - Environment details (OS, versions, etc.)
   - Relevant logs or screenshots

### Submitting Changes

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation if needed

4. **Test your changes**
   - Test on Ubuntu 22.04 LTS
   - Verify bash scripts with `bash -n script.sh`
   - Ensure no syntax errors
   - Test all affected functionality

5. **Commit your changes**
   ```bash
   git add .
   git commit -m "Brief description of changes"
   ```

6. **Push to your fork**
   ```bash
   git push origin feature/your-feature-name
   ```

7. **Create a Pull Request**
   - Describe what changed and why
   - Reference any related issues
   - Include testing details

## Development Guidelines

### Bash Scripts

- Use `set -euo pipefail` for error handling
- Add colored output for user-friendliness
- Include progress indicators for long operations
- Make scripts idempotent when possible
- Add comprehensive error messages
- Comment complex sections

**Example:**
```bash
#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Logging function
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
```

### Configuration Files

- Use clear, self-documenting variable names
- Provide examples in `.example` files
- Never commit sensitive data
- Document all configuration options

### Documentation

- Keep documentation up to date with code changes
- Use clear, simple language
- Provide examples for complex procedures
- Include troubleshooting tips

## Code Style

### Shell Scripts

- 4-space indentation
- Meaningful variable names in UPPER_CASE for constants
- lowercase_with_underscores for variables
- Functions should have descriptive names
- Add header comments explaining the script's purpose

### SQL Scripts

- Keywords in UPPERCASE
- Table/column names in PascalCase or as per existing convention
- Indent nested queries
- Add comments for complex queries

## Testing

Before submitting:

1. **Syntax Check:**
   ```bash
   bash -n your-script.sh
   ```

2. **Test on Clean Environment:**
   - Use fresh Ubuntu 22.04 LTS instance
   - Test full installation flow
   - Verify all components work

3. **Test Edge Cases:**
   - Empty inputs
   - Invalid inputs
   - Insufficient resources
   - Network failures

4. **Verify Documentation:**
   - Ensure new features are documented
   - Update CHANGELOG if applicable
   - Check for broken links

## What to Contribute

### High Priority

- Bug fixes
- Performance improvements
- Security enhancements
- Documentation improvements
- Test coverage

### Welcome Contributions

- Support for additional .NET versions
- Support for other database systems
- Monitoring enhancements
- Additional deployment options
- Automation improvements
- Better error handling

### Before Starting Large Changes

- Open an issue to discuss the change
- Get feedback from maintainers
- Ensure it aligns with project goals

## Commit Messages

Use clear, descriptive commit messages:

**Good:**
```
Add support for .NET 8 in API deployment

- Updated detection logic to support .NET 8
- Added installation for .NET 8 runtime
- Updated documentation
```

**Bad:**
```
Fixed stuff
```

## Pull Request Process

1. Ensure your PR:
   - Solves one problem or adds one feature
   - Doesn't break existing functionality
   - Includes updated documentation
   - Has been tested

2. PR will be reviewed for:
   - Code quality
   - Functionality
   - Security implications
   - Documentation completeness
   - Test coverage

3. Address review comments promptly

4. Once approved, maintainers will merge

## Community Guidelines

- Be respectful and constructive
- Welcome newcomers
- Help others learn
- Give credit where due
- Focus on the issue, not the person

## Questions?

- Open an issue for questions
- Use GitHub Discussions for general topics
- Check existing documentation first

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing! 🎉
