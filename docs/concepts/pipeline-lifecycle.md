# Pipeline Lifecycle

This document explains the lifecycle of changes flowing through the ALM4Dataverse pipeline system.

## Development Workflow

The typical development workflow follows this pattern:

```
   Development Environment
          │
          ▼
   ┌──────────────┐
   │    EXPORT    │ ─────▶ Git Repository
   └──────────────┘
          │
          ▼
   ┌──────────────┐
   │    BUILD     │ ─────▶ Artifacts
   └──────────────┘
          │
          ▼
   ┌──────────────┐
   │   DEPLOY     │ ─────▶ TEST ──▶ UAT ──▶ PROD
   └──────────────┘
```

## Pipeline Details

### 1. EXPORT Pipeline

**Purpose**: Capture changes from the development environment into source control.

**When to run**: Manually, after completing development work and ready to commit.

**What it does**:
1. Connects to the development Dataverse environment
2. Exports each solution defined in `alm-config.psd1`
3. Unpacks solutions into folder structure (including Power Apps canvas apps)
4. Detects changes compared to existing source
5. Auto-increments solution version if changes detected:
   - Minor version bump for breaking changes (components removed)
   - Revision bump for additive changes (new components only)
6. Updates the solution version in both source and environment
7. Executes `postExport` hooks (e.g., data export)
8. Commits and pushes changes to the repository

**Key Parameters**:
- `commitMessage`: Required message describing the exported changes

### 2. BUILD Pipeline

**Purpose**: Create deployable artifacts from source control.

**When to run**: Automatically triggered on any commit to any branch.

**What it does**:
1. Checks out source code and ALM4Dataverse templates
2. Installs PowerShell dependencies
3. Executes `preBuild` hooks
4. Packs each solution into both managed and unmanaged zip files
5. Copies assets defined in `alm-config.psd1`
6. Copies deployment scripts into artifacts
7. Creates a lock file pinning exact module versions
8. Executes `postBuild` hooks
9. Publishes artifacts
10. Tags the source with the build version

**Artifacts produced**:
```
artifacts/
├── solutions/
│   ├── MySolution.zip           (unmanaged)
│   └── MySolution_managed.zip   (managed)
├── data/                         (assets)
├── pipelines/scripts/           (deployment scripts)
├── alm-config.psd1
└── scriptDependencies.lock.json
```

### 3. DEPLOY Pipeline

**Purpose**: Deploy artifacts to target environments.

**When to run**: Automatically triggered when BUILD completes on main branch, or manually.

**What it does** (for each target environment):
1. Downloads build artifacts
2. Connects to the target Dataverse environment
3. Installs PowerShell dependencies (using locked versions)
4. Executes `preDeploy` hooks
5. Stages all solutions (imports to holding solution or direct)
6. Executes `dataMigrations` hooks
7. Applies solution upgrades in reverse dependency order
8. Activates workflows and flows with proper ownership
9. Publishes all customizations
10. Executes `postDeploy` hooks (e.g., data import)

**Smart Import Logic**:
- Skips import if solution version unchanged
- Uses Update if major.minor version matches (faster)
- Uses Upgrade for version changes (complete replacement)
- Handles single vs. multiple solution optimization

### 4. IMPORT Pipeline

**Purpose**: Import solutions from source control into a development environment.

**When to run**: Manually, when you need to sync source control changes to a dev environment.

**What it does**:
1. Runs a local build (unmanaged solutions)
2. Deploys unmanaged solutions to the development environment
3. Useful for:
   - Setting up a new development environment
   - Syncing changes from other developers
   - Recovering from environment issues

## Branch-Based Development

ALM4Dataverse supports branch-based development:

- **Development environments**: Named with branch suffix (e.g., `Dev-main`, `Dev-feature-x`)
- **Target environments**: Can be branch-specific or shared (e.g., `TEST-main`, `PROD`)
- **Pipelines**: Automatically use the current branch name for environment lookups

### Creating a Feature Branch

1. Create a branch from main: `git checkout -b feature-x`
2. Set up a development environment: `Dev-feature-x`
3. Create service connection: `Dev-feature-x`
4. Create variable group: `Environment-Dev-feature-x`
5. Create `DEPLOY-feature-x.yml` with appropriate stages
6. Work in isolation until ready to merge

## Version Management

Solution versions follow semantic versioning: `Major.Minor.Build.Revision`

**Automatic versioning during export**:
- **Revision increment**: When changes are additive only (new components)
- **Minor increment**: When changes include removals (potentially breaking)

**Example**:
```
1.0.0.0  →  1.0.0.1   (added new form)
1.0.0.1  →  1.1.0.0   (removed field)
```

## Error Recovery

### Failed Export
- Changes are not committed until successful
- Re-run the export after fixing issues

### Failed Build
- No artifacts are published
- Fix source issues and commit to trigger new build

### Failed Deploy
- Deployment continues from where it stopped
- Manual intervention may be needed for data issues
- Use approvals to gate risky deployments
