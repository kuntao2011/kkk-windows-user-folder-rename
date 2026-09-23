# Generates step2-as-admin.bat: renames C:\Users\<OldName> to C:\Users\<NewName>,
# updates ProfileImagePath, creates a fallback junction.
# The .bat is written ANSI(GBK on zh-CN) + CRLF with English prompts, so it parses
# correctly under any console codepage (UTF-8 + chcp 65001 breaks if-block parsing).
param(
    [Parameter(Mandatory = $true)][string]$OldName,
    [Parameter(Mandatory = $true)][string]$NewName,
    [Parameter(Mandatory = $true)][string]$Sid,
    [string]$OutFile = "$env:USERPROFILE\Desktop\step2-as-admin.bat",
    [string[]]$KillServices  = @('MSPCManagerService'),      # MS PC Manager holds profile handles
    [string[]]$KillProcesses = @('MSPCManagerService.exe')
)

if ($OldName -ieq $NewName) { throw 'OldName and NewName must differ' }

# Validate the SID against ProfileList (readable without elevation): a typo would
# make the generated bat silently reg add a garbage key.
$plKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $Sid
if (-not (Test-Path $plKey)) { throw "SID '$Sid' not found under ProfileList - rerun scan-old-refs.ps1 and copy the SID exactly" }
$plPath = (Get-ItemProperty $plKey -ErrorAction SilentlyContinue).ProfileImagePath
if ($plPath -and ($plPath -notlike "*\$OldName")) { throw "ProfileList\$Sid currently points to '$plPath', not to a folder ending with '\$OldName' - wrong SID?" }

$stopCmds = ''
foreach ($s in $KillServices)  { $stopCmds += "sc stop $s >nul 2>&1" + "`r`n" }
foreach ($p in $KillProcesses) { $stopCmds += "taskkill /f /im $p >nul 2>&1" + "`r`n" }

# Note on the %USERNAME% guard below: it only catches accounts whose login name
# equals OldName. When a Microsoft account display name differs from the profile
# folder name, the guard passes but ren still fails with access denied (the
# ntuser.dat of the signed-in owner is locked); the [FAIL] branch handles that.
$bat = @"
@echo off
setlocal
title User profile folder rename __OLD__ to __NEW__

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] No admin rights. Right-click this file and choose "Run as administrator".
    pause
    exit /b 1
)

if /i "%USERNAME%"=="__OLD__" (
    echo [ERROR] You are signed in as __OLD__. The profile is locked while its owner is
    echo        signed in. Restart, sign in as another admin account, then run this script.
    pause
    exit /b 1
)

fsutil reparsepoint query "C:\Users\__OLD__" >nul 2>&1
if %errorlevel% equ 0 (
    echo [INFO] C:\Users\__OLD__ is already a junction - this script already succeeded before.
    echo        Just sign back into the original account.
    pause
    exit /b 0
)

if exist "C:\Users\__NEW__" (
    echo [ERROR] C:\Users\__NEW__ exists but the old folder is not a junction. Abnormal state.
    echo        Stop here and inspect manually.
    pause
    exit /b 1
)

if not exist "C:\Users\__OLD__" (
    echo [ERROR] C:\Users\__OLD__ not found. Abnormal state. Stop here and inspect manually.
    pause
    exit /b 1
)

echo.
echo [0/3] Stopping services known to hold handles inside the profile ...
__STOPCMDS__
timeout /t 2 /nobreak >nul
echo        Done.

echo.
echo [1/3] Renaming C:\Users\__OLD__ to C:\Users\__NEW__ ...
ren "C:\Users\__OLD__" "__NEW__"
if %errorlevel% neq 0 (
    echo.
    echo [FAIL] Access denied - some process still holds handles under C:\Users\__OLD__.
    echo        resmon cannot find service-type handles. Use Sysinternals handle.exe:
    echo            handle.exe -a Users\__OLD__
    echo        Stop the holders ^(also check services running as that user^), then re-run
    echo        this script - it is safe to re-run.
    pause
    exit /b 1
)
echo        OK.

echo.
echo [2/3] Updating ProfileImagePath in registry ...
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\__SID__" "%~dp0profilelist-backup.reg" /y >nul 2>&1
if exist "%~dp0profilelist-backup.reg" echo        Pre-change backup saved: %~dp0profilelist-backup.reg
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\__SID__" /v ProfileImagePath /t REG_EXPAND_SZ /d "C:\Users\__NEW__" /f
if %errorlevel% neq 0 (
    echo [FAIL] Registry update failed. Screenshot this window before closing.
    echo        The pre-change backup is %~dp0profilelist-backup.reg ^(double-click to restore^).
    pause
    exit /b 1
)
echo        OK.

echo.
echo [3/3] Creating fallback junction C:\Users\__OLD__ -^> C:\Users\__NEW__ ...
mklink /J "C:\Users\__OLD__" "C:\Users\__NEW__"
if %errorlevel% neq 0 (
    echo        [WARN] Junction creation failed. The rename itself is fine, continuing.
) else (
    echo        OK.
)

echo.
echo ============================================================
echo   Done. Sign out of this admin account and sign back into
echo   the original account, then continue residue cleanup.
echo ============================================================
pause
"@

$bat = $bat.Replace('__STOPCMDS__', $stopCmds.TrimEnd("`r`n"))
$bat = $bat.Replace('__OLD__', $OldName).Replace('__NEW__', $NewName).Replace('__SID__', $Sid)

# normalize line endings to CRLF regardless of how this .ps1 was saved
$bat = $bat.Replace("`r`n", "`n").Replace("`n", "`r`n")

$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

# GetEncoding(0) = system ANSI codepage (GBK on zh-CN) under both PS 5.1 and pwsh 7;
# [Text.Encoding]::Default would be UTF-8 (no BOM) under pwsh 7 and garble Chinese paths.
[IO.File]::WriteAllText($OutFile, $bat, [Text.Encoding]::GetEncoding(0))
Write-Output ("GENERATED: " + $OutFile)
Write-Output ("Size: " + (Get-Item $OutFile).Length + " bytes, ANSI encoding, CRLF")
Write-Output "Reminder: must be run from ANOTHER admin account after a reboot (not the profile owner)."
