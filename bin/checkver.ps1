if (!$env:SCOOP) { $env:SCOOP = 'D:\Programs\Scoop' }
if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Join-Path $env:SCOOP 'apps\scoop\current' }

$scoopShims = Join-Path $env:SCOOP 'shims'
if ($env:Path -notlike "*$scoopShims*") {
    $env:Path = "$scoopShims;$env:Path"
}

$checkver = Join-Path $env:SCOOP_HOME 'bin\checkver.ps1'
$dir = Join-Path $PSScriptRoot '..\bucket'
& $checkver -Dir $dir @args
