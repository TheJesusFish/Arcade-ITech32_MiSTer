<#
.SYNOPSIS
Build the core with the pinned sources and build date using Quartus 17.0.x.
.DESCRIPTION
Run map, fit, asm and sta directly, without rewriting project settings or
regenerating build_id.v. Install Quartus Prime Lite 17.0.2 with Cyclone V support.
Quartus discovery order: -QuartusRoot, QUARTUS_ROOTDIR, QUARTUS_ROOTDIR_OVERRIDE,
then quartus_map on PATH. All stages must come from the same installation.
.PARAMETER QuartusRoot
The Quartus installation directory containing bin64 (or bin on Linux).
.PARAMETER SubstDrive
Optional unused Windows drive letter, for example Q:. This works around old
Quartus Tcl path-normalization problems. SUBST mappings are shared with other
processes; an existing mapping is never replaced, and only this run's unchanged
mapping is removed. Omit this option to use the normal project path.
.EXAMPLE
./scripts/build_quartus.ps1 -QuartusRoot C:/intelFPGA_lite/17.0/quartus -SubstDrive Q:
.EXAMPLE
./scripts/build_quartus.ps1 -Flow map -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('compile', 'map', 'fit', 'asm', 'sta')]
    [string]$Flow = 'compile',
    [string]$QuartusRoot,
    [ValidatePattern('^[A-Za-z]:?$')]
    [string]$SubstDrive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$BuildProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$BuildOnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
$BuildExeSuffix = if ($BuildOnWindows) { '.exe' } else { '' }
$BuildStages = if ($Flow -eq 'compile') { @('map', 'fit', 'asm', 'sta') } else { @($Flow) }

foreach ($BuildInput in @('Arcade-ITech32.qpf', 'Arcade-ITech32.qsf', 'files.qip', 'build_id.v')) {
    if (-not (Test-Path -LiteralPath (Join-Path $BuildProjectRoot $BuildInput) -PathType Leaf)) {
        throw "Required source input is missing: $BuildInput. Restore it from the source checkout."
    }
}

if (-not $QuartusRoot) { $QuartusRoot = $env:QUARTUS_ROOTDIR }
if (-not $QuartusRoot) { $QuartusRoot = $env:QUARTUS_ROOTDIR_OVERRIDE }
$BuildQuartusBin = $null
if ($QuartusRoot) {
    $BuildQuartusRoot = (Resolve-Path -LiteralPath $QuartusRoot).Path
    foreach ($BuildBinCandidate in @((Join-Path $BuildQuartusRoot 'bin64'), (Join-Path $BuildQuartusRoot 'bin'), $BuildQuartusRoot)) {
        if (Test-Path -LiteralPath (Join-Path $BuildBinCandidate "quartus_map$BuildExeSuffix") -PathType Leaf) {
            $BuildQuartusBin = $BuildBinCandidate
            break
        }
    }
} else {
    $BuildMapCommand = Get-Command "quartus_map$BuildExeSuffix" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($BuildMapCommand) { $BuildQuartusBin = Split-Path -Parent $BuildMapCommand.Source }
}
if (-not $BuildQuartusBin) {
    throw 'Quartus was not found. Set -QuartusRoot or QUARTUS_ROOTDIR, or add Quartus 17.0.x to PATH.'
}
$BuildTools = @{}
foreach ($BuildToolName in @('map', 'fit', 'asm', 'sta')) {
    $BuildToolPath = Join-Path $BuildQuartusBin "quartus_$BuildToolName$BuildExeSuffix"
    if (-not (Test-Path -LiteralPath $BuildToolPath -PathType Leaf)) {
        throw "The selected Quartus installation is incomplete: $BuildToolPath"
    }
    $BuildTools[$BuildToolName] = $BuildToolPath
}

function Get-BuildSubstTarget {
    param([string]$Program, [string]$Drive)
    $BuildMappings = & $Program
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect existing SUBST mappings.' }
    foreach ($BuildMapping in $BuildMappings) {
        if ($BuildMapping -match '^([A-Za-z]:)\\:\s*=>\s*(.+)$' -and $Matches[1] -eq $Drive) {
            return $Matches[2]
        }
    }
    return $null
}

$BuildDrive = $null
$BuildSubstProgram = $null
if ($SubstDrive) {
    if (-not $BuildOnWindows) { throw '-SubstDrive is only supported on Windows.' }
    $BuildDrive = $SubstDrive.TrimEnd(':').ToUpperInvariant() + ':'
    $BuildSubstProgram = (Get-Command subst.exe -CommandType Application -ErrorAction Stop).Source
    $BuildExistingMapping = Get-BuildSubstTarget -Program $BuildSubstProgram -Drive $BuildDrive
    $BuildExistingDrive = Get-PSDrive -Name $BuildDrive.TrimEnd(':') -ErrorAction SilentlyContinue
    if ($BuildExistingMapping -or $BuildExistingDrive -or
        ([Environment]::GetLogicalDrives() -contains "$BuildDrive\") -or
        (Test-Path -LiteralPath "$BuildDrive\")) {
        throw "$BuildDrive is already in use; choose a different unused drive letter or omit -SubstDrive."
    }
}

if (-not $PSCmdlet.ShouldProcess($BuildProjectRoot, "Run Quartus $($BuildStages -join ', ') from $BuildQuartusBin")) { return }

$BuildCreatedMapping = $false
$BuildLocationPushed = $false
$BuildFailure = $null
$BuildCleanupFailure = $null
try {
    $BuildWorkingRoot = $BuildProjectRoot
    if ($BuildDrive) {
        & $BuildSubstProgram $BuildDrive $BuildProjectRoot
        if ($LASTEXITCODE -ne 0) { throw "Unable to create SUBST mapping $BuildDrive. No mapping will be removed." }
        $BuildCreatedMapping = $true
        $BuildWorkingRoot = "$BuildDrive\"
    }
    Push-Location -LiteralPath $BuildWorkingRoot
    $BuildLocationPushed = $true
    $BuildProjectPath = Join-Path $BuildWorkingRoot 'Arcade-ITech32'
    foreach ($BuildStage in $BuildStages) {
        $BuildArguments = @($BuildProjectPath, '-c', 'Arcade-ITech32')
        if ($BuildStage -ne 'sta') {
            $BuildArguments += '--read_settings_files=on', '--write_settings_files=off'
        }
        # Quartus 17 STA does not accept the map/fit/asm settings switches.
        & $BuildTools[$BuildStage] @BuildArguments
        if ($LASTEXITCODE -ne 0) { throw "Quartus $BuildStage failed (exit $LASTEXITCODE)." }
    }
} catch {
    $BuildFailure = $_
} finally {
    if ($BuildLocationPushed) { Pop-Location }
    if ($BuildCreatedMapping) {
        try {
            $BuildCurrentTarget = Get-BuildSubstTarget -Program $BuildSubstProgram -Drive $BuildDrive
            if (-not $BuildCurrentTarget) {
                throw "$BuildDrive no longer has the mapping created by this build; no drive was removed."
            }
            $BuildExpectedTarget = [IO.Path]::GetFullPath($BuildProjectRoot).TrimEnd([char[]]'\/')
            $BuildObservedTarget = [IO.Path]::GetFullPath($BuildCurrentTarget).TrimEnd([char[]]'\/')
            if (-not [StringComparer]::OrdinalIgnoreCase.Equals($BuildExpectedTarget, $BuildObservedTarget)) {
                throw "$BuildDrive changed ownership during the build; its current mapping was left untouched."
            }
            & $BuildSubstProgram $BuildDrive /d
            if ($LASTEXITCODE -ne 0) { throw "Unable to remove this build's SUBST mapping $BuildDrive." }
        } catch {
            $BuildCleanupFailure = $_
        }
    }
}
if ($BuildFailure) {
    if ($BuildCleanupFailure) { Write-Warning $BuildCleanupFailure.Exception.Message }
    throw $BuildFailure
}
if ($BuildCleanupFailure) { throw $BuildCleanupFailure }
