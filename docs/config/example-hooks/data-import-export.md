# Data Import and Export for Config/System Data

For further information about this approach see the following articles:

- [Rob Wood - Versioning config data in D365/Power Apps - beyond the Configuration Migration Tool](https://rnwood.co.uk/posts/versioning-config-data-in-power-platform-beyond-the-cmt)
- [Rob Wood - Versioning config data in D365/Power Apps - beyond the CMT - part 2](https://rnwood.co.uk/posts/versioning-config-data-in-power-platform-beyond-the-cmt-part2/)

The following configuration is required to ensure the example scripts below are executed and that the resulting `data` folder is copied to build assets (so it's available to deploy from).

*alm-config.psd1 (partial content)*

```powershell
hooks = @{
    postExport     = @('data/system/export.ps1')
    postDeploy     = @('data/system/import.ps1')
}


assets = @(
    'data'
)
```

## Exporting

Add your tables with the pattern below, reproducing the block for each table. By default, all non-system columns will be output. You can add `-columns new_column1, new_column2` if you'd rather list them individually.

*data/system/export.ps1*

```
Get-DataverseRecord -TableName new_exampleconfigtable |
  Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_exampleconfigtable -withdeletions

Get-DataverseRecord -TableName new_anotherconfigtable |
  Set-DataverseRecordsFolder -OutputPath $PSScriptRoot/new_anotherconfigtable -withdeletions
```

When `EXPORT` runs, a folder will be created, with a JSON file representing each record. 

The filename is the ID of the record. For some records (for example Teams automatically created when Business Units are created) this is an unstable system generated value. You can specify a list of column names to `-idproperties` to use these instead. For example  `-idproperties new_name` or  `-idproperties firstname, lastname`

`-withdeletions` is optional. It records the records you've deleted in a subfolder called `deletions` so you can take action to mirror this as deletions or deactivations. See the section below for options when processing these.

## Importing/Deploying

Add your tables with the pattern below, reproducing the block for each table. Tables need to be in dependency order with those that reference others, below the tables they reference. (For tables with circular dependencies you need to use a two step approach by breaking the chain somewhere and then setting the final lookup field.)

*data/system/import.ps1*

```
### Phase 1 - Upsert new and updated records

Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_exampleconfigtable |
  Set-DataverseRecord -TableName new_exampleconfigtable -Verbose

Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_anotherconfigtable |
  Set-DataverseRecord -TableName new_anotherconfigtable -Verbose

### Phase 2 - Remove/deactivate deleted records

Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_exampleconfigtable -deletions |
     Remove-DataverseRecord -Connection $c -Verbose -IfExists

Get-DataverseRecordsFolder -InputPath $PSScriptRoot/new_anotherconfigtable -deletions | @{ $_.statuscode=1; $_ } | Set-DataverseRecord -Verbose
     
```

The first phase creates or updates records.

The standard process will upsert records matching them to existing records on the primary ID. This can be varied with the `-matchon` option for `Set-DataverseRecord`. For example `-matchon firstname, lastname`.

The second phase deals with any records that have been removed from the source. You can either delete them, deactivate them (and/or add custom logic to rename them with a prefix for example).


