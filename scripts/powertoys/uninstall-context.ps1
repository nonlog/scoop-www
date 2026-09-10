$classRoot = '{{registry_scope}}:\Software\Classes'

@(
    'powertoys',
    'CLSID\{0440049F-D1DC-4E46-B27B-98393D79486B}',
    'AllFileSystemObjects\ShellEx\ContextMenuHandlers\PowerRenameExt',
    'Directory\background\ShellEx\ContextMenuHandlers\PowerRenameExt',
    'CLSID\{51B4D7E5-7568-4234-B4BB-47FB3C016A69}',
    'Directory\ShellEx\DragDropHandlers\ImageResizer',
    'CLSID\{84D68575-E186-46AD-B0CB-BAEB45EE29C0}',
    'AllFileSystemObjects\ShellEx\ContextMenuHandlers\FileLocksmithExt',
    'Drive\ShellEx\ContextMenuHandlers\FileLocksmithExt',
    'CLSID\{DD5CACDA-7C2E-4997-A62A-04A597B58F76}'
) + @('.bmp', '.dib', '.gif', '.jfif', '.jpe', '.jpeg', '.jpg', '.jxr', '.png', '.rle', '.tif', '.tiff', '.wdp') | ForEach-Object {
    if ($_.StartsWith('.')) {
        "SystemFileAssociations\$_\ShellEx\ContextMenuHandlers\ImageResizer"
    } else {
        $_
    }
} | ForEach-Object {
    $path = Join-Path $classRoot $_
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force | Out-Null
    }
}

if ($PSVersionTable.PSVersion.Major -ge 6) {
    Import-Module Appx -UseWindowsPowerShell 3>$null
}
@('ImageResizerContextMenu', 'PowerRenameContextMenu') | ForEach-Object {
    Get-AppxPackage | Where-Object { $_.PackageFullName -like "*$_*" } | Remove-AppxPackage | Out-Null
}
