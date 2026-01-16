# Deploying Solutions

The DEPLOY pipeline takes build artifacts and deploys them to target environments like TEST, UAT, and PROD.

## When Deployments Run

The DEPLOY pipeline can be triggered:
- **Automatically**: When BUILD completes on the main branch
- **Manually**: For any build from any branch

## Running the Deploy Pipeline

### Automatic Trigger (Main Branch)

When a build completes on `main`, the DEPLOY pipeline automatically starts and progresses through configured environments.

### Manual Run

1. Navigate to **Pipelines** > **Pipelines**
2. Select the **DEPLOY-main** pipeline (or your branch)
3. Click **Run pipeline**
4. Select the **Resources** > **Pipeline** to choose a specific build
5. Click **Run**

## What Happens During Deployment

For each target environment:

1. **Download Artifacts**: Build artifacts are downloaded
2. **Install Tools**: Power Platform Build Tools are installed
3. **Install Dependencies**: PowerShell modules (using locked versions)
4. **Connect**: Establish connection to target Dataverse environment
5. **Pre-Deploy Hooks**: Run any `preDeploy` hooks
6. **Stage Solutions**: Import solutions (in dependency order)
7. **Data Migrations**: Run any `dataMigrations` hooks
8. **Apply Upgrades**: Complete upgrades (in reverse dependency order)
9. **Activate Processes**: Activate workflows/flows with proper ownership
10. **Publish Customizations**: Publish all changes
11. **Post-Deploy Hooks**: Run any `postDeploy` hooks (e.g., data import)

## Multi-Environment Deployment

Configure deployment stages in `pipelines/DEPLOY-main.yml`:

```yaml
stages:
  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: TEST-main

  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: UAT-main

  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: PROD
```

Environments deploy sequentially, and each can have approval gates.

## Approval Gates

### Setting Up Approvals

Approvals can be configured on:
- **Variable Groups**: `Environment-{name}` 
- **Environments**: Azure DevOps Environments

1. Go to the variable group or environment
2. Click **Approvals and checks**
3. Add **Approvals**
4. Select approvers (users or teams)
5. Configure timeout and options

### Approval Flow

```
BUILD Complete
     │
     ▼
TEST Deployment ─── (auto-approved or approval) ───▶ TEST Complete
     │
     ▼
UAT Approval Required ─── (manual approval) ───▶ UAT Deployment ───▶ UAT Complete
     │
     ▼
PROD Approval Required ─── (manual approval) ───▶ PROD Deployment ───▶ PROD Complete
```

## Solution Import Strategy

### Smart Import Logic

ALM4Dataverse determines the best import method:

| Scenario | Method | Behavior |
|----------|--------|----------|
| Same version exists | Skip | No action needed |
| Major.Minor matches | Update | Fast update, preserves unmanaged changes |
| Version differs | Upgrade | Full replacement via holding solution |
| New solution | Install | Fresh installation |

### Holding Solution Pattern

For multiple solutions with upgrades:

1. All solutions imported as holding solutions (side-by-side)
2. Data migrations run while both versions exist
3. Upgrades applied in reverse dependency order
4. This ensures referential integrity throughout

## Configuration During Deployment

### Connection References

Set connection references via environment variables:

```
CONNREF_{connectionreference_uniquename} = {connection_id}
```

### Environment Variables

Set Dataverse environment variable values:

```
ENVVAR_{environmentvariable_schemaname} = {value}
```

These are configured in the `Environment-{name}` variable group.

## Process Activation

After solution import, ALM4Dataverse:

1. Finds all workflows/flows in the deployed solutions
2. Reassigns ownership to the configured service account
3. Activates any deactivated processes

Configure the service account in environment variables:
```
ServiceAccountUpn = serviceaccount@contoso.com
```

## Importing Configuration Data

Use the `postDeploy` hook to import configuration data:

```powershell
# data/system/import.ps1
param([hashtable]$Context)

# Phase 1: Upsert records
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_configuration |
    Set-DataverseRecord -TableName new_configuration -Verbose

# Phase 2: Delete removed records
Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_configuration -Deletions |
    Remove-DataverseRecord -Verbose -IfExists
```

## Handling Deployment Issues

### Deployment Fails

1. Check pipeline logs for specific errors
2. Look for `##[error]` markers
3. Common issues:
   - Missing environment variables
   - Connection reference not configured
   - Service account not found
   - Solution dependency missing

### Partial Deployment

If deployment fails mid-way:
- Some solutions may be in holding state
- Re-run the deployment to continue
- Or manually complete upgrades in target environment

### Rollback

To rollback:
1. Find the previous successful build
2. Manually run DEPLOY with that build
3. Or restore from environment backup

## Exclusive Locks

Configure exclusive locks on variable groups to prevent concurrent deployments:

1. Go to variable group **Approvals and checks**
2. Add **Exclusive lock**
3. Only one deployment can run at a time for that environment

## Pipeline Configuration

### DEPLOY-main.yml

```yaml
trigger: none  # Triggered by build completion

resources:
  pipelines:
    - pipeline: build
      source: 'BUILD'
      trigger:
        branches:
          include:
          - main
  repositories:
    - repository: ALM4Dataverse
      type: git
      name: ALM4Dataverse

stages:
  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: TEST-main
```

### Per-Environment Requirements

Each environment needs:
- Service connection: `{EnvironmentName}`
- Variable group: `Environment-{EnvironmentName}`
- Azure DevOps Environment: `{EnvironmentName}` (optional, for approvals)

## Best Practices

### 1. Always Deploy Through Pipelines

Never manually import solutions to managed environments. This ensures:
- Consistent deployment process
- Audit trail
- Proper configuration

### 2. Use Approvals for Production

Always require approval for PROD deployments with appropriate reviewers.

### 3. Test in Lower Environments First

Deploy to TEST → UAT → PROD in sequence, validating at each stage.

### 4. Monitor Deployments

Watch for:
- Deployment duration changes
- Failure patterns
- Environment-specific issues

### 5. Keep Environments in Sync

Regularly deploy to keep environments from drifting too far apart.
