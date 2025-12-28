<#
.SYNOPSIS
    Connects to a Dataverse environment using the provided connection string.
.DESCRIPTION

    This script establishes a connection to the Dataverse environment specified 
    by the connection string.

.PARAMETER ConnectionString
    The connection string used to connect to the Dataverse environment.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString
)

Write-Host "##[group] Connecting to Dataverse environment with connection string: $ConnectionString"
Get-DataverseConnection -setasdefault -connectionstring $ConnectionString | out-null
Write-Host "Connected to Dataverse environment"
Write-Host "##[endgroup]"