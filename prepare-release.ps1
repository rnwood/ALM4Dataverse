#Requires -Version 7.0

<#
.SYNOPSIS
    Script to prepare setup.ps1 for release
    This extracts the release logic from the GitHub workflow for testability

.DESCRIPTION
    Processes setup.ps1 by replacing placeholders with actual values for a release.
    This script can be run locally to test the release preparation process.

.PARAMETER TagName
    The release tag (e.g., v1.0.0)

.PARAMETER OutputDir
    Directory where the processed setup.ps1 will be written

.PARAMETER UpstreamRepo
    (Optional) URL of the upstream repository. Defaults to https://github.com/rnwood/ALM4Dataverse.git

.EXAMPLE
    .\prepare-release.ps1 -TagName v1.2.3 -OutputDir ./release

.EXAMPLE
    .\prepare-release.ps1 -TagName v1.2.3 -OutputDir ./release -UpstreamRepo https://github.com/myorg/MyRepo.git
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TagName,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputDir,

    [Parameter(Position = 2)]
    [string]$UpstreamRepo = 'https://github.com/rnwood/ALM4Dataverse.git'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get the directory where this script is located
$ScriptDir = $PSScriptRoot

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Preparing setup.ps1 for release" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration:"
Write-Host "  Tag:          $TagName"
Write-Host "  Output dir:   $OutputDir"
Write-Host "  Upstream URL: $UpstreamRepo"
Write-Host "  Script dir:   $ScriptDir"
Write-Host ""

# Step 1: Extract Rnwood.Dataverse.Data.PowerShell version from alm-config-defaults.psd1
Write-Host "Step 1: Extracting version from alm-config-defaults.psd1..." -ForegroundColor Yellow

$ConfigFile = Join-Path $ScriptDir 'alm-config-defaults.psd1'
if (-not (Test-Path $ConfigFile)) {
    Write-Host "ERROR: Config file not found: $ConfigFile" -ForegroundColor Red
    exit 1
}

# Use Import-PowerShellDataFile to reliably read the version
try {
    $config = Import-PowerShellDataFile -Path $ConfigFile
    $DataverseVersion = $config.scriptDependencies.'Rnwood.Dataverse.Data.PowerShell'
    
    if ([string]::IsNullOrWhiteSpace($DataverseVersion)) {
        throw "Version string is empty"
    }
    
    Write-Host "  Found version: $DataverseVersion" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Could not extract Rnwood.Dataverse.Data.PowerShell version from config file" -ForegroundColor Red
    Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 2: Process setup.ps1 and replace placeholders
Write-Host "Step 2: Processing setup.ps1..." -ForegroundColor Yellow

$SetupFile = Join-Path $ScriptDir 'setup.ps1'
if (-not (Test-Path $SetupFile)) {
    Write-Host "ERROR: Setup file not found: $SetupFile" -ForegroundColor Red
    exit 1
}

# Define placeholders
$Alm4DataverseRefPlaceholder = '__ALM4DATAVERSE_REF__'
$RnwoodDataverseVersionPlaceholder = '__RNWOOD_DATAVERSE_VERSION__'
$UpstreamRepoPlaceholder = '__UPSTREAM_REPO__'

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$OutputFile = Join-Path $OutputDir 'setup.ps1'

# Read the setup file
$setupContent = Get-Content -Path $SetupFile -Raw

# Replace placeholders
$setupContent = $setupContent -replace [regex]::Escape($Alm4DataverseRefPlaceholder), $TagName
$setupContent = $setupContent -replace [regex]::Escape($RnwoodDataverseVersionPlaceholder), $DataverseVersion
$setupContent = $setupContent -replace [regex]::Escape($UpstreamRepoPlaceholder), $UpstreamRepo

# Write to output file
Set-Content -Path $OutputFile -Value $setupContent -NoNewline

Write-Host "  Processed setup.ps1 with:" -ForegroundColor Green
Write-Host "    ALM4DATAVERSE_REF: $TagName"
Write-Host "    RNWOOD_DATAVERSE_VERSION: $DataverseVersion"
Write-Host "    UPSTREAM_REPO: $UpstreamRepo"
Write-Host ""

# Step 3: Verify placeholders were replaced
Write-Host "Step 3: Verifying placeholder replacement..." -ForegroundColor Yellow

$outputContent = Get-Content -Path $OutputFile -Raw
$remainingPlaceholders = @()

if ($outputContent -match [regex]::Escape($Alm4DataverseRefPlaceholder)) {
    $remainingPlaceholders += $Alm4DataverseRefPlaceholder
}
if ($outputContent -match [regex]::Escape($RnwoodDataverseVersionPlaceholder)) {
    $remainingPlaceholders += $RnwoodDataverseVersionPlaceholder
}
if ($outputContent -match [regex]::Escape($UpstreamRepoPlaceholder)) {
    $remainingPlaceholders += $UpstreamRepoPlaceholder
}

if ($remainingPlaceholders.Count -gt 0) {
    Write-Host "ERROR: Placeholders were not fully replaced!" -ForegroundColor Red
    Write-Host "Remaining placeholders:" -ForegroundColor Red
    foreach ($placeholder in $remainingPlaceholders) {
        Write-Host "  - $placeholder" -ForegroundColor Red
    }
    exit 1
}

Write-Host "  ✓ All placeholders replaced successfully" -ForegroundColor Green
Write-Host ""

# Step 4: Display summary
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "✓ Release preparation complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output file: $OutputFile"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Review the processed file"
Write-Host "  2. Upload to GitHub release as an asset"
Write-Host ""
