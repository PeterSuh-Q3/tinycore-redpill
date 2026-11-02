# Builds the Windows CLI and GUI with MSVC and packs them into dist\.
# Usage: powershell -ExecutionPolicy Bypass -File build.ps1

param(
    [string]$VcpkgRoot = $(if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { 'C:\vcpkg' })
)

$ErrorActionPreference = 'Stop'
$Version = '1.1'
$Triplet = 'x64-windows-static'

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed with exit code $LASTEXITCODE" }
}

function New-Package([string]$ExeName, [string]$ZipName) {
    $zip = Join-Path 'dist' $ZipName
    Compress-Archive -Path (Join-Path 'build' $ExeName) -DestinationPath $zip -Force
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
    [IO.File]::WriteAllText("$zip.sha256sum", "$hash  $ZipName`n")
    Write-Host "$hash  $ZipName"
}

Set-Location $PSScriptRoot

# Load the MSVC x64 environment
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) { throw 'Visual Studio with the C++ tools was not found' }
Import-Module (Join-Path $vsPath 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $vsPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null

# Install dependencies into .\vcpkg_installed
Invoke-Native (Join-Path $VcpkgRoot 'vcpkg.exe') @('install', "--triplet=$Triplet")
$deps = Join-Path $PSScriptRoot "vcpkg_installed\$Triplet"

New-Item -ItemType Directory -Force build, dist | Out-Null

$cflags = @('/nologo', '/std:c++17', '/EHsc', '/O2', '/MT', '/W3', '/utf-8',
            '/DNOMINMAX', '/DSODIUM_STATIC', '/DMSGPACK_NO_BOOST',
            "/I$deps\include", '/Fobuild\')
$lflags = @('/link', "/LIBPATH:$deps\lib", '/MANIFEST:NO', 'libsodium.lib')

# CLI
Invoke-Native 'rc' @('/nologo', '/fo', 'build\cli.res', 'cli.rc')
Invoke-Native 'cl' ($cflags + @('main.cpp', 'build\cli.res', '/Febuild\synoxtract.exe') + $lflags + @('/SUBSYSTEM:CONSOLE'))

# GUI
Invoke-Native 'rc' @('/nologo', '/fo', 'build\resource.res', 'resource.rc')
Invoke-Native 'cl' ($cflags + @('gui.cpp', 'build\resource.res', '/Febuild\synoxtract-gui.exe') + $lflags +
    @('/SUBSYSTEM:WINDOWS', 'user32.lib', 'gdi32.lib', 'comctl32.lib', 'comdlg32.lib', 'shell32.lib', 'ole32.lib'))

New-Package 'synoxtract.exe' "synoxtract-$Version-win.zip"
New-Package 'synoxtract-gui.exe' "synoxtract-gui-$Version-win.zip"
