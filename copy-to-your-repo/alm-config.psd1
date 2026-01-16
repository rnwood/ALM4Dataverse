@{
    # ALM for Dataverse configuration
    #
    # Paths in this file are relative to the directory this file is in (the repo root).
    #
    # FORK CONFIGURATION:
    # To customize this configuration in a fork, create a fork-almconfig.psd1 file
    # in the ALM4Dataverse repository root.
    # Fork configuration is merged with this file (this file's values take precedence).
    # Arrays are concatenated, hashtables are merged.
    # This allows forks to add custom defaults without modifying this template.
    #
    # HOOK SCRIPT PATHS AND [ALM] REPLACEMENT:
    # Hook script paths can use the [alm] placeholder to reference the ALM4Dataverse
    # repository root. For example:
    #   '[alm]/custom-hooks/myScript.ps1' -> executes the script from the fork's copy of ALM4Dataverse
    # This is useful for running custom hook scripts provided by the ALM4Dataverse fork.
    # The placeholder is replaced with the absolute path to the ALM repo root before execution.

    # Solutions to process, in dependency order.
    # Each entry is a hashtable with keys
    # - name: unique solution name.
    # - deployUnmanaged: (optional) boolean indicating whether to deploy unmanaged version.
    # - serviceAccountUpnConfigKey: (optional) name of the environment configuration key containing
    #   the service account UPN to use when activating processes in this solution.
    #   The default is 'ServiceAccountUpn'
    solutions = @(
    )


    # Extra folders/files to include in build artifacts (copied verbatim).
    assets = @(
        'data'
    )

    # Hook scripts executed by the pipeline scripts.
    #
    # Each hook is a list of script paths (relative to repo/artifact root).
    # Hooks are optional; leave them empty (@()) when not needed.
    #
    # Hook scripts receive a -Context parameter with a hashtable containing:
    # - HookType: the type of hook being executed
    # - BaseDirectory: the base directory for the hook (source or artifacts root)
    # - Config: the loaded alm-config.psd1 configuration
    # - Additional context specific to the hook type (see details below)
    #
    # Hook-specific context:
    #
    # preBuild, postBuild:
    #   - SourceDirectory: path to the source directory
    #   - ArtifactStagingDirectory: path to the artifact staging directory
    #
    # preExport, postExport:
    #   - SourceDirectory: path to the source directory
    #   - ArtifactStagingDirectory: path to the artifact staging directory
    #   - TempDirectory: path to temporary directory for export operations
    #   - EnvironmentName: name of the Dataverse environment being exported from
    #
    # preDeploy, dataMigrations, postDeploy:
    #   - ArtifactsPath: path to the artifacts directory
    #   - UseUnmanagedSolutions: boolean indicating if unmanaged solutions are being deployed
    #
    hooks = @{
        # Called by `pipelines/scripts/export.ps1` before exporting solutions.
        preExport  = @()

        # Called by `pipelines/scripts/export.ps1` after exporting/unpacking/version bump logic.
        postExport = @(
            'data/system/export.ps1'
        )

        # Called by `pipelines/scripts/deploy.ps1` before staging/importing solutions.
        preDeploy  = @()

        # Called by `pipelines/scripts/deploy.ps1` after publish customizations.
        postDeploy = @(
            'data/system/import.ps1'
        )

        # Called by `pipelines/scripts/build.ps1` before packing solutions.
        preBuild   = @()

        # Called by `pipelines/scripts/build.ps1` after packing solutions/copying assets.
        postBuild  = @()

        # Called by `pipelines/scripts/deploy.ps1` after solutions are staged but before upgrades.
        # Use this for data migration scripts (e.g., moving data from one column to another before they disappear).
        dataMigrations = @()
    }

    # PowerShell modules required by the scripts.
    # Key = module name, 
    # Value = version ('' = latest stable version, 'prerelease' = latest prerelease, or specific version).
    scriptDependencies = @{
        'Rnwood.Dataverse.Data.PowerShell' = '2.12.1'
    }
}
