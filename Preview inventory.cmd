@echo off
setlocal
set "PREVIEW_ENGINE=%~dp0..\..\Godot_v4.0-stable_win64.exe"
if not exist "%PREVIEW_ENGINE%" (
    echo Godot 4.0 was not found next to the PathofDan workspace.
    echo Open this project in Godot and run tests/ui_inventory_preview.tscn with F6.
    pause
    exit /b 1
)
start "Path of Dan - UI preview" "%PREVIEW_ENGINE%" --rendering-method gl_compatibility --path "%~dp0." res://tests/ui_inventory_preview.tscn
