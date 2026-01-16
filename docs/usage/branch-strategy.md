# Branch Strategy

ALM4Dataverse supports flexible branching strategies for team development. This guide covers common approaches and how to configure them.

## Supported Branching Models

### 1. Trunk-Based Development (Recommended)

All developers work on `main` with short-lived feature branches:

```
main ─────●─────●─────●─────●─────●─────●─────▶
           \         /       \         /
            feature-a         feature-b
```

**Advantages**:
- Simple to manage
- Quick integration
- Reduced merge conflicts

**Environment Mapping**:
- `Dev-main`: Shared development
- `TEST-main`: Testing
- `PROD`: Production

### 2. Feature Branch Development

Each feature gets a dedicated branch and environment:

```
main ─────●─────────────●─────────────●─────▶
           \           /
            feature-x ●─────●─────●
                      (Dev-feature-x)
```

**Advantages**:
- Isolated development
- Independent testing
- No interference between features

### 3. GitFlow-Style

Long-running branches for different purposes:

```
main (PROD)    ─────●─────────────────●─────▶
                     \               /
develop (UAT)  ───●───●───●───●───●───●───▶
                   \     /
                    feature-a
```

## Setting Up Feature Branches

### 1. Create the Branch

In Azure DevOps:
1. Go to **Repos** > **Branches**
2. Click **New branch**
3. Enter branch name: `feature-new-workflow`
4. Base branch: `main`
5. Click **Create**

### 2. Provision Development Environment

Create a new Dataverse environment:
- Name: `Project - Dev - feature-new-workflow`
- Type: Developer or Sandbox
- Copy from: Your main dev environment (optional)

### 3. Create Service Connection

In Azure DevOps Project Settings > Service Connections:
- Name: `Dev-feature-new-workflow`
- Type: Power Platform
- Configure with app registration credentials

### 4. Create Variable Group

In Pipelines > Library:
- Name: `Environment-Dev-feature-new-workflow`
- Copy variables from `Environment-Dev-main`
- Update connection reference IDs for new environment

### 5. Create Deploy Pipeline (Optional)

If you want to deploy feature branches to test environments:

Create `pipelines/DEPLOY-feature-new-workflow.yml`:

```yaml
trigger: none

resources:
  pipelines:
    - pipeline: build
      source: 'BUILD'
      trigger:
        branches:
          include:
          - feature-new-workflow
  repositories:
    - repository: ALM4Dataverse
      type: git
      name: ALM4Dataverse

stages:
  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse
    parameters:
      environmentName: TEST-feature-new-workflow
```

### 6. Work on the Feature

Normal workflow:
1. Make changes in `Dev-feature-new-workflow`
2. Run EXPORT on `feature-new-workflow` branch
3. BUILD triggers automatically
4. DEPLOY to test environment if configured

### 7. Merge to Main

When feature is complete, create a Pull Request:

1. Go to **Repos** > **Pull requests**
2. Click **New pull request**
3. Source branch: `feature-new-workflow`
4. Target branch: `main`
5. Add title and description
6. Add reviewers
7. Click **Create**
8. After approval, complete the pull request

## Branch Naming Conventions

Consistent naming helps with automation:

| Branch Type | Pattern | Example |
|-------------|---------|---------|
| Main | `main` | `main` |
| Feature | `feature-{name}` | `feature-new-workflow` |
| Bugfix | `bugfix-{name}` | `bugfix-form-validation` |
| Release | `release-{version}` | `release-2.0` |

## Resource Naming by Branch

Resources are named dynamically based on branch:

| Resource | Pattern | Main Branch | Feature Branch |
|----------|---------|-------------|----------------|
| Dev Environment | `Dev-{branch}` | `Dev-main` | `Dev-feature-x` |
| Service Connection | `Dev-{branch}` | `Dev-main` | `Dev-feature-x` |
| Variable Group | `Environment-Dev-{branch}` | `Environment-Dev-main` | `Environment-Dev-feature-x` |

## Handling Merges

### Simple Merge (No Conflicts)

When your feature branch has no conflicts with main:

1. Create a Pull Request from `feature-x` to `main`
2. Review the changes
3. Complete the pull request to merge
4. Run EXPORT from `main` to update the dev environment if needed

### Merge with Solution Conflicts

If both branches modified the same solution components:

1. Create a Pull Request
2. Resolve file conflicts in the Azure DevOps web editor or locally
3. The merge may result in invalid solution XML
4. Import the merged source to a test environment
5. Fix any issues
6. Export clean solution back

### Best Practice: Merge Often

Merge main into your feature branch frequently to keep it up to date:

1. Go to **Repos** > **Pull requests**
2. Create a Pull Request from `main` to `feature-x`
3. Complete the merge (resolve conflicts if any)
4. This reduces the size of conflicts at final merge

## Environment Management

### Shared vs. Isolated Development

**Shared (Main)**:
- All developers use `Dev-main`
- Export/Import coordinates changes
- Simpler setup, requires communication

**Isolated (Feature Branches)**:
- Each developer/feature has own environment
- No coordination needed
- More environments to manage

### Environment Lifecycle

Feature branch environments:
1. **Create**: When starting feature work
2. **Use**: Throughout development
3. **Delete**: After merge to main (optional)

Consider automation for environment provisioning/cleanup.

## Pull Request Workflow

### Setting Up PR Validation

Configure branch policies on `main`:

1. Go to Repos > Branches
2. Click **...** on `main` > Branch policies
3. Enable **Build validation**
4. Select the BUILD pipeline

### PR Process

1. Developer creates PR from `feature-x` to `main`
2. BUILD runs automatically on the PR
3. Reviewer checks:
   - Code changes
   - Solution structure
   - Data changes
   - Build success
4. After approval, merge completes
5. DEPLOY triggers for main branch

### PR Best Practices

- Keep PRs small and focused
- Include meaningful description
- Reference related work items
- Review exported solution changes carefully

## Multiple Developers, One Branch

When multiple developers share a dev environment:

### Workflow

```
Dev-main (shared)
    │
    ├── Developer A: Make changes
    ├── Developer A: EXPORT (pipeline commits changes)
    │
    ├── Developer B: View latest in Repos > Files
    ├── Developer B: IMPORT (sync environment)
    ├── Developer B: Make changes
    └── Developer B: EXPORT (pipeline commits changes)
```

### Coordination Rules

1. Communicate before exporting
2. Run IMPORT before starting work to get latest changes
3. Export frequently (via EXPORT pipeline) to avoid large change sets
4. Don't work on same components simultaneously

## Release Branches

For long-term support of released versions:

### Creating a Release Branch

1. Go to **Repos** > **Branches**
2. Click **New branch**
3. Enter branch name: `release-1.0`
4. Base branch: `main`
5. Click **Create**

### Hotfix Process

1. Create hotfix branch from release: `hotfix-1.0.1`
2. Make fix in hotfix environment
3. Export and commit
4. Merge to release branch
5. Deploy from release branch
6. Merge fix to main (if applicable)

### Release Branch Resources

- Service connection: `PROD-release-1.0` (or reuse `PROD`)
- Deploy pipeline: `DEPLOY-release-1.0.yml`

## Tips for Success

### 1. Document Your Strategy

Write down your team's branching strategy and share it.

### 2. Automate Environment Setup

Create scripts or pipelines to provision dev environments consistently.

### 3. Clean Up Regularly

Delete old feature branches (Repos > Branches) and their associated environments.

### 4. Use Consistent Naming

Stick to naming conventions for easy identification.

### 5. Monitor Build Health

Ensure all active branches have passing builds.
