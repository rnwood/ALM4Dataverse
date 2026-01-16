# Hooks and Extensibility

ALM4Dataverse provides a powerful hooks system that allows you to extend the pipeline behavior at key points in the build, export, and deployment processes.

## Hook Overview

Hooks are PowerShell scripts that run at specific stages of the pipeline. They enable you to:

- Export and import configuration data
- Run data migrations during upgrades
- Perform custom validations
- Integrate with external systems
- Transform solution components

## Available Hooks

| Hook | Stage | Use Cases |
|------|-------|-----------|
| `preExport` | Before solution export | Clear caches, prepare environment |
| `postExport` | After solution export | Export config data, generate documentation |
| `preBuild` | Before solution packing | Code generation, validation |
| `postBuild` | After artifact creation | Custom packaging, notifications |
| `preDeploy` | Before solution import | Validate target environment, backup |
| `dataMigrations` | After staging, before upgrade | Move data between columns/tables |
| `postDeploy` | After deployment complete | Import config data, send notifications |

## Configuring Hooks

Hooks are configured in `alm-config.psd1`:

```powershell
@{
    hooks = @{
        preExport      = @()
        postExport     = @('data/system/export.ps1')
        preBuild       = @()
        postBuild      = @()
        preDeploy      = @()
        dataMigrations = @()
        postDeploy     = @('data/system/import.ps1')
    }
}
```

### Multiple Hook Scripts

You can specify multiple scripts for each hook:

```powershell
hooks = @{
    postDeploy = @(
        'data/system/import.ps1',
        'scripts/send-notification.ps1',
        'scripts/update-documentation.ps1'
    )
}
```

Scripts execute in the order listed.

## Hook Context

Every hook script receives a `-Context` parameter containing a hashtable with:

### Common Context Properties

| Property | Description |
|----------|-------------|
| `HookType` | The type of hook being executed |
| `BaseDirectory` | Base directory for the hook (source or artifacts root) |
| `Config` | The loaded `alm-config.psd1` configuration |

### Stage-Specific Context

**preBuild, postBuild**:
- `SourceDirectory`: Path to the source directory
- `ArtifactStagingDirectory`: Path to the artifact staging directory

**preExport, postExport**:
- `SourceDirectory`: Path to the source directory
- `ArtifactStagingDirectory`: Path to the artifact staging directory
- `TempDirectory`: Path to temporary directory
- `EnvironmentName`: Name of the Dataverse environment

**preDeploy, dataMigrations, postDeploy**:
- `ArtifactsPath`: Path to the artifacts directory
- `UseUnmanagedSolutions`: Boolean indicating if deploying unmanaged

## Writing Hook Scripts

### Basic Structure

```powershell
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

# Access context properties
$hookType = $Context.HookType
$baseDir = $Context.BaseDirectory
$config = $Context.Config

Write-Host "Running $hookType hook"

# Your custom logic here
```

### Example: Data Export Hook

```powershell
# data/system/export.ps1
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

Write-Host "Exporting configuration data..."

# Export lookup table data
Get-DataverseRecord -TableName new_configurationitem |
    Set-DataverseRecordsFolder -OutputPath "$PSScriptRoot/new_configurationitem" -WithDeletions
```

### Example: Data Import Hook

```powershell
# data/system/import.ps1
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

Write-Host "Importing configuration data..."

# Phase 1: Upsert records
Get-DataverseRecordsFolder -InputPath "$PSScriptRoot/new_configurationitem" |
    Set-DataverseRecord -TableName new_configurationitem -Verbose

# Phase 2: Delete removed records
Get-DataverseRecordsFolder -InputPath "$PSScriptRoot/new_configurationitem" -Deletions |
    Remove-DataverseRecord -Verbose -IfExists
```

### Example: Data Migration Hook

```powershell
# migrations/move-data-to-new-column.ps1
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

# Run during dataMigrations phase - after staging but before upgrade
# This allows access to both old and new schema

Write-Host "Migrating data from old_field to new_field..."

Get-DataverseRecord -TableName account -FilterValues @{
    "new_field:IsNull" = $true
    "old_field:NotNull" = $true
} | ForEach-Object {
    Set-DataverseRecord -TableName account -Id $_.accountid -InputObject @{
        new_field = $_.old_field
    }
}
```

## The [alm] Placeholder

Hook script paths can use `[alm]` to reference scripts from the ALM4Dataverse repository:

```powershell
hooks = @{
    postExport = @('[alm]/custom-hooks/standard-export.ps1')
}
```

This is useful for:
- Sharing hooks across multiple application repositories
- Maintaining standard hooks in a fork of ALM4Dataverse
- Keeping application repositories simple

## Fork Configuration

You can provide default hook configurations in a fork:

1. Fork ALM4Dataverse
2. Create `fork-almconfig.psd1` in the fork root
3. Define default hooks

```powershell
# fork-almconfig.psd1
@{
    hooks = @{
        postDeploy = @('[alm]/standard-hooks/audit-deployment.ps1')
    }
}
```

When merged with your application's `alm-config.psd1`:
- Arrays are concatenated (your hooks + fork hooks)
- Application values take precedence for non-array properties

## Best Practices

### 1. Keep Hooks Idempotent

Hooks may run multiple times (retries, re-runs). Ensure they can safely run repeatedly:

```powershell
# Good: Upsert pattern
Set-DataverseRecord -TableName mytable -Key @{name = 'config1'} -InputObject @{value = 'x'}

# Avoid: Insert without checking existence
Add-DataverseRecord -TableName mytable -InputObject @{name = 'config1'; value = 'x'}
```

### 2. Handle Errors Gracefully

```powershell
try {
    # Your logic
}
catch {
    Write-Host "##[error]Hook failed: $_"
    throw  # Re-throw to fail the pipeline
}
```

### 3. Log Progress

Use Azure DevOps logging commands:

```powershell
Write-Host "##[section]Starting data migration"
Write-Host "##[group]Processing table: accounts"
# ... work ...
Write-Host "##[endgroup]"
```

### 4. Use Transactions Where Appropriate

For complex data operations, consider using transactions or implementing rollback logic.

### 5. Test Hooks Locally

Before committing:
```powershell
$context = @{
    HookType = 'postDeploy'
    BaseDirectory = 'C:\path\to\repo'
    Config = Import-PowerShellDataFile 'alm-config.psd1'
    ArtifactsPath = 'C:\path\to\artifacts'
    UseUnmanagedSolutions = $false
}

& .\data\system\import.ps1 -Context $context
```

## Dataverse PowerShell Commands

Hooks commonly use the `Rnwood.Dataverse.Data.PowerShell` module:

| Command | Purpose |
|---------|---------|
| `Get-DataverseRecord` | Query records |
| `Set-DataverseRecord` | Create/update records |
| `Remove-DataverseRecord` | Delete records |
| `Get-DataverseRecordsFolder` | Read records from folder |
| `Set-DataverseRecordsFolder` | Write records to folder |

See the module documentation for full details.
