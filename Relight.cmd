@echo off
setlocal
if "%~1"=="" (
  echo Drag a foliage GLB onto this file or pass an input GLB as its first argument.
  pause
  exit /b 2
)
set "engine=%GODOT_BIN%"
if not defined engine if exist "%~dp0godot.exe" set "engine=%~dp0godot.exe"
if not defined engine set "engine=godot"
set "mesh=%~2"
if not defined mesh set "mesh=auto"
set "mode=%~3"
if not defined mode set "mode=auto"
"%engine%" --headless --path "%~dp0." --script res://convert.gd -- "%~f1" "%mesh%" "%mode%"
if errorlevel 1 (
  echo Check the Godot executable and the mesh names printed above.
  pause
  exit /b 1
)
