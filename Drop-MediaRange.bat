@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Drop-MediaRange.ps1" %*
