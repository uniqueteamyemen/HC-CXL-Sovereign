# === File: Builder.ps1 (FINAL CORRECTED VERSION) ===
<#
Builder.ps1
Role: Builder (produce unsigned package + manifest only)
Principles enforced:
 - CRITICAL: Add Package Hash to BUILDER_MANIFEST for Verifier integrity check.
 - No package signing in builder stage.
 - Produce builder manifest with file hashes and reference binding.
 - Write immutable audit events to governance log.
Usage: .\Builder.ps1 -Root "D:\HC-CXL\Reconstruction\v2.1R" -Force -Clean -Verbose
#>
param(
    [string]$Root = "D:\HC-CXL\Reconstruction\v2.1R",
    [switch]$Force,
    [switch]$Clean,
    [switch]$Verbose
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$GOV = Join-Path $Root '0_governance'
$WORK = Join-Path $Root '1_source'
$BUILD = Join-Path $Root '2_build'
$PACKAGE_NAME = 'HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip'
$PACKAGE_PATH = Join-Path $BUILD $PACKAGE_NAME
$MANIFEST_PATH = Join-Path $BUILD 'BUILDER_MANIFEST.json'
function Write-Audit { param($evt,$details,$outcome,$extra=@{})
    if (-not (Test-Path $GOV)) { New-Item -Path $GOV -ItemType Directory -Force | Out-Null }
    $rec = @{ timestamp = (Get-Date).ToString('o'); event=$evt; details=$details; outcome=$outcome; extra=$extra }
    $rec | ConvertTo-Json -Depth 10 | Add-Content -Path (Join-Path $GOV 'sovereign_audit_trail.json') -Encoding UTF8
}
try {
    if ($Verbose) { Write-Host "Builder: init" }
    foreach ($d in @($Root,$WORK,$BUILD,$GOV)) { if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null } }
    if ($Clean) { Remove-Item -Path (Join-Path $BUILD '*') -Recurse -Force -ErrorAction SilentlyContinue }

    $workFiles = @((Get-ChildItem -Path $WORK -File -ErrorAction SilentlyContinue))
    if ($null -eq $workFiles -or $workFiles.Count -eq 0) { Write-Audit 'BUILDER_FAILED' 'No work files' 'FAILED'; throw 'No work files' }

    if ((@((Get-ChildItem -Path $BUILD -File -ErrorAction SilentlyContinue))).Count -gt 0) {
        if ($Force) { Remove-Item -Path (Join-Path $BUILD '*') -Recurse -Force } else { Write-Audit 'BUILDER_FAILED' 'Build dir not empty' 'FAILED'; throw 'Build dir not empty; use -Force' }
    }

    # copy source files to build directory
    foreach ($f in $workFiles) { Copy-Item -Path $f.FullName -Destination (Join-Path $BUILD $f.Name) -Force }

    # CRITICAL ENFORCEMENT: Check if ALL required files exist after copy. Placeholders are forbidden.
    $required = @(
        'HC-CXL_v2.1R_Theory.md','HC-CXL_v2.1R_Architecture.md','HC-CXL_v2.1R_Protocol.md','HC-CXL_v2.1R_Definitions.md',
        'HC-CXL_v2.1R_Reference_Model.json','HC-CXL_v2.1R_Axioms.json','HC-CXL_v2.1R_Measurement_Model.json',
        'HC-CXL_v2.1R_Validation_Map.json','HC-CXL_v2.1R_Modification_Map.json','Unified_References_v21R.md',
        'operational_model_v21r.md','v2.1R_measurement_schema.json', $PACKAGE_NAME # Include package name for later hash calculation
    )
    $missingRequired = @()
    foreach ($r in $required) {
        # We skip checking the package zip file itself in the build folder at this point, as it hasn't been created yet.
        if ($r -ne $PACKAGE_NAME) {
            $p = Join-Path $BUILD $r
            if (-not (Test-Path $p)) {
                $missingRequired += $r
            }
        }
    }

    if ($missingRequired.Count -gt 0) {
        Write-Audit 'BUILDER_FAILED' 'Critical required files missing from source' 'FAILED' -extra @{missing=$missingRequired}
        throw "CRITICAL FAILURE: Missing mandatory source files: $($missingRequired -join ', ')"
    }
    if ($Verbose) { Write-Host "Builder: All mandatory files verified." }

    # manifest
    $files = @(Get-ChildItem -Path $BUILD -File)
    $manifest = [ordered]@{
        manifest_type = 'BUILDER_MANIFEST'
        version = '2.1R'
        build_timestamp = (Get-Date).ToString('o')
        files = @{
            total_count = $files.Count
            list = $files | Select-Object -ExpandProperty Name
            hashes = @{}
        }
        governance = @{ applied = $false; required = $true }
    }
    # Calculate hash for source files
    foreach ($file in $files) { $h=(Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash; $manifest.files.hashes[$file.Name]=$h }

    # package (unsigned)
    Compress-Archive -Path (Join-Path $BUILD '*') -DestinationPath $PACKAGE_PATH -Force
    $pkgHash = (Get-FileHash -Path $PACKAGE_PATH -Algorithm SHA256).Hash

    # CRITICAL FIX: Add package hash to the manifest for the Verifier to check integrity
    $manifest.files.hashes[$PACKAGE_NAME]=$pkgHash
    $manifest.files.total_count = $manifest.files.total_count + 1 # Update total count
    $manifest.files.list += $PACKAGE_NAME # Add package name to list

    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $MANIFEST_PATH -Encoding UTF8

    # critical enforcement: no package signature allowed here
    $sigs = @(Get-Item -Path "$PACKAGE_PATH.asc","$PACKAGE_PATH.sig","$PACKAGE_PATH.p7s" -ErrorAction SilentlyContinue)
    if ($sigs.Count -gt 0) { Write-Audit 'BUILDER_FAILED' 'Pre-existing package signature detected' 'FAILED' -extra @{sig=$sigs.Name}; throw 'Pre-existing package signature detected; aborting to preserve separation' }

    Write-Audit 'BUILDER_COMPLETED' "Package created" 'SUCCESS' -extra @{package_hash=$pkgHash; file_count=$manifest.files.total_count}
    if ($Verbose) { Write-Host "Builder done: $PACKAGE_PATH (sha256:$pkgHash)" }
    return @{ Success=$true; PackagePath=$PACKAGE_PATH; ManifestPath=$MANIFEST_PATH; PackageHash=$pkgHash }
} catch {
    Write-Audit 'BUILDER_EXCEPTION' $_.Exception.Message 'FAILED'
    throw
}
