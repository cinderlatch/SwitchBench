param([Parameter(Mandatory)][string]$Bundle, [Parameter(Mandatory)][string]$Fixtures)
$ErrorActionPreference = 'Stop'
$app = Start-Process -FilePath "$Bundle/SwitchBench.exe" -ArgumentList '--smoke-test' -PassThru
if (!$app.WaitForExit(30000)) { $app.Kill(); throw 'The Windows interface smoke test timed out.' }
if ($app.ExitCode) { throw "The Windows interface smoke test failed ($($app.ExitCode))." }
Write-Host 'PASS: Windows app opens and navigates all tools'
$root = Join-Path ([IO.Path]::GetTempPath()) "SwitchBench-ü-$([Guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $root | Out-Null
function Invoke-Worker($Request) {
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new("$Bundle/Engine/SwitchBenchWorker.exe")
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    try {
        if (!$process.Start()) { throw 'Could not start the packaged worker.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $bytes = [Text.Encoding]::UTF8.GetBytes(($Request | ConvertTo-Json -Compress) + "`n")
        $process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $process.StandardInput.BaseStream.Flush()
        if (!$process.WaitForExit(120000)) { $process.Kill(); throw 'The packaged worker timed out.' }
        if ($process.ExitCode) { throw "The packaged worker failed: $($stderr.Result)" }
        $stdout.Result -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
    } finally { $process.Dispose() }
}
try {
    $source = Join-Path $root 'Jeu échantillon.nsp'
    Copy-Item "$Fixtures/Sample Game.nsp" $source
    $before = (Get-FileHash -LiteralPath $source).Hash
    $request = @{
        tool = 'inspect'; files = @($source); folder = $null; keys = "$Fixtures/test-prod.keys"
        titleKeys = $null; previewOnly = $false
    }
    $events = @(Invoke-Worker $request)
    if (!(($events | Where-Object status -eq 'Checked').Count)) {
        $events | ConvertTo-Json -Depth 5 | Write-Host
        throw 'The packaged worker did not verify a game in a Unicode path.'
    }
    $request.tool = 'combine'
    $request.files = @($source, "$Fixtures/Sample Add-on.nsp")
    $request.folder = $root
    $events = @(Invoke-Worker $request)
    $saved = $events | Where-Object status -eq 'Saved'
    if (!$saved -or !(Test-Path -LiteralPath $saved.output)) {
        $events | ConvertTo-Json -Depth 5 | Write-Host
        throw 'The packaged worker did not publish its combined copy.'
    }
    $request.tool = 'compress'
    $request.files = @($source)
    $events = @(Invoke-Worker $request)
    $compressed = $events | Where-Object status -eq 'Saved'
    if (!$compressed -or !(Test-Path -LiteralPath $compressed.output) -or
        (Get-Item -LiteralPath $compressed.output).Length -ge (Get-Item -LiteralPath $source).Length) {
        $events | ConvertTo-Json -Depth 5 | Write-Host
        throw 'The packaged worker did not publish a smaller NSZ copy.'
    }
    $request.tool = 'inspect'
    $request.folder = $null
    $request.files = @($compressed.output)
    $events = @(Invoke-Worker $request)
    if (!(($events | Where-Object status -eq 'Checked').Count)) {
        $events | ConvertTo-Json -Depth 5 | Write-Host
        throw 'The packaged worker could not check its saved NSZ copy.'
    }
    if ((Get-FileHash -LiteralPath $source).Hash -ne $before) { throw 'The original changed.' }
    Write-Host 'PASS: packaged worker verified, combined and compressed files with Unicode paths and preserved the original'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
