# Exporting Solutions

The EXPORT pipeline captures changes from your development Dataverse environment and commits them to source control.

## When to Export

Run the EXPORT pipeline when you have:
- Completed development work in your dev environment
- Made changes you want to commit to source control
- Changes ready for code review or deployment

## Running the Export Pipeline

### From Azure DevOps

1. Navigate to **Pipelines** > **Pipelines**
2. Select the **EXPORT** pipeline
3. Click **Run pipeline**
4. Select your branch
5. Enter a **commit message** describing your changes
6. Click **Run**

### What Happens During Export

1. **Connect**: Pipeline connects to your development environment (`Dev-{branch}`)
2. **Pre-Export Hooks**: Any `preExport` hooks run
3. **Export Solutions**: Each solution in `alm-config.psd1` is exported
4. **Unpack**: Solutions are unpacked into folder structure
5. **Canvas Apps**: `.msapp` files are unpacked for better diff support
6. **Detect Changes**: Git compares exported files with existing source
7. **Version Bump**: If changes detected, solution version is incremented
8. **Post-Export Hooks**: Any `postExport` hooks run (e.g., data export)
9. **Commit**: Changes are committed and pushed to the branch

## Version Increment Logic

The pipeline automatically increments the solution version based on the type of changes:

| Change Type | Version Impact | Example |
|-------------|----------------|---------|
| Additive only (new components) | Revision +1 | 1.0.0.0 → 1.0.0.1 |
| Removals/breaking changes | Minor +1, reset lower | 1.0.0.5 → 1.1.0.0 |

This versioning strategy helps downstream processes determine the appropriate import method.

## Export Requirements

### Service Connection

A Power Platform service connection named `Dev-{branch}` must exist:
- For `main` branch: `Dev-main`
- For feature branch `feature-x`: `Dev-feature-x`

### Variable Group

A variable group named `Environment-Dev-{branch}` should exist with any required environment variables.

### Permissions

The pipeline needs:
- Access to the service connection
- Contribute permission on the Git repository (to push commits)

## Exporting Configuration Data

Use the `postExport` hook to export configuration/reference data:

```powershell
# data/system/export.ps1
param([hashtable]$Context)

# Export configuration table
Get-DataverseRecord -TableName new_configuration |
    Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_configuration -WithDeletions

# Export lookup values
Get-DataverseRecord -TableName new_lookupvalues |
    Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_lookupvalues -WithDeletions
```

The `-WithDeletions` flag tracks deleted records so they can be removed during import.

## Handling Export Issues

### No Changes Detected

If export runs but commits nothing:
- Changes may already be in source control
- Or no actual changes were made in the environment

### Export Fails

Common causes:
- Invalid service connection credentials
- Service principal lacks permissions in Dataverse
- Network connectivity issues

Check the pipeline logs for specific error messages.

### Large Canvas Apps

Canvas apps are unpacked during export, which can create many files. This is normal and enables:
- Meaningful code review
- Proper merge handling
- Change tracking

## Best Practices

### 1. Export Frequently

Export after each logical unit of work rather than accumulating many changes.

### 2. Write Good Commit Messages

The commit message you provide becomes part of the Git history. Make it descriptive:

✅ Good: "Add account validation workflow and update form layout"
❌ Bad: "Updates"

### 3. Review Before Committing

The export creates a commit automatically. Review changes in Azure DevOps or locally before proceeding with builds.

### 4. Coordinate with Team

If multiple developers work on the same environment:
- Communicate before exporting
- Export your changes before others make conflicting changes
- Consider using feature branches with dedicated dev environments

### 5. Export Data Separately

Keep solution exports and data exports as separate concerns using hooks. This allows:
- Independent versioning
- Selective data deployment
- Easier troubleshooting

## Pipeline Configuration

The EXPORT pipeline is defined in `pipelines/EXPORT.yml`:

```yaml
trigger: none # Manual only

parameters:
- name: commitMessage
  type: string
  displayName: 'Commit message for exported changes'

stages:
- template: pipelines/templates/export.yml@ALM4Dataverse
  parameters:
    commitMessage: ${{ parameters.commitMessage }}
```

The template handles:
- Environment connection
- Solution export and unpacking
- Version management
- Git commit and push
