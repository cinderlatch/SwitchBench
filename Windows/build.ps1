param([switch]$Test)
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$out = (Resolve-Path 'build/windows').Path
# The framework compiler produces a WinForms executable that runs with Windows 11's .NET Framework.
$csc = Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 "/out:$(Join-Path $out 'SwitchBench.exe')" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'SwitchBench.cs')
if ($LASTEXITCODE) { throw 'Could not build the Windows interface.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$msvc = Get-ChildItem "$vs/VC/Tools/MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1
& "$($msvc.FullName)/bin/Hostx64/x64/lib.exe" /nologo /machine:x64 /def:Windows/Native.def "/out:$out/SwitchBenchNative.lib"
if ($LASTEXITCODE) { throw 'Could not create native import library.' }
$sources = @('Core','Container','CompressedContent','Utility','FileOperations','Workflow') | ForEach-Object { "Sources/$_.swift" }
$common = @('-swift-version','5','-whole-module-optimization','-I','Windows') + $sources + @('Windows/Platform.swift', '-L', $out, '-lSwitchBenchNative')
& swiftc @common -O Windows/Worker.swift -o "$out/SwitchBenchWorker.exe"
if ($LASTEXITCODE) { throw 'Could not build SwitchBench worker.' }
$toolchain = (Get-Command swiftc).Source -replace '[\\/]Toolchains[\\/].*$', ''
$runtimeCandidates = @(
    "$toolchain/Runtimes/6.3.3/usr/bin"
    "$env:ProgramFiles/Swift/Runtimes/6.3.3/usr/bin"
    "$env:LOCALAPPDATA/Programs/Swift/Runtimes/6.3.3/usr/bin"
) + $env:PATH.Split(';')
$runtime = $runtimeCandidates | Where-Object { $_ -and (Test-Path (Join-Path $_ 'swiftCore.dll')) -and $_ -match 'Runtimes' } | Select-Object -First 1
if (!$runtime) { throw 'Could not locate the Swift 6.3.3 runtime DLLs.' }
Copy-Item "$runtime/*.dll" $out
$redist = Get-ChildItem "$vs/VC/Redist/MSVC" -Directory | Sort-Object Name -Descending | ForEach-Object {
    Get-ChildItem "$($_.FullName)/x64" -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue
} | Select-Object -First 1
if ($redist) { Copy-Item "$($redist.FullName)/*.dll" $out }
Write-Host "Using Swift runtime at $runtime"
if ($Test) {
    $env:QA_FIXTURES = "$out/fixtures"
    & swiftc @common Tests/CoreTests.swift -o "$out/CoreTests.exe"
    if ($LASTEXITCODE) { throw 'Could not build Windows engine tests.' }
    & "$out/CoreTests.exe" "$out/hactool.exe" "$out/hacpack.exe"
    if ($LASTEXITCODE) { throw "Windows engine tests failed with exit code $LASTEXITCODE." }
    & swiftc @common Tests/UtilityTests.swift -o "$out/UtilityTests.exe"
    if ($LASTEXITCODE) { throw 'Could not build Windows utility tests.' }
    & "$out/UtilityTests.exe" "$out/hactool.exe"
    if ($LASTEXITCODE) { throw "Windows utility tests failed with exit code $LASTEXITCODE." }
    & swiftc @common Tests/WorkflowTests.swift -o "$out/WorkflowTests.exe"
    if ($LASTEXITCODE) { throw 'Could not build Windows workflow tests.' }
    & "$out/WorkflowTests.exe" "$out/hactool.exe" $env:QA_FIXTURES "$out/hacpack.exe"
    if ($LASTEXITCODE) { throw "Windows workflow tests failed with exit code $LASTEXITCODE." }
}
