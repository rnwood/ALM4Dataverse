@{
    # ALM for Dataverse configuration
    #
    # Paths in this file are relative to the repository root when running locally,
    # and relative to the artifact root when running in pipelines.

    # Solutions to process, in dependency order.
    # Each entry is a hashtable with keys
    # - name: unique solution name.
    # - deployUnmanaged: (optional) boolean indicating whether to deploy unmanaged version.
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
