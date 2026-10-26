param(
    [string] $Manifest = (Join-Path $PSScriptRoot '..\bucket\wechat.json'),
    [string] $Output = (Join-Path $PSScriptRoot '..\wechat-package.7z'),
    [string] $Metadata = (Join-Path $PSScriptRoot '..\wechat-metadata.json'),
    [string] $BetterWX,
    [string] $SourcePath,
    [string] $SourceUrl,
    [string] $DownloadPage = 'https://pc.weixin.qq.com/',
    [string] $Curl = 'curl.exe',
    [string] $SevenZip = '7z.exe'
)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param(
        [string] $FilePath,
        [string[]] $Arguments
    )

    $output = & $FilePath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE`n$($output -join "`n")"
    }
    return $output
}

function Write-Metadata {
    param([hashtable] $Value)

    $metadataPath = [IO.Path]::GetFullPath($Metadata)
    $metadataDirectory = Split-Path -Parent $metadataPath
    New-Item -ItemType Directory -Path $metadataDirectory -Force | Out-Null
    $Value | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metadataPath -Encoding utf8
}

function Resolve-SourceUrl {
    $response = Invoke-WebRequest -Uri $DownloadPage -UseBasicParsing
    $candidates = @(
        [regex]::Matches(
            $response.Content,
            'https://dldir1v6\.qq\.com/weixin/Universal/Windows/WeChatWin_[0-9.]+\.exe'
        ) | ForEach-Object { $_.Value } | Sort-Object -Unique
    )
    if ($candidates.Length -ne 1) {
        throw "Expected one official WeChat installer URL on $DownloadPage, found $($candidates.Length)."
    }
    return $candidates[0]
}

function Invoke-RangeDownload {
    param(
        [string] $Url,
        [string] $Path
    )

    $probeHeader = "$Path.probe.header"
    $probeBody = "$Path.probe.body"
    try {
        Invoke-Checked $curlPath @(
            '--fail',
            '--location',
            '--silent',
            '--show-error',
            '--retry',
            '5',
            '--retry-delay',
            '5',
            '--range',
            '0-0',
            '--dump-header',
            $probeHeader,
            '--output',
            $probeBody,
            $Url
        ) | Out-Null
        $rangeMatch = [regex]::Match(
            (Get-Content -LiteralPath $probeHeader -Raw),
            '(?im)^Content-Range:\s*bytes\s+0-0/(\d+)\s*$'
        )
        if (-not $rangeMatch.Success) {
            throw "Could not determine the download size for $Url"
        }
        $total = [long]$rangeMatch.Groups[1].Value
    } finally {
        foreach ($probeFile in @($probeHeader, $probeBody)) {
            if (Test-Path -LiteralPath $probeFile) {
                Remove-Item -LiteralPath $probeFile -Force
            }
        }
    }

    $chunkSize = 64MB
    $outputStream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Create,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        for ($start = 0; $start -lt $total; $start += $chunkSize) {
            $end = [Math]::Min($start + $chunkSize - 1, $total - 1)
            $part = "$Path.$start.part"
            try {
                Invoke-Checked $curlPath @(
                    '--fail',
                    '--location',
                    '--silent',
                    '--show-error',
                    '--retry',
                    '5',
                    '--retry-delay',
                    '5',
                    '--range',
                    "$start-$end",
                    '--header',
                    'Referer: https://pc.weixin.qq.com/',
                    '--user-agent',
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/142.0.0.0 Safari/537.36',
                    '--output',
                    $part,
                    $Url
                ) | Out-Null

                $expected = $end - $start + 1
                $actual = (Get-Item -LiteralPath $part).Length
                if ($actual -ne $expected) {
                    throw "Downloaded $actual bytes for range $start-$end; expected $expected."
                }

                $partStream = [IO.File]::OpenRead($part)
                try {
                    $partStream.CopyTo($outputStream, 1024 * 1024)
                } finally {
                    $partStream.Dispose()
                }
            } finally {
                if (Test-Path -LiteralPath $part) {
                    Remove-Item -LiteralPath $part -Force
                }
            }
        }
    } finally {
        $outputStream.Dispose()
    }

    $written = (Get-Item -LiteralPath $Path).Length
    if ($written -ne $total) {
        throw "Downloaded $written bytes for $Url; expected $total."
    }
}

if (-not $BetterWX) {
    throw '-BetterWX is required.'
}

$sevenZipPath = (Get-Command $SevenZip -ErrorAction Stop).Source
$curlPath = (Get-Command $Curl -ErrorAction Stop).Source
$betterwxPath = [IO.Path]::GetFullPath($BetterWX)
if (-not (Test-Path -LiteralPath $betterwxPath -PathType Leaf)) {
    throw "BetterWX was not found at $betterwxPath"
}

$manifestPath = [IO.Path]::GetFullPath($Manifest)
$outputPath = [IO.Path]::GetFullPath($Output)
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$currentVersion = [version]$manifest.version

$workRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$workDirectory = Join-Path $workRoot ("scoop-wechat-build-{0}" -f [guid]::NewGuid())
New-Item -ItemType Directory -Path $workDirectory | Out-Null

try {
    $installerPath = if ($SourcePath) {
        [IO.Path]::GetFullPath($SourcePath)
    } else {
        if (-not $SourceUrl) {
            $SourceUrl = Resolve-SourceUrl
        }
        $downloadPath = Join-Path $workDirectory 'WeChatWin.exe'
        Invoke-RangeDownload -Url $SourceUrl -Path $downloadPath
        $downloadPath
    }
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "WeChat installer was not found at $installerPath"
    }

    $outerDirectory = Join-Path $workDirectory 'outer'
    Invoke-Checked $sevenZipPath @('x', $installerPath, "-o$outerDirectory", '-y', '-bb0') | Out-Null

    $installArchive = Join-Path $outerDirectory 'install.7z'
    if (-not (Test-Path -LiteralPath $installArchive -PathType Leaf)) {
        throw 'The official installer did not contain install.7z.'
    }

    $listing = Invoke-Checked $sevenZipPath @('l', '-slt', $installArchive)
    $versionMatch = [regex]::Match(($listing -join "`n"), '(?m)^Path = (\d+\.\d+\.\d+\.\d+)\s*$')
    if (-not $versionMatch.Success) {
        throw 'Could not determine the WeChat version from install.7z.'
    }

    $version = $versionMatch.Groups[1].Value
    $parsedVersion = [version]$version
    $betterwxVersion = ((Invoke-Checked $betterwxPath @('--version')) -join "`n").Trim()
    $sourceHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sourceSize = (Get-Item -LiteralPath $installerPath).Length
    $changed = $parsedVersion -gt $currentVersion

    $metadataValue = @{
        changed = $changed
        version = $version
        betterwx_version = $betterwxVersion
        source_url = $SourceUrl
        source_size = $sourceSize
        source_sha256 = $sourceHash
    }

    if (-not $changed) {
        Write-Metadata $metadataValue
        Write-Host "WeChat $version is not newer than manifest version $currentVersion."
        return
    }

    $payloadDirectory = Join-Path $workDirectory 'payload'
    Invoke-Checked $sevenZipPath @('x', $installArchive, "-o$payloadDirectory", '-y', '-bb0') | Out-Null

    $sourceVersionDirectory = Join-Path $payloadDirectory $version
    $sourceWeixinExe = Join-Path $payloadDirectory 'Weixin.exe'
    if (-not (Test-Path -LiteralPath $sourceVersionDirectory -PathType Container)) {
        throw "The extracted version directory was not found at $sourceVersionDirectory"
    }
    if (-not (Test-Path -LiteralPath $sourceWeixinExe -PathType Leaf)) {
        throw "The extracted Weixin.exe was not found at $sourceWeixinExe"
    }

    $weixinDirectory = Join-Path $workDirectory 'Weixin'
    New-Item -ItemType Directory -Path $weixinDirectory | Out-Null
    $versionDirectory = Join-Path $weixinDirectory $version
    Move-Item -LiteralPath $sourceVersionDirectory -Destination $versionDirectory
    $weixinExe = Join-Path $weixinDirectory 'Weixin.exe'
    Move-Item -LiteralPath $sourceWeixinExe -Destination $weixinExe

    $weixinDll = Join-Path $versionDirectory 'Weixin.dll'
    foreach ($required in @($weixinDll, $weixinExe)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Required WeChat file was not found at $required"
        }
    }

    $dllHashBefore = (Get-FileHash -LiteralPath $weixinDll -Algorithm SHA256).Hash
    $exeHashBefore = (Get-FileHash -LiteralPath $weixinExe -Algorithm SHA256).Hash

    Invoke-Checked $betterwxPath @('enable', 'revoke', $weixinExe) | Out-Null
    Invoke-Checked $betterwxPath @('enable', 'coexist', $weixinExe) | Out-Null
    Invoke-Checked $betterwxPath @('enable', 'no-updates', $weixinExe) | Out-Null

    $patchStatus = (Invoke-Checked $betterwxPath @('status', $weixinExe)) -join "`n"
    Write-Host $patchStatus
    $patchLines = $patchStatus -split "`r?`n"
    $featureLabels = @{
        revoke = [string][char]0x9632 + [char]0x64A4 + [char]0x56DE
        coexist = [string][char]0x591A + [char]0x8D26 + [char]0x53F7 + [char]0x5171 + [char]0x5B58
        'no-updates' = [string][char]0x4E0D + [char]0x8981 + [char]0x66F4 + [char]0x65B0
    }
    $enabledSuffix = [string][char]0xFF1A + [char]0x5DF2 + [char]0x542F + [char]0x7528
    foreach ($feature in $featureLabels.GetEnumerator()) {
        $line = $patchLines | Where-Object { $_.StartsWith($feature.Value + [char]0xFF1A) } | Select-Object -First 1
        if (-not $line -or -not $line.EndsWith($enabledSuffix)) {
            throw "BetterWX did not report the expected patch state: $($feature.Key)"
        }
        Write-Host "BetterWX $($feature.Key): enabled"
    }

    $dllHashAfter = (Get-FileHash -LiteralPath $weixinDll -Algorithm SHA256).Hash
    $exeHashAfter = (Get-FileHash -LiteralPath $weixinExe -Algorithm SHA256).Hash
    if ($dllHashBefore -eq $dllHashAfter) {
        throw 'BetterWX did not modify Weixin.dll.'
    }
    if ($exeHashBefore -eq $exeHashAfter) {
        throw 'BetterWX did not modify Weixin.exe.'
    }

    Get-ChildItem -LiteralPath $weixinDirectory -Recurse -File -Filter '*.bak' |
        Remove-Item -Force

    $outputDirectory = Split-Path -Parent $outputPath
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $outputPath) {
        Remove-Item -LiteralPath $outputPath -Force
    }

    Push-Location $workDirectory
    try {
        Invoke-Checked $sevenZipPath @('a', '-t7z', '-mx=9', $outputPath, 'Weixin', '-bb0') | Out-Null
    } finally {
        Pop-Location
    }

    $metadataValue.sha256 = (Get-FileHash -LiteralPath $outputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadataValue.download_size = (Get-Item -LiteralPath $outputPath).Length
    Write-Metadata $metadataValue
    Write-Host "Built WeChat $version with $betterwxVersion."
} finally {
    if (Test-Path -LiteralPath $workDirectory) {
        $resolvedWorkDirectory = (Resolve-Path -LiteralPath $workDirectory).Path
        if (-not $resolvedWorkDirectory.StartsWith($workRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove unexpected path: $resolvedWorkDirectory"
        }
        Remove-Item -LiteralPath $resolvedWorkDirectory -Recurse -Force
    }
}
