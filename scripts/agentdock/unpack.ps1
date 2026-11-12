[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $PackageDir,
    [Parameter(Mandatory = $true)] [string] $SetupPath
)

$ErrorActionPreference = 'Stop'
$PackageDir = [IO.Path]::GetFullPath($PackageDir)
$staging = Join-Path $PackageDir '_setup'
Expand-InnoArchive -Path $SetupPath -DestinationPath $staging -ExtractDir '{tmp}'
$archive = Join-Path $staging 'agentdock_windows_amd64.zip'
$expected = ((Get-Content -LiteralPath "$archive.sha256" -Raw).Trim() -split '\s+')[0]
if ($expected -notmatch '^[a-fA-F0-9]{64}$' -or
    (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) {
    throw 'AgentDock embedded ZIP checksum mismatch.'
}

Expand-7zipArchive -Path $archive -DestinationPath $PackageDir
foreach ($required in @('agentdock.exe', 'control-panel\agentdock-tray.exe', 'share\agentdock\core-skills\manifest.json')) {
    if (!(Test-Path -LiteralPath (Join-Path $PackageDir $required) -PathType Leaf)) {
        throw "AgentDock embedded ZIP is missing $required"
    }
}

# Run the upstream prerequisite checker separately: it exits its PowerShell host.
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $staging 'ensure-windows-runtimes.ps1') -Architecture amd64 -MetadataPath (Join-Path $staging 'runtime-dependencies.json') -PayloadArchivePath $archive -ResultFile (Join-Path $staging 'runtime-result.ini')
if ($LASTEXITCODE -ne 0) {
    throw 'AgentDock Microsoft runtime prerequisite check failed; the existing installation was not stopped.'
}

Remove-Item -LiteralPath $staging -Recurse -Force
Remove-Item -LiteralPath $SetupPath -Force
