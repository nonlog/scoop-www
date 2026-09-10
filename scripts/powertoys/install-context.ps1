$classRoot = '{{registry_scope}}:\Software\Classes'

function Set-DefaultValue {
    param([string] $Path, [string] $Value)

    New-Item -Path $Path -Value $Value -Force | Out-Null
}

$protocol = Join-Path $classRoot 'powertoys'
Set-DefaultValue -Path $protocol -Value 'URL:PowerToys custom internal URI protocol'
New-ItemProperty -Path $protocol -Name 'InstallScope' -Value '{{install_scope}}' -Force | Out-Null
New-ItemProperty -Path $protocol -Name 'URL Protocol' -Value '' -Force | Out-Null

$components = Join-Path $protocol 'components'
New-Item -Path $components -Force | Out-Null
@(
    'BugReportTool_exe', 'License_rtf', 'Module_KeyboardManager_Editor',
    'Module_KeyboardManager_Engine', 'Module_VideoConference',
    'Module_VideoConferenceIcons', 'Notice_md', 'StylesReportTool_exe',
    'WebcamReportTool_exe', 'WinUI3AppsMicrosoftUIXamlAssets_NoiseAsset_256x256_PNG'
) | ForEach-Object {
    New-ItemProperty -Path $components -Name $_ -Value '' -Force | Out-Null
}
Set-DefaultValue -Path (Join-Path $protocol 'DefaultIcon') -Value 'PowerToys.exe'
Set-DefaultValue -Path (Join-Path $protocol 'shell\open\command') -Value '"{{scoop_dir}}\PowerToys.exe" "%1"'

$powerRenameClsid = '{0440049F-D1DC-4E46-B27B-98393D79486B}'
$powerRename = Join-Path $classRoot "CLSID\$powerRenameClsid"
Set-DefaultValue -Path $powerRename -Value 'PowerRename Shell Extension'
New-ItemProperty -Path $powerRename -Name 'ContextMenuOptIn' -Value '' -Force | Out-Null
Set-DefaultValue -Path (Join-Path $powerRename 'InprocServer32') -Value '{{scoop_dir}}\WinUI3Apps\PowerToys.PowerRenameExt.dll'
New-ItemProperty -Path (Join-Path $powerRename 'InprocServer32') -Name 'ThreadingModel' -Value 'Apartment' -Force | Out-Null
@(
    'AllFileSystemObjects\ShellEx\ContextMenuHandlers\PowerRenameExt',
    'Directory\background\ShellEx\ContextMenuHandlers\PowerRenameExt'
) | ForEach-Object { Set-DefaultValue -Path (Join-Path $classRoot $_) -Value $powerRenameClsid }

$imageResizerClsid = '{51B4D7E5-7568-4234-B4BB-47FB3C016A69}'
$imageResizer = Join-Path $classRoot "CLSID\$imageResizerClsid\InprocServer32"
Set-DefaultValue -Path $imageResizer -Value '{{scoop_dir}}\PowerToys.ImageResizerExt.dll'
New-ItemProperty -Path $imageResizer -Name 'ThreadingModel' -Value 'Apartment' -Force | Out-Null
Set-DefaultValue -Path (Join-Path $classRoot 'Directory\ShellEx\DragDropHandlers\ImageResizer') -Value $imageResizerClsid
@('.bmp', '.dib', '.gif', '.jfif', '.jpe', '.jpeg', '.jpg', '.jxr', '.png', '.rle', '.tif', '.tiff', '.wdp') | ForEach-Object {
    Set-DefaultValue -Path (Join-Path $classRoot "SystemFileAssociations\$_\ShellEx\ContextMenuHandlers\ImageResizer") -Value $imageResizerClsid
}

$fileLocksmithClsid = '{84D68575-E186-46AD-B0CB-BAEB45EE29C0}'
$fileLocksmith = Join-Path $classRoot "CLSID\$fileLocksmithClsid"
Set-DefaultValue -Path $fileLocksmith -Value 'File Locksmith Shell Extension'
New-ItemProperty -Path $fileLocksmith -Name 'ContextMenuOptIn' -Value '' -Force | Out-Null
Set-DefaultValue -Path (Join-Path $fileLocksmith 'InprocServer32') -Value '{{scoop_dir}}\WinUI3Apps\PowerToys.FileLocksmithExt.dll'
New-ItemProperty -Path (Join-Path $fileLocksmith 'InprocServer32') -Name 'ThreadingModel' -Value 'Apartment' -Force | Out-Null
@(
    'AllFileSystemObjects\ShellEx\ContextMenuHandlers\FileLocksmithExt',
    'Drive\ShellEx\ContextMenuHandlers\FileLocksmithExt'
) | ForEach-Object { Set-DefaultValue -Path (Join-Path $classRoot $_) -Value $fileLocksmithClsid }

$toastClsid = Join-Path $classRoot 'CLSID\{DD5CACDA-7C2E-4997-A62A-04A597B58F76}'
Set-DefaultValue -Path $toastClsid -Value 'PowerToys Toast Notifications Background Activator'
$toast = Join-Path $toastClsid 'LocalServer32'
Set-DefaultValue -Path $toast -Value '{{scoop_dir}}\PowerToys.exe -ToastActivated'
New-ItemProperty -Path $toast -Name 'ThreadingModel' -Value 'Apartment' -Force | Out-Null

if ($PSVersionTable.PSVersion.Major -ge 6) {
    Import-Module Appx -UseWindowsPowerShell 3>$null
}
Add-AppxPackage -Path '{{scoop_dir}}\WinUI3Apps\ImageResizerContextMenuPackage.msix' -ExternalLocation '{{scoop_dir}}\WinUI3Apps' | Out-Null
Add-AppxPackage -Path '{{scoop_dir}}\WinUI3Apps\PowerRenameContextMenuPackage.msix' -ExternalLocation '{{scoop_dir}}\WinUI3Apps' | Out-Null
