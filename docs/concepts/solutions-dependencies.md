# Solutions and Dependencies

This document explains how ALM4Dataverse handles multiple Dataverse solutions and their dependencies.

## Solution Configuration

Solutions are configured in the `alm-config.psd1` file in your repository root:

```powershell
@{
    solutions = @(
        @{
            name = 'CoreSolution'
        }
        @{
            name = 'ExtensionSolution'
            deployUnmanaged = $false
            serviceAccountUpnConfigKey = 'ExtensionServiceAccountUpn'
        }
    )
}
```

### Configuration Properties

| Property | Required | Default | Description |
|----------|----------|---------|-------------|
| `name` | Yes | - | The unique name of the Dataverse solution |
| `deployUnmanaged` | No | `$false` | Deploy unmanaged instead of managed |
| `serviceAccountUpnConfigKey` | No | `'ServiceAccountUpn'` | Environment variable key for the service account UPN |

## Dependency Order

**Critical**: Solutions must be listed in dependency order in `alm-config.psd1`.

Solutions are:
- **Exported** in the order listed (dependencies first)
- **Imported** in the order listed (dependencies first)
- **Upgraded** in reverse order (dependent solutions first)

### Example Dependency Chain

```
CoreSolution          (no dependencies)
     │
     ▼
IntegrationSolution   (depends on CoreSolution)
     │
     ▼
UIExtensionSolution   (depends on IntegrationSolution)
```

Configuration:
```powershell
solutions = @(
    @{ name = 'CoreSolution' }
    @{ name = 'IntegrationSolution' }
    @{ name = 'UIExtensionSolution' }
)
```

## Managed vs. Unmanaged Solutions

### Managed Solutions (Default)

- Used for deployment to TEST, UAT, PROD environments
- Cannot be directly edited in target environment
- Upgrades replace all components
- Provides clean separation between environments

### Unmanaged Solutions

- Used for development environments
- Can be edited directly
- Set `deployUnmanaged = $true` for solutions that need local customization
- IMPORT pipeline always uses unmanaged

## Solution Import Behavior

ALM4Dataverse intelligently handles solution imports:

### Skip If Same Version

If the solution version in the environment matches the artifact version, the import is skipped. This optimizes deployment time and reduces risk.

### Update vs. Upgrade

| Condition | Import Method | Behavior |
|-----------|---------------|----------|
| Major.Minor matches | Update | Fast, preserves customizations |
| Major.Minor differs | Upgrade | Full replacement via holding solution |
| New solution | Install | Fresh installation |

### Holding Solution Strategy

When upgrading multiple solutions:

1. All solutions are first imported as holding solutions
2. Data migrations run while both versions exist
3. Upgrades are applied in reverse dependency order
4. This ensures dependent components exist throughout the process

## Service Account Configuration

Each solution can specify which service account to use for activating workflows and flows.

### Default Behavior

By default, all solutions use the `ServiceAccountUpn` environment variable.

### Custom Service Accounts

For solutions requiring different ownership:

```powershell
@{
    solutions = @(
        @{
            name = 'IntegrationSolution'
            serviceAccountUpnConfigKey = 'IntegrationServiceAccountUpn'
        }
    )
}
```

Add the corresponding variable to your environment variable groups:
- `Environment-Dev-main`: `IntegrationServiceAccountUpn = integration@contoso.com`
- `Environment-PROD`: `IntegrationServiceAccountUpn = integration-prod@contoso.com`

## Solution Source Structure

After export, each solution is stored in a folder structure:

```
solutions/
├── MySolution/
│   ├── Other/
│   │   ├── Solution.xml
│   │   ├── Customizations.xml
│   │   └── Relationships.xml
│   ├── Entities/
│   │   └── account/
│   │       ├── Entity.xml
│   │       └── FormXml/
│   ├── Workflows/
│   ├── CanvasApps/
│   │   └── myapp_DocumentUri.msapp/  (unpacked)
│   └── ...
└── AnotherSolution/
    └── ...
```

### Canvas App Handling

Canvas apps (`.msapp` files) are automatically unpacked during export and repacked during build. This enables:
- Meaningful diffs in source control
- Code review of canvas app changes
- Merge conflict resolution

## Best Practices

### 1. Keep Dependencies Minimal

Minimize cross-solution dependencies to reduce complexity and deployment time.

### 2. Use Layered Architecture

```
Base/Core Layer        (rarely changes)
     │
Integration Layer      (integration logic)
     │
Customization Layer    (frequently changes)
```

### 3. Version Strategically

- Manual major version bumps for breaking changes to dependent solutions
- Let the system auto-increment for normal changes

### 4. Test Independently

Each solution should be testable in isolation where possible.

### 5. Document Dependencies

Keep a dependency diagram updated as your solution architecture evolves.
