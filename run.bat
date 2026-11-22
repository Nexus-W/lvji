@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "TMAP_KEY="
if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%a in (".env") do (
    if /i "%%a"=="TMAP_KEY" set "TMAP_KEY=%%b"
  )
)

if "%TMAP_KEY%"=="" (
  echo [提示] 未找到 TMAP_KEY，地图功能会回退到本地地名表。
  echo        在项目根目录建 .env，写一行：TMAP_KEY=你的Key
  echo.
)

flutter run --dart-define=TMAP_KEY=%TMAP_KEY% %*
