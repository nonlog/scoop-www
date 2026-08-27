[CmdletBinding()]
param(
    [string] $RuntimeRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    $RuntimeRoot = Split-Path -Parent $PSCommandPath
}
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$runtimeManifestPath = Join-Path $RuntimeRoot 'runtime.json'
$logsDir = Join-Path $RuntimeRoot 'logs'
$logPath = Join-Path $logsDir 'tunnel-self-heal.log'

function Write-SelfHealLog {
    param([string] $Message)

    try {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        if ((Test-Path -LiteralPath $logPath -PathType Leaf) -and (Get-Item -LiteralPath $logPath).Length -gt 1048576) {
            $previous = "$logPath.1"
            Remove-Item -LiteralPath $previous -Force -ErrorAction SilentlyContinue
            Move-Item -LiteralPath $logPath -Destination $previous -Force
        }
        Add-Content -LiteralPath $logPath -Encoding UTF8 -Value ('{0} {1}' -f (Get-Date -Format o), $Message)
    } catch {
    }
}

if (-not (Test-Path -LiteralPath $runtimeManifestPath -PathType Leaf)) {
    exit 0
}

try {
    $manifest = Get-Content -LiteralPath $runtimeManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $agentDockBinary = [string] $manifest.agentdock_binary
    if (-not (Test-Path -LiteralPath $agentDockBinary -PathType Leaf)) {
        exit 0
    }

    $rawStatus = & $agentDockBinary tunnel status --runtime-root $RuntimeRoot 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($rawStatus -join ''))) {
        exit 0
    }
    $status = (($rawStatus -join [Environment]::NewLine) | ConvertFrom-Json)

    # Respect the user's AgentDock autostart setting. A deliberate disable or
    # stop must not be undone by the self-heal task.
    if (-not [bool] $status.startup_enabled -or [bool] $status.running) {
        exit 0
    }

    Write-SelfHealLog 'tunnel missing; requesting recovery through agentdock tunnel start'
    & $agentDockBinary tunnel start --runtime-root $RuntimeRoot | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-SelfHealLog 'tunnel start command completed'
    } else {
        Write-SelfHealLog "tunnel start command failed, exit code=$LASTEXITCODE"
    }
    exit 0
} catch {
    Write-SelfHealLog "self-heal check failed: $($_.Exception.Message)"
    exit 0
}
