<#
.SYNOPSIS
    Connects to a Dataverse environment using the provided connection string.
.DESCRIPTION

    This script establishes a connection to the Dataverse environment specified 
    by the connection string. After connecting, it validates the connection by
    calling WhoAmI to ensure the identity has access to the target environment.

.PARAMETER ConnectionString
    The connection string used to connect to the Dataverse environment.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConnectionString
)

Write-Host "##[group] Connecting to Dataverse environment with connection string: $ConnectionString"
Get-DataverseConnection -setasdefault -connectionstring $ConnectionString | out-null
Write-Host "Validating connection using WhoAmI..."
$whoAmI = Get-DataverseWhoAmI
Write-Host "Connected to Dataverse environment. UserId: $($whoAmI.UserId), BusinessUnitId: $($whoAmI.BusinessUnitId), OrganizationId: $($whoAmI.OrganizationId)"
Write-Host "##[endgroup]"