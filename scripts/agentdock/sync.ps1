[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('pre', 'post')]
    [string] $Phase,

    [Parameter(Mandatory = $true)]
    [string] $PackageDir,

    [string] $RuntimeRoot = 'D:\Programs\Scoop\persist\agentdock'
)

$ErrorActionPreference = 'Stop'
$PackageDir = [IO.Path]::GetFullPath($PackageDir)
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
$statePath = Join-Path ([IO.Path]::GetTempPath()) 'agentdock-scoop-state.json'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

$agent = Join-Path $PackageDir 'agentdock.exe'
$tray = Join-Path $PackageDir 'agentdock-tray.exe'
$oldAgent = 'D:\Programs\AgentDock\bin\agentdock.exe'
$oldTray = 'D:\Programs\AgentDock\bin\agentdock-tray.exe'
$manager = Join-Path $RuntimeRoot 'installer\manage-windows.ps1'
$coreLauncher = Join-Path $RuntimeRoot 'start-agentdock.ps1'
$tunnelLauncher = Join-Path $RuntimeRoot 'start-cloudflared.ps1'
$trayLauncher = Join-Path $RuntimeRoot 'start-agentdock-tray.ps1'
$runtimeManifestPath = Join-Path $RuntimeRoot 'runtime.json'
$wingetCloudflared = 'C:\Program Files (x86)\cloudflared\cloudflared.exe'

function Get-ProcessesAtPath {
    param(
        [string] $Name,
        [string[]] $Paths
    )

    $normalized = @($Paths | Where-Object { $_ } | ForEach-Object { [IO.Path]::GetFullPath($_) })
    return @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq "$Name.exe" -and $_.ExecutablePath -and
        ($normalized -contains [IO.Path]::GetFullPath($_.ExecutablePath))
    })
}

function Test-RunValue {
    param([string] $Name)
    try {
        $value = (Get-ItemProperty -LiteralPath $runKey -Name $Name -ErrorAction Stop).$Name
        return -not [string]::IsNullOrWhiteSpace([string] $value)
    } catch {
        return $false
    }
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [psobject] $Object,
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [AllowNull()] $Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    } else {
        $property.Value = $Value
    }
}

function Start-HiddenPowerShell {
    param([string] $ScriptPath)

    $pwsh = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $pwsh -ArgumentList @(
        '-NoLogo', '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath
    ) -WindowStyle Hidden | Out-Null
}

if ($Phase -eq 'pre') {
    if (-not (Test-Path -LiteralPath $runtimeManifestPath -PathType Leaf)) {
        throw "现有 AgentDock 运行目录不存在 runtime.json：$RuntimeRoot"
    }

    $runtime = Get-Content -LiteralPath $runtimeManifestPath -Raw | ConvertFrom-Json
    $runtimeAgent = [string] $runtime.agentdock_binary
    $runtimeTray = [string] $runtime.tray_binary
    $corePaths = @($agent, $runtimeAgent, $oldAgent)
    $trayPaths = @($tray, $runtimeTray, $oldTray)
    $coreProcesses = @(Get-ProcessesAtPath -Name 'agentdock' -Paths $corePaths)
    $trayProcesses = @(Get-ProcessesAtPath -Name 'agentdock-tray' -Paths $trayPaths)
    $cloudProcesses = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'cloudflared.exe' -and $_.ExecutablePath -and
        ([IO.Path]::GetFullPath($_.ExecutablePath) -eq [IO.Path]::GetFullPath($wingetCloudflared))
    })

    $coreStartup = Test-RunValue -Name 'AgentDock'
    $tunnelStartup = Test-RunValue -Name 'AgentDockCloudflared'
    try {
        $serviceStatus = (& $runtimeAgent service status --runtime-root $RuntimeRoot 2>$null | ConvertFrom-Json)
        $coreStartup = [bool] $serviceStatus.startup_enabled
    } catch {
    }
    try {
        $tunnelStatus = (& $runtimeAgent tunnel status --runtime-root $RuntimeRoot 2>$null | ConvertFrom-Json)
        $tunnelStartup = [bool] $tunnelStatus.startup_enabled
    } catch {
    }

    $state = [ordered]@{
        CoreRunning = ($coreProcesses.Count -gt 0)
        TrayRunning = ($trayProcesses.Count -gt 0)
        TunnelRunning = ($cloudProcesses.Count -gt 0)
        CoreStartup = $coreStartup
        TrayStartup = (Test-RunValue -Name 'AgentDockTray')
        TunnelStartup = $tunnelStartup
    }
    Write-Utf8NoBom -Path $statePath -Content ($state | ConvertTo-Json)

    foreach ($process in @($trayProcesses + $coreProcesses)) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
        $remaining = @(
            Get-ProcessesAtPath -Name 'agentdock' -Paths $corePaths +
            Get-ProcessesAtPath -Name 'agentdock-tray' -Paths $trayPaths
        )
        if ($remaining.Count -eq 0) {
            break
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    if ($remaining.Count -ne 0) {
        throw 'AgentDock 或托盘进程未在 15 秒内退出。'
    }
    return
}

foreach ($path in @(
    (Join-Path $PackageDir 'agentdock.exe'),
    (Join-Path $PackageDir 'agentdock-tray.exe'),
    (Join-Path $PackageDir 'agentdock.ico'),
    (Join-Path $PackageDir 'manage-windows.ps1'),
    (Join-Path $PackageDir 'share\agentdock\core-skills\manifest.json')
)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Scoop 包缺少必需文件：$path"
    }
}
if (-not (Test-Path -LiteralPath $wingetCloudflared -PathType Leaf)) {
    throw "找不到 Winget 管理的 cloudflared：$wingetCloudflared"
}

$state = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}
if ($null -eq $state) {
    $state = [pscustomobject]@{
        CoreRunning = $true
        TrayRunning = $true
        TunnelRunning = $true
        CoreStartup = $true
        TrayStartup = $true
        TunnelStartup = $true
    }
}

$installerDir = Join-Path $RuntimeRoot 'installer'
$shareDir = Join-Path $RuntimeRoot 'share'
$logsDir = Join-Path $RuntimeRoot 'logs'
New-Item -ItemType Directory -Path $RuntimeRoot, $installerDir, $shareDir, $logsDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $PackageDir 'agentdock.ico') -Destination (Join-Path $RuntimeRoot 'agentdock.ico') -Force
Copy-Item -LiteralPath (Join-Path $PackageDir 'manage-windows.ps1') -Destination (Join-Path $RuntimeRoot 'manage-windows.ps1') -Force
Copy-Item -LiteralPath (Join-Path $PackageDir 'manage-windows.ps1') -Destination (Join-Path $installerDir 'manage-windows.ps1') -Force
Copy-Item -Path (Join-Path $PackageDir 'share\*') -Destination $shareDir -Recurse -Force

if (Test-Path -LiteralPath $runtimeManifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $runtimeManifestPath -Raw | ConvertFrom-Json
} else {
    $manifest = [pscustomobject]@{
        schema_version = 1
        host = '127.0.0.1'
        port = 8765
        local_mcp_url = 'http://127.0.0.1:8765/mcp'
        tunnel_mode = 'named'
        public_url = ''
        privilege_mode = 'standard'
    }
}

Set-JsonProperty -Object $manifest -Name 'agentdock_binary' -Value $agent
Set-JsonProperty -Object $manifest -Name 'tray_binary' -Value $tray
Set-JsonProperty -Object $manifest -Name 'agentdock_launcher' -Value $coreLauncher
Set-JsonProperty -Object $manifest -Name 'cloudflared_binary' -Value $wingetCloudflared
Set-JsonProperty -Object $manifest -Name 'cloudflared_launcher' -Value $tunnelLauncher
Set-JsonProperty -Object $manifest -Name 'install_channel' -Value 'scoop'
$tmpManifest = "$runtimeManifestPath.scoop.tmp"
Write-Utf8NoBom -Path $tmpManifest -Content ($manifest | ConvertTo-Json -Depth 20)
Move-Item -LiteralPath $tmpManifest -Destination $runtimeManifestPath -Force

$settings = $null
$settingsPath = Join-Path $RuntimeRoot 'control-panel-settings.json'
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
}
$port = [int] $manifest.port
if ($port -lt 1 -or $port -gt 65535) {
    $port = 8765
}
if ($settings -and $settings.port -ge 1 -and $settings.port -le 65535) {
    $port = [int] $settings.port
}

$coreLines = @(
    '$ErrorActionPreference = ''Stop''',
    ('$env:AGENTDOCK_RUNTIME_DIR = ''{0}''' -f $RuntimeRoot),
    ('$env:AGENTDOCK_PORT = ''{0}''' -f $port),
    ("& '{0}' service launch-core --runtime-root '{1}'" -f $agent, $RuntimeRoot),
    'exit $LASTEXITCODE'
)
Write-Utf8NoBom -Path $coreLauncher -Content ($coreLines -join [Environment]::NewLine)

$tunnelLines = @(
    '$ErrorActionPreference = ''Stop''',
    ("& '{0}' -Action launch-tunnel -RuntimeRoot '{1}'" -f $manager, $RuntimeRoot),
    'exit $LASTEXITCODE'
)
Write-Utf8NoBom -Path $tunnelLauncher -Content ($tunnelLines -join [Environment]::NewLine)

$trayLines = @(
    '$ErrorActionPreference = ''Stop''',
    ('$env:AGENTDOCK_RUNTIME_DIR = ''{0}''' -f $RuntimeRoot),
    ("& '{0}' --background" -f $tray),
    'exit $LASTEXITCODE'
)
Write-Utf8NoBom -Path $trayLauncher -Content ($trayLines -join [Environment]::NewLine)

[Environment]::SetEnvironmentVariable('AGENTDOCK_RUNTIME_DIR', $RuntimeRoot, 'User')
$env:AGENTDOCK_RUNTIME_DIR = $RuntimeRoot
if ([bool] $state.CoreRunning) {
    Start-HiddenPowerShell -ScriptPath $coreLauncher
}
if ([bool] $state.TrayRunning) {
    Start-Process -FilePath $tray -ArgumentList @('--background') -WindowStyle Hidden | Out-Null
}
if (-not [bool] $state.TunnelRunning -and [bool] $state.TunnelStartup) {
    Start-Process -FilePath $tray -ArgumentList @('--start-tunnel', '--runtime-root', $RuntimeRoot) -WindowStyle Hidden | Out-Null
}

if ([bool] $state.CoreRunning) {
    $healthy = $false
    for ($i = 0; $i -lt 40; $i++) {
        try {
            $response = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/healthz" -f $port) -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) {
                $healthy = $true
                break
            }
        } catch {
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $healthy) {
        throw ("AgentDock 未能在 127.0.0.1:{0} 恢复健康。" -f $port)
    }
}

# Restore startup through AgentDock's native registration commands. This keeps
# logon entries on agentdock-tray.exe instead of long-lived PowerShell wrappers,
# and lets elevated core startup remain owned by AgentDock's scheduled task.
$coreStartupValue = ([bool] $state.CoreStartup).ToString().ToLowerInvariant()
$trayStartupValue = ([bool] $state.TrayStartup).ToString().ToLowerInvariant()
$tunnelStartupValue = ([bool] $state.TunnelStartup).ToString().ToLowerInvariant()

& $agent service autostart --runtime-root $RuntimeRoot --component core --enabled $coreStartupValue
if ($LASTEXITCODE -ne 0) {
    throw "AgentDock core 开机启动恢复失败，退出码：$LASTEXITCODE"
}
& $agent service autostart --runtime-root $RuntimeRoot --component tray --enabled $trayStartupValue
if ($LASTEXITCODE -ne 0) {
    throw "AgentDock tray 开机启动恢复失败，退出码：$LASTEXITCODE"
}
& $agent tunnel autostart --runtime-root $RuntimeRoot --enabled $tunnelStartupValue
if ($LASTEXITCODE -ne 0) {
    throw "AgentDock tunnel 开机启动恢复失败，退出码：$LASTEXITCODE"
}

Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
[pscustomobject]@{
    RuntimeRoot = $RuntimeRoot
    PackageDir = $PackageDir
    Cloudflared = $wingetCloudflared
    Health = if ([bool] $state.CoreRunning) { 'HTTP 200' } else { 'not-started-by-migration' }
} | Format-List
