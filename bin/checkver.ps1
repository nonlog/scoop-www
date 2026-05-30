if (!$env:SCOOP) {
    $userScoop = Join-Path $env:USERPROFILE 'scoop'
    if (Test-Path 'D:\Programs\Scoop') {
        $env:SCOOP = 'D:\Programs\Scoop'
    } else {
        $env:SCOOP = $userScoop
    }
}

if (!$env:SCOOP_HOME) {
    $env:SCOOP_HOME = Join-Path $env:SCOOP 'apps\scoop\current'
}

$scoopShims = Join-Path $env:SCOOP 'shims'
if ((Test-Path $scoopShims) -and $env:Path -notlike "*$scoopShims*") {
    $env:Path = "$scoopShims;$env:Path"
}

$checkver = Join-Path $env:SCOOP_HOME 'bin\checkver.ps1'
if (!(Test-Path $checkver)) {
    throw "Scoop checkver was not found at $checkver"
}

$dir = Join-Path $PSScriptRoot '..\bucket'
& $checkver -Dir $dir @args
