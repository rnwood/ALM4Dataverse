
[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [switch]$UseDeviceAuthentication,

    [Parameter()]
    [string]$ALM4DataverseRef = 'stable'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Common Functions

function Write-Section {
    param([Parameter(Mandatory)][string]$Message)
    Clear-Host
    Write-Host "==== $Message ====" -ForegroundColor Cyan
    Write-Host ""
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Select-FromMenu {
    <#
    .SYNOPSIS
        Simple interactive console menu selection using PSMenu.

    .DESCRIPTION
        Arrow keys to move, Enter to select, Esc to cancel.

        This function wraps the PSMenu module's Show-Menu function.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Items
    )

    if ($Items.Count -eq 0) { return $null }

    # Use PSMenu's Show-Menu with title display
    Write-Host $Title -ForegroundColor Green
    Write-Host "" # Add spacing
    
    $selectedIndex = Show-Menu -MenuItems $Items -ReturnIndex
    return $selectedIndex
}

function Read-YesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter()][switch]$DefaultNo
    )

    $suffix = if ($DefaultNo) { ' [y/N]' } else { ' [Y/n]' }
    $answer = Read-Host ($Prompt + $suffix)
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return (-not $DefaultNo)
    }
    return ($answer.Trim().ToLowerInvariant() -in @('y', 'yes'))
}

function ConvertFrom-GitRefToBranchName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Ref
    )

    if ($Ref -match '^refs/heads/(.+)$') {
        return $Matches[1]
    }
    return $Ref
}

#endregion

#region Initialization

function Get-ModulePathDelimiter {
    # Use platform-agnostic delimiter for PSModulePath.
    # ';' on Windows, ':' on Unix.
    return [System.IO.Path]::PathSeparator
}

function Install-NuGetProviderIfMissing {
    # Save-Module requires a package provider (NuGet). This installs the provider if missing.
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget) {
        Write-Host "Installing NuGet package provider (required for Save-Module)..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }
}

function Get-ModuleAvailableExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RequiredVersion
    )

    # Use ListAvailable so we also see modules in our temp PSModulePath.
    $mods = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue
    if (-not $mods) { return $null }

    return $mods | Where-Object { $_.Version -eq [version]$RequiredVersion } | Select-Object -First 1
}

function Save-ModuleExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RequiredVersion,
        [Parameter(Mandatory)][string]$Destination
    )

    Install-NuGetProviderIfMissing

    Write-Host "Downloading $Name $RequiredVersion to $Destination" -ForegroundColor Yellow
    Save-Module -Name $Name -RequiredVersion $RequiredVersion -Path $Destination -Force
}

function Import-RequiredModuleVersion {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RequiredVersion,
        [Parameter(Mandatory)][string]$Destination
    )

    # Use a different variable name to avoid conflicts
    $targetVersion = $RequiredVersion

    $available = Get-ModuleAvailableExact -Name $Name -RequiredVersion $targetVersion
    if (-not $available) {
        Save-ModuleExact -Name $Name -RequiredVersion $targetVersion -Destination $Destination
        $available = Get-ModuleAvailableExact -Name $Name -RequiredVersion $targetVersion
        if (-not $available) {
            throw "Module $Name $targetVersion was downloaded but is still not discoverable on PSModulePath."
        }
    }

    # Import the exact version we found.
    Import-Module -Name $Name -RequiredVersion $targetVersion -Force -ErrorAction Stop
    $loaded = Get-Module -Name $Name | Where-Object { $_.Version -eq [version]$targetVersion } | Select-Object -First 1
    if (-not $loaded) {
        throw "Failed to import $Name version $targetVersion. Loaded version: $((Get-Module -Name $Name | Select-Object -First 1).Version)"
    }

    Write-Host "Loaded $Name $($loaded.Version)"
}

function Install-PortableGit {
    param(
        [Parameter(Mandatory)][string]$Destination
    )

    $gitDir = Join-Path $Destination "Git"
    $gitExe = Join-Path $gitDir "bin\git.exe"
    
    if (Test-Path $gitExe) {
        Write-Host "Git already available at: $gitExe"
        return $gitDir
    }

    Write-Host "Downloading portable Git..." -ForegroundColor Yellow
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.52.0.windows.1/PortableGit-2.52.0-64-bit.7z.exe"
    $gitInstaller = Join-Path $Destination "PortableGit.exe"
    
    try {
        # PowerShell 5.1 sometimes needs TLS 1.2 explicitly.
        try {
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            }
        }
        catch {
            # Non-fatal; continue.
        }

        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
        
        if (-not (Test-Path $gitInstaller)) {
            throw "Failed to download Git installer"
        }

        Write-Host "Extracting portable Git to $gitDir..." -ForegroundColor Yellow
        New-DirectoryIfMissing -Path $gitDir
        
        # The .7z.exe is a self-extracting archive
        $extractArgs = @('-o"' + $gitDir + '"', '-y')
        $process = Start-Process -FilePath $gitInstaller -ArgumentList $extractArgs -Wait -NoNewWindow -PassThru
        
        if ($process.ExitCode -ne 0) {
            throw "Git extraction failed with exit code $($process.ExitCode)"
        }

        # Clean up installer
        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue

        if (-not (Test-Path $gitExe)) {
            throw "Git extraction completed but git.exe not found at expected location"
        }

        Write-Host "Git extracted successfully to: $gitDir"
        return $gitDir
    }
    catch {
        Write-Host "Failed to install portable Git: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

Write-Section "Initialising setup"

$TempModuleRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ALM4Dataverse\\Modules"
New-DirectoryIfMissing -Path $TempModuleRoot

$delim = Get-ModulePathDelimiter
if (-not ($env:PSModulePath -split [Regex]::Escape($delim) | Where-Object { $_ -eq $TempModuleRoot })) {
    $env:PSModulePath = "$TempModuleRoot$delim$env:PSModulePath"
}

Write-Host "Using temp module root: $TempModuleRoot"

$requiredModules = @{
    'VSTeam'                           = '7.15.2'
    'PSMenu'                           = '0.2.0'
    'Rnwood.Dataverse.Data.PowerShell' = '2.14.0'
}

# Ensure modules are downloaded before loading so we can patch them
foreach ($modName in $requiredModules.Keys) {
    $version = $requiredModules[$modName]
    if (-not (Get-ModuleAvailableExact -Name $modName -RequiredVersion $version)) {
        Save-ModuleExact -Name $modName -RequiredVersion $version -Destination $TempModuleRoot
    }
}

foreach ($modName in $requiredModules.Keys) {
    $version = $requiredModules[$modName]
    Import-RequiredModuleVersion -Name $modName -RequiredVersion $version -Destination $TempModuleRoot
}

# Download and install portable Git
$gitInstallDir = Install-PortableGit -Destination $TempModuleRoot
$gitBinDir = Join-Path $gitInstallDir "bin"

# Add Git to PATH for this session
if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $gitBinDir })) {
    $env:PATH = "$gitBinDir;$env:PATH"
}

# Verify Git is now available
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    throw "Git was installed but is still not available in PATH"
}

Write-Host "Git is now available: $($git.Source)"
Write-Host "Version: $(git --version)"

#endregion

#region Authentication

function Get-AuthToken {
    param(
        [Parameter(Mandatory)][string]$ResourceUrl,
        [Parameter()][string]$TenantId,
        [Parameter()][string]$ClientId = '1950a258-227b-4e31-a9cf-717495945fc2' # Azure PowerShell Client ID
    )

    # Try to load the assembly using LoadWithPartialName as requested
    [void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.Identity.Client")

    # If the type is still not available, try to load it explicitly from the Rnwood module
    try {
        [void][Microsoft.Identity.Client.PublicClientApplicationBuilder]
    }
    catch {
        Write-Host "Type not found, attempting to load from module..." -ForegroundColor Yellow
        $module = Get-Module -Name "Rnwood.Dataverse.Data.PowerShell"
        if ($module) {
            $base = $module.ModuleBase
            $dllPath = $null
            
            if ($PSVersionTable.PSEdition -eq 'Core') {
                # PowerShell Core
                $dllPath = Join-Path $base "cmdlets\net8.0\Microsoft.Identity.Client.dll"
                if (-not (Test-Path $dllPath)) {
                    # Fallback or check for other net core versions if net8.0 isn't there
                    $dllPath = Join-Path $base "cmdlets\netcoreapp3.1\Microsoft.Identity.Client.dll"
                }
            }
            else {
                # PowerShell Desktop
                $dllPath = Join-Path $base "cmdlets\net462\Microsoft.Identity.Client.dll"
            }

            if ($dllPath -and (Test-Path $dllPath)) {
                Write-Host "Loading MSAL from: $dllPath" -ForegroundColor DarkGray
                Add-Type -Path $dllPath
            }
            else {
                Write-Host "MSAL DLL not found at expected path: $dllPath" -ForegroundColor Red
                # Fallback to recursive search
                $allDlls = Get-ChildItem $base -Recurse -Filter "Microsoft.Identity.Client.dll"
                $found = $null
                if ($PSVersionTable.PSEdition -eq 'Core') {
                    $found = $allDlls | Where-Object { $_.FullName -match 'netcore|netstandard|net\d\.\d' } | Select-Object -First 1
                }
                else {
                    $found = $allDlls | Where-Object { $_.FullName -match 'net4' } | Select-Object -First 1
                }
                
                if ($found) {
                    Write-Host "DLL found recursively at: $($found.FullName)" -ForegroundColor Yellow
                    Add-Type -Path $found.FullName
                }
            }
        }
    }

    $ResourceUrl = $ResourceUrl.TrimEnd('/')
    $scopes = [string[]]@("$ResourceUrl/.default")
    
    # Use a script-scoped variable to persist the app instance and its token cache
    # Check if variable exists in script scope
    $app = $null
    try {
        $app = Get-Variable -Name "MsalApp" -Scope Script -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Value
    }
    catch {}

    if (-not $app) {
        $builder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId)
        
        $authority = "https://login.microsoftonline.com/common"
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $authority = "https://login.microsoftonline.com/$TenantId"
        }
        
        $builder = $builder.WithAuthority($authority)
        $builder = $builder.WithRedirectUri("http://localhost")
        $app = $builder.Build()
        
        Set-Variable -Name "MsalApp" -Value $app -Scope Script
    }

    $accounts = $app.GetAccountsAsync().GetAwaiter().GetResult()
    $account = $accounts | Select-Object -First 1

    $authResult = $null

    try {
        if ($account) {
            $authResult = $app.AcquireTokenSilent($scopes, $account).ExecuteAsync().GetAwaiter().GetResult()
        }
    }
    catch {
        # Silent acquisition failed, try interactive
    }

    if (-not $authResult) {
        try {
            $authResult = $app.AcquireTokenInteractive($scopes).ExecuteAsync().GetAwaiter().GetResult()
        }
        catch {
            Write-Error "Failed to acquire token interactively: $_"
            throw
        }
    }

    return $authResult
}

Write-Section "Authenticating"

Write-Host "To enable automated setup setup, we need to authenticate with the necessary services." -ForegroundColor Green
Write-Host ""
Write-Host "When prompted, please log in with an account that has access to:" -ForegroundColor Green
Write-Host "- Your Azure DevOps organization/project (PROJECT administrator role for existing project, ORGANISATION OWNER role if you want to create a new project)" -ForegroundColor Green
Write-Host "- Your Dataverse DEV environment (SYSTEM ADMINISTRATOR role)" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to open browser for authentication..."


# Azure DevOps resource for AAD token acquisition.
$adoResourceUrl = '499b84ac-1321-427f-aa17-267ca6975798'
$adoAuthResult = Get-AuthToken -ResourceUrl $adoResourceUrl -TenantId $TenantId

if (-not $adoAuthResult -or -not $adoAuthResult.AccessToken) {
    throw "Failed to acquire an Azure DevOps access token."
}

$adoAccessToken = [pscustomobject]@{ Token = $adoAuthResult.AccessToken }
$secureToken = ConvertTo-SecureString -String $adoAccessToken.Token -AsPlainText -Force

#endregion

#region Azure DevOps Setup

function ConvertTo-AzDoOrganizationName {
    param([Parameter(Mandatory)][string]$InputText)

    $text = $InputText.Trim()

    # Accept:
    # - myorg
    # - https://dev.azure.com/myorg
    # - https://dev.azure.com/myorg/
    # - dev.azure.com/myorg
    if ($text -match 'dev\.azure\.com/([^/]+)') {
        return $Matches[1]
    }

    # Also accept legacy Visual Studio URLs like https://myorg.visualstudio.com
    if ($text -match '^https?://([^\.]+)\.visualstudio\.com/?$') {
        return $Matches[1]
    }

    return $text
}

function New-AzDoProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter()][string]$Visibility = 'private'
    )

    $ProjectName = $ProjectName.Trim()
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        throw "Project name cannot be empty."
    }

    Write-Section "Creating new Azure DevOps project"
    Write-Host "Project: $ProjectName" -ForegroundColor Cyan

    $processes = @(Get-VSTeamProcess)
    if ($processes.Count -eq 0) {
        throw "Unable to list Azure DevOps processes to create a project. Verify permissions in the organization."
    }

    # Prefer Agile if present, otherwise first.
    $defaultProcess = $processes | Where-Object { $_.name -eq 'Agile' } | Select-Object -First 1
    if (-not $defaultProcess) {
        $defaultProcess = $processes | Select-Object -First 1
    }

    $processNames = @($processes | Sort-Object -Property name | ForEach-Object { $_.name })
    $selectedProcessName = $defaultProcess.name

    # Let user choose the process template.
    $procIndex = Select-FromMenu -Title "Select a process (template) for the new project" -Items $processNames
    if ($null -ne $procIndex) {
        $selectedProcessName = $processNames[$procIndex]
    }

    $selectedProcess = $processes | Where-Object { $_.name -eq $selectedProcessName } | Select-Object -First 1
    if (-not $selectedProcess -or -not $selectedProcess.id) {
        throw "Unable to resolve selected process '$selectedProcessName'."
    }

    # Use VSTeam command to create project - it handles async operation polling automatically
    Write-Host "Creating project using process template: $selectedProcessName" -ForegroundColor Yellow
    
    try {
        # Note: Add-VSTeamProject uses -ProjectName instead of -Name and doesn't have VersionControlSource
        $addParams = @{
            ProjectName     = $ProjectName
            ProcessTemplate = $selectedProcessName
            Visibility      = $Visibility
        }
        
        
        $created = Add-VSTeamProject @addParams
        
        if ($created -and $created.name) {
            Write-Host "Project '$ProjectName' created successfully."
            return $created
        }
        else {
            throw "Project creation returned no result."
        }
    }
    catch {
        Write-Host "Failed to create project '$ProjectName': $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Test-AzDoGitRepositoryHasCommits {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RepositoryId
    )

    # Use VSTeam command to get commits - if repo is empty, no commits are returned
    try {
        $commits = @(Get-VSTeamGitCommit -ProjectName $Project -RepositoryId $RepositoryId -Top 1 -ErrorAction SilentlyContinue)
        return ($commits.Count -gt 0)
    }
    catch {
        # If we can't get commits, assume empty repo
        return $false
    }
}

function Start-AzDoGitRepositoryImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][string]$SourceGitUrl
    )

    # Use Invoke-VSTeamRequest since VSTeam doesn't support repository import directly
    $resource = "git/repositories/$RepositoryId/importRequests"
    $body = @{
        parameters = @{
            gitSource = @{
                url = $SourceGitUrl
            }
        }
    }
    return Invoke-VSTeamRequest -Method POST -Resource $resource -Body ($body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -Version '7.1-preview.1'
}

function Wait-AzDoGitRepositoryImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$RepositoryId,
        [Parameter(Mandatory)][object]$ImportResponse,
        [Parameter()][int]$TimeoutSeconds = 600
    )

    $importId = $null
    foreach ($prop in @('importRequestId', 'id', 'ImportRequestId')) {
        if ($ImportResponse.PSObject.Properties.Name -contains $prop) {
            $importId = $ImportResponse.$prop
            if ($importId) { break }
        }
    }

    if (-not $importId) {
        throw "Unable to determine import request ID from response."
    }

    # Use Invoke-VSTeamRequest since VSTeam doesn't support repository import status directly
    $resource = "git/repositories/$RepositoryId/importRequests/$importId"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        
        $status = Invoke-VSTeamRequest -Method GET -Resource $resource -Version '7.1-preview.1'

        if (-not $status) { continue }

        $state = $null
        foreach ($prop in @('status', 'state')) {
            if ($status.PSObject.Properties.Name -contains $prop) {
                $state = $status.$prop
                if ($state) { break }
            }
        }

        if ($state) {
            Write-Host "Import status: $state" -ForegroundColor DarkGray
        }

        if ($state -in @('completed', 'succeeded', 'success')) {
            return $status
        }
        if ($state -in @('failed', 'rejected', 'canceled', 'cancelled')) {
            $details = $status | ConvertTo-Json -Depth 20
            throw "Repository import did not succeed. Status: $state. Details: $details"
        }
    }

    throw "Timed out waiting for repository import to complete after $TimeoutSeconds seconds."
}

Write-Section "Select Azure DevOps organization"

# Use direct REST API to get organizations (VSTeam requires an org to connect to first)
try {
    $headers = @{
        Authorization = "Bearer $($adoAccessToken.Token)"
    }

    # Get current user profile to obtain member ID
    $profileUrl = "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=6.0"
    $profileResponse = Invoke-RestMethod -Uri $profileUrl -Method Get -Headers $headers
    
    $memberId = $profileResponse.publicAlias
    if (-not $memberId) {
        $memberId = $profileResponse.id
    }
    if (-not $memberId) {
        throw "Unable to determine memberId from profile response."
    }

    Write-Host "Fetching organizations for memberId: $memberId" -ForegroundColor DarkGray
    
    $accountsUrl = "https://app.vssps.visualstudio.com/_apis/accounts?memberId=$memberId&api-version=6.0"
    $accountsResponse = Invoke-RestMethod -Uri $accountsUrl -Method Get -Headers $headers
    
    $orgs = @($accountsResponse.value)
    
    if ($orgs.Count -eq 0) {
        throw "No Azure DevOps organizations were returned for this user."
    }

    $orgs | ConvertTo-Json -Depth 100 | Write-Host -ForegroundColor DarkGray

    $orgsSorted = $orgs | Sort-Object -Property accountName
    $orgNames = @($orgsSorted | ForEach-Object { $_.accountName })
}
catch {
    Write-Host "Failed to discover organizations: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

$orgIndex = 0
if ($orgNames.Count -gt 1) {
    $orgIndex = Select-FromMenu -Title "Select an Azure DevOps organization" -Items $orgNames
    if ($null -eq $orgIndex) {
        Write-Host "No organization selected." -ForegroundColor Yellow
        return
    }
}

$orgName = $orgNames[$orgIndex]
$orgUri = $orgsSorted[$orgIndex].accountUri
Write-Host "Selected organization: $orgName"
if ($orgUri) {
    Write-Host "Organization URI: $orgUri" -ForegroundColor DarkGray
}

# VSTeam expects -Account to be the org name (not the full URL).
Set-VSTeamAccount -Account $orgName -SecurePersonalAccessToken $secureToken -UseBearerToken -Force
Write-Host "VSTeam configured for organization '$orgName' using a bearer token."

Write-Section "Ensuring Needed Extensions are Enabled"

$requiredExtension = "microsoft-IsvExpTools.PowerPlatform-BuildTools"
try {
    # Check if the extension is already installed
    $installedExtensions = Get-VSTeamExtension
    $ppBuildTools = $installedExtensions | Where-Object { $_.publisherId -eq "microsoft-IsvExpTools" -and $_.extensionId -eq "PowerPlatform-BuildTools" }
    
    if ($ppBuildTools) {
        Write-Host "Power Platform Build Tools extension is already installed (Version: $($ppBuildTools.version))."
    }
    else {
        if (-not (Read-YesNo -Prompt "Power Platform Build Tools extension not found. Install it?")) {
            throw "Power Platform Build Tools extension is required. Setup cannot continue without it."
        }
        Write-Host "Power Platform Build Tools extension not found. Installing..." -ForegroundColor Yellow
        
        # Install the extension
        Install-VSTeamExtension -PublisherId "microsoft-IsvExpTools" -ExtensionId "PowerPlatform-BuildTools"
        
        # Verify installation
        $installedExtensions = Get-VSTeamExtension
        $ppBuildTools = $installedExtensions | Where-Object { $_.publisherId -eq "microsoft-IsvExpTools" -and $_.extensionId -eq "PowerPlatform-BuildTools" }
        
        if ($ppBuildTools) {
            Write-Host "Power Platform Build Tools extension installed successfully (Version: $($ppBuildTools.version))."
        }
        else {
            throw "Failed to verify Power Platform Build Tools extension installation after install command completed."
        }
    }
}
catch {
    Write-Host "Error installing Power Platform Build Tools extension: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "This may be due to insufficient permissions to manage extensions in the organization." -ForegroundColor Yellow
    Write-Host "Please ensure you have AzDO organization administrative rights or ask your admin to install the extension manually from the Azure DevOps marketplace:" -ForegroundColor Yellow
    Write-Host "https://marketplace.visualstudio.com/acquisition?itemName=microsoft-IsvExpTools.PowerPlatform-BuildTools"
    throw
}

Write-Section "Select target Azure DevOps Project"

# We'll use the Azure DevOps access token that was already obtained via Get-AzAccessToken

$azDevOpsAccessToken = $adoAccessToken.Token

$projects = Get-VSTeamProject
$projectNames = @()
if ($projects) {
    $projectNames = @($projects | ForEach-Object { $_.Name })
}

$menuItems = $projectNames + @('Create a new project')
$index = Select-FromMenu -Title "Select the target Azure DevOps project" -Items $menuItems

if ($null -eq $index) {
    Write-Host "No project selected." -ForegroundColor Yellow
    return
}

if ($index -eq ($menuItems.Count - 1)) {
    # Create new project

    $name = Read-Host 'Enter the name for the new Azure DevOps project'    

    $created = New-AzDoProject -Organization $orgName -ProjectName $name -Visibility private

    # Refresh VSTeam project list
    $projects = Get-VSTeamProject
    $selectedProject = $null

    if ($projects) {
        $selectedProject = $projects | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    }
    if (-not $selectedProject -and $created -and $created.name) {
        # As a fallback, adapt REST project shape.
        $selectedProject = [pscustomobject]@{ Name = $created.name; Id = $created.id }
    }
    if (-not $selectedProject) {
        throw "Project creation completed, but the project could not be resolved for selection."
    }

    Write-Host "Created and selected project: $($selectedProject.Name)"
}
else {
    $selectedProject = $projects[$index]
    Write-Host "Selected project: $($selectedProject.Name)"
}

# Optional: set default project for subsequent VSTeam calls in this session.
if (Get-Command -Name Set-VSTeamDefaultProject -ErrorAction SilentlyContinue) {
    Set-VSTeamDefaultProject -Project $selectedProject.Name | Out-Null
    Write-Host "Default VSTeam project set to '$($selectedProject.Name)'."
}

Write-Section "Ensuring Shared Git repository"

$sharedRepoName = "ALM4Dataverse"
$existingRepos = Get-VSTeamGitRepository -ProjectName $selectedProject.Name
$repo = $existingRepos | Where-Object { $_.Name -eq $sharedRepoName } | Select-Object -First 1

if (-not $repo) {
    Write-Host "Creating Git repository '$sharedRepoName' in project '$($selectedProject.Name)'..." -ForegroundColor Yellow
    $repo = Add-VSTeamGitRepository -ProjectName $selectedProject.Name -Name $sharedRepoName
    if ($repo) {
        Write-Host "Git repository '$sharedRepoName' created successfully."
    }
    else {
        Write-Host "Failed to create Git repository '$sharedRepoName'." -ForegroundColor Red
    }
}
else {
    Write-Host "Git repository '$sharedRepoName' already exists."
}

if (-not $repo -or -not $repo.Id) {
    throw "Shared repository '$sharedRepoName' could not be created or resolved."
}

# Ensure the script is running interactively
try {
    [void]$Host.UI.RawUI
}
catch {
    throw "This script must be run in an interactive PowerShell session."
}

Write-Section "Creating/updating shared repository '$sharedRepoName'"

$hasCommits = Test-AzDoGitRepositoryHasCommits -Organization $orgName -Project $selectedProject.Name -RepositoryId $repo.Id
if (-not $hasCommits) {
    Write-Host "Repository '$sharedRepoName' has no commits. Seeding it from the upstream repo..." -ForegroundColor Yellow

    $sharedSourceUrl = 'https://github.com/rnwood/ALM4Dataverse.git'
    try {
        $import = Start-AzDoGitRepositoryImport -Organization $orgName -Project $selectedProject.Name -RepositoryId $repo.Id -SourceGitUrl $sharedSourceUrl
        [void](Wait-AzDoGitRepositoryImport -Organization $orgName -Project $selectedProject.Name -RepositoryId $repo.Id -ImportResponse $import -TimeoutSeconds 600)

        Write-Host "shared import completed."
    }
    catch {
        Write-Host "Repository import attempt failed." -ForegroundColor Red
        Write-Host "If Azure DevOps reports it needs a service connection, create a Git service connection with access to the source repo and retry." -ForegroundColor Yellow
        throw
    }
}

# Check if we can fast-forward from the shared repo
$sharedSourceUrl = 'https://github.com/rnwood/ALM4Dataverse.git'
$destUrl = $repo.remoteUrl
if (-not $destUrl) {
    throw "Could not determine remoteUrl for repository '$sharedRepoName'."
}

$branch = 'main'
if ($repo.defaultBranch) {
    $branch = ConvertFrom-GitRefToBranchName -Ref $repo.defaultBranch
}

# Create a temp folder for checking history
$workRoot = Join-Path $env:TEMP ("ALM4Dataverse-Check-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

try {
    Write-Host "Checking shared repository status against shared repo..." -ForegroundColor DarkGray
    
    # Clone the current shared repo
    & git -c "http.extraheader=AUTHORIZATION: bearer $azDevOpsAccessToken" clone $destUrl $workRoot | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Git clone failed with exit code $LASTEXITCODE"
    }

    Push-Location $workRoot
    
    # Add upstream remote
    & git remote add upstream $sharedSourceUrl | Out-Null
    & git fetch upstream --tags | Out-Null
    
    # Check relationship between HEAD and upstream ref
    $targetRef = "upstream/$ALM4DataverseRef"
    & git rev-parse --verify --quiet $targetRef | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $targetRef = $ALM4DataverseRef
        & git rev-parse --verify --quiet $targetRef | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not resolve reference '$ALM4DataverseRef' from upstream repository."
        }
    }
    $upstreamRef = $targetRef
    
    # Check if they are exactly the same
    $localHash = (& git rev-parse HEAD).Trim()
    $upstreamHash = (& git rev-parse $upstreamRef).Trim()
        
    if ($localHash -eq $upstreamHash) {
        Write-Host "Shared repository is already up to date."
    }
    else {
        # Check if fast-forward is possible (HEAD is ancestor of upstream)
        & git merge-base --is-ancestor HEAD $upstreamRef
        $canFastForward = ($LASTEXITCODE -eq 0)
            
        if ($canFastForward) {
            if (Read-YesNo -Prompt "Updates are available from the shared repo (fast-forward). Update '$sharedRepoName'?" ) {
                Write-Host "Fast-forwarding..." -ForegroundColor Yellow
                & git merge --ff-only $upstreamRef
                if ($LASTEXITCODE -ne 0) { throw "Git merge failed" }
                    
                & git -c "http.extraheader=AUTHORIZATION: bearer $azDevOpsAccessToken" push origin $branch
                if ($LASTEXITCODE -ne 0) { throw "Git push failed" }
                    
                Write-Host "Repository updated successfully."
            }
        }
        else {
            # Check if local is ahead (upstream is ancestor of HEAD)
            & git merge-base --is-ancestor $upstreamRef HEAD
            $isAhead = ($LASTEXITCODE -eq 0)
                
            if ($isAhead) {
                Write-Host "Shared repository is ahead of the shared repo."
            }
            else {
                # Diverged
                if (Read-YesNo -Prompt "The shared repo '$sharedRepoName' has diverged from the shared repo with local changes. Attempt rebase to update?") {
                    Write-Host "Rebasing..." -ForegroundColor Yellow
                    & git rebase $upstreamRef
                    if ($LASTEXITCODE -ne 0) { throw "Git rebase failed - this script can't handle conflicts. You need to rebase your local changes manually." }
                        
                    Write-Host "Pushing rebased branch (force-with-lease)..." -ForegroundColor Yellow
                    & git -c "http.extraheader=AUTHORIZATION: bearer $azDevOpsAccessToken" push --force-with-lease origin $branch
                    if ($LASTEXITCODE -ne 0) { throw "Git push failed" }
                        
                    Write-Host "Repository updated successfully."
                }
            }
        }
    }
}
catch {
    Write-Host "Failed to check or update repository: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if ((Get-Location).Path -eq $workRoot) { Pop-Location }
    try { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

#endregion

#region Pipeline Setup

function Select-AzDoMainRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$SharedRepositoryName
    )

    Write-Section "Selecting main Git repository"

    $repos = @(Get-VSTeamGitRepository -ProjectName $ProjectName)
    # 'Main' repo is the user's application repo (not the shared ALM4Dataverse repo)
    $reposSorted = @($repos | Sort-Object -Property Name)

    $repoNames = @($reposSorted | ForEach-Object { $_.Name })
    $repoNames = @($repoNames | Where-Object { $_ -ne $SharedRepositoryName })
    $menu = @($repoNames + @('Create a new repository'))

    Write-Host "Select the repository where you want to set up pipelines:" -ForegroundColor Green

    $selectedIndex = Select-FromMenu -Title "Select the repo" -Items $menu
    if ($null -eq $selectedIndex) {
        throw "No main repository selected."
    }

    if ($selectedIndex -eq ($menu.Count - 1)) {
        $newRepoName = Read-Host "Enter the name for the new main repository"
        $newRepoName = $newRepoName.Trim()
        if ([string]::IsNullOrWhiteSpace($newRepoName)) {
            throw "Repository name cannot be empty."
        }

        Write-Host "Creating Git repository '$newRepoName' in project '$ProjectName'..." -ForegroundColor Yellow
        $created = Add-VSTeamGitRepository -ProjectName $ProjectName -Name $newRepoName
        if (-not $created -or -not $created.Id) {
            throw "Failed to create Git repository '$newRepoName'."
        }
        Write-Host "Created repository '$newRepoName'."
        return $created
    }

    $selectedName = $menu[$selectedIndex]
    $selected = $reposSorted | Where-Object { $_.Name -eq $selectedName } | Select-Object -First 1
    if (-not $selected -or -not $selected.Id) {
        throw "Failed to resolve selected repository '$selectedName'."
    }

    Write-Host "Selected main repository: $($selected.Name)"
    return $selected
}

function Sync-CopyToYourRepoIntoGitRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][object]$TargetRepo,
        [Parameter(Mandatory)][string]$PreferredBranch
    )

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw "Source folder not found: $SourceRoot"
    }

    if (-not $TargetRepo.remoteUrl) {
        throw "Could not determine remoteUrl for repository '$($TargetRepo.Name)'."
    }

    $cloneRoot = Join-Path $env:TEMP ("ALM4Dataverse-MainRepo-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $cloneRoot -Force | Out-Null

    Write-Host "Cloning '$($TargetRepo.Name)' to a temp folder..." -ForegroundColor Yellow
    try {
        & git -c "http.extraheader=AUTHORIZATION: bearer $azDevOpsAccessToken" clone $TargetRepo.remoteUrl $cloneRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone exited with code $LASTEXITCODE"
        }
    }
    catch {
        throw "Git clone failed for '$($TargetRepo.remoteUrl)': $($_.Exception.Message)"
    }

    Push-Location $cloneRoot
    try {
        $branch = $PreferredBranch

        # If the repo already has a defaultBranch, prefer it.
        if ($TargetRepo.defaultBranch) {
            $branch = ConvertFrom-GitRefToBranchName -Ref $TargetRepo.defaultBranch
        }
        if ([string]::IsNullOrWhiteSpace($branch)) {
            $branch = 'main'
        }

        # Check if repository has any commits (empty repos may not have HEAD)
        $hasCommits = $false
        try {
            & git rev-parse HEAD 2>$null
            $hasCommits = ($LASTEXITCODE -eq 0)
        }
        catch {
            $hasCommits = $false
        }

        if ($hasCommits) {
            & git -c "http.extraheader=AUTHORIZATION: bearer $azDevOpsAccessToken" fetch origin
            if ($LASTEXITCODE -ne 0) {
                throw "Git fetch failed with exit code $LASTEXITCODE"
            }
            
            # Check if branch exists
            & git show-ref --verify --quiet "refs/heads/$branch"
            if ($LASTEXITCODE -eq 0) {
                # Branch exists, check it out
                & git checkout $branch
                if ($LASTEXITCODE -ne 0) {
                    throw "Git checkout failed with exit code $LASTEXITCODE"
                }
            }
            else {
                # Branch doesn't exist locally, create it
                & git checkout -b $branch
                if ($LASTEXITCODE -ne 0) {
                    throw "Git checkout -b failed with exit code $LASTEXITCODE"
                }
            }
        }
        else {
            # Empty repo - create and checkout branch
            & git checkout -b $branch
            if ($LASTEXITCODE -ne 0) {
                throw "Git checkout -b failed with exit code $LASTEXITCODE"
            }
        }

 
        Write-Section "Syncing pipeline files into main repository"
        Write-Host "Source: $SourceRoot" -ForegroundColor DarkGray
        Write-Host "Target: $cloneRoot" -ForegroundColor DarkGray

        # Copy-Item with '*' won't include hidden items; use Get-ChildItem -Force instead.
        $top = Get-ChildItem -LiteralPath $SourceRoot -Force
        foreach ($item in $top) {
            Copy-Item -LiteralPath $item.FullName -Destination $cloneRoot -Recurse -Force -ErrorAction Stop
        }
      
        

        # Check for changes
        & git add -A
        if ($LASTEXITCODE -ne 0) {
            throw "Git add failed with exit code $LASTEXITCODE"
        }
        
        # Check if there are changes to commit
        & git diff --cached --quiet
        $hasChanges = ($LASTEXITCODE -ne 0)
        
        if ($hasChanges) {
            Write-Host "Committing changes..." -ForegroundColor Yellow
            
            # Configure git user if not already configured
            & git config user.name "ALM4Dataverse Setup" 2>$null
            & git config user.email "setup@alm4dataverse.local" 2>$null
            
            & git commit -m "Add ALM4Dataverse pipelines"
            if ($LASTEXITCODE -ne 0) {
                throw "Git commit failed with exit code $LASTEXITCODE"
            }

            Write-Host "Pushing to origin/$branch..." -ForegroundColor Yellow
            & git -c "http.extraheader=AUTHORIZATION: bearer $azDevOpsAccessToken" push origin $branch
            if ($LASTEXITCODE -ne 0) {
                throw "Git push failed with exit code $LASTEXITCODE. Ensure you have permission and that authentication succeeds."
            }
            Write-Host "Main repo updated successfully."
        }
        else {
            Write-Host "No changes to commit; main repo already contains the required files."
        }
    }
    finally {
        Pop-Location
        try { Remove-Item -LiteralPath $cloneRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

function Get-AzDoDefaultAgentQueueId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project
    )

    $queues = @(Get-VSTeamQueue -ProjectName $Project)
    if ($queues.Count -eq 0) {
        throw "No agent queues found in project '$Project'."
    }

    $preferred = $queues | Where-Object { $_.name -eq 'Azure Pipelines' } | Select-Object -First 1
    if (-not $preferred) {
        $preferred = $queues | Where-Object { $_.name -eq 'Default' } | Select-Object -First 1
    }
    if (-not $preferred) {
        $preferred = $queues | Select-Object -First 1
    }

    if (-not $preferred -or -not $preferred.id) {
        throw "Unable to resolve an agent queue id."
    }

    return [int]$preferred.id
}

function Get-AzDoSecurityNamespaceByName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Name
    )

    # Use VSTeam command to get security namespace by name
    $allNamespaces = Get-VSTeamSecurityNamespace
    $ns = $allNamespaces | Where-Object { $_.Name -eq $Name -or $_.DisplayName -eq $Name } | Select-Object -First 1
    if (-not $ns -or -not $ns.Id) {
        throw "Unable to resolve security namespace '$Name'."
    }
    return $ns
}

function Get-AzDoSecurityNamespaceActionBit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Namespace,
        [Parameter(Mandatory)][string]$ActionName
    )

    $actions = @()
    if ($Namespace -and $Namespace.actions) {
        $actions = @($Namespace.actions)
    }

    $action = $actions | Where-Object {
        ($_.name -eq $ActionName) -or ($_.displayName -eq $ActionName)
    } | Select-Object -First 1

    if (-not $action -or -not ($action.PSObject.Properties.Name -contains 'bit')) {
        throw "Unable to resolve action '$ActionName' in security namespace '$($Namespace.name)'."
    }

    return [long]$action.bit
}

function Get-AzDoBuildServiceIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter()][string]$ProjectName
    )

    # Use VSTeam command to search for Build Service identity
    $serviceIdentities = @(Get-VSTeamUser -SubjectTypes svc)
    
    $buildServicePattern = "Build:$ProjectId"
    $buildIdentity = $null
    
    foreach ($identity in $serviceIdentities) {
        if ($identity.descriptor -and $identity.descriptor.StartsWith('svc.')) {
            try {
                # Remove "svc." prefix and base64 decode
                $encodedPart = $identity.descriptor.Substring(4)
                
                # Add padding if needed for proper base64 decoding
                $padding = (4 - ($encodedPart.Length % 4)) % 4
                if ($padding -gt 0) {
                    $encodedPart += '=' * $padding
                }
                
                $decodedBytes = [Convert]::FromBase64String($encodedPart)
                $decodedString = [Text.Encoding]::UTF8.GetString($decodedBytes)
                
                # Check if decoded string ends with "Build:$ProjectId"
                if ($decodedString.EndsWith($buildServicePattern)) {
                    $buildIdentity = $identity
                    $correctDescriptor = "Microsoft.TeamFoundation.ServiceIdentity;$decodedString"
                    break
                }
            }
            catch {
                # Skip if base64 decode fails
                continue
            }
        }
    }

    if (-not $buildIdentity) {
        throw "Unable to find Build Service identity with descriptor ending 'Build:$ProjectId' for project '$ProjectName'."
    }

    if (-not $correctDescriptor) {
        throw "Build Service identity found but correct descriptor could not be constructed."
    }

    Write-Host "Found Build Service identity: $($buildIdentity.displayName)"
    return $correctDescriptor
}

function Get-AzDoAccessControlEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$NamespaceId,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Descriptor
    )

    try {
        # Use VSTeam command to get access control list
        $acls = Get-VSTeamAccessControlList -SecurityNamespaceId $NamespaceId -Token $Token -Descriptors $Descriptor
        
        if (-not $acls -or $acls.Count -eq 0) {
            return $null
        }

        $acl = $acls | Select-Object -First 1
        if (-not $acl -or -not $acl.acesDictionary) {
            return $null
        }

        # Extract the ACE for the requested descriptor
        $ace = $null
        try {
            if ($acl.acesDictionary.PSObject.Properties.Name -contains $Descriptor) {
                $ace = $acl.acesDictionary.$Descriptor
            }
            elseif ($acl.acesDictionary.ContainsKey -and $acl.acesDictionary.ContainsKey($Descriptor)) {
                $ace = $acl.acesDictionary[$Descriptor]
            }
        }
        catch {
            $ace = $null
        }

        return $ace
    }
    catch {
        # If VSTeam command fails, return null (ACE doesn't exist)
        return $null
    }
}

function Set-AzDoAccessControlEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$NamespaceId,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Descriptor,
        [Parameter(Mandatory)][long]$Allow,
        [Parameter(Mandatory)][long]$Deny
    )

    # Use VSTeam command to set access control entry
    # Note: Add-VSTeamAccessControlEntry requires a SecurityNamespace object, so we need to get it first
    $ns = Get-VSTeamSecurityNamespace -Id $NamespaceId
    Add-VSTeamAccessControlEntry -SecurityNamespace $ns -Token $Token -Descriptor $Descriptor -AllowMask $Allow -DenyMask $Deny -OverwriteMask
}

function Ensure-AzDoBuildServiceHasContributeOnRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$RepositoryId
    )

    # Find the Build Service identity by searching identities
    $descriptor = Get-AzDoBuildServiceIdentity -Organization $Organization -ProjectId $ProjectId -ProjectName $ProjectName
    $descriptor = $descriptor.Trim()  # Clean any whitespace
    Write-Host "Found Build Service descriptor: $descriptor" -ForegroundColor DarkGray

    $ns = Get-AzDoSecurityNamespaceByName -Organization $Organization -Name 'Git Repositories'
    $contributeBit = Get-AzDoSecurityNamespaceActionBit -Namespace $ns -ActionName 'Contribute'

    # Repo token format for Git Repositories namespace:
    #   repoV2/<projectId>/<repoId>
    $token = "repoV2/$ProjectId/$RepositoryId"

    $existing = Get-AzDoAccessControlEntry -Organization $Organization -NamespaceId $ns.Id -Token $token -Descriptor $descriptor
    $existingAllow = 0L
    $existingDeny = 0L

    if ($existing) {
        if ($existing.PSObject.Properties.Name -contains 'allow') { $existingAllow = [long]$existing.allow }
        if ($existing.PSObject.Properties.Name -contains 'deny') { $existingDeny = [long]$existing.deny }
    }

    $alreadyAllowed = (($existingAllow -band $contributeBit) -ne 0)
    $isDenied = (($existingDeny -band $contributeBit) -ne 0)

    if ($alreadyAllowed -and -not $isDenied) {
        Write-Host "Build Service already has 'Contribute' on repo."
        return
    }

    $desiredAllow = ($existingAllow -bor $contributeBit)
    $desiredDeny = ($existingDeny -band (-bnot $contributeBit))

    Write-Host "Granting Build Service 'Contribute' on repo..." -ForegroundColor Yellow
    Set-AzDoAccessControlEntry -Organization $Organization -NamespaceId $ns.Id -Token $token -Descriptor $descriptor -Allow $desiredAllow -Deny $desiredDeny | out-null
    Write-Host "Granted 'Contribute' to Build Service on repository."
}

function Ensure-AzDoYamlPipelineDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][object]$Repository,
        [Parameter(Mandatory)][string]$DefinitionName,
        [Parameter(Mandatory)][string]$YamlPath,
        [Parameter(Mandatory)][int]$QueueId,
        [Parameter()][string]$FolderPath = '\\'
    )

    $YamlPath = $YamlPath.TrimStart('/')

    $existing = @(Get-VSTeamBuildDefinition -ProjectName $Project) | Where-Object { $_.name -eq $DefinitionName }
    $def = $existing | Select-Object -First 1

    if (-not $def) {
        Write-Host "Creating pipeline '$DefinitionName' (YAML: $YamlPath)..." -ForegroundColor Yellow

        $repoBranch = 'refs/heads/main'
        if ($Repository.defaultBranch) {
            $repoBranch = $Repository.defaultBranch
        }

        # Use Invoke-VSTeamRequest since VSTeam build definition commands require JSON files
        $body = @{
            name       = $DefinitionName
            path       = $FolderPath
            type       = 'build'
            queue      = @{ id = $QueueId }
            repository = @{
                id            = $Repository.Id
                name          = $Repository.Name
                type          = 'TfsGit'
                defaultBranch = $repoBranch
            }
            process    = @{
                type         = 2
                yamlFilename = $YamlPath
            }
        }

        $resource = "build/definitions"
        [void](Invoke-VSTeamRequest -Method POST -Resource $resource -Body ($body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -Version '7.1')
        Write-Host "Created pipeline '$DefinitionName'."
        return
    }

    # Ensure existing points at expected YAML + repo
    $full = Get-VSTeamBuildDefinition -ProjectName $Project -Id $def.id

    $needsUpdate = $false
    if (-not $full.process -or -not $full.process.type -or [int]$full.process.type -ne 2) {
        $needsUpdate = $true
    }
    elseif ($full.process.PSObject.Properties.Name -contains 'yamlFilename') {
        if ($full.process.yamlFilename -ne $YamlPath) { $needsUpdate = $true }
    }
    else {
        # If yamlFilename isn't present, treat as needs update.
        $needsUpdate = $true
    }

    if ($full.repository -and $full.repository.id -and ($full.repository.id -ne $Repository.Id)) {
        $needsUpdate = $true
    }

    if (-not $needsUpdate) {
        Write-Host "Pipeline '$DefinitionName' already exists and points at '$YamlPath'."
        return
    }

    Write-Host "Updating pipeline '$DefinitionName' to point at '$YamlPath'..." -ForegroundColor Yellow

    $def.repository.name = $Repository.Name
    $def.repository.id = $Repository.Id
    if ($Repository.defaultBranch) {
        $def.repository.defaultBranch = $Repository.defaultBranch
    }
    $def.process.yamlFilename = $YamlPath

    # Use Invoke-VSTeamRequest since VSTeam update commands require JSON files
    $resource = "build/definitions/$($def.id)"
    [void](Invoke-VSTeamRequest -Method PUT -Resource $resource -Body ($def | ConvertTo-Json -Depth 50) -ContentType 'application/json' -Version '7.1')
    Write-Host "Updated pipeline '$DefinitionName'."
}

function Ensure-AzDoPipelinesForMainRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][object]$Repository,
        [Parameter(Mandatory)][string[]]$YamlFiles,
        [Parameter()][string]$FolderPath = '\\'
    )

    Write-Section "Ensuring Azure DevOps pipeline definitions exist"

    $queueId = Get-AzDoDefaultAgentQueueId -Organization $Organization -Project $Project
    Write-Host "Using agent queue id: $queueId" -ForegroundColor DarkGray

    foreach ($yaml in $YamlFiles) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($yaml)
        Ensure-AzDoYamlPipelineDefinition -Organization $Organization -Project $Project -Repository $Repository -DefinitionName $name -YamlPath $yaml -QueueId $queueId -FolderPath $FolderPath
    }
}

function Ensure-AzDoDeploymentApproversTeam {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][string]$EnvironmentName
    )

    $teamName = "$EnvironmentName deployment approvers"
    Write-Host "Ensuring team '$teamName' exists..." -ForegroundColor DarkGray

    $team = Get-VSTeam -ProjectName $ProjectName -Name $teamName -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if (-not $team) {
        Write-Host "Creating team '$teamName'..." -ForegroundColor Yellow
        Add-VSTeam -ProjectName $ProjectName -Name $teamName -Description "Approvers for $EnvironmentName deployment" | Out-Null
        $team = Get-VSTeam -ProjectName $ProjectName -Name $teamName | Select-Object -First 1
    }
       
    # Add current user to the team
    
    $me = Invoke-VSTeamRequest -NoProject -Method GET -Url "https://app.vssps.visualstudio.com/_apis/profile/profiles/me" -Version "7.1"
    Write-Host "Adding current user ($($me.emailAddress)) to team '$teamName'..." -ForegroundColor Yellow
    
    $user = Get-VSTeamUser | Where-Object { $_.UniqueName -eq $me.emailAddress } | Select-Object -First 1
    $group = Get-VSTeamGroup -ProjectName $ProjectName | Where-Object { $_.DisplayName -eq $teamName } | Select-Object -First 1

    if ($user -and $group) {
        Add-VSTeamMembership -MemberDescriptor $user.Descriptor -ContainerDescriptor $group.Descriptor | Out-Null
    }
    else {
        Write-Warning "Could not resolve user or group to add membership."
    }

    
    return $team
}

function Ensure-AzDoVariableGroupApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$VariableGroupId,
        [Parameter(Mandatory)][string]$VariableGroupName,
        [Parameter(Mandatory)][object]$ApproverTeam
    )

    Write-Host "Ensuring Approval check on variable group '$VariableGroupName'..." -ForegroundColor DarkGray

    # Check for existing checks
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/pipelines/checks/configurations?resourceType=variablegroup&resourceId=$VariableGroupId&api-version=7.1-preview.1"
    $headers = @{ Authorization = "Bearer $($adoAccessToken.Token)" }
    
    $existingChecks = $null

    $existingChecks = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers

    
    $hasApproval = $false
    if ($existingChecks -and $existingChecks.count -gt 0) {
        foreach ($check in $existingChecks.value) {
            if ($check.resource.type -eq 'variablegroup' -and [string]$check.resource.id -eq [string]$VariableGroupId -and $check.type -and $check.type.name -eq 'Approval') {
                $hasApproval = $true
                break
            }
        }
    }

    if ($hasApproval) {
        Write-Host "Approval check already exists on variable group '$VariableGroupName'."
        return
    }

    Write-Host "Adding Approval check to variable group '$VariableGroupName'..." -ForegroundColor Yellow

    # We need the descriptor for the team. Get-VSTeamTeam doesn't return it directly.
    # We can find the group identity using Get-VSTeamGroup.
    $teamIdentity = Get-VSTeamGroup -ProjectName $Project | Where-Object { $_.principalName -eq $ApproverTeam.name -or $_.displayName -eq $ApproverTeam.name } | Select-Object -First 1
    
    if (-not $teamIdentity) {
        Write-Warning "Could not resolve identity for team '$($ApproverTeam.name)'. Skipping approval check creation."
        return
    }

    $body = @{
        type = @{
            id = "8C6F20A7-A545-4486-9777-F762FAFE0D4D"
            name = "Approval"
        }
        settings = @{
            approvers = @(
                @{
                    id = $teamIdentity.originId
                    descriptor = $teamIdentity.descriptor
                    displayName = $teamIdentity.displayName
                }
            )
            executionOrder = 1
            minRequiredApprovers = 0
            requesterCannotBeApprover = $false
        }
        resource = @{
            type = "variablegroup"
            id = [string]$VariableGroupId
            name = $VariableGroupName
        }
        timeout = 43200
    }

    $resource = "pipelines/checks/configurations"
    [void](Invoke-VSTeamRequest -Method POST -Resource $resource -Body ($body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -Version '7.1-preview.1')
    Write-Host "Approval check added."
}

function Ensure-AzDoVariableGroupExclusiveLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$VariableGroupId,
        [Parameter(Mandatory)][string]$VariableGroupName
    )

    Write-Host "Ensuring ExclusiveLock check on variable group '$VariableGroupName'..." -ForegroundColor DarkGray

    # Check for existing checks
    $uri = "https://dev.azure.com/$Organization/$Project/_apis/pipelines/checks/configurations?resourceType=variablegroup&resourceId=$VariableGroupId&api-version=7.1-preview.1"
    $headers = @{ Authorization = "Bearer $($adoAccessToken.Token)" }
    
    $existingChecks = $null
    try {
        $existingChecks = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers
    } catch {
        Write-Warning "Failed to list existing checks: $_"
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            Write-Warning "Response Body: $($reader.ReadToEnd())"
        }
    }
    
    $hasExclusiveLock = $false
    if ($existingChecks -and $existingChecks.count -gt 0) {
        foreach ($check in $existingChecks.value) {
            if ($check.resource.type -eq 'variablegroup' -and [string]$check.resource.id -eq [string]$VariableGroupId -and $check.type -and $check.type.name -eq 'ExclusiveLock') {
                $hasExclusiveLock = $true
                break
            }
        }
    }

    if ($hasExclusiveLock) {
        Write-Host "ExclusiveLock check already exists on variable group '$VariableGroupName'."
        return
    }

    Write-Host "Adding ExclusiveLock check to variable group '$VariableGroupName'..." -ForegroundColor Yellow

    $body = @{
        type = @{
            id = "2EF31AD6-BAA0-403A-8B45-2CBC9B4E5563"
            name = "ExclusiveLock"
        }
        settings = @{}
        resource = @{
            type = "variablegroup"
            id = [string]$VariableGroupId
            name = $VariableGroupName
        }
        timeout = 43200
    }

    $resource = "pipelines/checks/configurations"
    [void](Invoke-VSTeamRequest -Method POST -Resource $resource -Body ($body | ConvertTo-Json -Depth 10) -ContentType 'application/json' -Version '7.1-preview.1')
    Write-Host "ExclusiveLock check added."
}

function Ensure-AzDoVariableGroupExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Organization,
        [Parameter(Mandatory)][string]$Project,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$GroupName,
        [Parameter(Mandatory)][hashtable]$Variables
    )

    $group = $null

    # Use VSTeam command to check for existing variable groups
    try {
        $existing = Get-VSTeamVariableGroup -ProjectName $Project -Name $GroupName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "Variable group '$GroupName' already exists (id: $($existing.id))."
            $group = $existing
        }
    }
    catch {
        # Group doesn't exist, continue with creation
    }

    if (-not $group) {
        Write-Host "Creating variable group '$GroupName'..." -ForegroundColor Yellow

        # Build variables payload in the format expected by Add-VSTeamVariableGroup
        $variablesPayload = @{}
        foreach ($k in $Variables.Keys) {
            $variablesPayload[$k] = @{ value = [string]$Variables[$k] }
        }

        # Use VSTeam command to create variable group
        $created = Add-VSTeamVariableGroup -ProjectName $Project -Name $GroupName -Type 'Vsts' -Variables $variablesPayload -Description 'ALM4Dataverse environment variable group (created by setup.ps1)'

        if ($created -and $created.id) {
            Write-Host "Created variable group '$GroupName' (id: $($created.id))."
            $group = $created
        }
        else {
            Write-Host "Created variable group '$GroupName'."
            $group = $created
        }
    }

    if ($group -and $group.id) {
        Ensure-AzDoVariableGroupExclusiveLock -Organization $Organization -Project $Project -VariableGroupId $group.id -VariableGroupName $GroupName

        if ($GroupName -notmatch 'Dev') {
            $envName = $GroupName -replace '^Environment-', ''
            $team = Ensure-AzDoDeploymentApproversTeam -ProjectName $Project -EnvironmentName $envName
            Ensure-AzDoVariableGroupApproval -Organization $Organization -Project $Project -VariableGroupId $group.id -VariableGroupName $GroupName -ApproverTeam $team
            
        }
    }

    return $group
}

Write-Section "Ensuring main repository contains pipeline YAMLs"

Write-Section "Ensuring environment variable group"

# Create the environment variable group only if it doesn't exist.
# This seeds example values that you can later replace with your real connection reference ids / environment variable values.
[void](Ensure-AzDoVariableGroupExists `
        -Organization $orgName `
        -Project $selectedProject.Name `
        -ProjectId $selectedProject.Id `
        -GroupName 'Environment-Dev-main' `
        -Variables @{
        'CONNREF_example_uniquename' = 'connectionid'
        'ENVVAR_example_uniquename'  = 'value'
    })

$mainRepo = Select-AzDoMainRepository -ProjectName $selectedProject.Name -SharedRepositoryName $sharedRepoName

$copyRoot = Join-Path $PSScriptRoot 'copy-to-your-repo'
Sync-CopyToYourRepoIntoGitRepo -SourceRoot $copyRoot -TargetRepo $mainRepo -PreferredBranch 'main'

Write-Section "Ensuring Build Service has Contribute on main repo"
Ensure-AzDoBuildServiceHasContributeOnRepo -Organization $orgName -ProjectName $selectedProject.Name -ProjectId $selectedProject.Id -RepositoryId $mainRepo.Id

# Create/ensure actual Azure DevOps pipelines that point at the YAML files we just synced.
$yamlFiles = @(
    'pipelines/BUILD.yml',
    'pipelines/DEPLOY-main.yml',
    'pipelines/EXPORT.yml',
    'pipelines/IMPORT.yml'
)

Ensure-AzDoPipelinesForMainRepo -Organization $orgName -Project $selectedProject.Name -Repository $mainRepo -YamlFiles $yamlFiles -FolderPath '\\ALM4Dataverse'

#endregion

#region Solutions Selection

function Get-DataverseSolutionsSelection {
    [CmdletBinding()]
    param(
        [Parameter()][string]$AccessToken
    )
    
    try {
        Write-Host "Listing Dataverse environments current user has access to..." -ForegroundColor Yellow
        
        Write-Host ""
        Write-Host "When prompted, select your dataverse DEV environment containing the solution(s) you want to manage" -ForegroundColor Green
        Write-Host ""

        # Connect to Dataverse using provided URL and token
        # If no URL is provided, Get-DataverseConnection will prompt for environment selection
        # We pass the token provider to allow it to get tokens for discovery AND the selected environment
        $connection = Get-DataverseConnection -AccessToken { 
            param($resource)
            if (-not $resource) { $resource = 'https://globaldisco.crm.dynamics.com/' }
            
            # The cmdlet passes the full API URL (e.g. .../api/discovery/... or .../XRMServices/...), 
            # but we need the resource root (scheme + authority) for the token scope.
            try {
                $uri = [System.Uri]$resource
                $resource = $uri.GetLeftPart([System.UriPartial]::Authority)
            }
            catch {
                # If parsing fails, use the original string (shouldn't happen for valid URLs)
            }

            $auth = Get-AuthToken -ResourceUrl $resource
            return $auth.AccessToken
        }
        
        if (-not $connection) {
            throw "Failed to connect to Dataverse environment."
        }
        
        $devEnvUrl = $connection.ConnectedOrgPublishedEndpoints["WebApplication"]
        
        Write-Host "Connected to environment: $($connection.ConnectedOrgFriendlyName)"
        Write-Host "Retrieving solutions..." -ForegroundColor Yellow
        
        # Get all solutions (excluding system solutions)
        $allSolutions = Get-DataverseRecord -Connection $connection -TableName 'solution' -Columns @('solutionid', 'uniquename', 'friendlyname', 'version', 'ismanaged', 'description') -FilterValues @{
            'isvisible' = $true
            'ismanaged' = $false
        }
        
        if (-not $allSolutions -or $allSolutions.Count -eq 0) {
            Write-Host "No unmanaged solutions found in the environment." -ForegroundColor Yellow
            return @{ Solutions = @(); EnvironmentUrl = $devEnvUrl }
        }
        
        # Filter out system solutions and prepare for selection
        $userSolutions = $allSolutions | Where-Object { 
            $_.uniquename -notmatch '^(Default|Active|Basic|msdyn_|ms|MicrosoftFlow|PowerPlatform)' -and 
            $_.uniquename -ne 'System' 
        } | Sort-Object friendlyname
        
        if (-not $userSolutions -or $userSolutions.Count -eq 0) {
            Write-Host "No user-created solutions found in the environment." -ForegroundColor Yellow
            return @{ Solutions = @(); EnvironmentUrl = $devEnvUrl }
        }

        Write-Host ""
        Write-Host "Select the solution(s) to manage" -ForegroundColor Green
        Write-Host "You must select solutions in dependency order (base solutions first)." -ForegroundColor Green
        Write-Host "After selecting each solution, you will be prompted to select additional solutions or finish." -ForegroundColor Green
        Write-Host ""
        
        # Prepare menu items
        $menuItems = @()
        foreach ($solution in $userSolutions) {
            $displayName = "$($solution.friendlyname) ($($solution.uniquename))"
            $menuItems += $displayName
        }
        $menuItems += "--- Done selecting solutions ---"
        
        # Multi-select loop
        $selectedSolutions = @()
        $selectedIndices = @()
        
        do {
            $availableItems = @()
            for ($i = 0; $i -lt ($menuItems.Count - 1); $i++) {
                if ($i -notin $selectedIndices) {
                    $availableItems += $menuItems[$i]
                }
            }
            
            if ($availableItems.Count -eq 0) {
                break
            }
            
            $availableItems += "--- Done selecting solutions ---"
            
            $title = if ($selectedSolutions.Count -eq 0) {
                "Select solutions to include in ALM configuration (in dependency order)"
            }
            else {
                "Selected $($selectedSolutions.Count) solution(s). Select additional solutions or finish"
            }
            
            $selectedIndex = Select-FromMenu -Title $title -Items $availableItems
            
            if ($null -eq $selectedIndex -or $selectedIndex -eq ($availableItems.Count - 1)) {
                # User selected "Done" or cancelled
                break
            }
            
            # Find the original index of the selected item
            $selectedDisplayName = $availableItems[$selectedIndex]
            $originalIndex = $menuItems.IndexOf($selectedDisplayName)
            
            if ($originalIndex -ge 0 -and $originalIndex -lt $userSolutions.Count) {
                $selectedSolutions += $userSolutions[$originalIndex]
                $selectedIndices += $originalIndex
                Write-Host "Added: $($userSolutions[$originalIndex].friendlyname)"
            }
            
        } while ($true)
        
        if ($selectedSolutions.Count -eq 0) {
            Write-Host "No solutions selected." -ForegroundColor Yellow
            return @{ Solutions = @(); EnvironmentUrl = $devEnvUrl }
        }
        
        Write-Host "Selected $($selectedSolutions.Count) solution(s) for ALM configuration:"
        foreach ($sol in $selectedSolutions) {
            Write-Host "  - $($sol.friendlyname) ($($sol.uniquename))"
        }
        
        # Convert to the format needed for alm-config.psd1
        $configSolutions = @()
        foreach ($sol in $selectedSolutions) {
            $configSolutions += @{
                name            = $sol.uniquename
                deployUnmanaged = $false
            }
        }
        
        return @{ Solutions = $configSolutions; EnvironmentUrl = $devEnvUrl }
        
    }
    catch {
        Write-Host "Error retrieving solutions from Dataverse: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Update-AlmConfigInMainRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Solutions,
        [Parameter(Mandatory)][object]$MainRepo,
        [Parameter(Mandatory)][string]$AccessToken
    )
    
    if (-not $MainRepo.remoteUrl) {
        throw "Could not determine remoteUrl for repository '$($MainRepo.Name)'."
    }

    $cloneRoot = Join-Path $env:TEMP ("ALM4Dataverse-ConfigUpdate-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $cloneRoot -Force | Out-Null

    Write-Host "Cloning '$($MainRepo.Name)' to update alm-config.psd1..." -ForegroundColor Yellow
    try {
        & git -c "http.extraheader=AUTHORIZATION: bearer $AccessToken" clone $MainRepo.remoteUrl $cloneRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone exited with code $LASTEXITCODE"
        }
    }
    catch {
        throw "Git clone failed for '$($MainRepo.remoteUrl)': $($_.Exception.Message)"
    }

    Push-Location $cloneRoot
    try {
        $branch = 'main'
        if ($MainRepo.defaultBranch) {
            $branch = ConvertFrom-GitRefToBranchName -Ref $MainRepo.defaultBranch
        }

        # Checkout the correct branch
        & git checkout $branch
        if ($LASTEXITCODE -ne 0) {
            throw "Git checkout failed with exit code $LASTEXITCODE"
        }

        # Update the alm-config.psd1 file
        $configPath = Join-Path $cloneRoot 'alm-config.psd1'
        if (-not (Test-Path $configPath)) {
            Write-Host "alm-config.psd1 not found in main repository. Skipping update." -ForegroundColor Yellow
            return $false
        }

        # Read the current config file
        $configContent = Get-Content -LiteralPath $configPath -Raw
        
        # Build the solutions array string
        $solutionsArray = "    solutions = @("
        if ($Solutions.Count -gt 0) {
            $solutionsArray += "`n"
            foreach ($solution in $Solutions) {
                $solutionsArray += "        @{`n"
                $solutionsArray += "            name = '$($solution.name)'`n"
                if ($solution.deployUnmanaged) {
                    $solutionsArray += "            deployUnmanaged = `$$true`n"
                }
                $solutionsArray += "        }`n"
            }
            $solutionsArray += "    )`n"
        }
        else {
            $solutionsArray += "`n    )`n"
        }
        
        # Replace the solutions array in the config
        $updatedContent = $configContent -replace '(?s)    solutions = @\([^)]*\)', $solutionsArray
        
        # Write back to file
        Set-Content -LiteralPath $configPath -Value $updatedContent -NoNewline

        # Check for changes
        & git add alm-config.psd1
        if ($LASTEXITCODE -ne 0) {
            throw "Git add failed with exit code $LASTEXITCODE"
        }
        
        # Check if there are changes to commit
        & git diff --cached --quiet
        $hasChanges = ($LASTEXITCODE -ne 0)
        
        if ($hasChanges) {
            Write-Host "Committing alm-config.psd1 changes..." -ForegroundColor Yellow
            
            # Configure git user if not already configured
            & git config user.name "ALM4Dataverse Setup" 2>$null
            & git config user.email "setup@alm4dataverse.local" 2>$null
            
            & git commit -m "Update alm-config.psd1 with selected solutions"
            if ($LASTEXITCODE -ne 0) {
                throw "Git commit failed with exit code $LASTEXITCODE"
            }

            Write-Host "Pushing changes to origin/$branch..." -ForegroundColor Yellow
            & git -c "http.extraheader=AUTHORIZATION: bearer $AccessToken" push origin $branch
            if ($LASTEXITCODE -ne 0) {
                throw "Git push failed with exit code $LASTEXITCODE. Ensure you have permission and that authentication succeeds."
            }
            Write-Host "alm-config.psd1 updated successfully in main repository."
            return $true
        }
        else {
            Write-Host "No changes to alm-config.psd1; solutions already configured."
            return $false
        }
    }
    finally {
        Pop-Location
        try { Remove-Item -LiteralPath $cloneRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

#endregion

#region Dataverse Environments Selection

function Get-DataverseEnvironmentsSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)][string]$ExcludedUrl
    )

    $selectedEnvironments = @()

    while ($true) {
        Clear-Host
        Write-Host "Target Deployment Environments" -ForegroundColor Cyan
        Write-Host "==============================" -ForegroundColor Cyan
        Write-Host ""
        
        if ($selectedEnvironments.Count -eq 0) {
            Write-Host "No environments selected." -ForegroundColor DarkGray
        }
        else {
            Write-Host "Selected environments ($($selectedEnvironments.Count)):" -ForegroundColor Green
            $selectedEnvironments | Format-Table -Property ShortName, FriendlyName, Url -AutoSize | Out-Host
        }
        Write-Host ""

        $menuItems = @('Add an environment', 'Clear list')
        if ($selectedEnvironments.Count -gt 0) {
            $menuItems += 'Done'
        }

        $selection = Select-FromMenu -Title "Manage deployment environments" -Items $menuItems

        if ($null -eq $selection) { return $selectedEnvironments }

        $action = $menuItems[$selection]

        switch ($action) {
            'Add an environment' {
                try {
                    Write-Host "Connecting to Dataverse environment..." -ForegroundColor Yellow
                    
                    $connection = Get-DataverseConnection -AccessToken { 
                        param($resource)
                        if (-not $resource) { $resource = 'https://globaldisco.crm.dynamics.com/' }
                        try {
                            $uri = [System.Uri]$resource
                            $resource = $uri.GetLeftPart([System.UriPartial]::Authority)
                        } catch {}
                        $auth = Get-AuthToken -ResourceUrl $resource
                        return $auth.AccessToken
                    }

                    if ($connection) {

                        $url =  $connection.ConnectedOrgPublishedEndpoints["WebApplication"]

                        if ($ExcludedUrl -and $url -eq $ExcludedUrl) {
                            Write-Host "Cannot select the same environment used for solutions." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }

                        if ($selectedEnvironments | Where-Object { $_.Url -eq $url }) {
                            Write-Host "An environment with Url '$url' is already selected." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }

                        $shortName = Read-Host "Enter a short name for this environment (e.g. TEST, UAT, PROD)"
                        if ([string]::IsNullOrWhiteSpace($shortName)) {
                            Write-Host "Short name is required." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }
                        $shortName = $shortName.Replace("-main", "").Trim() + "-main"
 
                        if ($selectedEnvironments | Where-Object { $_.ShortName -eq $shortName }) {
                            Write-Host "An environment with short name '$shortName' is already selected." -ForegroundColor Red
                            Start-Sleep -Seconds 2
                            continue
                        }

                        $envInfo = [pscustomobject]@{
                            ShortName = $shortName
                            FriendlyName = $connection.ConnectedOrgFriendlyName
                            Url = $url
                        }
                        $selectedEnvironments += $envInfo
                    }
                }
                catch {
                    Write-Host "Failed to connect: $_" -ForegroundColor Red
                    Start-Sleep -Seconds 3
                }
            }
            'Clear list' {
                $selectedEnvironments = @()
                Write-Host "List cleared." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
            'Done' {
                return $selectedEnvironments
            }
        }
    }
}

function Update-DeployPipelineInMainRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Environments,
        [Parameter(Mandatory)][object]$MainRepo,
        [Parameter(Mandatory)][string]$AccessToken
    )

    if ($Environments.Count -eq 0) { return }

    if (-not $MainRepo.remoteUrl) {
        throw "Could not determine remoteUrl for repository '$($MainRepo.Name)'."
    }

    $cloneRoot = Join-Path $env:TEMP ("ALM4Dataverse-DeployUpdate-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $cloneRoot -Force | Out-Null

    Write-Host "Cloning '$($MainRepo.Name)' to update DEPLOY-main.yml..." -ForegroundColor Yellow
    try {
        & git -c "http.extraheader=AUTHORIZATION: bearer $AccessToken" clone $MainRepo.remoteUrl $cloneRoot
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone exited with code $LASTEXITCODE"
        }
    }
    catch {
        throw "Git clone failed for '$($MainRepo.remoteUrl)': $($_.Exception.Message)"
    }

    Push-Location $cloneRoot
    try {
        $branch = 'main'
        if ($MainRepo.defaultBranch) {
            $branch = ConvertFrom-GitRefToBranchName -Ref $MainRepo.defaultBranch
        }

        & git checkout $branch
        if ($LASTEXITCODE -ne 0) {
            throw "Git checkout failed with exit code $LASTEXITCODE"
        }

        $deployYamlPath = Join-Path $cloneRoot 'pipelines\DEPLOY-main.yml'
        if (-not (Test-Path $deployYamlPath)) {
            throw "pipelines\DEPLOY-main.yml not found"
        }

        $newStages = "`n"
        foreach ($env in $Environments) {
            $newStages += "  - template: pipelines/templates/stages/deploy-environment.yml@ALM4Dataverse`n"
            $newStages += "    parameters:`n"
            $newStages += "      environmentName: $($env.ShortName)`n"
        }

        Add-Content -LiteralPath $deployYamlPath -Value $newStages

        & git add pipelines\DEPLOY-main.yml
        
        & git diff --cached --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Committing DEPLOY-main.yml changes..." -ForegroundColor Yellow
            
            & git config user.name "ALM4Dataverse Setup" 2>$null
            & git config user.email "setup@alm4dataverse.local" 2>$null
            
            $envNames = $Environments | ForEach-Object { $_.ShortName }
            & git commit -m "Configure deployment environments: $($envNames -join ', ')"
            
            & git -c "http.extraheader=AUTHORIZATION: bearer $AccessToken" push origin $branch
            if ($LASTEXITCODE -ne 0) {
                throw "Git push failed."
            }
            Write-Host "DEPLOY-main.yml updated successfully."
        }
    }
    finally {
        Pop-Location
        try { Remove-Item -LiteralPath $cloneRoot -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
}

Write-Section "Selecting Dataverse solution(s) to manage"

# Use the same access token from Azure DevOps setup
# We don't need to pre-fetch the token here anymore, as Get-DataverseSolutionsSelection will handle it via the callback

$result = Get-DataverseSolutionsSelection
$solutions = $result.Solutions
$devEnvUrl = $result.EnvironmentUrl

if ($solutions.Count -gt 0) {
    # Update alm-config.psd1 in the main repository and commit the changes
    $configUpdated = Update-AlmConfigInMainRepo -Solutions $solutions -MainRepo $mainRepo -AccessToken $azDevOpsAccessToken
    if ($configUpdated) {
        Write-Host "Updated alm-config.psd1 with $($solutions.Count) solution(s) in main repository."
    }
}

Write-Section "Selecting Deployment Environments"
$environments = Get-DataverseEnvironmentsSelection -ExcludedUrl $devEnvUrl

if ($environments.Count -gt 0) {
    Update-DeployPipelineInMainRepo -Environments $environments -MainRepo $mainRepo -AccessToken $azDevOpsAccessToken

    foreach ($env in $environments) {
        [void](Ensure-AzDoVariableGroupExists `
            -Organization $orgName `
            -Project $selectedProject.Name `
            -ProjectId $selectedProject.Id `
            -GroupName "Environment-$($env.ShortName)" `
            -Variables @{
            'CONNREF_example_uniquename' = 'connectionid'
            'ENVVAR_example_uniquename'  = 'value'
        })
    }
}

#endregion

Clear-Host
Write-Host "Setup completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "https://github.com/rnwood/ALM4Dataverse/tree/stable#getting-started" -ForegroundColor Green
