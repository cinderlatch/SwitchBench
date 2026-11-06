$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$out = (Resolve-Path 'build/windows').Path
$bundle = Join-Path $out 'SwitchBench'
$engine = Join-Path $bundle 'Engine'
$licenses = Join-Path $bundle 'Licenses'
if (Test-Path $bundle) { Remove-Item -LiteralPath $bundle -Recurse -Force }
New-Item -ItemType Directory -Path $engine, $licenses | Out-Null
Copy-Item "$out/SwitchBench.exe" $bundle
Copy-Item "$out/SwitchBenchWorker.exe", "$out/SwitchBenchNative.dll", "$out/hactool.exe", "$out/hacpack.exe" $engine

Copy-Item "$out/*.dll" $engine

Copy-Item LICENSE, COPYRIGHT.md, CREDITS.md, THIRD_PARTY_NOTICES.md, AI_DISCLOSURE.md, PRIVACY.md $bundle
Copy-Item docs/WINDOWS.md "$bundle/Start Here.md"
Copy-Item Vendor/hactool/LICENSE "$licenses/hactool.txt"
Copy-Item Vendor/hacPack/LICENSE "$licenses/hacPack.txt"
Copy-Item Vendor/hacPack/LICENSES "$licenses/hacPack-notices" -Recurse
Copy-Item Vendor/hactool/mbedtls/apache-2.0.txt "$licenses/Mbed-TLS.txt"
Copy-Item Vendor/zstd-1.5.7/LICENSE "$licenses/Zstandard.txt"
Copy-Item "$out/zlib-license.txt" "$licenses/zlib.txt"
$swiftComponents = [ordered]@{
    'swift' = 'LICENSE.txt'
    'swift-corelibs-foundation' = 'LICENSE'
    'swift-foundation' = 'LICENSE.md'
    'swift-corelibs-libdispatch' = 'LICENSE'
    'swift-foundation-icu' = 'LICENSE.md'
}
foreach ($component in $swiftComponents.Keys) {
    $url = "https://raw.githubusercontent.com/swiftlang/$component/swift-6.3.3-RELEASE/$($swiftComponents[$component])"
    Invoke-WebRequest -Uri $url -OutFile "$licenses/$component.txt"
}

Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/unicode-org/icu/release-76-1/LICENSE' -OutFile "$licenses/ICU-76.1.txt"

# Test from the packaged folder with only system locations on PATH.
$previousPath = $env:Path
try {
    $env:Path = "$env:SystemRoot/System32;$env:SystemRoot"
    & "$PSScriptRoot/test-package.ps1" -Bundle $bundle -Fixtures "$out/fixtures"
} finally { $env:Path = $previousPath }
$zip = Join-Path $out 'SwitchBench-Windows-x64.zip'
Compress-Archive -Path $bundle -DestinationPath $zip -Force
Write-Host "Packaged $zip"
