# Runs Godot 4.0 headless (or windowed with -Windowed) with a timeout; prints filtered output.
# usage: powershell -File tests/run_timeout.ps1 <scene> <seconds> [-Windowed] [extra user args]
param([string]$Scene, [int]$Seconds = 300, [switch]$Windowed, [string]$UserArgs = "")
$godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
$proj = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP "pod_run_out.txt"
$err = Join-Path $env:TEMP "pod_run_err.txt"
$a = @()
if (-not $Windowed) { $a += "--headless" }
$a += @("--fixed-fps", "60", "--path", "`"$proj`"", $Scene)
if ($UserArgs -ne "") { $a += @("--", $UserArgs) }
$p = Start-Process -FilePath $godot -ArgumentList $a -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $p.WaitForExit($Seconds * 1000)) { $p.Kill(); Write-Output "TIMEOUT after $Seconds s" }
Get-Content $out, $err | Select-String "====|FAIL|SCRIPT ERROR|Parse Error|ERROR|shot |at:" | Select-Object -First 60 | ForEach-Object { $_.Line }
Write-Output "exit $($p.ExitCode)"
