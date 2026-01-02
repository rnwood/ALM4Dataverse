# Azure DevOps Pipeline Usage Instructions

This document provides step-by-step instructions for using the ALM4Dataverse pipelines in common development and deployment scenarios.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Common Workflows](#common-workflows)
3. [Development Workflow](#development-workflow)
4. [Feature Branch Workflow](#feature-branch-workflow)
5. [Deployment Workflow](#deployment-workflow)
6. [Troubleshooting Scenarios](#troubleshooting-scenarios)

## Prerequisites

Before using the pipelines, ensure you have completed the automated setup:

1. Azure DevOps project with pipelines configured
2. Service connections created for each environment
3. Variable groups configured for each environment
4. At least one Dataverse development environment
5. Solutions defined in `alm-config.psd1`

See [automated-setup.md](automated-setup.md) for initial configuration.

## Common Workflows

### Workflow 1: Making Changes in Development Environment

**Scenario**: You need to add a new field to a table in your solution.

**Steps**:

1. **Make changes in Dataverse**
   - Open your development environment (e.g., `Dev-main`)
   - Navigate to your solution
   - Add the new field, form, or other customizations
   - Test your changes in the development environment

2. **Export changes to source control**
   - Go to Azure DevOps → Pipelines
   - Select the **EXPORT** pipeline
   - Click **Run pipeline**
   - Enter a descriptive commit message (e.g., "Added customer phone number field")
   - Click **Run**
   - Wait for the pipeline to complete

3. **Review the changes**
   - Go to Repos → Files
   - Review the commit created by the EXPORT pipeline
   - Verify only expected changes are included
   - The solution version will be automatically incremented

4. **Create a Pull Request** (if using feature branches)
   - Create a PR from your feature branch to main
   - Request code review
   - Wait for approval and merge

### Workflow 2: Getting Latest Changes from Source Control

**Scenario**: Another developer has committed changes, and you want to update your development environment.

**Steps**:

1. **Pull latest changes**
   - In your local Git client or Azure DevOps
   - Pull the latest changes from the branch
   - (This step is optional if you're using the IMPORT pipeline, as it uses the latest from the branch)

2. **Run the IMPORT pipeline**
   - Go to Azure DevOps → Pipelines
   - Select the **IMPORT** pipeline
   - Click **Run pipeline**
   - Select your branch (e.g., `main` or `feature-branch`)
   - Click **Run**
   - Wait for the pipeline to complete

3. **Verify in your environment**
   - Open your development environment
   - Navigate to your solution
   - Verify the changes are present
   - Test the functionality

**Important**: If you have uncommitted changes in your development environment, export them first (Workflow 1) to avoid losing work.

### Workflow 3: Deploying to Test/Production

**Scenario**: You want to deploy the latest version to a test or production environment.

**Steps**:

1. **Ensure BUILD completed successfully**
   - Go to Azure DevOps → Pipelines
   - Find the latest **BUILD** pipeline run for your branch
   - Verify it completed successfully
   - Note the build number (e.g., `YourRepo-main-2026-01-02-143022`)

2. **Run the DEPLOY pipeline** (if not automatic)
   - Go to Azure DevOps → Pipelines
   - Select the **DEPLOY-main** pipeline
   - Click **Run pipeline**
   - Select the BUILD run to deploy (usually latest)
   - Click **Run**

3. **Monitor the deployment**
   - Watch the pipeline execution
   - If approvals are configured, approve the deployment when prompted
   - Wait for deployment to complete

4. **Verify in target environment**
   - Open the target environment (Test, UAT, or Production)
   - Verify solutions are installed/upgraded
   - Test key functionality
   - Verify connection references are configured correctly

## Development Workflow

### Daily Development Process

This is the typical day-to-day workflow for a developer:

```
Morning:
1. Pull latest changes from Git
2. Run IMPORT pipeline to update dev environment
3. Verify environment is up-to-date

During Development:
4. Make changes in Dataverse dev environment
5. Test changes locally

End of Day / Feature Complete:
6. Run EXPORT pipeline with descriptive commit message
7. Review exported changes in Git
8. Create PR (if using feature branches)
```

### Working with Multiple Solutions

When you have multiple solutions in `alm-config.psd1`:

1. **Maintain dependency order**
   ```powershell
   solutions = @(
       @{ name = 'CoreSolution' }        # Base solution
       @{ name = 'ExtensionSolution' }   # Depends on Core
   )
   ```

2. **Export all solutions together**
   - The EXPORT pipeline processes all solutions in order
   - Each solution gets its own folder under `solutions/`

3. **Import maintains order**
   - The IMPORT pipeline deploys in dependency order
   - Ensures dependencies are satisfied

### Using Hooks for Custom Logic

Hooks allow you to extend the pipeline behavior:

1. **Create a hook script**
   ```powershell
   # data/system/export.ps1
   Write-Host "Exporting system configuration data..."
   # Your custom export logic here
   ```

2. **Register in alm-config.psd1**
   ```powershell
   hooks = @{
       postExport = @('data/system/export.ps1')
       postDeploy = @('data/system/import.ps1')
   }
   ```

3. **Hook execution**
   - preExport: Before exporting solutions
   - postExport: After exporting and unpacking
   - preBuild: Before packing solutions
   - postBuild: After packing and copying assets
   - preDeploy: Before importing solutions
   - dataMigrations: After staging, before upgrade
   - postDeploy: After publishing customizations

## Feature Branch Workflow

### Creating and Using Feature Branches

**Scenario**: You're working on a new feature that requires multiple changes.

**Steps**:

1. **Create feature branch**
   - In Azure DevOps or your Git client
   - Create a new branch from `main`
   - Name it descriptively (e.g., `feature/customer-portal`)

2. **Set up development environment** (if needed)
   - Create or use an existing Dataverse environment
   - Name it according to convention: `Dev-feature-customer-portal`
   - Create service connection: `Dev-feature-customer-portal`
   - Create variable group: `Environment-Dev-feature-customer-portal`

3. **Initial IMPORT to feature environment**
   - Switch to your feature branch
   - Run IMPORT pipeline
   - This sets up your feature environment with latest from main

4. **Develop on feature branch**
   - Make changes in your feature environment
   - Use EXPORT pipeline to commit changes
   - Repeat as needed

5. **Keep feature branch updated**
   - Periodically merge `main` into your feature branch
   - Run IMPORT to update your environment with merged changes

6. **Complete the feature**
   - Create Pull Request to main
   - Request code review
   - BUILD pipeline runs automatically on PR
   - Address review comments
   - Merge to main when approved

7. **Clean up** (optional)
   - Delete feature branch
   - Delete feature environment (if dedicated)
   - Delete service connection and variable group

### Branch Naming Conventions

Recommended naming patterns:

- **Feature branches**: `feature/description` → `feature/add-reporting`
- **Bugfix branches**: `bugfix/description` → `bugfix/fix-validation`
- **Hotfix branches**: `hotfix/description` → `hotfix/critical-security-fix`
- **Environment names**: `Dev-{BranchName}` → `Dev-feature-add-reporting`

## Deployment Workflow

### Setting Up Multi-Environment Deployment

**Scenario**: You want to deploy to Test, then UAT, then Production.

**Steps**:

1. **Configure DEPLOY-main.yml**
   
   Edit `/copy-to-your-repo/pipelines/DEPLOY-main.yml`:
   ```yaml
   stages:
     - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
       parameters:
         environmentName: Test-main
     
     - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
       parameters:
         environmentName: UAT-main
     
     - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
       parameters:
         environmentName: Production
   ```

2. **Create service connections**
   - `Test-main` → Points to Test Dataverse environment
   - `UAT-main` → Points to UAT Dataverse environment
   - `Production` → Points to Production Dataverse environment

3. **Create variable groups**
   - `Environment-Test-main` with Test-specific configuration
   - `Environment-UAT-main` with UAT-specific configuration
   - `Environment-Production` with Production-specific configuration

4. **Create Azure DevOps Environments** (for approvals)
   - Go to Pipelines → Environments
   - Create environments: `Test-main`, `UAT-main`, `Production`
   - Configure approvals on `Production` (recommended)

5. **Deploy**
   - Push changes to main branch
   - BUILD pipeline runs automatically
   - DEPLOY pipeline triggers automatically
   - Deployments proceed through Test → UAT → Production
   - Approve Production deployment when prompted

### Configuring Connection References

Connection references need to be configured per environment:

1. **Identify connection references**
   - In Dataverse, open your solution
   - Note the logical names of connection references (e.g., `shared_commondataservice`)

2. **Add to variable groups**
   
   In `Environment-Test-main` variable group:
   ```
   ConnRef_shared_commondataservice = <connection-id-for-test>
   ConnRef_shared_sharepointonline = <connection-id-for-test>
   ```
   
   In `Environment-Production` variable group:
   ```
   ConnRef_shared_commondataservice = <connection-id-for-production>
   ConnRef_shared_sharepointonline = <connection-id-for-production>
   ```

3. **Get connection IDs**
   - In Power Platform, go to Connections
   - Open developer tools (F12)
   - Copy the connection ID from the URL or inspect network traffic

### Configuring Environment Variables

Environment variables for environment-specific configuration:

1. **Add to variable groups**
   
   In `Environment-Test-main` variable group:
   ```
   EnvVar_ApiEndpoint = https://test-api.example.com
   EnvVar_MaxRecords = 100
   ```
   
   In `Environment-Production` variable group:
   ```
   EnvVar_ApiEndpoint = https://api.example.com
   EnvVar_MaxRecords = 1000
   ```

2. **Variables are set automatically**
   - DEPLOY pipeline reads all `EnvVar_` prefixed variables
   - Sets them in the target environment during deployment

### Rolling Back a Deployment

**Scenario**: A deployment caused issues, and you need to rollback.

**Steps**:

1. **Identify the previous good build**
   - Go to Pipelines → BUILD
   - Find the previous successful build
   - Note the build number and Git tag

2. **Revert code in Git** (optional)
   - Create a branch from the previous good tag
   - Merge to main (or revert commits)

3. **Redeploy previous version**
   - Go to Pipelines → DEPLOY-main
   - Click **Run pipeline**
   - Under **Resources**, select the previous BUILD run
   - Click **Run**

4. **Verify rollback**
   - Check target environment
   - Verify previous version is active
   - Test functionality

**Note**: Managed solutions cannot be easily downgraded. Consider:
- Uninstalling the current version first
- Using unmanaged solutions in non-production for easier rollback
- Testing thoroughly in lower environments

## Troubleshooting Scenarios

### Scenario 1: EXPORT Pipeline - No Changes Detected

**Problem**: You made changes in Dataverse, but EXPORT says "No changes to commit".

**Possible Causes**:
1. Changes were made outside the managed solutions
2. Changes were already exported
3. Changes are in a different solution than configured

**Resolution**:
1. Verify you're in the correct development environment
2. Check `alm-config.psd1` lists all your solutions
3. Ensure changes are in the solutions listed
4. Try exporting again after making a small change

### Scenario 2: IMPORT Pipeline - Missing Dependencies

**Problem**: IMPORT fails with "Missing dependencies" error.

**Possible Causes**:
1. Solutions not in correct dependency order
2. Referenced solution not installed in target environment
3. Referenced component was deleted

**Resolution**:
1. Check `alm-config.psd1` solutions are in dependency order
2. Ensure all required solutions are listed
3. Check for missing managed solutions in the environment
4. Review solution dependencies in Power Platform

### Scenario 3: BUILD Pipeline - Tag Already Exists

**Problem**: BUILD fails because the Git tag already exists.

**Possible Causes**:
1. Previous build with same timestamp (rare)
2. Manual tag creation with same name

**Resolution**:
1. Wait a few seconds and retry the build
2. The timestamp will be different
3. Or delete the conflicting tag (not recommended)

### Scenario 4: DEPLOY Pipeline - Connection Reference Not Set

**Problem**: After deployment, connection references are blank.

**Possible Causes**:
1. Variable group missing `ConnRef_` variables
2. Incorrect connection reference name
3. Invalid connection ID

**Resolution**:
1. Check variable group `Environment-{EnvironmentName}` exists
2. Verify variable names match: `ConnRef_{logical_name}`
3. Get correct connection IDs from target environment
4. Update variable group
5. Redeploy

### Scenario 5: Multiple Developers - Merge Conflicts

**Problem**: Two developers exported changes, and Git has merge conflicts.

**Possible Causes**:
1. Both modified the same component (form, field, etc.)
2. Solution file conflicts

**Resolution**:
1. Identify conflicting files (usually XML in solution folders)
2. Manually resolve conflicts in Git
3. Test resolution by running IMPORT in a test environment
4. Or use one developer's changes and have the other reapply their changes
5. Commit the resolved merge

### Scenario 6: Environment Out of Sync

**Problem**: Development environment doesn't match source control.

**Possible Causes**:
1. Manual changes made without EXPORT
2. IMPORT not run after pulling changes
3. Failed IMPORT left environment in partial state

**Resolution**:
1. If you have uncommitted work, EXPORT it first
2. Pull latest from Git
3. Run IMPORT pipeline to sync environment
4. Verify environment state
5. Re-export if you had local changes

## Advanced Usage

### Running Pipelines with Different Parameters

Most pipelines can be customized via parameters:

**EXPORT Pipeline**:
- `commitMessage`: Required parameter for commit message

**DEPLOY Pipeline**:
- Can select which BUILD run to deploy
- Can run on different branches (advanced)

### Using Data Hooks

Data import/export hooks enable managing configuration data:

**Example postExport hook** (`data/system/export.ps1`):
```powershell
# Export configuration records
Connect-DataverseEnvironment -ConnectionString $env:DATAVERSE_CONNECTION

Get-DataverseRecords -Table "cr123_configuration" |
    Export-Csv -Path "data/system/configuration.csv" -NoTypeInformation

Write-Host "Exported configuration data"
```

**Example postDeploy hook** (`data/system/import.ps1`):
```powershell
# Import configuration records
Connect-DataverseEnvironment -ConnectionString $env:DATAVERSE_CONNECTION

Import-Csv -Path "data/system/configuration.csv" | ForEach-Object {
    New-DataverseRecord -Table "cr123_configuration" -Data $_
}

Write-Host "Imported configuration data"
```

### Customizing Build Numbers

Edit the BUILD template to customize build numbering:

In `copy-to-your-repo/pipelines/BUILD.yml`, you can override the default:
```yaml
name: 'v1.0.$(Rev:r)'  # Custom versioning scheme
```

### Parallel Deployments

For independent solutions, you can deploy to multiple environments in parallel:

```yaml
stages:
  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: Test-US
  
  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: Test-EU
  # These run in parallel if no dependencies defined
```

## Best Practices Summary

1. **EXPORT frequently** to avoid losing work
2. **Use descriptive commit messages** when exporting
3. **Review changes** before pushing to main
4. **IMPORT before starting work** to stay in sync
5. **Test in lower environments** before production
6. **Use Pull Requests** for code review
7. **Configure approvals** on production deployments
8. **Tag releases** for easy rollback (done automatically by BUILD)
9. **Document your hooks** if you use custom logic
10. **Keep solutions in dependency order** in `alm-config.psd1`

## Getting Help

If you encounter issues not covered here:

1. Check the pipeline logs in Azure DevOps
2. Review the [pipeline-concepts.md](pipeline-concepts.md) documentation
3. Check the PowerShell scripts in `pipelines/scripts/` for error messages
4. Review Azure DevOps service connection permissions
5. Verify Dataverse environment security roles

## Next Steps

- [Pipeline Concepts](pipeline-concepts.md) - Detailed explanation of each pipeline
- [Automated Setup](automated-setup.md) - Initial configuration guide
