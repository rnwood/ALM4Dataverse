# Automated Dependency Update Workflow

This workflow automatically checks for outdated PowerShell module dependencies and creates pull requests to update them.

## Overview

The workflow consists of:
- A GitHub Actions workflow that runs daily at 2 AM UTC (or can be manually triggered)
- Two PowerShell scripts that handle dependency checking and PR management
- A test script to validate the workflow logic

## Files

### `.github/workflows/update-dependencies.yml`
The main workflow file that:
- Runs on a schedule (daily at 2 AM UTC)
- Can be manually triggered via workflow_dispatch
- Sets up PowerShell environment with NuGet provider and PSGallery
- Executes the dependency check and PR creation scripts

### `.github/scripts/check-outdated-dependencies.ps1`
Checks for outdated dependencies by:
- Reading `scriptDependencies` from `alm-config-defaults.psd1`
- Querying PowerShell Gallery for the latest version of each module
- Comparing current vs latest versions
- Creating a JSON file with outdated dependencies

### `.github/scripts/update-dependency-prs.ps1`
Manages pull requests by:
- Creating a new PR for each outdated dependency
- Updating existing PRs if one already exists for the same module
- Using the branch naming convention: `deps/update-{module}-to-{version}`
- Rebasing on the base branch to maintain linear history
- Using `--force-with-lease` for safe force pushes

### `.github/scripts/test-dependency-workflow.ps1`
Tests the workflow logic without requiring network access:
- Validates config file parsing
- Tests version comparison and serialization
- Tests the regex pattern for updating versions
- Validates branch naming convention

## How It Works

1. **Scheduled Run**: The workflow runs daily at 2 AM UTC
2. **Check Dependencies**: The script reads `alm-config-defaults.psd1` and queries PowerShell Gallery for each module
3. **Identify Updates**: Compares versions and creates a list of outdated dependencies
4. **Create/Update PRs**: For each outdated dependency:
   - If no PR exists, creates a new PR with branch `deps/update-{module}-to-{version}`
   - If a PR already exists for the same module (any version), updates that PR to the latest version
   - Each PR updates only one dependency in `alm-config-defaults.psd1`

## PR Behavior

- **New Dependencies**: When a module is outdated, a new PR is created
- **Existing PRs**: If a PR already exists for the same module (even for a different version), it will be updated to the latest version
- **Branch Names**: Follow the pattern `deps/update-{module-name}-to-{version}`
- **Commit Messages**: Use conventional commit format: `chore(deps): update {module} to {version}`

## Manual Trigger

To manually trigger the workflow:
1. Go to the Actions tab in GitHub
2. Select "Update Script Dependencies" workflow
3. Click "Run workflow"
4. Select the branch and click "Run workflow"

## Testing

Run the test script to validate the workflow logic:
```powershell
pwsh -File .github/scripts/test-dependency-workflow.ps1
```

This test verifies:
- Config file parsing works correctly
- Version comparison logic is sound
- Regex patterns correctly update versions
- Branch naming follows conventions
