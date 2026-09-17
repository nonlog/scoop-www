[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Backup', 'Restore')]
    [string] $Phase,

    [Parameter(Mandatory = $true)]
    [string] $PersistDir,

    [string] $PackageDir
)

$ErrorActionPreference = 'Stop'
$localState = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.CommandPalette_8wekyb3d8bbwe\LocalState'
$backupDir = Join-Path $PersistDir 'command-palette'

function Copy-StateFile {
    param([string] $Source, [string] $Destination)

    if (Test-Path -LiteralPath $Source -PathType Leaf) {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

if ($Phase -eq 'Backup') {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach ($file in @('settings.json', 'state.json')) {
        Copy-StateFile -Source (Join-Path $localState $file) -Destination (Join-Path $backupDir $file)
    }
    return
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    throw 'PackageDir is required when restoring Command Palette.'
}

$msix = @(Get-ChildItem -LiteralPath (Join-Path $PackageDir 'WinUI3Apps\CmdPal') -Filter 'Microsoft.CmdPal.UI_*.msix' -File)
if ($msix.Count -ne 1) {
    throw 'Expected exactly one bundled Command Palette MSIX.'
}

if ($PSVersionTable.PSVersion.Major -ge 6) {
    Import-Module Appx -UseWindowsPowerShell 3>$null
}

Add-AppxPackage -Path $msix[0].FullName -ForceApplicationShutdown | Out-Null

$backupSettings = Join-Path $backupDir 'settings.json'
$targetSettings = Join-Path $localState 'settings.json'
if (Test-Path -LiteralPath $backupSettings -PathType Leaf) {
    New-Item -ItemType Directory -Path $localState -Force | Out-Null
    Copy-StateFile -Source $backupSettings -Destination $targetSettings
}

$backupState = Join-Path $backupDir 'state.json'
$targetState = Join-Path $localState 'state.json'
if (Test-Path -LiteralPath $backupState -PathType Leaf) {
    New-Item -ItemType Directory -Path $localState -Force | Out-Null
    Copy-StateFile -Source $backupState -Destination $targetState
}
