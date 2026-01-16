# ALM4Dataverse Overview

ALM4Dataverse is an advanced and extendable Application Lifecycle Management (ALM/CI-CD) implementation for Microsoft Dataverse. It provides a comprehensive pipeline system for managing the development, build, and deployment lifecycle of Dataverse solutions.

## What is ALM for Dataverse?

Application Lifecycle Management (ALM) for Dataverse encompasses the processes and tools used to manage the lifecycle of Power Platform solutions from development through production deployment. This includes:

- **Source Control**: Storing solution definitions in Git repositories
- **Continuous Integration**: Automatically building and validating changes
- **Continuous Deployment**: Deploying solutions across environments with proper controls
- **Configuration Management**: Managing environment-specific settings

## How ALM4Dataverse Works

ALM4Dataverse provides a set of Azure DevOps pipelines and PowerShell scripts that work together to automate the ALM process:

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│ Development │──────│   Export    │──────│    Build    │──────│   Deploy    │
│ Environment │      │  Pipeline   │      │  Pipeline   │      │  Pipeline   │
└─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘
                           │                     │                     │
                           ▼                     ▼                     ▼
                      Git Commit             Artifacts           Target Envs
                                           (Managed &           (TEST, UAT,
                                           Unmanaged)             PROD)
```

### Repository Structure

ALM4Dataverse uses a two-repository model:

1. **ALM4Dataverse Repository**: Contains shared pipeline templates and scripts
2. **Your Application Repository**: Contains your solution source code, pipeline definitions, and configuration

## Key Features

### Multi-Solution Support

Handle zero to many Dataverse solutions per repository, with proper dependency ordering during deployment.

### Smart Solution Import

Automatically determines the correct import method (Install, Upgrade, or Update) based on the state of the target environment.

### Branch Support

Full support for branches and pull requests with minimal configuration changes. Each branch can have its own development environment.

### Configuration Data

Include configuration, system, and lookup data in your deployments using the assets and hooks system.

### Extensibility

Easy to extend using:
- PowerShell hook scripts at various pipeline stages
- The extensive PowerShell ecosystem
- Fork configuration for custom defaults

## Architecture Components

### Pipelines

- **BUILD**: Packs solutions and creates deployment artifacts
- **EXPORT**: Exports solutions from development environment to source control
- **IMPORT**: Imports solutions from source control to development environment
- **DEPLOY**: Deploys artifacts to target environments

### Scripts

PowerShell scripts that perform the actual work:
- `build.ps1`: Packs solutions and creates artifacts
- `export.ps1`: Exports and unpacks solutions
- `deploy.ps1`: Deploys solutions with all supporting operations
- `import.ps1`: Builds and deploys to development environment
- `common.ps1`: Shared functions
- `connect.ps1`: Establishes Dataverse connections
- `installdependencies.ps1`: Installs required PowerShell modules

### Configuration

- `alm-config.psd1`: Central configuration file defining solutions, assets, and hooks
- Environment variable groups: Store environment-specific settings
- Service connections: Authenticate to Dataverse environments

## Next Steps

- [Understanding the Pipeline Lifecycle](pipeline-lifecycle.md)
- [Solutions and Dependencies](solutions-dependencies.md)
- [Hooks and Extensibility](hooks-extensibility.md)
