param(
    [Parameter(Mandatory = $true)]
    [string] $Dir
)

$ErrorActionPreference = 'Stop'
$installer = Get-ChildItem -LiteralPath $Dir -File -Filter '*.exe' |
    Where-Object { $_.Name -ne 'SoundInstaller.exe' } |
    Select-Object -First 1
if (-not $installer) { throw 'SoundInstaller installer executable was not found.' }

$x86PowerShell = Join-Path $env:WINDIR 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $x86PowerShell)) { throw '32-bit Windows PowerShell is required to read the installer resource.' }

$archive = Join-Path $env:TEMP "shilan-sound-$PID.zip"
$helper = Join-Path $env:TEMP "shilan-sound-$PID.ps1"
$helperSource = @'
param([string] $Installer, [string] $Output)
$assembly = [Reflection.Assembly]::LoadFrom($Installer)
$stream = $assembly.GetManifestResourceStream('SoundInstaller.Installer.Resources.Build.zip')
if (-not $stream) { throw 'Embedded SoundInstaller build was not found.' }
$file = [IO.File]::Create($Output)
try { $stream.CopyTo($file) } finally { $file.Dispose(); $stream.Dispose() }
'@

try {
    Set-Content -LiteralPath $helper -Value $helperSource -Encoding UTF8
    & $x86PowerShell -NoProfile -ExecutionPolicy Bypass -File $helper $installer.FullName $archive
    if ($LASTEXITCODE -ne 0) { throw "Failed to extract embedded build (exit code $LASTEXITCODE)." }

    $stage = Join-Path $env:TEMP "shilan-sound-stage-$PID"
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        7z.exe x $archive "-o$stage" -y | Out-Null
        Get-ChildItem -LiteralPath $Dir -Force |
            Where-Object { $_.Name -notin @('scoop-manifest.json', 'scoop-install.json') } |
            Remove-Item -Recurse -Force
        Get-ChildItem -LiteralPath $stage -Force | Move-Item -Destination $Dir -Force
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    }
} finally {
    Remove-Item -LiteralPath $archive, $helper, $installer.FullName -Force -ErrorAction SilentlyContinue
}
