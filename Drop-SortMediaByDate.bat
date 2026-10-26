@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Drop-SortMediaByDate.ps1" -PauseOnExit %*
