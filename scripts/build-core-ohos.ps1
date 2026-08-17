[CmdletBinding()]
param(
    [ValidateSet('debug', 'release')]
    [string]$Profile = 'debug',

    [string]$OhosSdkPath = $env:OHOS_SDK_HOME
)

$ErrorActionPreference = 'Stop'

$target = 'aarch64-unknown-linux-ohos'

if ([string]::IsNullOrWhiteSpace($OhosSdkPath)) {
    throw "OHOS_SDK_HOME is not set. Set it to the OpenHarmony SDK directory that contains 'native', then rerun this script."
}

$sdkRoot = (Resolve-Path -LiteralPath $OhosSdkPath).Path
$nativeRoot = Join-Path $sdkRoot 'native'
$clang = Join-Path $nativeRoot 'llvm\bin\clang.exe'
$llvmAr = Join-Path $nativeRoot 'llvm\bin\llvm-ar.exe'
$llvmRanlib = Join-Path $nativeRoot 'llvm\bin\llvm-ranlib.exe'
$sysroot = Join-Path $nativeRoot 'sysroot'
$clangWrapper = Join-Path $PSScriptRoot 'aarch64-unknown-linux-ohos-clang.cmd'
$clangxxWrapper = Join-Path $PSScriptRoot 'aarch64-unknown-linux-ohos-clangxx.cmd'

foreach ($requiredPath in @($clang, $llvmAr, $llvmRanlib, $sysroot, $clangWrapper, $clangxxWrapper)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "HarmonyOS native SDK component not found: $requiredPath"
    }
}

foreach ($tool in @('cargo', 'rustup')) {
    if ($null -eq (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' was not found on PATH. Install Rust with rustup, reopen PowerShell, then run 'rustup target add $target'."
    }
}

$installedTargets = & rustup target list --installed
if ($LASTEXITCODE -ne 0) {
    throw "Unable to query installed Rust targets with rustup."
}

if ($installedTargets -notcontains $target) {
    throw "Rust target '$target' is not installed. Run: rustup target add $target"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$targetDirectory = Join-Path $repoRoot "target\$target\$Profile"

# The checked-in linker wrappers quote the SDK paths correctly when DevEco Studio
# is installed under Program Files and supply the API-20 target and sysroot.
$savedOhosSdkHome = $env:OHOS_SDK_HOME
$savedLinker = $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER
$savedAr = $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR
$savedRanlib = $env:RANLIB_aarch64_unknown_linux_ohos
$savedCc = $env:CC_aarch64_unknown_linux_ohos
$savedCxx = $env:CXX_aarch64_unknown_linux_ohos
$savedCargoTargetDir = $env:CARGO_TARGET_DIR

try {
    $env:OHOS_SDK_HOME = $sdkRoot
    $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER = $clangWrapper
    $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR = $llvmAr
    $env:RANLIB_aarch64_unknown_linux_ohos = $llvmRanlib
    $env:CC_aarch64_unknown_linux_ohos = $clangWrapper
    $env:CXX_aarch64_unknown_linux_ohos = $clangxxWrapper
    $env:CARGO_TARGET_DIR = (Join-Path $repoRoot 'target')

    $cargoArgs = @('build', '-p', 'keymagic-core', '--target', $target)
    if ($Profile -eq 'release') {
        $cargoArgs += '--release'
    }

    Push-Location $repoRoot
    try {
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Cargo failed while building keymagic-core for $target."
        }
    }
    finally {
        Pop-Location
    }
}
finally {
    $env:OHOS_SDK_HOME = $savedOhosSdkHome
    $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER = $savedLinker
    $env:CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_AR = $savedAr
    $env:RANLIB_aarch64_unknown_linux_ohos = $savedRanlib
    $env:CC_aarch64_unknown_linux_ohos = $savedCc
    $env:CXX_aarch64_unknown_linux_ohos = $savedCxx
    $env:CARGO_TARGET_DIR = $savedCargoTargetDir
}

$archive = Join-Path $targetDirectory 'libkeymagic_core.a'
if (-not (Test-Path -LiteralPath $archive)) {
    throw "Cargo completed but the expected static library was not produced: $archive"
}

Write-Host "Built HarmonyOS Rust archive: $archive"
