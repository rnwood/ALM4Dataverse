# Playwright Tests Before Export

Running Playwright tests as a `preExport` hook lets you validate the state of your dev environment before its solutions are captured. If any tests fail, the export is aborted, ensuring you only version a working environment.

## Configuration

### alm-config.psd1

Register the hook script in your `alm-config.psd1`:

*alm-config.psd1 (partial content)*

```powershell
hooks = @{
    preExport = @('tests/playwright/run-tests.ps1')
}
```

### Pipeline secrets

Store the test account credentials as variables in the `Environment-Dev-<branch>` variable group in Azure DevOps. Mark the password and TOTP seed as **secret**.

| Variable name | Secret | Description |
|---|---|---|
| `PLAYWRIGHT_USERNAME` | No | UPN of the test account (e.g. `testuser@contoso.com`) |
| `PLAYWRIGHT_PASSWORD` | Yes | Password for the test account |
| `PLAYWRIGHT_TOTP_SECRET` | Yes | Base-32 TOTP seed for the test account's authenticator app |

> **Note:** Azure DevOps does **not** automatically expose secret variables as environment variables in script steps. You must explicitly map them in the pipeline YAML (see below). Non-secret variables such as `PLAYWRIGHT_USERNAME` are available automatically.

### EXPORT.yml — exposing secrets to the hook

The `export.yml` template accepts an optional `env` parameter. Use it to pass the secret variables into the pipeline step so your hook script can read them:

*pipelines/EXPORT.yml (your copy)*

```yaml
trigger: none
name: Export from Dev-${{ variables['Build.SourceBranchName'] }}
appendCommitMessageToRunName: false

resources:
  repositories:
    - repository: ALM4Dataverse
      type: git
      name: ALM4Dataverse

parameters:
- name: commitMessage
  type: string
  displayName: 'Commit message for exported changes'

stages:
- template: pipelines/templates/export.yml@ALM4Dataverse
  parameters:
    commitMessage: ${{ parameters.commitMessage }}
    env:
      PLAYWRIGHT_BASE_URL: $(ALM4DataverseSetConnectionVariables.EnvironmentUrl)
      PLAYWRIGHT_PASSWORD: $(PLAYWRIGHT_PASSWORD)
      PLAYWRIGHT_TOTP_SECRET: $(PLAYWRIGHT_TOTP_SECRET)
```

`$(ALM4DataverseSetConnectionVariables.EnvironmentUrl)` is an output variable set by the **Set Connection Variables** step earlier in the job and contains the Dataverse environment URL (e.g. `https://contoso.crm.dynamics.com/`). Passing it here makes the correct base URL available to Playwright automatically.

## Hook script

*tests/playwright/run-tests.ps1*

```powershell
param(
    [Parameter(Mandatory=$true)]
    [hashtable]$Context
)

$ErrorActionPreference = 'Stop'

# Tell playwright.config.ts where to write each report so they land in the
# artifact staging directory and can be picked up by the publish commands below.
$reportDir = Join-Path $Context.ArtifactStagingDirectory 'playwright-report'
$junitFile = Join-Path $Context.ArtifactStagingDirectory 'playwright-results' 'results.xml'

$env:PLAYWRIGHT_HTML_OUTPUT_DIR  = $reportDir
$env:PLAYWRIGHT_JUNIT_OUTPUT_FILE = $junitFile

Push-Location $PSScriptRoot
try {
    # Performs a clean install from package-lock.json (uses npm cache when available)
    npm ci

    # Run the tests; do not throw immediately so the report is always uploaded
    npx playwright test
    $playwrightExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

# Publish the HTML report as a build artifact
if (Test-Path $reportDir) {
    Write-Host "##vso[artifact.upload containerfolder=playwright-report;artifactname=playwright-report]$reportDir"
}

# Publish JUnit results so Azure DevOps shows a Tests tab on the run
if (Test-Path $junitFile) {
    Write-Host "##vso[results.publish type=JUnit;mergeResults=true;testRunTitle=Playwright Tests]$junitFile"
}

if ($playwrightExitCode -ne 0) {
    throw "Playwright tests failed (exit code $playwrightExitCode). Export aborted."
}
```

## Playwright configuration

*tests/playwright/playwright.config.ts*

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  retries: 0,
  workers: 1,

  // The base URL is supplied by the pipeline via the PLAYWRIGHT_BASE_URL env var.
  // Locally you can set it in a .env file or export it before running tests.
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL,
    trace: 'on-first-retry',
  },

  reporter: [
    // Output paths are set by the hook script via env vars so that reports
    // land in the artifact staging directory.  Defaults are used locally.
    ['html', {
      outputFolder: process.env.PLAYWRIGHT_HTML_OUTPUT_DIR ?? 'playwright-report',
      open: 'never',
    }],
    ['junit', {
      outputFile: process.env.PLAYWRIGHT_JUNIT_OUTPUT_FILE ?? 'test-results/results.xml',
    }],
  ],

  projects: [
    // Authentication setup runs once before all tests
    { name: 'setup', testMatch: /.*\.setup\.ts/ },

    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        storageState: '.auth/user.json',
      },
      dependencies: ['setup'],
    },
  ],
});
```

## Login with TOTP

Use a [global setup project](https://playwright.dev/docs/auth#basic-shared-account-in-all-workers) to log in once and reuse the authentication state across all tests.

The example below handles a standard Microsoft Entra ID login page that may prompt for a TOTP code. All credentials are read from the `PLAYWRIGHT_` prefixed environment variables exposed in the pipeline.

*tests/playwright/auth.setup.ts*

```typescript
import { test as setup, expect } from '@playwright/test';
import { authenticator } from 'otplib';
import * as path from 'path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('authenticate', async ({ page }) => {
  const username = process.env.PLAYWRIGHT_USERNAME;
  const password = process.env.PLAYWRIGHT_PASSWORD;
  const totpSecret = process.env.PLAYWRIGHT_TOTP_SECRET;

  if (!username) throw new Error('PLAYWRIGHT_USERNAME environment variable is required');
  if (!password) throw new Error('PLAYWRIGHT_PASSWORD environment variable is required');
  if (!totpSecret) throw new Error('PLAYWRIGHT_TOTP_SECRET environment variable is required');

  // Navigate to the application — baseURL is set in playwright.config.ts
  await page.goto('/');

  // --- Username ---
  await page.getByPlaceholder('Email, phone, or Skype').fill(username);
  await page.getByRole('button', { name: 'Next' }).click();

  // --- Password ---
  await page.getByPlaceholder('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();

  // --- TOTP (if prompted) ---
  // The authenticator app code is generated from the TOTP secret.
  // Install otplib: npm install otplib
  const totpCode = authenticator.generate(totpSecret);
  const totpInput = page.getByPlaceholder(/code/i);
  if (await totpInput.isVisible({ timeout: 5000 }).catch(() => false)) {
    await totpInput.fill(totpCode);
    await page.getByRole('button', { name: /verify|next/i }).click();
  }

  // --- Stay signed in prompt ---
  const staySignedIn = page.getByRole('button', { name: "Yes" });
  if (await staySignedIn.isVisible({ timeout: 3000 }).catch(() => false)) {
    await staySignedIn.click();
  }

  // Save the signed-in browser state for reuse by other tests
  // Wait until we are no longer on any Microsoft login page
  await page.waitForURL(url => !url.includes('login.microsoftonline.com'));
  await page.context().storageState({ path: authFile });
});
```

Add `otplib` to your project's `package.json`:

```json
{
  "devDependencies": {
    "@playwright/test": "^1.44.0",
    "otplib": "^12.0.1"
  }
}
```

> **Tip:** Make sure `.auth/` is listed in your `.gitignore` — it contains browser cookies and tokens that should never be committed.

## Test report

The hook script uploads two artifacts automatically using Azure DevOps logging commands — no extra pipeline steps are needed:

- **`playwright-report`** — the interactive HTML report, visible on the pipeline run's **Artifacts** tab.
- **Playwright Tests** — JUnit results parsed by Azure DevOps and shown on the pipeline run's **Tests** tab.

If any tests fail, the hook throws an error which aborts the export and marks the pipeline run as failed.
