@echo off
rem Opens the Android USB Reverse Tether window (gui.ps1).
rem Prefer the console version? Use Start-ReverseTether.bat instead.
start "" powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0gui.ps1"
