# Verifier.ps1 (?????? ???????)
# Role: Verifier (verify builder outputs; sign verification records & timestamps)
param(
    [string]$Root = 'D:\HC-CXL\Reconstruction\v2.1R',
    [switch]$SkipSigning,
    [switch]$AllowPackageSigning,
    [switch]$SPF,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Verbose) { $VerbosePreference = 'Continue' }

# Paths
$GOV = Join-Path $Root '0_governance'
$BUILD = Join-Path $Root '2_build'
$SEAL = Join-Path $Root '3_seal'
$PACKAGE_NAME = 'HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip'
$PACKAGE_PATH = Join-Path $BUILD $PACKAGE_NAME
$MANIFEST_PATH = Join-Path $BUILD 'BUILDER_MANIFEST.json'

# Sovereign key identifier (fingerprint)
$SOV_KEY = '5552541D93559EEF53A2DEB4B20DE574B24DA9E3'

# Helpers
function Write-Audit {
    param($evt, $details, $outcome, $extra = @{})
    try {
        if (-not (Test-Path $GOV)) { New-Item -Path $GOV -ItemType Directory -Force | Out-Null }
        $rec = @{
            timestamp = (Get-Date).ToString('o')
            event     = $evt
            details   = $details
            outcome   = $outcome
            extra     = $extra
            runner    = $env:USERNAME
            host      = $env:COMPUTERNAME
        }
        $rec | ConvertTo-Json -Depth 10 | Add-Content -Path (Join-Path $GOV 'sovereign_audit_trail.json') -Encoding UTF8
    } catch {
        Write-Host "AUDIT WRITE FAILED: $_" -ForegroundColor Yellow
    }
}

function Has-GpgKey {
    param([string]$finger)
    try {
        $gpgCmd = Get-Command gpg -ErrorAction SilentlyContinue
        if (-not $gpgCmd) { return $false }
        # list-secret-keys ensures signing capability; use --with-colons for machine readable output
        $out = & gpg --batch --with-colons --list-secret-keys $finger 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) { return $false }
        return $true
    } catch {
        return $false
    }
}

try {
    if ($SPF) { $AllowPackageSigning = $true }

    # prepare directories
    foreach ($d in @($GOV, $BUILD, $SEAL)) { if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null } }

    if (-not (Test-Path $PACKAGE_PATH)) {
        Write-Audit 'VERIFIER_FAILED' 'Package not found' 'FAILED'
        throw "Builder package not found: $PACKAGE_PATH"
    }
    if (-not (Test-Path $MANIFEST_PATH)) {
        Write-Audit 'VERIFIER_FAILED' 'Manifest not found' 'FAILED'
        throw "Builder manifest not found: $MANIFEST_PATH"
    }

    # create verification workspace
    $vt = Get-Date -Format 'yyyyMMdd_HHmmss'
    $verifyDir = Join-Path $SEAL "VERIFICATION_$vt"
    $evidence = Join-Path $verifyDir 'EVIDENCE'
    $signs = Join-Path $verifyDir 'SIGNATURES'
    $reports = Join-Path $verifyDir 'REPORTS'
    foreach ($p in @($verifyDir, $evidence, $signs, $reports)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }

    # copy inputs to evidence
    Copy-Item -Path $PACKAGE_PATH -Destination (Join-Path $evidence (Split-Path -Leaf $PACKAGE_PATH)) -Force
    Copy-Item -Path $MANIFEST_PATH -Destination (Join-Path $evidence (Split-Path -Leaf $MANIFEST_PATH)) -Force
    Write-Audit 'VERIFIER_START' 'Copied package and manifest to evidence' 'STARTED' -extra @{ package = (Split-Path -Leaf $PACKAGE_PATH) }

    # integrity check: package hash vs manifest
    $pkgHash = (Get-FileHash -Path $PACKAGE_PATH -Algorithm SHA256).Hash
    $manifest = Get-Content $MANIFEST_PATH -Raw | ConvertFrom-Json

    # validate manifest structure robustly
    if (-not $manifest.files -or -not $manifest.files.list) {
        Write-Audit 'VERIFIER_FAILED' 'Manifest incomplete or missing files.list' 'FAILED'
        throw "Manifest incomplete: files.list missing"
    }

    if (-not $manifest.files.hashes) { $manifest.files.hashes = @{} } # tolerate older manifests

    # If manifest contains package entry, compare (FIXED: using $null check for compatibility)
    if ($manifest.files.hashes.$PACKAGE_NAME -ne $null) {
        $manifestPkgHash = $manifest.files.hashes.$PACKAGE_NAME
        if ($manifestPkgHash -ne $pkgHash) {
            Write-Audit 'VERIFIER_FAILED' 'Package hash mismatch' 'FAILED' -extra @{ manifest = $manifestPkgHash; actual = $pkgHash }
            throw "Package hash mismatch: $pkgHash != $manifestPkgHash"
        }
    } else {
        # not fatal ? manifest may list package hash elsewhere; record warning
        Write-Audit 'VERIFIER_WARNING' 'Manifest does not list package hash' 'PARTIAL' -extra @{ package_has_hash = $false }
    }

    # extract package to temp and verify required files listed in manifest
    $tmp = Join-Path $env:TEMP "HCX_VERIFY_$vt"
    New-Item -Path $tmp -ItemType Directory -Force | Out-Null
    try {
        Expand-Archive -Path $PACKAGE_PATH -DestinationPath $tmp -Force
        $required = @($manifest.files.list)  # ensure array
        $checks = @()
        $missing = @()
        foreach ($f in $required) {
            $fp = Join-Path $tmp $f
            if (Test-Path $fp) {
                $fi = Get-Item $fp
                $checks += [pscustomobject]@{ file = $f; status = 'PASS'; size_bytes = $fi.Length; timestamp = (Get-Date).ToString('o') }
            } else {
                $missing += $f
                $checks += [pscustomobject]@{ file = $f; status = 'FAIL'; size_bytes = 0; timestamp = (Get-Date).ToString('o'); details = 'Not found in package' }
            }
        }
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    $missingCount = @($missing).Count
    if ($missingCount -gt 0) {
        Write-Audit 'VERIFIER_WARNING' 'Missing files in package' 'PARTIAL' -extra @{ missing = $missing }
    }

    # create verification record and timestamp (always allowed artifacts)
    $verRec = @{
        document_type = 'SOVEREIGN_VERIFICATION_RECORD'
        version = ($manifest.version -ne $null) ? $manifest.version : '2.1R'
        verification_timestamp = (Get-Date).ToString('o')
        verifier = @{ name = $env:USERNAME; fingerprint = $SOV_KEY }
        package = @{ name = $PACKAGE_NAME; hash = $pkgHash; size_bytes = (Get-Item $PACKAGE_PATH).Length }
        checks = $checks
        missing_count = $missingCount
        overall_status = (if ($missingCount -eq 0) { 'PASS' } else { 'PARTIAL' })
    }

    $vpath = Join-Path $reports 'SOVEREIGN_VERIFICATION_RECORD.json'
    $tpath = Join-Path $reports 'package_timestamp.json'

    # write verification artifacts reliably
    $verRec | ConvertTo-Json -Depth 15 | Out-File -FilePath $vpath -Encoding UTF8
    @{ timestamp = (Get-Date).ToString('o'); package_hash = $pkgHash; issuer = $SOV_KEY } | ConvertTo-Json -Depth 10 | Out-File -FilePath $tpath -Encoding UTF8

    Write-Audit 'VERIFIER_ARTIFACTS_CREATED' 'Verification record & timestamp created' 'SUCCESS' -extra @{ verRec = (Split-Path -Leaf $vpath); tstamp = (Split-Path -Leaf $tpath) }

    # signing allowed artifacts (verification record & timestamp)
    $gpgOk = Has-GpgKey -finger $SOV_KEY
    if (-not $SkipSigning -and $gpgOk) {
        try {
            & gpg --batch --yes --default-key $SOV_KEY --armor --detach-sign --output "$vpath.asc" $vpath 2>$null
            & gpg --batch --yes --default-key $SOV_KEY --armor --detach-sign --output "$tpath.asc" $tpath 2>$null

            if (Test-Path "$vpath.asc") { Copy-Item -Path "$vpath.asc" -Destination $signs -Force -ErrorAction SilentlyContinue }
            if (Test-Path "$tpath.asc") { Copy-Item -Path "$tpath.asc" -Destination $signs -Force -ErrorAction SilentlyContinue }

            Write-Audit 'VERIFIER_SIGNED' 'Verification record & timestamp signed' 'SUCCESS' -extra @{ signed = @((Split-Path -Leaf $vpath.asc), (Split-Path -Leaf $tpath.asc)) }
        } catch {
            Write-Audit 'VERIFIER_SIGN_ERROR' "GPG signing failed: $($_.Exception.Message)" 'FAILED'
            # do not fail entire flow for signing error; continue with unsigned artifacts
        }
    } else {
        Write-Audit 'VERIFIER_SIGN_SKIPPED' 'Signing skipped or GPG key not available' 'SKIPPED' -extra @{ gpg_available = $gpgOk; skip_flag = $SkipSigning.IsPresent }
    }

    # package signing: only if explicitly authorized (AllowPackageSigning) and SPF
    if ($AllowPackageSigning) {
        if (-not $SPF) {
            Write-Audit 'VERIFIER_FAILED' 'AllowPackageSigning without SPF' 'FAILED'
            throw 'AllowPackageSigning requires SPF'
        }
        if (-not $gpgOk -and -not $SkipSigning) {
            Write-Audit 'VERIFIER_FAILED' 'GPG required for package signing' 'FAILED'
            throw "Sovereign key not available for package signing"
        }
        try {
            $packageCopy = Join-Path $signs (Split-Path -Leaf $PACKAGE_PATH)
            Copy-Item -Path $PACKAGE_PATH -Destination $packageCopy -Force
            if (-not $SkipSigning -and $gpgOk) {
                & gpg --batch --yes --default-key $SOV_KEY --armor --detach-sign --output "$packageCopy.asc" $packageCopy 2>$null
                if (Test-Path "$packageCopy.asc") { Write-Audit 'PACKAGE_SIGNED' 'Package signed under explicit authorization' 'SUCCESS' -extra @{ signed = (Split-Path -Leaf $packageCopy.asc) } }
                else { Write-Audit 'PACKAGE_SIGN_WARN' 'Package signing attempted but asc not found' 'WARNING' }
            } else {
                Write-Audit 'PACKAGE_PREPARED' 'Package copied to signs (no signing)' 'INFO'
            }
        } catch {
            Write-Audit 'PACKAGE_SIGN_ERROR' "Package signing failed: $($_.Exception.Message)" 'FAILED'
            throw
        }
    } else {
        # safeguard: ensure no pre-existing package signatures are present in build
        $preSigs = @(Get-ChildItem -Path $BUILD -File -Filter "$PACKAGE_NAME*.asc","$PACKAGE_NAME*.sig" -ErrorAction SilentlyContinue)
        $preSigsCount = @($preSigs).Count
        if ($preSigsCount -gt 0) {
            Write-Audit 'VERIFIER_FAILED' 'Premature package signature(s) detected in builder output' 'FAILED' -extra @{ found = $preSigs | Select-Object -ExpandProperty Name }
            throw "Premature package signature(s) detected: $($preSigs | Select-Object -ExpandProperty Name -join ', ')"
        }
        Write-Audit 'PACKAGE_SIGNING_FORBIDDEN' 'Package signing not permitted in this run' 'INFO'
    }

    # final summary
    $passed = (@($checks | Where-Object { $_.status -eq 'PASS' })).Count
    $totalChecks = (@($checks)).Count
    $failed = $totalChecks - $passed
    $summary = @{
        summary_time    = (Get-Date).ToString('o')
        total_checks    = $totalChecks
        passed_checks   = $passed
        failed_checks   = $failed
        signing_applied = (-not $SkipSigning -and $gpgOk)
        package_signed  = $AllowPackageSigning -and (Test-Path (Join-Path $signs (Split-Path -Leaf "$PACKAGE_NAME.asc")))
        verification_outcome = (if ($failed -eq 0) { 'ACCEPTED' } else { 'PARTIAL' })
    }
    $summary | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $reports 'verification_summary.json') -Encoding UTF8

    # human-readable report
    $hr = @"
Sovereign verification: $($summary.verification_outcome)
Package hash: $pkgHash
Verification dir: $verifyDir
Signatures present: $((Get-ChildItem -Path $signs -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', ')
"@
    $hr | Out-File -FilePath (Join-Path $reports 'VERIFICATION_REPORT.md') -Encoding UTF8

    Write-Audit 'VERIFIER_COMPLETED' 'Verifier finished' 'SUCCESS' -extra @{ verifyDir = $verifyDir; outcome = $summary.verification_outcome }

    return @{ Success = $true; VerificationDir = $verifyDir; Summary = $summary; Signatures = @(Get-ChildItem -Path $signs -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) }

} catch {
    Write-Audit 'VERIFIER_FAILED' $_.Exception.Message 'FAILED'
    throw
}
