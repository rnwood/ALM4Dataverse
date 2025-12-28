<#
.SYNOPSIS
    Common functions for pipelines scripts.
.DESCRIPTION
    This script contains common functions used across various pipeline scripts
    such as build.ps1, deploy.ps1, and export.ps1.
#>

function Get-AlmConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseDirectory
    )

    $configPath = Join-Path $BaseDirectory "alm-config.psd1"
    if (-not (Test-Path $configPath)) {
        Write-Host "##[error]Configuration file not found: $configPath"
        throw "alm-config.psd1 not found at $configPath"
    }

    Import-PowerShellDataFile -Path $configPath
}

function Invoke-Hooks {
    param(
        [string]$HookType,
        [string]$BaseDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    if ($Config.hooks -and $Config.hooks.$HookType) {
        $hooks = $Config.hooks.$HookType
        if ($hooks -is [string]) {
            $hooks = @($hooks)
        }
        foreach ($hook in $hooks) {
            Write-Host "##[group] Executing $HookType hook: $hook"
            $hookPath = Join-Path $BaseDirectory $hook
            if (Test-Path $hookPath) {

                & $hookPath
                if (-not $? ) {
                    throw "Hook $hook failed"
                }

            }
            else {
                Write-Host "##[error]Hook script not found: $hookPath"
                throw "Hook script not found: $hookPath"
            }
            Write-Host "##[endgroup]"
        }
    }
}
