# Building Solutions

The BUILD pipeline creates deployable artifacts from your source control. It runs automatically on every commit and produces both managed and unmanaged solution packages.

## When Builds Run

The BUILD pipeline triggers automatically:
- On every commit to any branch
- When pull requests are created or updated
- Can also be run manually

## Running the Build Pipeline

### Automatic Trigger

The BUILD pipeline triggers automatically when changes are committed to any branch. Typically, the EXPORT pipeline commits changes, but you can also commit files directly in Azure DevOps (Repos > Files).

### Manual Run

1. Navigate to **Pipelines** > **Pipelines**
2. Select the **BUILD** pipeline
3. Click **Run pipeline**
4. Select your branch
5. Click **Run**

## What Happens During Build

1. **Checkout**: Source code and ALM4Dataverse templates are checked out
2. **Set Build Number**: Generates a unique build number with timestamp
3. **Install Tools**: Power Platform Build Tools are installed
4. **Install Dependencies**: PowerShell modules from `alm-config.psd1` are installed
5. **Pre-Build Hooks**: Any `preBuild` hooks run
6. **Pack Solutions**: Each solution is packed into managed and unmanaged zips
7. **Copy Assets**: Assets defined in `alm-config.psd1` are copied
8. **Copy Scripts**: Deployment scripts are included in artifacts
9. **Create Lock File**: Module versions are pinned for consistent deployment
10. **Post-Build Hooks**: Any `postBuild` hooks run
11. **Publish Artifacts**: Build output is published
12. **Tag Source**: Git tag is created with build version

## Build Artifacts

The build produces these artifacts:

```
artifacts/
├── solutions/
│   ├── MySolution.zip              # Unmanaged version
│   ├── MySolution_managed.zip      # Managed version
│   ├── OtherSolution.zip
│   └── OtherSolution_managed.zip
├── data/                            # Copied from assets
│   └── system/
│       ├── export.ps1
│       └── import.ps1
├── pipelines/
│   └── scripts/                     # Deployment scripts
│       ├── build.ps1
│       ├── common.ps1
│       ├── connect.ps1
│       ├── deploy.ps1
│       └── installdependencies.ps1
├── alm-config.psd1                  # Configuration
└── scriptDependencies.lock.json     # Pinned module versions
```

## Build Numbering

Build numbers follow the format:
```
{RepositoryName}-{BranchName}-{Timestamp}
```

Example: `MyProject-main-2024-01-15-143022`

This ensures:
- Unique identification of each build
- Easy tracing back to source
- Chronological ordering

## Version Locking

The build creates `scriptDependencies.lock.json` which pins the exact versions of PowerShell modules used:

```json
{
  "scriptDependencies": {
    "Rnwood.Dataverse.Data.PowerShell": "2.12.1"
  }
}
```

This ensures deployment uses the same module versions regardless of:
- When deployment runs
- Which environment is targeted
- What latest version is available

## Git Tagging

Each successful build creates a Git tag:
```
v{BuildNumber}
```

This enables:
- Tracing deployed versions to exact source
- Reproducing builds from any point in history
- Rollback reference points

## Configuring Assets

Assets are additional files/folders included in artifacts:

```powershell
# alm-config.psd1
@{
    assets = @(
        'data',           # Configuration data
        'documentation',  # User docs
        'config'          # Other config files
    )
}
```

Assets are copied verbatim from your repository root to the artifacts.

## Build Hooks

### preBuild

Runs before solution packing:

```powershell
# scripts/pre-build.ps1
param([hashtable]$Context)

# Validate solution structure
# Generate code files
# Run custom preprocessing
```

### postBuild

Runs after artifacts are created:

```powershell
# scripts/post-build.ps1
param([hashtable]$Context)

# Custom packaging
# Validation
# Notifications
```

## Build Failures

### Common Causes

1. **Invalid Solution Structure**
   - Missing required files
   - Corrupted XML

2. **Missing Assets**
   - Asset path in config doesn't exist
   - Check `alm-config.psd1` paths

3. **Module Installation Failure**
   - Network issues
   - Invalid version specification

4. **Hook Script Errors**
   - Script syntax errors
   - Missing dependencies

### Troubleshooting

1. Check the pipeline logs for specific error messages
2. Look for `##[error]` markers in the output
3. Verify file paths exist in source control
4. Test hooks locally before committing

## Pipeline Configuration

The BUILD pipeline is defined in `pipelines/BUILD.yml`:

```yaml
trigger:
  branches:
    include:
    - '*'  # Build all branches

resources:
  repositories:
    - repository: ALM4Dataverse
      type: git
      name: ALM4Dataverse

stages:
- template: pipelines/templates/build.yml@ALM4Dataverse
```

## Best Practices

### 1. Keep Builds Fast

- Minimize asset size
- Avoid unnecessary dependencies
- Keep hooks efficient

### 2. Monitor Build Health

- Set up notifications for build failures
- Review build logs regularly
- Track build times

### 3. Don't Break the Build

- Review changes carefully before committing to the repository
- Use feature branches for risky changes
- Review exports before committing

### 4. Use Build Artifacts

When troubleshooting deployment issues, download and inspect build artifacts to verify:
- Correct solutions are included
- Versions are as expected
- Assets are complete
