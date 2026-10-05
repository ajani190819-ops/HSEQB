@echo off
setlocal enabledelayedexpansion
title Minecraft World Migrator to 26.2

cd /d "%~dp0"

echo ======================================================================
echo    Floor 5 Worldwide - Automatic World Migrator to Minecraft 26.2
echo ======================================================================
echo.

if not exist "world" (
    echo [!] ERROR: 'world' folder not found in:
    echo     %~dp0
    echo     Please make sure this script is in your server folder next to 'world'.
    echo.
    pause
    exit /b 1
)

echo [*] Step 1: Creating Minecraft 26.2 dimensions folder structure...
if not exist "world\dimensions\minecraft\the_nether" mkdir "world\dimensions\minecraft\the_nether"
if not exist "world\dimensions\minecraft\the_end" mkdir "world\dimensions\minecraft\the_end"

echo [*] Step 2: Creating a safe backup in 'world_backup'...
if not exist "world_backup" mkdir "world_backup"
xcopy /E /I /Q /Y "world" "world_backup\world" >nul 2>&1
if exist "world_nether" xcopy /E /I /Q /Y "world_nether" "world_backup\world_nether" >nul 2>&1
if exist "world_the_end" xcopy /E /I /Q /Y "world_the_end" "world_backup\world_the_end" >nul 2>&1
echo [+] Backup saved to world_backup folder.

echo [*] Step 3: Migrating Nether dimension...
if exist "world_nether\DIM-1" (
    if exist "world_nether\DIM-1\region" xcopy /E /I /Q /Y "world_nether\DIM-1\region" "world\dimensions\minecraft\the_nether\region" >nul 2>&1
    if exist "world_nether\DIM-1\entities" xcopy /E /I /Q /Y "world_nether\DIM-1\entities" "world\dimensions\minecraft\the_nether\entities" >nul 2>&1
    if exist "world_nether\DIM-1\poi" xcopy /E /I /Q /Y "world_nether\DIM-1\poi" "world\dimensions\minecraft\the_nether\poi" >nul 2>&1
    echo [+] Nether migrated successfully.
) else if exist "world_nether\region" (
    xcopy /E /I /Q /Y "world_nether\region" "world\dimensions\minecraft\the_nether\region" >nul 2>&1
    if exist "world_nether\entities" xcopy /E /I /Q /Y "world_nether\entities" "world\dimensions\minecraft\the_nether\entities" >nul 2>&1
    if exist "world_nether\poi" xcopy /E /I /Q /Y "world_nether\poi" "world\dimensions\minecraft\the_nether\poi" >nul 2>&1
    echo [+] Nether migrated successfully.
) else (
    echo [!] No legacy Nether folder found or already migrated.
)

echo [*] Step 4: Migrating The End dimension...
if exist "world_the_end\DIM1" (
    if exist "world_the_end\DIM1\region" xcopy /E /I /Q /Y "world_the_end\DIM1\region" "world\dimensions\minecraft\the_end\region" >nul 2>&1
    if exist "world_the_end\DIM1\entities" xcopy /E /I /Q /Y "world_the_end\DIM1\entities" "world\dimensions\minecraft\the_end\entities" >nul 2>&1
    if exist "world_the_end\DIM1\poi" xcopy /E /I /Q /Y "world_the_end\DIM1\poi" "world\dimensions\minecraft\the_end\poi" >nul 2>&1
    echo [+] The End migrated successfully.
) else if exist "world_the_end\region" (
    xcopy /E /I /Q /Y "world_the_end\region" "world\dimensions\minecraft\the_end\region" >nul 2>&1
    if exist "world_the_end\entities" xcopy /E /I /Q /Y "world_the_end\entities" "world\dimensions\minecraft\the_end\entities" >nul 2>&1
    if exist "world_the_end\poi" xcopy /E /I /Q /Y "world_the_end\poi" "world\dimensions\minecraft\the_end\poi" >nul 2>&1
    echo [+] The End migrated successfully.
) else (
    echo [!] No legacy End folder found or already migrated.
)

echo [*] Step 5: Removing temporary lock folders...
if exist "world upgraded" rmdir /S /Q "world upgraded" >nul 2>&1
if exist "world\filefix" rmdir /S /Q "world\filefix" >nul 2>&1

echo.
echo ======================================================================
echo  MIGRATION COMPLETE!
echo.
echo  Your world is now 100%% formatted for Minecraft 26.2!
echo  To start your server:
echo    Double-click start.bat
echo ======================================================================
echo.
pause
