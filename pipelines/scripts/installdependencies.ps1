<#
.SYNOPSIS
    Installs the required PowerShell modules as defined in alm-config.psd1 with optional lock file.
.DESCRIPTION
    This script reads the alm-config.psd1 file to determine which PowerShell modules    
    need to be installed for the scripts to run. It supports version pinning via a
    scriptDependencies.lock.json file which is used for consistent module versions
    in the version that goes into artifacts.

    The versions can be specified as:
    - '' (empty string): installs the latest version
    - 'prerelease': installs the latest prerelease version
    - specific version number (e.g. '1.2.3' or '1.2.3-beta.1'): installs that specific version
#>

Write-Host "##[group] Installing Dependencies"

$config = Import-PowerShellDataFile -Path 'alm-config.psd1'

$lockFile = 'scriptDependencies.lock.json'
if (Test-Path $lockFile) {
    $lockData = Get-Content $lockFile -Raw | ConvertFrom-Json -AsHashtable
    $config.scriptDependencies = $lockData.scriptDependencies
    Write-Host "Using pinned versions from lock file"
}

foreach ($module in $config.scriptDependencies.Keys) {

    $version = $config.scriptDependencies[$module]
    Write-Host "Installing $module module with version specifier: '$version'"
    if ($version -eq '') {
        $installedModule = Install-Module -Name $module -Scope CurrentUser -Force -PassThru
    }
    elseif ($version -eq 'prerelease') {
        $installedModule = Install-Module -Name $module -Scope CurrentUser -Force -AllowPrerelease -PassThru
    }
    else {
        $installedModule = Install-Module -Name $module -Scope CurrentUser -Force -RequiredVersion $version -AllowPrerelease:($version.Contains("-")) -PassThru
    }
    Write-Host "Installed $module version $($installedModule.Version)"

    # Manually load the installed module to ensure the correct version is used
    # This is complex because Import-Module does not support version ranges or prerelease directly

    # This ensures that we load the exact installed version even when running locally
    # where multiple versions may be present

    $moduletoload = get-installedmodule -Name $module -RequiredVersion $installedModule.Version -AllowPrerelease:($installedModule.Version.Contains("-"))

    if (-not $moduletoload) {
        Write-Host "##[error]Failed to find installed module $module version $($installedModule.Version)"
        
        throw "Failed to find installed module $module version $($installedModule.Version)"
    }
    Import-Module "$($moduletoload.InstalledLocation)/*.psd1"
  
    $loadedModule = Get-Module -Name $module
    Write-Host "Loaded $module version $($loadedModule.Version) $($loadedModule.Prerelease)"
}

Write-Host "Dependencies Installed"
Write-Host "##[endgroup]"