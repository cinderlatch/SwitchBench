param([switch]$Test)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$out = (Resolve-Path 'build/windows').Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$msvc = Get-ChildItem "$vs/VC/Tools/MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1
& "$($msvc.FullName)/bin/Hostx64/x64/lib.exe" /nologo /machine:x64 /def:Windows/Native.def "/out:$out/SwitchBenchNative.lib"
if ($LASTEXITCODE) { throw 'Could not create native import library.' }
$sources = @('Core','Container','CompressedContent','Utility','FileOperations','Workflow') | ForEach-Object { "Sources/$_.swift" }
$common = @('-swift-version','5','-O') + $sources + @('Windows/Platform.swift', "$out/SwitchBenchNative.lib")
& swiftc @common Windows/Worker.swift -o "$out/SwitchBenchWorker.exe"
if ($LASTEXITCODE) { throw 'Could not build SwitchBench worker.' }
if ($Test) {
    & swiftc @common Tests/CoreTests.swift -o "$out/CoreTests.exe"
    if ($LASTEXITCODE) { throw 'Could not build Windows engine tests.' }
    & "$out/CoreTests.exe" "$out/hactool.exe"
    if ($LASTEXITCODE) { throw 'Windows engine tests failed.' }
}
