# Importing Solutions to Development

The IMPORT pipeline deploys solutions from source control to a development environment. This is useful for setting up new dev environments or syncing changes from other developers.

## When to Import

Use the IMPORT pipeline when you need to:
- Set up a new development environment
- Sync changes from source control to your dev environment
- Recover from environment issues
- Apply changes made by other developers

## Running the Import Pipeline

### From Azure DevOps

1. Navigate to **Pipelines** > **Pipelines**
2. Select the **IMPORT** pipeline
3. Click **Run pipeline**
4. Select your branch
5. Click **Run**

## What Happens During Import

1. **Checkout**: Source code is checked out from the selected branch
2. **Install Tools**: Power Platform Build Tools and dependencies installed
3. **Connect**: Pipeline connects to your development environment
4. **Build**: Solutions are packed from source (unmanaged versions)
5. **Deploy**: Unmanaged solutions are imported to the dev environment

## Differences from DEPLOY

| Aspect | IMPORT | DEPLOY |
|--------|--------|--------|
| Target | Development environment | TEST/UAT/PROD |
| Solution Type | Unmanaged | Managed |
| Source | Current source code | Build artifacts |
| Trigger | Manual only | Auto or manual |
| Purpose | Sync dev environment | Release to production |

## Prerequisites

### Service Connection

A service connection named `Dev-{branch}` must exist:
- For `main` branch: `Dev-main`
- For feature branch: `Dev-feature-x`

### Variable Group

A variable group `Environment-Dev-{branch}` should contain:
- Connection reference IDs
- Environment variable values
- Service account UPN

### Permissions

The pipeline needs access to:
- The service connection
- The variable group
- The repository

## Use Cases

### 1. New Developer Onboarding

When a new developer joins:
1. Provision a new Dataverse environment
2. Create service connection and variable group
3. Run IMPORT to populate with current solution

### 2. Environment Reset

If your dev environment becomes corrupted:
1. Delete problematic solutions manually
2. Run IMPORT to restore from source

### 3. Sync Team Changes

After other team members export changes (via EXPORT pipeline):
1. The changes will be visible in Azure DevOps (Repos > Files)
2. Run IMPORT to get their changes in your environment

### 4. Feature Branch Setup

When starting work on a feature branch:
1. Create branch in Azure DevOps (Repos > Branches > New branch)
2. Set up new dev environment: `Dev-feature-x`
3. Create service connection and variable group
4. Run IMPORT to initialize the environment

## What Gets Imported

The IMPORT pipeline imports:
- **Solutions**: All solutions in `alm-config.psd1` (unmanaged)
- **Configuration Data**: Via `postDeploy` hooks
- **Environment Variables**: From variable group
- **Connection References**: From variable group

## Connection References and Environment Variables

Even for import, you need to configure:

### Variable Group: `Environment-Dev-main`

```
CONNREF_contoso_sharedconnection = {connection-id-in-dev}
ENVVAR_contoso_APIEndpoint = https://api.dev.contoso.com
ServiceAccountUpn = dev-service@contoso.com
```

The connection IDs will be different from TEST/PROD because you're pointing to dev connections.

## Pipeline Configuration

The IMPORT pipeline is defined in `pipelines/IMPORT.yml`:

```yaml
trigger: none  # Manual only

resources:
  repositories:
    - repository: ALM4Dataverse
      type: git
      name: ALM4Dataverse

variables:
- group: Environment-Dev-${{ variables['Build.SourceBranchName'] }}

stages:
- template: pipelines/templates/import.yml@ALM4Dataverse
```

## Handling Import Issues

### Solution Already Exists

If importing over existing solutions:
- Unmanaged components merge/update
- Existing customizations are preserved
- New components are added

### Missing Dependencies

If a solution depends on another not in your environment:
1. Import the dependency first, or
2. Ensure it's listed first in `alm-config.psd1`

### Connection Reference Errors

If connection reference setup fails:
1. Verify the connection exists in the dev environment
2. Check the connection ID in your variable group
3. Ensure the connection is shared with the importing user

## Best Practices

### 1. Import Before Exporting

Before starting development work, import to ensure you have the latest:
```
View Latest (Repos) → Import → Develop → Export (commits automatically)
```

### 2. Use Consistent Environments

Keep dev environment structure similar to TEST/PROD:
- Same connection types
- Similar security roles
- Matching entity structures

### 3. Clean Up Before Import

If you have many local changes you want to discard:
1. Delete the solutions from dev environment
2. Run IMPORT for a clean state

### 4. Coordinate with Team

Let team members know when you're importing, especially if:
- You're resetting shared components
- You might affect ongoing work

## Comparison: Import vs Manual Import

| Aspect | IMPORT Pipeline | Manual Import |
|--------|-----------------|---------------|
| Consistency | Always same process | Varies by person |
| Configuration | Automatic via variable group | Manual each time |
| Data Migration | Runs hooks | Must run separately |
| Audit Trail | Full pipeline history | None |
| Reproducibility | Run again anytime | Must remember steps |

Always prefer the IMPORT pipeline over manual imports for development environments.
