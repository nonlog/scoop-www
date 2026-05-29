param(
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

$bucketRoot = $PSScriptRoot
$manifest = Join-Path $bucketRoot 'bucket\uotantoolbox.json'
$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { 'D:\Programs\Scoop' }
$scoop = Join-Path $scoopRoot 'shims\scoop.ps1'
$scoopHome = Join-Path $scoopRoot 'apps\scoop\current'
$checkver = Join-Path $scoopHome 'bin\checkver.ps1'
$scoopShims = Join-Path $scoopRoot 'shims'

if (!(Test-Path -LiteralPath $scoop)) {
    throw "Scoop was not found at $scoop"
}
if (!(Test-Path -LiteralPath $checkver)) {
    throw "Scoop checkver helper was not found at $checkver"
}
if (!(Test-Path -LiteralPath $manifest)) {
    throw "Manifest was not found at $manifest"
}

$env:SCOOP = $scoopRoot
$env:SCOOP_HOME = $scoopHome
if ($env:Path -notlike "*$scoopShims*") {
    $env:Path = "$scoopShims;$env:Path"
}

Push-Location $bucketRoot
try {
    $dirtyBefore = git status --porcelain
    if ($dirtyBefore) {
        throw "The www bucket has uncommitted changes. Commit or discard them before running this updater.`n$dirtyBefore"
    }

    $argsForCheckver = @('uotantoolbox', '-Dir', (Join-Path $bucketRoot 'bucket'), '-Update')
    if ($Force) {
        $argsForCheckver[-1] = '-ForceUpdate'
    }

    & $checkver @argsForCheckver

    $dirtyAfter = git status --porcelain
    if ($dirtyAfter) {
        $version = (Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json).version
        git add bucket\uotantoolbox.json
        git commit -m "Update Uotan Toolbox to $version"
        & $scoop update
    } else {
        Write-Host 'Uotan Toolbox manifest is already current.'
    }

    & $scoop update uotantoolbox
    & $scoop status
} finally {
    Pop-Location
}
