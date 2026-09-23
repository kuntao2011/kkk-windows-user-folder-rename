# Fixes hardcoded C:\Users\<OldName> paths in HKCU after a profile folder rename.
# Targeted keys first (Environment, Shell Folders, User Shell Folders, Lxss,
# OneDrive, SyncEngines), then optionally (-All) every REG_SZ / REG_EXPAND_SZ
# string value under HKCU (wallpaper, themes, protocol handlers, uninstall...).
#
# Keys from Get-Item/Get-ChildItem are READ-ONLY handles; SetValue on them throws
# "Cannot write to the registry key", so every key is reopened with
# OpenSubKey(rel, $true). Before each write the ORIGINAL value is flushed into the
# undo log, so a run aborted halfway can still restore what was already changed.
# -WhatIf previews every hit without touching anything.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$OldName,
    [Parameter(Mandatory = $true)][string]$NewName,
    [switch]$All,
    [string]$UndoLog = "$env:USERPROFILE\Desktop\hkcu-path-fix-undo.ps1"
)
$old = "C:\Users\$OldName"
$new = "C:\Users\$NewName"
if ($OldName -ieq $NewName) { throw 'OldName and NewName must differ' }
$script:fixed = 0
$script:undoWriter = $null
$script:cmdlet = $PSCmdlet

function Open-Writable($rel) {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($rel, $true)
    if (-not $k) { $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($rel) } # ACL-restricted: enumerable, writes will be reported WRITE_FAILED
    return $k
}

function Add-UndoLine($regPath, $valueName, $kind, $data) {
    $vSwitch = if ($valueName) { "/v '" + $valueName.Replace("'", "''") + "'" } else { '/ve' }
    $tSwitch = if ($kind -eq [Microsoft.Win32.RegistryValueKind]::ExpandString) { 'REG_EXPAND_SZ' } else { 'REG_SZ' }
    $line = "reg add 'HKCU\" + ($regPath -replace '^HKEY_CURRENT_USER\\', '') + "' " +
            $vSwitch + " /t " + $tSwitch + " /d '" + $data.Replace("'", "''") + "' /f"
    if (-not $script:undoWriter) {
        $script:undoWriter = New-Object System.IO.StreamWriter($UndoLog, $false, (New-Object System.Text.UTF8Encoding($true)))
        $script:undoWriter.WriteLine('# Restores the ORIGINAL values that fix-hkcu-paths.ps1 replaced in this run.')
        $script:undoWriter.WriteLine('# Run this script to roll every edited value back.')
        $script:undoWriter.WriteLine('# Multi-line values cannot be expressed here and must be restored manually.')
        $script:undoWriter.Flush()
    }
    $script:undoWriter.WriteLine($line)
    $script:undoWriter.Flush()
}

function Fix-Tree($rel, $recurse) {
    $keys = @()
    $root = Open-Writable $rel
    if ($root) { $keys += $root }
    if ($recurse) {
        Get-ChildItem ("HKCU:\" + $rel) -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $k2 = Open-Writable ($_.Name -replace '^HKEY_CURRENT_USER\\', '')
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
                $op = 'Replace path in ' + $wk.Name + ' ! ' + $vn
                if (-not $script:cmdlet.ShouldProcess($op)) { continue }
                Add-UndoLine $wk.Name $vn $kind $v
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

if ($script:undoWriter) {
    $script:undoWriter.Close()
    Write-Output ("Undo log: " + $UndoLog + " (run it to restore the original values)")
}

Write-Output ("TOTAL_FIXED: " + $script:fixed)
Write-Output "Reminder: OneDrive-managed keys may be rewritten by OneDrive itself -"
Write-Output "that requires the official unlink/relink flow, do not re-fix them."
