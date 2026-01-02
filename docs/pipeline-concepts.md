# Azure DevOps Pipeline Concepts

This document explains the Azure DevOps pipelines used in ALM4Dataverse and their purposes.

## Overview

ALM4Dataverse provides four main pipelines that work together to support a complete Application Lifecycle Management (ALM) workflow for Dataverse solutions:

1. **EXPORT** - Captures changes from development environments
2. **BUILD** - Packages solutions for deployment
3. **IMPORT** - Applies source code changes to development environments
4. **DEPLOY** - Deploys packaged solutions to target environments

## Pipeline Architecture

The pipelines follow a reference architecture pattern where:
- Main pipeline definitions are in `copy-to-your-repo/pipelines/` (to be copied to your solution repository)
- Reusable templates are in the ALM4Dataverse repository under `pipelines/templates/`
- PowerShell scripts providing the core functionality are in `pipelines/scripts/`

This separation allows:
- **Your repository** to have minimal pipeline configuration
- **ALM4Dataverse repository** to be updated with improvements without modifying your pipelines
- Consistent behavior across all projects using ALM4Dataverse

## EXPORT Pipeline

### Purpose
The EXPORT pipeline captures customizations made in a Dataverse development environment and commits them back to source control.

### When to Use
Run this pipeline manually when you have made changes in your development environment that need to be saved to source control:
- Created or modified forms, views, or business logic
- Added or modified fields, tables, or relationships
- Changed security roles, business rules, or workflows
- Updated any other customizations in your solutions

### What It Does
1. **Connects** to your development environment (Dev-{BranchName})
2. **Exports** each solution defined in `alm-config.psd1` as both managed and unmanaged
3. **Unpacks** the solution files into readable source format in the `solutions/` folder
4. **Detects changes** by comparing with existing source files
5. **Increments version** if changes are detected (both in source and environment)
6. **Executes hooks** (preExport and postExport) for custom logic
7. **Commits and pushes** all changes back to the current branch

### Configuration Requirements
- **Service Connection**: `Dev-{BranchName}` (e.g., `Dev-main`, `Dev-feature-branch`)
- **Variable Group**: Not required for export
- **Branch**: Can run on any branch

### Key Features
- Automatically versions solutions when changes are detected
- Unpacks solutions into developer-friendly source format
- Supports custom pre/post export hooks for additional automation
- Commits changes with a custom message you provide

### Manual Trigger
This pipeline requires manual execution with a parameter:
- **commitMessage**: The message to use when committing exported changes

## BUILD Pipeline

### Purpose
The BUILD pipeline packages solutions from source code into deployment-ready artifacts and creates a versioned release.

### When to Use
This pipeline runs automatically on every commit to any branch. It can also be triggered manually when needed.

### What It Does
1. **Checks out** your solution repository source code
2. **Sets build number** using format: `{Repository}-{Branch}-{Timestamp}`
3. **Installs dependencies** defined in `alm-config.psd1`
4. **Packs solutions** from unpacked source into managed and unmanaged ZIP files
5. **Copies assets** (like data folders) to the artifacts
6. **Executes hooks** (preBuild and postBuild) for custom logic
7. **Publishes artifacts** for use by deployment pipelines
8. **Tags the repository** with the build version (e.g., `v{Repository}-{Branch}-{Timestamp}`)

### Configuration Requirements
- **Service Connection**: None (build doesn't connect to Dataverse)
- **Variable Group**: None required
- **Branch**: Triggered on all branches

### Key Features
- Runs automatically on every push
- Creates versioned, reproducible artifacts
- Packages both managed and unmanaged solution versions
- Tags source code for traceability
- No Dataverse connection needed - pure packaging operation

### Artifacts Produced
The build creates an artifact named `artifacts` containing:
- `solutions/` - Managed and unmanaged solution ZIP files
- `data/` - Any data files defined in assets
- `pipelines/scripts/` - Deployment scripts (versioned with the build)
- `alm-config.psd1` - Configuration file

## IMPORT Pipeline

### Purpose
The IMPORT pipeline synchronizes your development environment with the latest changes from source control.

### When to Use
Run this pipeline manually when you want to update your development environment with changes from source control:
- After pulling changes from another branch or developer
- To reset your environment to match source control
- To test changes that were committed by another developer

### What It Does
1. **Checks out** your solution repository source code
2. **Builds** the solutions from source (same as BUILD pipeline)
3. **Connects** to your development environment
4. **Deploys** the solutions as **unmanaged** to the environment
5. **Executes hooks** (preDeploy and postDeploy) for custom logic
6. **Publishes customizations** to make them active

### Configuration Requirements
- **Service Connection**: `Dev-{BranchName}` (e.g., `Dev-main`)
- **Variable Group**: `Environment-Dev-{BranchName}` (can include ConnRef_ and EnvVar_ variables)
- **Branch**: Works with any branch

### Key Features
- Deploys unmanaged solutions for development
- Fresh build from current source code
- Supports connection references and environment variables
- Enables collaborative development across team members

### Important Notes
- This imports **unmanaged** solutions (suitable for development)
- Can overwrite customizations in the target environment
- Use EXPORT to save environment changes before IMPORT to avoid losing work

## DEPLOY Pipeline

### Purpose
The DEPLOY pipeline deploys built artifacts to target environments (Test, UAT, Production, etc.).

### When to Use
This pipeline can be triggered:
- **Automatically** when a BUILD completes on the `main` branch
- **Manually** for deployments to any environment

### What It Does
1. **Downloads artifacts** from a completed BUILD pipeline run
2. **Connects** to the target environment
3. **Stages solutions** - imports without activating them yet
4. **Executes data migrations** hook for pre-upgrade data transformations
5. **Upgrades/applies solutions** based on environment state
6. **Sets connection references** from environment variables (ConnRef_ prefix)
7. **Sets environment variables** from environment variables (EnvVar_ prefix)
8. **Publishes customizations** to make changes active
9. **Executes hooks** (preDeploy and postDeploy) for custom logic

### Configuration Requirements
- **Service Connection**: `{EnvironmentName}` (e.g., `Test-main`, `Production`)
- **Variable Group**: `Environment-{EnvironmentName}`
  - Include variables prefixed with `ConnRef_` for connection references
  - Include variables prefixed with `EnvVar_` for environment variables
- **Environment**: Azure DevOps Environment resource (for approvals/gates)

### Key Features
- Deploys managed solutions (production-ready)
- Automatically determines install vs. upgrade vs. update
- Supports multiple environments with different configurations
- Approval gates through Azure DevOps Environments
- Uses scripts from the artifact (versioned with the deployment)

### Deployment Strategy
The DEPLOY pipeline uses a `runOnce` deployment strategy with the following stages:
1. **Stage** - Import solutions without applying changes
2. **Migrate** - Run data migration hooks
3. **Upgrade** - Apply and upgrade solutions
4. **Configure** - Set connection references and environment variables
5. **Publish** - Publish all customizations

### Multiple Environments
To deploy to multiple environments, uncomment and duplicate the deployment stage in `DEPLOY-main.yml`:

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

## Configuration File: alm-config.psd1

All pipelines use the `alm-config.psd1` configuration file which defines:

### Solutions
List of solutions to process in dependency order:
```powershell
solutions = @(
    @{ name = 'CoreSolution' }
    @{ name = 'ExtensionSolution' }
    @{ name = 'TestSolution'; deployUnmanaged = $true }
)
```

### Assets
Additional files/folders to include in build artifacts:
```powershell
assets = @('data', 'documentation')
```

### Hooks
Custom PowerShell scripts to run at various stages:
```powershell
hooks = @{
    preExport  = @()
    postExport = @('data/system/export.ps1')
    preDeploy  = @()
    postDeploy = @('data/system/import.ps1')
    preBuild   = @()
    postBuild  = @()
    dataMigrations = @()
}
```

### Script Dependencies
PowerShell modules required by your scripts:
```powershell
scriptDependencies = @{
    'Rnwood.Dataverse.Data.PowerShell' = '2.12.1'
    'Microsoft.PowerApps.Administration.PowerShell' = ''
}
```

## Service Connections

Each pipeline that connects to Dataverse requires an Azure DevOps Service Connection:

### Naming Convention
- Development: `Dev-{BranchName}` (e.g., `Dev-main`, `Dev-feature-xyz`)
- Target Environments: `{EnvironmentName}` (e.g., `Test-main`, `Production`)

### Type
All service connections must be of type **Power Platform** with authentication type **Service Principal**.

### Setup
Service connections are typically created during the automated setup process. See [automated-setup.md](automated-setup.md) for details.

## Variable Groups

Variable groups store environment-specific configuration:

### Naming Convention
- `Environment-{EnvironmentName}`
- Examples: `Environment-Dev-main`, `Environment-Test-main`, `Environment-Production`

### Special Variables
- `ConnRef_*` - Connection reference values (e.g., `ConnRef_shared_commondataservice`)
- `EnvVar_*` - Environment variable values (e.g., `EnvVar_ApiEndpoint`)

## Branch Support

ALM4Dataverse pipelines support multiple branches out of the box:

- **BUILD** pipeline triggers on all branches
- **EXPORT** and **IMPORT** use branch-specific service connections (`Dev-{BranchName}`)
- **DEPLOY** typically triggers only on the `main` branch (configurable)

This enables:
- Feature branch development with isolated dev environments
- Pull request workflows
- Hotfix branches with separate deployment paths

## Pipeline Dependencies

```
Source Code Changes
    ↓
[EXPORT Pipeline] ← Manual trigger after changes in dev environment
    ↓
Source Control (Git)
    ↓
[BUILD Pipeline] ← Automatic trigger on push
    ↓
Build Artifacts (Tagged)
    ↓
[DEPLOY Pipeline] ← Automatic/Manual trigger
    ↓
Target Environments
```

For development synchronization:
```
Source Control (Git)
    ↓
[IMPORT Pipeline] ← Manual trigger to update dev environment
    ↓
Development Environment
```

## Best Practices

1. **Always EXPORT before IMPORT** to avoid losing uncommitted changes
2. **Review EXPORT changes** before pushing to ensure only intended changes are committed
3. **Use BUILD tags** for traceability and rollback capability
4. **Configure approval gates** on production deployments
5. **Test in lower environments** before production deployment
6. **Use hooks** for environment-specific configuration and data setup
7. **Keep solutions in dependency order** in `alm-config.psd1`
8. **Use descriptive commit messages** when running EXPORT

## Troubleshooting

### EXPORT Pipeline Issues
- **Solution not found**: Ensure solution exists in the development environment
- **Permission errors**: Check service connection has sufficient privileges
- **Nothing to commit**: No changes detected - this is expected if environment matches source

### BUILD Pipeline Issues
- **Packing fails**: Check solution source files are not corrupted
- **Missing dependencies**: Ensure `scriptDependencies` in `alm-config.psd1` are correct
- **Tag already exists**: Build number collision (rare) - retry the build

### IMPORT Pipeline Issues
- **Import fails**: Solution may have dependencies not present in environment
- **Connection errors**: Verify service connection and variable group configuration
- **Missing dependencies**: Check `alm-config.psd1` lists solutions in correct dependency order

### DEPLOY Pipeline Issues
- **Artifact not found**: Ensure BUILD pipeline completed successfully
- **Connection reference errors**: Verify `ConnRef_` variables in variable group
- **Environment variable errors**: Verify `EnvVar_` variables in variable group
- **Upgrade fails**: Check for breaking changes or missing dependencies

## Next Steps

- [Pipeline Usage Instructions](pipeline-usage.md) - Step-by-step workflows
- [Automated Setup](automated-setup.md) - Initial configuration guide
