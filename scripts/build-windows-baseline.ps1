[CmdletBinding()]
param(
    [string]$SourcePath = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory = $true)][string]$VcpkgRoot,
    [string]$CMake = 'cmake',
    [string]$EvidenceDirectory = (Join-Path $SourcePath 'build/windows/evidence'),
    [string]$BaselineCommit,
    [int]$Parallel = 4,
    [switch]$Fresh
)
$ErrorActionPreference = 'Stop'
$SourcePath = (Resolve-Path -LiteralPath $SourcePath).Path
$VcpkgRoot = (Resolve-Path -LiteralPath $VcpkgRoot).Path
$VcpkgCMakePath = $VcpkgRoot.Replace('\', '/')
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force $EvidenceDirectory | Out-Null
$CMake = (Get-Command $CMake -ErrorAction Stop).Source
$CTest = Join-Path (Split-Path -Parent $CMake) 'ctest.exe'
if (!(Test-Path -LiteralPath $CTest)) { throw 'CTest is missing beside CMake.' }
if (!(Test-Path -LiteralPath (Join-Path $VcpkgRoot 'scripts/buildsystems/vcpkg.cmake'))) { throw 'Invalid vcpkg directory.' }

function Invoke-LoggedTool {
    param([string]$Tool, [string[]]$Arguments, [string]$Log)
    & $Tool @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $EvidenceDirectory $Log)
    if ($LASTEXITCODE -ne 0) { throw "$Tool failed with exit code $LASTEXITCODE. See $Log." }
}

Push-Location $SourcePath
$previousMetrics = $env:VCPKG_DISABLE_METRICS
$previousConcurrency = $env:VCPKG_MAX_CONCURRENCY
try {
    $env:VCPKG_DISABLE_METRICS = '1'
    $env:VCPKG_MAX_CONCURRENCY = "$Parallel"
    & $CMake --version | Set-Content (Join-Path $EvidenceDirectory 'cmake-version.txt')
    if (Test-Path -LiteralPath '.git') {
        $BaselineCommit = (& git rev-parse HEAD)
        & git diff --stat | Set-Content (Join-Path $EvidenceDirectory 'source-changes.txt')
    } elseif (!$BaselineCommit) {
        throw 'A source archive requires an explicit BaselineCommit provenance value.'
    }
    $BaselineCommit | Set-Content (Join-Path $EvidenceDirectory 'source-commit.txt')
    $configureArguments = @('--preset', 'windows', "-DVCPKG_ROOT=$VcpkgCMakePath")
    if ($Fresh) { $configureArguments += '--fresh' }
    Invoke-LoggedTool $CMake $configureArguments 'configure.log'
    Invoke-LoggedTool $CMake @('--build', '--preset', 'windows-release', '--parallel', "$Parallel") 'build.log'
    Invoke-LoggedTool $CTest @('--test-dir', 'build/windows', '-C', 'Release', '--output-on-failure', '--parallel', "$Parallel", '--output-junit', (Join-Path $EvidenceDirectory 'tests.xml')) 'tests.log'
    $binary = Join-Path $SourcePath 'build/windows/Release/OpenLoco.exe'
    if (!(Test-Path -LiteralPath $binary)) { throw 'Release application was not produced.' }
    Get-FileHash -Algorithm SHA256 -LiteralPath $binary | ConvertTo-Json | Set-Content (Join-Path $EvidenceDirectory 'binary-sha256.json')
    Copy-Item -LiteralPath 'build/windows/CMakeCache.txt' -Destination (Join-Path $EvidenceDirectory 'CMakeCache.txt')
    $installed = Join-Path $SourcePath 'build/windows/vcpkg_installed/vcpkg/status'
    if (Test-Path -LiteralPath $installed) { Copy-Item -LiteralPath $installed -Destination (Join-Path $EvidenceDirectory 'vcpkg-installed-status.txt') }
    Write-Output 'Windows compilation and tests passed. Gameplay validation still requires user-owned game data.'
} finally {
    $env:VCPKG_DISABLE_METRICS = $previousMetrics
    $env:VCPKG_MAX_CONCURRENCY = $previousConcurrency
    Pop-Location
}
