@echo off
setlocal

if "%OHOS_SDK_HOME%"=="" (
  echo OHOS_SDK_HOME must point to the OpenHarmony SDK directory that contains native.
  exit /b 1
)

set "KEYMAGIC_OHOS_CLANGXX=%OHOS_SDK_HOME%\native\llvm\bin\clang++.exe"
set "KEYMAGIC_OHOS_SYSROOT=%OHOS_SDK_HOME%\native\sysroot"

if not exist "%KEYMAGIC_OHOS_CLANGXX%" (
  echo HarmonyOS clang++ was not found at "%KEYMAGIC_OHOS_CLANGXX%".
  exit /b 1
)

"%KEYMAGIC_OHOS_CLANGXX%" --target=aarch64-linux-ohos20.0.0 --sysroot="%KEYMAGIC_OHOS_SYSROOT%" -D__MUSL__ %*
