# Fixes hardcoded C:\Users\<OldName> paths in HKCU after a profile folder rename.
# Targeted keys first (Environment, Shell Folders, User Shell Folders, Lxss,
# OneDrive, SyncEngines), then optionally (-All) every REG_SZ / REG_EXPAND_SZ
# string value under HKCU (wallpaper, themes, protocol handlers, uninstall...).
#
# NOTE: keys from Get-Item/Get-ChildItem are READ-ONLY handles; SetValue throws
# "Cannot write to the registry key". We reopen via OpenSubKey(rel, $true).
param(
    [Parameter(Mandatory = $true)][string]$OldName,
    [Parameter(Mandatory = $true)][string]$NewName,
    [switch]$All
)
$old = "C:\Users\$OldName"
$new = "C:\Users\$NewName"
if ($OldName -ieq $NewName) { throw 'OldName and NewName must differ' }
$script:fixed = 0

function Fix-Tree($rel, $recurse) {
    $keys = @()
    $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($rel)
    if ($root) { $keys += $root }
    if ($recurse) {
        Get-ChildItem ("HKCU:\" + $rel) -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $k2 = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($_.Name -replace '^HKEY_CURRENT_USER\\', '')
            if ($k2) { $keys += $k2 }
        }
    }
    foreach ($wk in $keys) {
        foreach ($vn in @($wk.GetValueNames())) {
            try { $kind = $wk.GetValueKind($vn) } catch { continue }
            if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String -and
                $kind -ne [Microsoft.Win32.RegistryValueKind]::ExpandString) { continue }
            $v = $wk.GetValue($vn, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($v -is [string] -and $v.Contains($old)) {
                try {
                    $wk.SetValue($vn, $v.Replace($old, $new), $kind)
                    Write-Output ("FIXED: " + $wk.Name + " ! " + $vn)
                    $script:fixed++
                } catch { Write-Output ("WRITE_FAILED: " + $wk.Name + " ! " + $vn) }
            }
        }
        $wk.Close()
    }
}

Write-Output "== Targeted keys =="
Fix-Tree 'Environment' $false
Fix-Tree 'Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders' $false
Fix-Tree 'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' $false
Fix-Tree 'Software\Microsoft\Windows\CurrentVersion\Lxss' $true
Fix-Tree 'Software\Microsoft\OneDrive' $true
Fix-Tree 'Software\SyncEngines\Providers\OneDrive' $true

if ($All) {
    Write-Output "== Full HKCU sweep =="
    Fix-Tree 'Software' $true
    Fix-Tree 'Volatile Environment' $false
} else {
    Write-Output "(add -All for full HKCU sweep)"
}

Write-Output ("TOTAL_FIXED: " + $script:fixed)
Write-Output "Reminder: OneDrive-managed keys may be rewritten by OneDrive itself -"
Write-Output "that requires the official unlink/relink flow, do not re-fix them."
