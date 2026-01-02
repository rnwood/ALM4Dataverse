![ALM4Dataverse](logo.png)

This repo contains:
- an advanced and extendable application lifecycle management (ALM/CI-CD)
implementation for Dataverse.
- a set of process documentation and guidance on how to use and extend it.

Currently to be used with Azure DevOps, but may be extended to GitHub in future (which is straightforward due to the way it is implemented).

Features:

- Handles zero to many Dataverse solutions per repo.
- Correctly determines the install/upgrade/update method for each solution based on the state of the target environment
- Supports branches, PRs etc with minimal re-configuration
- Supports including config/system/lookup data
- Easy to extend using the extensive PowerShell ecosystem.

## Getting Started

1) [Run the automated setup process](docs/automated-setup.md) to put in place the pipelines and other configuration needed.

2) 