@echo off
setlocal
title PetMate emulator launcher

REM Usage:  run_emulator.bat            -> software GPU (most reliable)
REM         run_emulator.bat host       -> host GPU (faster, needs good drivers)

set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "EMU=%SDK%\emulator\emulator.exe"
set "AVD=Pixel_10_Pro_XL"
set "GPU=%~1"
if "%GPU%"=="" set "GPU=swiftshader_indirect"

REM Screen-recorder Vulkan capture layers (OBS / Bandicam) inject into qemu and
REM crash the emulator. These are each layer's documented opt-out switch.
set "DISABLE_VULKAN_OBS_CAPTURE=1"
set "VK_LAYER_bandicam_helper_DEBUG_1=1"

if not exist "%EMU%" (
  echo [X] emulator.exe not found at "%EMU%"
  echo     Android Studio ^> Settings ^> SDK Manager ^> SDK Tools ^> install "Android Emulator".
  pause
  exit /b 1
)

echo === Clearing stale emulator processes ===
taskkill /F /IM qemu-system-x86_64.exe          >nul 2>&1
taskkill /F /IM qemu-system-x86_64-headless.exe >nul 2>&1
taskkill /F /IM emulator.exe                    >nul 2>&1
taskkill /F /IM crashpad_handler.exe            >nul 2>&1
"%SDK%\platform-tools\adb.exe" kill-server      >nul 2>&1
echo done.
echo.

echo === Hardware acceleration check ===
"%EMU%" -accel-check
echo.

echo === Installed AVDs ===
"%EMU%" -list-avds
echo.

echo === Starting %AVD%  (cold boot, gpu=%GPU%) ===
echo Keep this window open - any emulator error is printed below.
echo.
"%EMU%" -avd %AVD% -no-snapshot-load -no-snapshot-save -gpu %GPU% -no-boot-anim -netdelay none -netspeed full -verbose

echo.
echo === Emulator exited with code %ERRORLEVEL% ===
pause
