# Cross-compile rust_guard for all 4 Android ABIs on Windows.
# Mirror of tool/build_rust.sh.
#
# Prereqs:
#   rustup target add aarch64-linux-android armv7-linux-androideabi `
#                      x86_64-linux-android i686-linux-android
#   Android NDK present under %ANDROID_NDK_HOME% or
#     %LOCALAPPDATA%\Android\Sdk\ndk\<version>
param(
  [string]$Seed = ""
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$Root    = (Get-Location).Path
$RustDir = Join-Path $Root "rust"
$JniDir  = Join-Path $Root "android\app\src\main\jniLibs"

if (-not $env:ANDROID_NDK_HOME -or -not (Test-Path $env:ANDROID_NDK_HOME)) {
  $candidates = @()
  if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\ndk") }
  if ($env:ANDROID_HOME) { $candidates += (Join-Path $env:ANDROID_HOME "ndk") }
  foreach ($c in $candidates) {
    if (Test-Path $c) {
      $env:ANDROID_NDK_HOME = (Get-ChildItem $c -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
    }
  }
}
if (-not $env:ANDROID_NDK_HOME) { throw "ANDROID_NDK_HOME not set and no NDK found under %LOCALAPPDATA%\Android\Sdk\ndk" }
$Toolchain = Join-Path $env:ANDROID_NDK_HOME "toolchains\llvm\prebuilt\windows-x86_64"
if (-not (Test-Path (Join-Path $Toolchain "bin"))) {
  throw "NDK toolchain missing: $Toolchain\bin"
}
$env:PATH = (Join-Path $Toolchain "bin") + ";" + $env:PATH

if ($Seed) { $env:RG_BUILD_SEED = $Seed }
Write-Host "NDK:  $env:ANDROID_NDK_HOME"
Write-Host ("SEED: " + (if ($env:RG_BUILD_SEED) { $env:RG_BUILD_SEED } else { "<default>" }))

$targets = @(
  @{ t = "aarch64-linux-android";   abi = "arm64-v8a"   },
  @{ t = "armv7-linux-androideabi"; abi = "armeabi-v7a" },
  @{ t = "x86_64-linux-android";    abi = "x86_64"      },
  @{ t = "i686-linux-android";      abi = "x86"         }
)

foreach ($x in $targets) {
  Write-Host "--- $($x.t) -> $($x.abi) ---"
  Push-Location $RustDir
  cargo build --release --target $x.t
  if ($LASTEXITCODE -ne 0) { Pop-Location; throw "cargo failed for $($x.t)" }
  Pop-Location

  $src = Join-Path $RustDir ("target\" + $x.t + "\release\librust_guard.so")
  if (-not (Test-Path $src)) { throw "missing build output: $src" }
  $destDir = Join-Path $JniDir $x.abi
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  $dest = Join-Path $destDir "librust_guard.so"
  Copy-Item $src $dest -Force
  & (Join-Path $Toolchain "bin\llvm-strip.exe") --strip-all $dest
}

Write-Host "`n[OK] librust_guard.so installed in:"
Get-ChildItem $JniDir -Recurse -Filter librust_guard.so | ForEach-Object { Write-Host $_.FullName }
