<#
.SYNOPSIS
    Common functions for pipelines scripts.
.DESCRIPTION
    This script contains common functions used across various pipeline scripts
    such as build.ps1, deploy.ps1, and export.ps1.
#>

function Get-AlmConfig {
    param(
        [Parameter]
        [string]$BaseDirectory = "."
    )

    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $defaultConfigPath = Join-Path $scriptDirectory ".." ".." ".." "almconfig-defaults.psd1"
    
    $config = @{}
    
    Write-Host "##[group] Loading default configuration from $defaultConfigPath"
    $defaultConfig = Import-PowerShellDataFile -Path $defaultConfigPath
    $config = $defaultConfig
    Write-Host "##[endgroup]"

    # Load main config and merge
    $configPath = Join-Path $BaseDirectory "alm-config.psd1"
    if (-not (Test-Path $configPath)) {
        Write-Host "##[error]Configuration file not found: $configPath"
        throw "alm-config.psd1 not found at $configPath"
    }

    $mainConfig = Import-PowerShellDataFile -Path $configPath
    
    # Merge configs: mainConfig overrides defaultConfig, arrays are concatenated
    foreach ($key in $mainConfig.Keys) {
        if ($config.ContainsKey($key)) {
            $defaultValue = $config[$key]
            $mainValue = $mainConfig[$key]
            
            # If both are arrays, concatenate them
            if ($defaultValue -is [array] -and $mainValue -is [array]) {
                $config[$key] = @($defaultValue) + @($mainValue)
            }
            # If both are hashtables, merge them
            elseif ($defaultValue -is [hashtable] -and $mainValue -is [hashtable]) {
                foreach ($subKey in $mainValue.Keys) {
                    $defaultValue[$subKey] = $mainValue[$subKey]
                }
                $config[$key] = $defaultValue
            }
            # Otherwise, main value wins
            else {
                $config[$key] = $mainValue
            }
        }
        else {
            $config[$key] = $mainConfig[$key]
        }
    }
    
    # Preserve any keys from default config that are not in main config
    foreach ($key in $defaultConfig.Keys) {
        if (-not $mainConfig.ContainsKey($key)) {
            $config[$key] = $defaultConfig[$key]
        }
    }

    $config["defaults"] = $defaultConfig
    
    return $config
}

function Invoke-Hooks {
    param(
        [string]$HookType,
        [string]$BaseDirectory,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [hashtable]$AdditionalContext = @{}
    )

    if ($Config.hooks -and $Config.hooks.$HookType) {
        $hooks = $Config.hooks.$HookType
        if ($hooks -is [string]) {
            $hooks = @($hooks)
        }
        foreach ($hook in $hooks) {
            Write-Host "##[group] Executing $HookType hook: $hook"
            
            # Build context hashtable with required and additional entries
            $context = @{
                HookType       = $HookType
                BaseDirectory  = $BaseDirectory
                Config         = $Config
            }
            # Add any additional context entries
            foreach ($key in $AdditionalContext.Keys) {
                $context[$key] = $AdditionalContext[$key]
            }
            
            # Replace [alm] placeholder with the absolute path of the ALM repo root
            $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
            $almRootPath = Join-Path $scriptDirectory ".." ".." ".." | Resolve-Path | Select-Object -ExpandProperty Path
            $processedHook = $hook -replace '\[alm\]', $almRootPath
            
            $hookPath = Join-Path $BaseDirectory $processedHook
            if (Test-Path $hookPath) {

                & $hookPath -Context $context
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
