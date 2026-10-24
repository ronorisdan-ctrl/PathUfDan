@echo off
REM ============================================================
REM  Path of Dan - one-click Git backup
REM  Double-click this file. First run asks a few questions.
REM  Every run after that just saves + uploads your latest work.
REM ============================================================
cd /d "%~dp0"

where git >nul 2>&1
if errorlevel 1 (
  echo Git is not installed yet.
  echo Download it from https://git-scm.com/download/win , install with default options, then run this again.
  pause
  exit /b 1
)

if not exist ".git" git init -b main

REM ---- Your name / email (only asked if still the placeholder) ----
set "GN="
set "GE="
for /f "delims=" %%i in ('git config user.name') do set "GN=%%i"
for /f "delims=" %%i in ('git config user.email') do set "GE=%%i"
if "%GN%"=="" goto askid
if "%GN%"=="Your Name" goto askid
goto idok
:askid
set /p GN=Your name (shown on commits):
set /p GE=Your email (use your GitHub email):
git config user.name "%GN%"
git config user.email "%GE%"
:idok

REM ---- GitHub link (only asked once) ----
git remote get-url origin >nul 2>&1
if not errorlevel 1 goto haveremote
echo.
echo No GitHub repository linked yet.
echo 1. Go to https://github.com/new
echo 2. Name it PathOfDan, set it to PRIVATE, do NOT tick any "add README" boxes, click Create.
echo 3. Copy the https://github.com/YOURNAME/PathOfDan.git address shown.
echo.
set /p URL=Paste the address here and press Enter:
git remote add origin "%URL%"
:haveremote

REM ---- Save a snapshot ----
git add -A
git commit -m "Backup %date% %time%"
git branch -M main

REM ---- Upload ----
git push -u origin main
if errorlevel 1 (
  echo.
  echo Upload failed. Check your internet / GitHub login window, then run this again.
) else (
  echo.
  echo Backup complete.
)
pause
