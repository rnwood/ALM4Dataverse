#!/bin/bash
# Script to prepare setup.ps1 for release
# This extracts the release logic from the GitHub workflow for testability
#
# Usage: ./prepare-release.sh <tag-name> <output-dir> [upstream-repo-url]
#
# Arguments:
#   tag-name: The release tag (e.g., v1.0.0)
#   output-dir: Directory where the processed setup.ps1 will be written
#   upstream-repo-url: (Optional) URL of the upstream repository. Defaults to https://github.com/rnwood/ALM4Dataverse.git

set -e

# Function to display usage
usage() {
    echo "Usage: $0 <tag-name> <output-dir> [upstream-repo-url]"
    echo ""
    echo "Arguments:"
    echo "  tag-name          The release tag (e.g., v1.0.0)"
    echo "  output-dir        Directory where the processed setup.ps1 will be written"
    echo "  upstream-repo-url (Optional) URL of the upstream repository"
    echo "                    Defaults to https://github.com/rnwood/ALM4Dataverse.git"
    echo ""
    echo "Example:"
    echo "  $0 v1.2.3 ./release"
    echo "  $0 v1.2.3 ./release https://github.com/myorg/MyRepo.git"
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    usage
fi

TAG_NAME="$1"
OUTPUT_DIR="$2"
UPSTREAM_REPO="${3:-https://github.com/rnwood/ALM4Dataverse.git}"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "Preparing setup.ps1 for release"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Tag:          $TAG_NAME"
echo "  Output dir:   $OUTPUT_DIR"
echo "  Upstream URL: $UPSTREAM_REPO"
echo "  Script dir:   $SCRIPT_DIR"
echo ""

# Step 1: Extract Rnwood.Dataverse.Data.PowerShell version from alm-config-defaults.psd1
echo "Step 1: Extracting version from alm-config-defaults.psd1..."

CONFIG_FILE="$SCRIPT_DIR/alm-config-defaults.psd1"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Use PowerShell to reliably read the version from the config file
DATAVERSE_VERSION=$(pwsh -Command "
  \$config = Import-PowerShellDataFile -Path '$CONFIG_FILE'
  \$config.scriptDependencies.'Rnwood.Dataverse.Data.PowerShell'
")

if [ -z "$DATAVERSE_VERSION" ]; then
    echo "ERROR: Could not extract Rnwood.Dataverse.Data.PowerShell version from config file"
    exit 1
fi

echo "  Found version: $DATAVERSE_VERSION"
echo ""

# Step 2: Process setup.ps1 and replace placeholders
echo "Step 2: Processing setup.ps1..."

SETUP_FILE="$SCRIPT_DIR/setup.ps1"
if [ ! -f "$SETUP_FILE" ]; then
    echo "ERROR: Setup file not found: $SETUP_FILE"
    exit 1
fi

# Define placeholders
ALM4DATAVERSE_REF_PLACEHOLDER="__ALM4DATAVERSE_REF__"
RNWOOD_DATAVERSE_VERSION_PLACEHOLDER="__RNWOOD_DATAVERSE_VERSION__"
UPSTREAM_REPO_PLACEHOLDER="__UPSTREAM_REPO__"

# Create output directory
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/setup.ps1"

# Process setup.ps1 and replace placeholders
sed -e "s|${ALM4DATAVERSE_REF_PLACEHOLDER}|${TAG_NAME}|g" \
    -e "s|${RNWOOD_DATAVERSE_VERSION_PLACEHOLDER}|${DATAVERSE_VERSION}|g" \
    -e "s|${UPSTREAM_REPO_PLACEHOLDER}|${UPSTREAM_REPO}|g" \
    "$SETUP_FILE" > "$OUTPUT_FILE"

echo "  Processed setup.ps1 with:"
echo "    ALM4DATAVERSE_REF: $TAG_NAME"
echo "    RNWOOD_DATAVERSE_VERSION: $DATAVERSE_VERSION"
echo "    UPSTREAM_REPO: $UPSTREAM_REPO"
echo ""

# Step 3: Verify placeholders were replaced
echo "Step 3: Verifying placeholder replacement..."

if grep -q "${ALM4DATAVERSE_REF_PLACEHOLDER}\|${RNWOOD_DATAVERSE_VERSION_PLACEHOLDER}\|${UPSTREAM_REPO_PLACEHOLDER}" "$OUTPUT_FILE"; then
    echo "ERROR: Placeholders were not fully replaced!"
    echo "Remaining placeholders:"
    grep -n "${ALM4DATAVERSE_REF_PLACEHOLDER}\|${RNWOOD_DATAVERSE_VERSION_PLACEHOLDER}\|${UPSTREAM_REPO_PLACEHOLDER}" "$OUTPUT_FILE" || true
    exit 1
fi

echo "  ✓ All placeholders replaced successfully"
echo ""

# Step 4: Display summary
echo "=========================================="
echo "✓ Release preparation complete"
echo "=========================================="
echo ""
echo "Output file: $OUTPUT_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the processed file"
echo "  2. Upload to GitHub release as an asset"
echo ""
