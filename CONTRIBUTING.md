# Contributing to Paperless-ngx Cluster

Thank you for considering contributing to the Paperless-ngx Cluster project! This document provides guidelines and instructions for contributing.

## 🤝 Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for all contributors.

## 🐛 Reporting Issues

### Before Submitting an Issue

1. **Search existing issues** to avoid duplicates
2. **Check the documentation** - your question might be answered there
3. **Test with the latest version** if possible

### Creating an Issue

When reporting a bug, please include:

- **Description**: Clear description of the problem
- **Environment**:
  - OS and version (e.g., Ubuntu 22.04)
  - Docker version
  - Docker Compose version
  - Script version/commit
- **Steps to reproduce**: Detailed steps to trigger the issue
- **Expected behavior**: What should happen
- **Actual behavior**: What actually happens
- **Logs**: Relevant error messages or logs
- **Screenshots**: If applicable

**Example:**
```markdown
### Description
Installation script fails when setting up PostgreSQL replication

### Environment
- OS: Ubuntu 22.04
- Docker: 24.0.6
- Docker Compose: 2.21.0
- Script: scripts/install-paperless-ngx-cluster.sh (commit abc123)

### Steps to Reproduce
1. Run installation script on Node 1
2. Select PostgreSQL as database
3. Complete Node 1 installation
4. Run installation on Node 2
5. Replication fails to initialize

### Expected Behavior
Replication should be established automatically

### Actual Behavior
Error: "could not connect to replication endpoint"

### Logs
```
[logs here]
```
```

## 💡 Suggesting Enhancements

We welcome feature requests and enhancement ideas!

When suggesting an enhancement:

1. **Check existing issues** for similar suggestions
2. **Describe the use case** - why is this needed?
3. **Provide examples** of how it would work
4. **Consider alternatives** you've evaluated

## 🔧 Contributing Code

### Getting Started

1. **Fork the repository**
   ```bash
   # Click "Fork" on GitHub
   git clone https://github.com/YOUR-USERNAME/paperless-ngx-cluster.git
   cd paperless-ngx-cluster
   ```

2. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/issue-123
   ```

3. **Make your changes**
   - Follow the coding guidelines below
   - Test your changes thoroughly
   - Update documentation if needed

4. **Commit your changes**
   ```bash
   git add .
   git commit -m "Description of changes"
   ```

5. **Push and create a Pull Request**
   ```bash
   git push origin feature/your-feature-name
   ```

### Coding Guidelines

#### Shell Scripts

1. **Use bash and include proper shebang:**
   ```bash
   #!/bin/bash
   ```

2. **Use `set -e` for error handling:**
   ```bash
   set -e  # Exit on error
   ```

3. **Quote variables:**
   ```bash
   # Good
   echo "${VARIABLE}"
   
   # Bad
   echo $VARIABLE
   ```

4. **Use functions for reusability:**
   ```bash
   print_info() {
       echo -e "${BLUE}[INFO]${NC} $1"
   }
   ```

5. **Add comments for complex logic:**
   ```bash
   # Check if running as root
   if [ "$EUID" -eq 0 ]; then
       print_error "Do not run as root"
       exit 1
   fi
   ```

6. **Follow ShellCheck recommendations:**
   ```bash
   shellcheck your-script.sh
   ```

7. **Make scripts executable:**
   ```bash
   chmod +x your-script.sh
   ```

#### Documentation

1. **Use Markdown for documentation**

2. **Follow existing formatting:**
   - Use headers consistently
   - Include code blocks with language specification
   - Add links where helpful

3. **Keep line length reasonable:**
   - Aim for 80-120 characters
   - Break long URLs appropriately

4. **Test all code examples:**
   - Verify commands work as written
   - Include necessary context

5. **Update table of contents** if adding sections

### Testing

Before submitting a PR:

1. **Run local tests:**
   ```bash
   # Check shell scripts
   shellcheck *.sh
   
   # Check markdown
   markdownlint *.md
   
   # Test syntax
   bash -n your-script.sh
   ```

2. **Test functionality:**
   - Test the installation process if modified
   - Verify scripts work on clean Ubuntu 22.04 system
   - Test both Node 1 and Node 2 configurations
   - Verify generated configurations are valid

3. **Review changes:**
   ```bash
   git diff
   ```

### Pull Request Process

1. **Update documentation** to reflect changes

2. **Add/update tests** if applicable

3. **Describe your changes:**
   - What does this PR do?
   - Why is this change needed?
   - How has it been tested?
   - Related issues (if any)

4. **PR title format:**
   ```
   feat: Add support for MariaDB
   fix: Correct Redis Sentinel configuration
   docs: Update deployment guide
   test: Add integration tests
   ```

5. **Wait for CI checks** to pass

6. **Respond to feedback** from reviewers

7. **Squash commits** if requested

### PR Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Refactoring

## Testing
How has this been tested?

## Checklist
- [ ] Code follows project guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] Tests added/updated
- [ ] CI checks pass
```

## 📚 Documentation Contributions

Documentation improvements are always welcome!

### Types of Documentation

1. **README.md** - Quick start and overview
2. **DEPLOYMENT-GUIDE.md** - Detailed deployment instructions
3. **QUICK-REFERENCE.md** - Command reference
4. **INSTALLATION-CHECKLIST.md** - Step-by-step checklist

### Documentation Standards

- Clear and concise language
- Step-by-step instructions where appropriate
- Code examples that can be copy-pasted
- Screenshots for complex UI interactions
- Links to related documentation

## 🎨 Workflow Contributions

You can contribute GitHub Actions workflows:

1. Create workflow in `.github/workflows/`
2. Test on your fork first
3. Document in `.github/README.md`
4. Submit PR with clear description

## 🔍 Review Process

1. **Maintainer review** - Project maintainers will review your PR
2. **CI checks** - Automated tests must pass
3. **Community feedback** - Other users may provide input
4. **Approval** - At least one maintainer approval required
5. **Merge** - Maintainer will merge once approved

## 📋 Commit Message Guidelines

Use conventional commits format:

```
type(scope): subject

body (optional)

footer (optional)
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Test additions or changes
- `chore`: Build process or auxiliary tool changes

**Examples:**
```
feat(backup): Add incremental backup support

fix(install): Correct Node 2 replication setup

docs(readme): Update installation instructions

test(ci): Add integration tests for backup script
```

## ⚡ Quick Contribution Tips

1. **Start small** - Fix typos, improve documentation
2. **Ask questions** - Use discussions for clarification
3. **Be patient** - Reviews may take time
4. **Stay updated** - Pull latest changes regularly
5. **Have fun!** - Enjoy contributing!

## 🏆 Recognition

Contributors will be:
- Listed in release notes
- Credited in documentation
- Thanked in the community

## 📞 Getting Help

- **Questions**: Open a [Discussion](https://github.com/KnutGrymn/paperless-ngx-cluster/discussions)
- **Issues**: Open an [Issue](https://github.com/KnutGrymn/paperless-ngx-cluster/issues)
- **Security**: Email security concerns privately

## 📄 License

By contributing, you agree that your contributions will be licensed under the MIT License, the same license as the project.

See [LICENSE](LICENSE) file for details.

---

Thank you for contributing to make Paperless-ngx Cluster better! 🎉
