<#
.SYNOPSIS
    Creates or updates PRs for outdated script dependencies
.DESCRIPTION
    For each outdated dependency found, this script creates a new PR or updates
    an existing PR if one is already open for the same dependency.
#>

$ErrorActionPreference = "Stop"

Write-Host "Creating/updating PRs for outdated dependencies..."

# Read the outdated dependencies
if (-not (Test-Path "outdated-deps.json")) {
    Write-Host "No outdated dependencies file found"
    exit 0
}

$outdatedDeps = Get-Content "outdated-deps.json" -Raw | ConvertFrom-Json

if (-not $outdatedDeps -or $outdatedDeps.Count -eq 0) {
    Write-Host "No outdated dependencies to process"
    exit 0
}

# Configure git
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

$baseBranch = "main"

foreach ($dep in $outdatedDeps) {
    $moduleName = $dep.name
    $currentVersion = $dep.currentVersion
    $latestVersion = $dep.latestVersion
    
    Write-Host "`nProcessing $moduleName ($currentVersion -> $latestVersion)..."
    
    # Create branch name
    $branchName = "deps/update-$($moduleName.ToLower())-to-$latestVersion"
    
    # Check if a PR already exists for this dependency
    $existingPRs = gh pr list --state open --json number,headRefName,title | ConvertFrom-Json
    $existingPR = $existingPRs | Where-Object { $_.headRefName -like "deps/update-$($moduleName.ToLower())-*" }
    
    if ($existingPR) {
        Write-Host "Found existing PR #$($existingPR.number) with branch $($existingPR.headRefName)"
        
        # Checkout and update the existing branch
        try {
            git fetch origin $existingPR.headRefName
            git checkout -B $existingPR.headRefName origin/$existingPR.headRefName
        }
        catch {
            Write-Host "##[warning]Could not checkout existing branch, creating new one"
            git checkout -b $branchName $baseBranch
        }
    } else {
        Write-Host "Creating new branch: $branchName"
        git checkout -b $branchName $baseBranch
    }
    
    # Update the dependency in alm-config-defaults.psd1
    $configPath = "alm-config-defaults.psd1"
    $configContent = Get-Content $configPath -Raw
    
    # Replace the version for this specific module
    $pattern = "(`"$moduleName`"\s*=\s*`")$currentVersion(`")"
    $replacement = "`${1}$latestVersion`${2}"
    $newContent = $configContent -replace $pattern, $replacement
    
    if ($configContent -eq $newContent) {
        Write-Host "##[warning]No changes made to config file for $moduleName"
        continue
    }
    
    Set-Content -Path $configPath -Value $newContent -NoNewline
    
    # Commit and push
    git add $configPath
    git commit -m "chore(deps): update $moduleName to $latestVersion"
    git push -f origin HEAD
    
    # Create or update PR
    $prTitle = "chore(deps): update $moduleName to $latestVersion"
    $prBody = @"
## Dependency Update

This PR updates the ``$moduleName`` PowerShell module dependency.

- **Current version:** $currentVersion
- **New version:** $latestVersion

### Changes
- Updates ``$moduleName`` in ``alm-config-defaults.psd1``

---
*This PR was automatically created by the Update Script Dependencies workflow.*
"@
    
    if ($existingPR) {
        Write-Host "Updating existing PR #$($existingPR.number)"
        gh pr edit $existingPR.number --title $prTitle --body $prBody
        Write-Host "✓ Updated PR #$($existingPR.number)"
    } else {
        Write-Host "Creating new PR"
        $newPR = gh pr create --title $prTitle --body $prBody --base $baseBranch --head $branchName
        Write-Host "✓ Created new PR: $newPR"
    }
    
    # Return to base branch for next iteration
    git checkout $baseBranch
}

Write-Host "`nAll PRs created/updated successfully!"
