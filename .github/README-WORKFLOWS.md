# GitHub Actions Workflows

This directory contains automated workflows for testing and releasing the Paperless-ngx cluster installation scripts.

## 📋 Workflows Overview

### 1. Shell Script Tests (`shell-check.yml`)

**Runs on:** Push, Pull Request, Manual trigger  
**Purpose:** Validates shell script quality and syntax

**Checks:**
- ✅ ShellCheck static analysis
- ✅ Bash syntax validation
- ✅ Script executable permissions
- ✅ Shebang line validation
- ✅ Docker Compose configuration validation
- ✅ Security scanning (hardcoded secrets)
- ✅ Documentation consistency

**Usage:**
```bash
# Automatically runs on push/PR
# Or trigger manually from Actions tab
```

### 2. Markdown Lint (`markdown-lint.yml`)

**Runs on:** Push, Pull Request, Manual trigger  
**Purpose:** Ensures documentation quality

**Checks:**
- ✅ Markdown syntax and formatting
- ✅ Link validation
- ✅ Spell checking
- ✅ Table of contents validation
- ✅ Consistent formatting

**Configuration Files:**
- `.github/markdown-link-check-config.json` - Link checking rules
- `.github/spellcheck-config.json` - Spell check configuration
- `.github/wordlist.txt` - Custom dictionary for technical terms

### 3. Integration Tests (`integration-tests.yml`)

**Runs on:** Push (main), Pull Request, Manual trigger, Weekly schedule  
**Purpose:** Tests script functionality and integration

**Checks:**
- ✅ Docker environment validation
- ✅ Script variable handling
- ✅ Dependency availability
- ✅ Backup/restore logic
- ✅ Configuration generation
- ✅ File operation safety
- ✅ Port conflict detection
- ✅ Environment variable validation
- ✅ Network configuration

### 4. Create Release (`release.yml`)

**Runs on:** Tag push (v*.*.*), Manual trigger  
**Purpose:** Automatically creates GitHub releases

**Features:**
- 📦 Creates release archive
- 🔒 Generates SHA256 and MD5 checksums
- 📝 Auto-generates release notes
- 🚀 Uploads release assets
- ✅ Version validation

**Usage:**
```bash
# Create and push a tag
git tag v1.0.0
git push origin v1.0.0

# Or trigger manually with version input from Actions tab
```

### 5. Scheduled Checks (`scheduled-checks.yml`)

**Runs on:** Weekly (Monday 9 AM UTC), Manual trigger  
**Purpose:** Monitors external dependencies and documentation freshness

**Checks:**
- ✅ External documentation links
- ✅ Docker image availability
- ✅ Script download URLs
- ✅ System dependencies
- ✅ Security advisories
- ✅ Ubuntu compatibility (20.04, 22.04, 24.04)
- ✅ Documentation freshness

## 🚀 Getting Started

### Enable Workflows

1. **Commit workflows to your repository:**
   ```bash
   git add .github/
   git commit -m "Add GitHub Actions workflows"
   git push
   ```

2. **Enable Actions in your repository:**
   - Go to your repository on GitHub
   - Click "Actions" tab
   - Enable workflows if prompted

### Configure Secrets (if needed)

Currently, no secrets are required. All workflows use the default `GITHUB_TOKEN`.

For future enhancements, you might add:
- `DOCKER_HUB_TOKEN` - For private Docker images
- `SLACK_WEBHOOK` - For notifications
- Custom secrets for specific integrations

## 📊 Status Badges

Add status badges to your README.md:

```markdown
![Shell Check](https://github.com/KnutGrymn/paperless-ngx-cluster/workflows/Shell%20Script%20Tests/badge.svg)
![Markdown Lint](https://github.com/KnutGrymn/paperless-ngx-cluster/workflows/Markdown%20Lint/badge.svg)
![Integration Tests](https://github.com/KnutGrymn/paperless-ngx-cluster/workflows/Integration%20Tests/badge.svg)
```

## 🔧 Customization

### Modify Schedule

Edit the cron expression in workflow files:

```yaml
on:
  schedule:
    - cron: '0 9 * * 1'  # Every Monday at 9 AM UTC
```

### Adjust Test Strictness

In `shell-check.yml`, modify ShellCheck options:

```yaml
env:
  SHELLCHECK_OPTS: -e SC1091 -e SC2164  # Ignore specific checks
```

### Add Custom Tests

Add new jobs to existing workflows:

```yaml
new-test-job:
  name: My Custom Test
  runs-on: ubuntu-latest
  steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Run custom test
      run: |
        echo "Running custom test..."
        # Your test commands here
```

## 📝 Workflow Details

### Shell Script Tests

**Key Features:**
- Uses `ludeeus/action-shellcheck` for comprehensive analysis
- Validates all `.sh` files in repository
- Checks for common security issues
- Ensures documentation references valid scripts

**Excluded Checks:**
- `SC1091` - Not following sourced files
- `SC2164` - cd without error handling

### Markdown Lint

**Key Features:**
- Uses `markdownlint-cli` for linting
- Validates internal and external links
- Spell checks with custom technical dictionary
- Configurable rules per project needs

**Ignored Rules:**
- `MD013` - Line length (often exceeds for URLs)
- `MD033` - Inline HTML (used for badges)
- `MD041` - First line heading (some files don't need)

### Integration Tests

**Key Features:**
- Multi-faceted validation approach
- Checks both structure and safety
- Validates generated configurations
- Tests compatibility across environments

**Test Categories:**
1. Environment validation
2. Script safety checks
3. Configuration generation
4. File operations
5. Network settings

### Release Workflow

**Automated Steps:**
1. Validates version format (v1.2.3)
2. Creates compressed archive
3. Generates checksums
4. Creates comprehensive release notes
5. Uploads all assets to GitHub

**Manual Trigger:**
Use workflow dispatch to create releases without pushing tags.

### Scheduled Checks

**Monitoring:**
- External dependency health
- Docker image availability
- Script download accessibility
- Security updates
- Documentation relevance

**Ubuntu Versions Tested:**
- 20.04 LTS (Focal)
- 22.04 LTS (Jammy)
- 24.04 LTS (Noble)

## 🐛 Troubleshooting

### Workflow Fails

**Check the logs:**
1. Go to Actions tab
2. Click on failed workflow
3. Expand failed job/step
4. Review error messages

**Common Issues:**

1. **ShellCheck Errors**
   - Review ShellCheck warnings
   - Fix or suppress with `# shellcheck disable=SCXXXX`

2. **Markdown Lint Failures**
   - Check line length
   - Validate link syntax
   - Review custom wordlist

3. **Permission Issues**
   - Ensure scripts have execute permissions
   - Commit with `git add --chmod=+x script.sh`

4. **Link Check Failures**
   - External links may be temporarily down
   - Update `.github/markdown-link-check-config.json` to ignore

### Disable Specific Workflows

Create `.github/workflows/disabled/` and move unwanted workflows there.

Or add to workflow file:
```yaml
on:
  workflow_dispatch:  # Only manual trigger
```

## 📈 Best Practices

1. **Keep workflows updated:**
   - Update action versions regularly
   - Monitor GitHub's action deprecation notices

2. **Test locally before pushing:**
   ```bash
   # Test shellcheck locally
   shellcheck *.sh
   
   # Test markdown
   markdownlint *.md
   ```

3. **Review workflow runs:**
   - Check Actions tab regularly
   - Address failures promptly
   - Monitor scheduled check results

4. **Optimize workflow runs:**
   - Use caching for dependencies
   - Skip unnecessary jobs
   - Use matrix strategies for parallel testing

## 🔐 Security

**Workflow Security:**
- Uses minimal permissions
- No external secret access required
- All dependencies pinned to specific versions
- Security scanning included

**Recommendations:**
- Review workflow changes in PRs
- Monitor for suspicious patterns
- Keep actions up to date
- Use Dependabot for action updates

## 📚 Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [ShellCheck Wiki](https://github.com/koalaman/shellcheck/wiki)
- [Markdown Lint Rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)
- [Workflow Syntax](https://docs.github.com/en/actions/reference/workflow-syntax-for-github-actions)

## 🤝 Contributing

To add new workflows:

1. Create workflow file in `.github/workflows/`
2. Test workflow on a branch
3. Document in this README
4. Submit pull request

## 📄 License

These workflows are part of the paperless-ngx-cluster project and follow the same license.

---

**Last Updated:** November 2024  
**Maintained by:** KnutGrymn
