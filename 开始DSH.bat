@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\handoff.ps1" -Start dsh -Intent "continue development" -Clipboard
echo.
echo Copied to clipboard. Paste into the DSH chat window now.
pause
