# Automated Setup

## Limitations

The account you use for setup must be in the same Entra ID tenant as:

- the Dataverse environments for development and deployment
- the Azure DevOps organisation.

The process works for the standard `Commercial` cloud and not `GCC` etc.

## Pre-requisites

Before you start, you need:

### 1) An Azure DevOps organisation.

If you don't have an existing AzDO organisation, follow [the instructions here](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/create-organization?view=azure-devops#create-an-organization-1) to create one.
  
### 2) An Azure DevOps project or permissions to create one.
   
You will need to be 'Project Collection Administrator' if you want the automated process to create a new project for you. Otherwise you will need a project with 'Project Administrator' role assigned to you. (Lesser privleges may work, but have not been documented/tested. Please feedback if it works for you).
  
[How to create a new project](https://learn.microsoft.com/en-us/azure/devops/organizations/projects/create-project?view=azure-devops&tabs=browser#create-a-project)

> **Project naming best practice** - 
> Don't include your phase name like "CRM System *Phase 1*" as AzDO projects should live long-term.

[How to assign the project administrator role for an existing project](https://learn.microsoft.com/en-us/azure/devops/user-guide/project-admin-tutorial?toc=%2Fazure%2Fdevops%2Forganizations%2Ftoc.json&view=azure-devops#add-members-to-the-project-administrators-group)

## Running Setup

The easiest way to run setup is:

1) Open "Windows PowerShell" from the start menu (every Windows computer has this installed)

2) Paste this in and hit enter.

   ```powershell
   iwr "https://raw.githubusercontent.com/rnwood/ALM4Dataverse/refs/heads/stable/setup.ps1" | iex
   ```

   > If you would like to review the script first (good practice) you can download the script and save it from https://raw.githubusercontent.com/rnwood/ALM4Dataverse/refs/heads/stable/setup.ps1

3) Follow the instructions.

## What Setup Does

1) Prompts you to authenticate. The account you select will be used when connecting to AzDO and Dataverse environments during setup. 
2) Ensures the required Power Platform AzDO Extension is installed in the target AzDO.
   If you have the required level of access it will be enabled automatically.
3) Prompts you to select an existing AzDO project, or create a new one.
   If you select the option to create a new one, you will be prompted for the name and process template.
4) Prompts you to select the Git repo in the AzDO project or create a new one.
5) Prompts you to select a Dataverse environment to be used as the main development environment.
6) Prompts you to select the solutions to be managed in dependency order and edits the `alm-config.psd1` file