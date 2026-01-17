# Azure DevOps Organisation Requirements

Before setting up ALM4Dataverse, your Azure DevOps organisation needs to be properly configured.

## Creating an Azure DevOps Organisation

If you don't have an existing Azure DevOps organisation, follow [the instructions provided by Microsoft](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops#create-an-organization-1) to create one.

> **Organisation naming best practice**: Use a name that represents your company or division, not a specific project or phase

## Pipeline Capabilities

Your organisation will need to be configured with pipeline capabilities. You have two options:

### Option A: Free Limited Pipelines Usage

If you qualify, you can use the free tier with limited pipeline parallel jobs.

[Follow the instructions provided by Microsoft to request free limited pipeline usage](https://learn.microsoft.com/en-us/azure/devops/pipelines/get-started/what-is-azure-pipelines?view=azure-devops#azure-pipelines-pricing)

### Option B: Paid Parallel Jobs

Alternatively, you can configure your organisation with at least one paid "parallel job" for unlimited pipeline usage.

[See the Microsoft documentation for information on configuring parallel jobs](https://learn.microsoft.com/en-us/azure/devops/pipelines/licensing/concurrent-jobs?view=azure-devops&tabs=ms-hosted)
