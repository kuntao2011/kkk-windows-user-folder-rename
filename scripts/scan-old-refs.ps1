# Read-only inventory before renaming a user profile folder.
# Finds: SID + ProfileImagePath, second admin entry point, hardcoded old paths
# (Environment, WSL Lxss, OneDrive), services/tasks running as the user, and
# HKCU / HKLM residual old-path counts (baseline for post-fix comparison).
param(
    [string]$OldName = ''
)
if (-not $OldName) { $OldName = Split-Path -Leaf $env:USERPROFILE }
$oldPath = "C:\Users\$OldName"
Write-Output "===================================================="
Write-Output " Profile rename inventory  (old path: $oldPath)"
Write-Output "===================================================="

# --- 1. SID / ProfileList ---
Write-Output "`n[1] ProfileList entries (S-1-5-21-*)"
$profileRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$found = $false
Get-ChildItem $profileRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -like 'S-1-5-21-*' } | ForEach-Object {
    $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
    $bak = Test-Path ($_.PSPath + '.bak')
    Write-Output ("    " + $_.PSChildName + "  ->  " + $p + $(if ($bak) { '   [.bak EXISTS!] ' } else { '' }))
    if ($p -like "*\$OldName") { $script:sid = $_.PSChildName; $found = $true }
}
if (-not $found) { Write-Output "    !! No ProfileImagePath ends with \$OldName (already renamed? wrong name?)" }

# --- 2. Accounts / second admin entry ---
Write-Output "`n[2] Local accounts (Enabled only)"
Get-LocalUser | Where-Object Enabled | ForEach-Object {
    $tag = if ($_.SID -like 'S-1-5-21-*-500') { '  <- built-in admin (RID 500) is ACTIVE' } else { '' }
    Write-Output ("    " + $_.Name + "  [" + $_.PrincipalSource + "]" + $tag)
}
$builtIn = Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID -like 'S-1-5-21-*-500' } | Select-Object -First 1
if ($builtIn) { Write-Output ("    Built-in Administrator '" + $builtIn.Name + "' enabled: " + $builtIn.Enabled) }
else { Write-Output '    Built-in Administrator (RID 500): not found or query failed' }

# --- 3. Hardcoded old paths in HKCU ---
Write-Output "`n[3] Hardcoded '$oldPath' in key spots"
function Show-TreeHits($label, $rel, $recurse) {
    $keys = @([Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($rel))
    if ($recurse) { $keys += Get-ChildItem ("HKCU:\" + $rel) -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_ } }
    foreach ($k in $keys) {
        if (-not $k) { continue }
        $rk = if ($k -is [Microsoft.Win32.RegistryKey]) { $k } else { [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($k.Name -replace '^HKEY_CURRENT_USER\\', '')) }
        if (-not $rk) { continue }
        foreach ($vn in $rk.GetValueNames()) {
            $v = $rk.GetValue($vn, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($v -is [string] -and $v -like "*$oldPath*") { Write-Output ("    [$label] " + $rk.Name + " ! " + $vn) }
        }
    }
}
Show-TreeHits 'Env'      'Environment' $false
Show-TreeHits 'Lxss'     'Software\Microsoft\Windows\CurrentVersion\Lxss' $true
Show-TreeHits 'OneDrive' 'Software\Microsoft\OneDrive\Accounts' $true
Show-TreeHits 'SyncEng'  'Software\SyncEngines\Providers\OneDrive' $true

# --- 4. Services running as the user ---
Write-Output "`n[4] Services running as $OldName"
$svc = Get-CimInstance Win32_Service | Where-Object { $_.StartName -like "*$OldName*" }
if ($svc) { $svc | ForEach-Object { Write-Output ("    " + $_.Name + " (" + $_.State + ")") } } else { Write-Output '    none' }

# --- 5. Scheduled tasks running as the user ---
Write-Output "`n[5] Scheduled tasks registered to $OldName"
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
    $_.Principal.UserId -and ($_.Principal.UserId -like "*$OldName*")
}
if ($tasks) { $tasks | ForEach-Object { Write-Output ("    " + $_.TaskPath + $_.TaskName + "  [" + $_.State + ", as " + $_.Principal.UserId + "]") } }
else { Write-Output '    none (or task enumeration unavailable)' }

# --- 6. Run keys / autologon ---
Write-Output "`n[6] Run keys referencing old path"
foreach ($rk in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
    (Get-ItemProperty $rk -ErrorAction SilentlyContinue).PSObject.Properties |
        Where-Object { $_.Value -is [string] -and $_.Value -like "*$oldPath*" } |
        ForEach-Object { Write-Output ("    [$rk] " + $_.Name) }
}
Write-Output '    (no output above = clean)'

# --- 7. Residual counts (baseline) ---
Write-Output "`n[7] Residual 'Users\$OldName' data-value counts (baseline)"
foreach ($hive in @('HKCU', 'HKLM\SOFTWARE')) {
    $out = & reg.exe query $hive /f "Users\$OldName" /s /d 2>&1
    $summary = ($out | Where-Object { $_ } | Select-Object -Last 1)
    Write-Output ("    $hive : " + $summary)
}
Write-Output "`nDone. Review output, then proceed to backup + gen-step2-bat.ps1."
