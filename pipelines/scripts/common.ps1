<#
.SYNOPSIS
    Common functions for pipelines scripts.
.DESCRIPTION
    This script contains common functions used across various pipeline scripts
    such as build.ps1, deploy.ps1, and export.ps1.
#>

function Get-AlmConfig {
    param(
        [string]$BaseDirectory = "."
    )

    $defaultConfigPath = Join-Path $PSScriptRoot ".." ".." "alm-config-defaults.psd1" | Resolve-Path | Select-Object -ExpandProperty Path
    
    $config = @{}
    
    Write-Host "##[group] Loading default configuration from $defaultConfigPath"
    $defaultConfig = Import-PowerShellDataFile -Path $defaultConfigPath
    Write-Host "##[endgroup]"

    # Load main config and merge
    $configPath = Join-Path $BaseDirectory "alm-config.psd1"
    if (-not (Test-Path $configPath)) {
        Write-Host "##[error]Configuration file not found: $configPath"
        throw "alm-config.psd1 not found at $configPath"
    }

    $mainConfig = Import-PowerShellDataFile -Path $configPath

    function mergeConfigValue($defaultConfig, $mainConfig) {
        if (-not $defaultConfig) {
            return $mainConfig
        }

        if (-not $mainConfig) {
            return $defaultConfig
        }

        # If both are arrays, concatenate them
        if ($defaultConfig -is [array] -and $mainConfig -is [array]) {
            return @(@($defaultConfig) + @($mainConfig))
        }

        # If neither is a hashtable, main value wins (primitive override)
        if ($defaultConfig -isnot [hashtable] -or $mainConfig -isnot [hashtable]) {
            return $mainConfig
        }

        $newValue = @{}
        foreach ($subKey in $defaultConfig.Keys + $mainConfig.Keys | Select-Object -Unique) {
            $newValue[$subKey] = mergeConfigValue $defaultConfig[$subKey] $mainConfig[$subKey]
        }
        return $newValue
    }
    
    # Merge configs: mainConfig overrides defaultConfig, arrays are concatenated
    foreach ($key in $mainConfig.Keys) {
        if ($defaultConfig.ContainsKey($key)) {
            $defaultValue = $defaultConfig[$key]
            $mainValue = $mainConfig[$key]
            
            # If both are arrays, concatenate them
            if ($defaultValue -is [array] -and $mainValue -is [array]) {
                $config[$key] = @(@($defaultValue) + @($mainValue)) 
            }
            # If both are hashtables, merge them
            elseif ($defaultValue -is [hashtable] -and $mainValue -is [hashtable]) {
                $config[$key] = mergeConfigValue $defaultValue $mainValue
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

    $config["_main"] = $mainConfig
    $config["_defaults"] = $defaultConfig

    Write-Host "##[debug]Loaded configuration: $($config | ConvertTo-Json -Depth 20)"
    
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
                HookType      = $HookType
                BaseDirectory = $BaseDirectory
                Config        = $Config
            }
            # Add any additional context entries
            foreach ($key in $AdditionalContext.Keys) {
                $context[$key] = $AdditionalContext[$key]
            }
            
            # Replace [alm] placeholder with the absolute path of the ALM repo root
            $almRootPath = Join-Path $PSScriptRoot ".." ".." | Resolve-Path | Select-Object -ExpandProperty Path
            $hookPath = $hook -replace '\[alm\]', $almRootPath
            
            if (Test-Path $hookPath) {

                write-host "##[debug] Executing hook script at path: $hookPath with context: $($context | ConvertTo-Json -Depth 10)"

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
