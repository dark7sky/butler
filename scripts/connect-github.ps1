param(
    [Parameter(Mandatory = $true)]
    [string]$AppRepoUrl,
    [Parameter(Mandatory = $true)]
    [string]$LegacyRepoUrl
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$legacy = Join-Path $root "legacy\butler"

Write-Host "[1/4] Configure app repo remote..."
if (git -C $root remote | Select-String -Pattern "^origin$" -Quiet) {
    git -C $root remote set-url origin $AppRepoUrl
} else {
    git -C $root remote add origin $AppRepoUrl
}

Write-Host "[2/4] Configure legacy repo remote..."
if (git -C $legacy remote | Select-String -Pattern "^origin$" -Quiet) {
    git -C $legacy remote set-url origin $LegacyRepoUrl
} else {
    git -C $legacy remote add origin $LegacyRepoUrl
}

Write-Host "[3/4] Push app repo..."
git -C $root push -u origin main

Write-Host "[4/4] Push legacy repo..."
git -C $legacy push -u origin main

Write-Host "Done."
