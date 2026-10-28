@echo off
rem Balatro Co-op dev mode: two windows on this PC, the right one is a bot.
rem F8 in a run = dev panel, F7 = autopilot on/off.
set "GAME=E:\SteamLibrary\steamapps\common\Balatro\Balatro.exe"
if not exist "%GAME%" set "GAME=C:\Program Files (x86)\Steam\steamapps\common\Balatro\Balatro.exe"
if not exist "%GAME%" (
  echo Balatro.exe not found, edit GAME in this file.
  pause
  exit /b 1
)
start "" "%GAME%" --coop-dev host
timeout /t 4 /nobreak >nul
start "" "%GAME%" --coop-dev guest
