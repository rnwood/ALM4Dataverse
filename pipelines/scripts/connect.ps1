<#
.SYNOPSIS
    Connects to a Dataverse environment using the provided connection string.
.DESCRIPTION

    This script establishes a connection to the Dataverse environment specified 
    by the URL. After connecting, it validates the connection by
    calling WhoAmI to ensure the identity has access to the target environment.

.PARAMETER Url
    The URL of the Dataverse environment to connect to.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$url
)

Write-Host "##[group] Connecting to Dataverse environment with URL: $url"
Get-DataverseConnection -setasdefault -DefaultAzureCredential -Url $url | out-null
Write-Host "Validating connection using WhoAmI..."
$whoAmI = Get-DataverseWhoAmI
Write-Host "Connected to Dataverse environment. UserId: $($whoAmI.UserId), BusinessUnitId: $($whoAmI.BusinessUnitId), OrganizationId: $($whoAmI.OrganizationId)"
Write-Host "##[endgroup]"

Write-Host "##[group] Signing in to Azure CLI"
if ($env:AZURE_CLIENT_ID -and $env:AZURE_TENANT_ID) {
    if ($env:AZURE_FEDERATED_TOKEN_FILE) {
        Write-Host "Signing in to Azure CLI using federated token..."
        if (-not (Test-Path $env:AZURE_FEDERATED_TOKEN_FILE)) {
            throw "Azure CLI sign-in failed (federated token): file not found at '$($env:AZURE_FEDERATED_TOKEN_FILE)'"
        }
        $federatedToken = Get-Content $env:AZURE_FEDERATED_TOKEN_FILE -Raw
        az login --service-principal --username $env:AZURE_CLIENT_ID --federated-token $federatedToken --tenant $env:AZURE_TENANT_ID --output none
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI sign-in failed (federated token)"
        }
    } elseif ($env:AZURE_CLIENT_SECRET) {
        Write-Host "Signing in to Azure CLI using client secret..."
        $secretFile = [System.IO.Path]::GetTempFileName()
        try {
            $env:AZURE_CLIENT_SECRET | Out-File -FilePath $secretFile -NoNewline -Encoding utf8
            az login --service-principal --username $env:AZURE_CLIENT_ID --password "@$secretFile" --tenant $env:AZURE_TENANT_ID --output none
        } finally {
            Remove-Item $secretFile -Force -ErrorAction SilentlyContinue
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Azure CLI sign-in failed (client secret)"
        }
    } else {
        Write-Host "##[warning]AZURE_CLIENT_ID and AZURE_TENANT_ID are set but neither AZURE_CLIENT_SECRET nor AZURE_FEDERATED_TOKEN_FILE was found. Skipping Azure CLI sign-in."
    }
    Write-Host "Azure CLI sign-in successful."
} else {
    Write-Host "##[debug]AZURE_CLIENT_ID or AZURE_TENANT_ID not set. Skipping Azure CLI sign-in."
}
Write-Host "##[endgroup]"