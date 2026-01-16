# Managing Configuration Data

ALM4Dataverse supports deploying configuration and reference data alongside your solutions. This enables you to maintain lookup tables, system settings, and other configuration data in source control.

## Data Management Overview

Configuration data flows through the pipeline using hooks:

```
Development Environment
        │
        ▼ (postExport hook)
   Source Control (JSON files)
        │
        ▼ (build copies assets)
   Build Artifacts
        │
        ▼ (postDeploy hook)
   Target Environments
```

## Setting Up Data Export

### 1. Configure the Hook

In `alm-config.psd1`, ensure the `postExport` hook is configured:

```powershell
@{
    hooks = @{
        postExport = @('data/system/export.ps1')
    }
    
    assets = @('data')  # Include data folder in artifacts
}
```

### 2. Create the Export Script

Create `data/system/export.ps1`:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

Write-Host "##[section]Exporting Configuration Data"

# Export configuration table
Write-Host "##[group]Exporting new_configuration"
Get-DataverseRecord -TableName new_configuration |
    Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_configuration -WithDeletions
Write-Host "##[endgroup]"

# Export lookup values
Write-Host "##[group]Exporting new_lookupvalues"
Get-DataverseRecord -TableName new_lookupvalues |
    Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_lookupvalues -WithDeletions
Write-Host "##[endgroup]"

Write-Host "##[section]Data Export Complete"
```

### 3. Run Export

When you run the EXPORT pipeline, data will be:
1. Queried from your dev environment
2. Saved as JSON files in `data/system/{tablename}/`
3. Committed alongside your solution changes

## Setting Up Data Import

### 1. Configure the Hook

In `alm-config.psd1`:

```powershell
@{
    hooks = @{
        postDeploy = @('data/system/import.ps1')
    }
}
```

### 2. Create the Import Script

Create `data/system/import.ps1`:

```powershell
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

Write-Host "##[section]Importing Configuration Data"

# Phase 1: Upsert new and updated records
Write-Host "##[group]Upserting new_configuration"
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_configuration |
    Set-DataverseRecord -TableName new_configuration -Verbose
Write-Host "##[endgroup]"

Write-Host "##[group]Upserting new_lookupvalues"
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_lookupvalues |
    Set-DataverseRecord -TableName new_lookupvalues -Verbose
Write-Host "##[endgroup]"

# Phase 2: Remove deleted records
Write-Host "##[group]Removing deleted records"
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_configuration -Deletions |
    Remove-DataverseRecord -Verbose -IfExists

Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_lookupvalues -Deletions |
    Remove-DataverseRecord -Verbose -IfExists
Write-Host "##[endgroup]"

Write-Host "##[section]Data Import Complete"
```

## Data File Structure

After export, your data folder will contain:

```
data/
└── system/
    ├── export.ps1
    ├── import.ps1
    ├── new_configuration/
    │   ├── {guid1}.json
    │   ├── {guid2}.json
    │   └── deletions.json
    └── new_lookupvalues/
        ├── {guid1}.json
        ├── {guid2}.json
        └── deletions.json
```

### Record Files

Each record is stored as a JSON file named by its primary key:

```json
{
  "new_configurationid": "12345678-1234-1234-1234-123456789abc",
  "new_name": "Setting1",
  "new_value": "Value1",
  "statecode": 0
}
```

### Deletions File

`deletions.json` tracks records that were deleted:

```json
[
  "87654321-4321-4321-4321-cba987654321",
  "11111111-2222-3333-4444-555555555555"
]
```

## Handling Dependencies

### Parent-Child Relationships

If tables have relationships, import in dependency order:

```powershell
# Import parent first
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_category |
    Set-DataverseRecord -TableName new_category

# Then import children
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_subcategory |
    Set-DataverseRecord -TableName new_subcategory
```

### Circular Dependencies

For circular dependencies, use multiple phases:

```powershell
# Phase 1: Create records without lookup values
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_entity |
    ForEach-Object {
        $record = $_
        $record.PSObject.Properties.Remove('new_relatedentityid')
        Set-DataverseRecord -TableName new_entity -InputObject $record
    }

# Phase 2: Update with lookup values
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_entity |
    Where-Object { $_.new_relatedentityid } |
    ForEach-Object {
        Set-DataverseRecord -TableName new_entity -Id $_.'new_entityid' -InputObject @{
            new_relatedentityid = $_.new_relatedentityid
        }
    }
```

## Filtering Data

### Export Filtered Records

Export only specific records:

```powershell
# Export only active records
Get-DataverseRecord -TableName new_configuration -FilterValues @{
    statecode = 0
} | Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_configuration

# Export with specific conditions
Get-DataverseRecord -TableName new_settings -FilterValues @{
    new_issystemsetting = $true
} | Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_settings
```

### Export Specific Columns

Limit exported columns:

```powershell
Get-DataverseRecord -TableName new_configuration -Columns @(
    'new_configurationid',
    'new_name',
    'new_value',
    'statecode'
) | Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_configuration
```

## Environment-Specific Data

Some data may need to vary by environment:

### Option 1: Use Environment Variables

Store environment-specific values in variable groups and update after import:

```powershell
# In import.ps1
$apiEndpoint = $env:ENVVAR_contoso_APIEndpoint

# Update environment-specific record
Set-DataverseRecord -TableName new_configuration -Key @{
    new_name = 'APIEndpoint'
} -InputObject @{
    new_value = $apiEndpoint
}
```

### Option 2: Conditional Data

Include environment checks in import:

```powershell
# Only import test data to non-production
if ($Context.EnvironmentName -notlike '*PROD*') {
    Get-DataverseRecordsFolder -InputPath $PSScriptRoot/testdata |
        Set-DataverseRecord -TableName new_testrecords
}
```

## Data Migrations

For schema changes that require data migration, use the `dataMigrations` hook:

```powershell
# migrations/migrate-to-new-schema.ps1
param([hashtable]$Context)

Write-Host "Running data migration..."

# Move data from old column to new column
# This runs after staging but before upgrade, so both columns exist

Get-DataverseRecord -TableName account -FilterValues @{
    'new_oldfield:NotNull' = $true
    'new_newfield:IsNull' = $true
} -MaxPageSize 1000 | ForEach-Object {
    Set-DataverseRecord -TableName account -Id $_.accountid -InputObject @{
        new_newfield = $_.new_oldfield
    }
    Write-Host "Migrated account: $($_.name)"
}
```

Configure in `alm-config.psd1`:

```powershell
@{
    hooks = @{
        dataMigrations = @('migrations/migrate-to-new-schema.ps1')
    }
}
```

## Best Practices

### 1. Keep Data Sets Small

Only include essential configuration data. Large data sets:
- Slow down deployments
- Increase merge conflicts
- Are harder to review

### 2. Use Meaningful Primary Keys

Where possible, use alternate keys (natural keys) instead of GUIDs for easier identification.

### 3. Document Data Tables

Maintain a list of which tables are managed through ALM:

| Table | Purpose | Update Frequency |
|-------|---------|------------------|
| `new_configuration` | System settings | Rare |
| `new_lookupvalues` | Dropdown options | Occasional |

### 4. Review Data Changes

When reviewing PRs, pay attention to data changes:
- New records being added
- Values being changed
- Records being deleted

### 5. Test Data Imports

Before deploying to production, verify data imports work correctly in TEST/UAT.

### 6. Handle Failures Gracefully

Make import scripts idempotent and handle errors:

```powershell
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_configuration | ForEach-Object {
    try {
        Set-DataverseRecord -TableName new_configuration -InputObject $_ -Verbose
    }
    catch {
        Write-Host "##[warning]Failed to import record: $($_.new_name) - $_"
        # Decide: continue or throw
    }
}
```
