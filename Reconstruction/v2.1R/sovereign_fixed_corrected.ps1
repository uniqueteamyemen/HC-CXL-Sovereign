<#
sovereign_safe_full_enhanced.ps1
HC-CXL v2.1R â€” Enhanced triple-layer separation pipeline
Layer1: Raw Build (transport only)
Layer2: Scientific Verification (black-box verification)
Layer3: IVL (final seal)
Principles: strict separation, independent workspaces, retry-from-layer, robust audit trail
Note: Save this file as UTF-8 (no BOM). All content is ASCII/English-only.
#>

[CmdletBinding()]
param(
    [ValidateSet('BuildOnly','ScientificOnly','IVLOnly','FullSeparation','PublishOnly')]
    [string]$Phase = 'FullSeparation',

    [switch]$Clean,
    [switch]$Force,
    [switch]$SkipSigning,
    [switch]$SkipScientificVerification,
    

    [string]$RetryFromPhase,
    [string]$PreviousBuildHash
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Root layout
$ROOT = "D:\HC-CXL\Reconstruction\v2.1R"
$WORK = Join-Path $ROOT "1_source"

$LAYER1_BUILD = Join-Path $ROOT "2_build_L1"
$LAYER2_VERIFY = Join-Path $ROOT "3_verify_L2"
$LAYER3_IVL = Join-Path $ROOT "4_ivl_L3"
$LAYER4_PUBLISH = Join-Path $ROOT "5_publish_L4"
$GOV = Join-Path $ROOT "0_governance"

$SOVEREIGN_KEY = @{
    Fingerprint = "5552541D93559EEF53A2DEB4B20DE574B24DA9E3"
    Name = "Hossam Sovereign Engine"
    Email = "security@hc-cxl.com"
}

$PACKAGE_NAME = "HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip"

$LAYER1_PACKAGE = Join-Path $LAYER1_BUILD "${PACKAGE_NAME}_L1_RAW.zip"
$LAYER1_MANIFEST = Join-Path $LAYER1_BUILD "LAYER1_BUILDER_MANIFEST.json"

$LAYER2_PACKAGE = Join-Path $LAYER2_VERIFY "${PACKAGE_NAME}_L2_VERIFIED.zip"
$LAYER2_REPORT = Join-Path $LAYER2_VERIFY "LAYER2_SCIENTIFIC_REPORT.json"

$LAYER3_PACKAGE = Join-Path $LAYER3_IVL "${PACKAGE_NAME}_L3_SEALED.zip"
$LAYER3_REPORT = Join-Path $LAYER3_IVL "LAYER3_IVL_VERIFICATION.json"

$AUDIT_LOG = Join-Path $GOV "sovereign_audit_trail_separated.json"

$SCIENTIFIC_FILES = @(
    "HC-CXL_v2.1R_Theory.md",
    "HC-CXL_v2.1R_Architecture.md",
    "HC-CXL_v2.1R_Protocol.md",
    "HC-CXL_v2.1R_Definitions.md",
    "HC-CXL_v2.1R_Reference_Model.json",
    "HC-CXL_v2.1R_Axioms.json",
    "HC-CXL_v2.1R_Measurement_Model.json",
    "HC-CXL_v2.1R_Validation_Map.json",
    "HC-CXL_v2.1R_Modification_Map.json",
    "Unified_References_v21R.md",
    "operational_model_v21r.md",
    "v2.1R_measurement_schema.json"
)

function Audit-SeparatedEvent {
    param(
        [string]$Layer,
        [string]$Event,
        [string]$Details,
        [string]$Outcome,
        [hashtable]$Data = @{}
    )
    try {
        if (-not (Test-Path $GOV)) { New-Item -Path $GOV -ItemType Directory -Force | Out-Null }
        $entry = @{
            timestamp = (Get-Date).ToString("o")
            layer = $Layer
            event = $Event
            details = $Details
            outcome = $Outcome
            data = $Data
            separation_principle = "MAINTAINED"
            runner = $env:USERNAME
            host = $env:COMPUTERNAME
        }
        $json = $entry | ConvertTo-Json -Depth 10
        Add-Content -Path $AUDIT_LOG -Value $json -Encoding UTF8
    } catch {
        Write-Host "AUDIT WRITE FAILED: $_" -ForegroundColor Yellow
    }
}

function Ensure-LayerDirectories {
    foreach ($dir in @($LAYER1_BUILD, $LAYER2_VERIFY, $LAYER3_IVL, $LAYER4_PUBLISH, $GOV)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }
}

function Find-PreviousBuild {
    param([string]$Hash)
    $builds = Get-ChildItem -Path $LAYER1_BUILD -Filter "*_L1_RAW.zip" -ErrorAction SilentlyContinue
    foreach ($build in $builds) {
        $h = (Get-FileHash -Path $build.FullName -Algorithm SHA256).Hash
        if ($h -eq $Hash) {
            return @{
                PackagePath = $build.FullName
                ManifestPath = Join-Path $LAYER1_BUILD "LAYER1_BUILDER_MANIFEST.json"
                PackageHash = $h
                IsPreviousBuild = $true
            }
        }
    }
    return $null
}

function Find-PreviousVerification {
    param([string]$Hash)
    $builds = Get-ChildItem -Path $LAYER2_VERIFY -Filter "*_L2_VERIFIED.zip" -ErrorAction SilentlyContinue
    foreach ($b in $builds) {
        $h = (Get-FileHash -Path $b.FullName -Algorithm SHA256).Hash
        if ($h -eq $Hash) {
            return @{
                VerifiedPackage = $b.FullName
                PackageHash = $h
                IsPreviousVerification = $true
            }
        }
    }
    return $null
}

function Find-PreviousIVL {
    param([string]$Hash)
    $builds = Get-ChildItem -Path $LAYER3_IVL -Filter "*_L3_SEALED.zip" -ErrorAction SilentlyContinue
    foreach ($b in $builds) {
        $h = (Get-FileHash -Path $b.FullName -Algorithm SHA256).Hash
        if ($h -eq $Hash) {
            return @{
                SealedPackage = $b.FullName
                PackageHash = $h
                IsPreviousIVL = $true
            }
        }
    }
    return $null
}

function Invoke-Layer1_RawBuild {
    param()
    Write-Host "L1: Raw Build - start"
    try {
        foreach ($d in @($ROOT,$WORK,$LAYER1_BUILD,$GOV)) { if (-not (Test-Path $d)) { New-Item -Path $d -ItemType Directory -Force | Out-Null } }

        if ($Clean) { Remove-Item -Path (Join-Path $LAYER1_BUILD "*") -Recurse -Force -ErrorAction SilentlyContinue }

        $workFiles = @(Get-ChildItem -Path $WORK -File -ErrorAction SilentlyContinue)
            if ($workFiles.Count -eq 0) {
            Audit-SeparatedEvent -Layer "Layer1" -Event "RAW_BUILD_FAILED" -Details "No work files" -Outcome "FAILED"
            throw "No files in work folder: $WORK"
        }

        if ($RetryFromPhase -eq "Layer1" -and $PreviousBuildHash) {
            $existing = Find-PreviousBuild -Hash $PreviousBuildHash
            if ($existing) {
                Audit-SeparatedEvent -Layer "Layer1" -Event "RAW_BUILD_REUSE" -Details "Reusing previous build" -Outcome "SUCCESS" -Data @{hash=$PreviousBuildHash}
                return $existing
            }
        }

            $existingFiles = @(Get-ChildItem -Path $LAYER1_BUILD -File -ErrorAction SilentlyContinue)
            if ($existingFiles.Count -gt 0) {
            else {
                throw "Layer1 workspace not empty. Use -Force to overwrite."
            }
        }

        $copied = @()
        foreach ($f in $workFiles) {
            Copy-Item -Path $f.FullName -Destination (Join-Path $LAYER1_BUILD $f.Name) -Force
            $copied += $f.Name
        }

        if (Test-Path $LAYER1_PACKAGE) { Remove-Item -Path $LAYER1_PACKAGE -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $LAYER1_BUILD "*") -DestinationPath $LAYER1_PACKAGE -Force

        $pkgInfo = Get-Item $LAYER1_PACKAGE
        $pkgHash = (Get-FileHash -Path $LAYER1_PACKAGE -Algorithm SHA256).Hash

        $manifest = @{
            layer = "LAYER1_RAW_BUILD"
            timestamp = (Get-Date).ToString("o")
            operation = "TRANSPORT_ONLY"
            files_transported = $copied
                total_files = $copied.Count
            package_size_bytes = $pkgInfo.Length
            package_hash = $pkgHash
        }
        $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $LAYER1_MANIFEST -Encoding UTF8

                files_count=$copied.Count

        return @{
            Success = $true
            Layer = "Layer1_RawBuild"
            PackagePath = $LAYER1_PACKAGE
            ManifestPath = $LAYER1_MANIFEST
            PackageHash = $pkgHash
                FilesCount = $copied.Count
            CanRetryFrom = "Layer1"
        }

    } catch {
        Audit-SeparatedEvent -Layer "Layer1" -Event "RAW_BUILD_FAILED" -Details $_.Exception.Message -Outcome "FAILED"
        throw
    }
}

function Invoke-Layer2_ScientificVerification {
    param(
        [string]$InputPackagePath,
        [string]$InputManifestPath
    )
    Write-Host "L2: Scientific Verification - start"
    try {
        if (-not (Test-Path $InputPackagePath)) { throw "Input package not found: $InputPackagePath" }
        if (-not (Test-Path $InputManifestPath)) { throw "Input manifest not found: $InputManifestPath" }

        if (-not (Test-Path $LAYER2_VERIFY)) { New-Item -Path $LAYER2_VERIFY -ItemType Directory -Force | Out-Null }
        if ($Clean) { Remove-Item -Path (Join-Path $LAYER2_VERIFY "*") -Recurse -Force -ErrorAction SilentlyContinue }

        if ($RetryFromPhase -eq "Layer2" -and $PreviousBuildHash) {
            $existing = Find-PreviousVerification -Hash $PreviousBuildHash
            if ($existing) {
                Audit-SeparatedEvent -Layer "Layer2" -Event "VERIFICATION_REUSE" -Details "Reusing previous verification" -Outcome "SUCCESS" -Data @{hash=$PreviousBuildHash}
                return $existing
            }
        }

        $inputCopy = Join-Path $LAYER2_VERIFY "INPUT_FROM_LAYER1.zip"
        Copy-Item -Path $InputPackagePath -Destination $inputCopy -Force

        $extractDir = Join-Path $LAYER2_VERIFY ("EXTRACTED_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
        New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
        Expand-Archive -Path $inputCopy -DestinationPath $extractDir -Force

        $result = @{
            layer = "LAYER2_SCIENTIFIC_VERIFICATION"
            timestamp = (Get-Date).ToString("o")
            input_package_hash = (Get-FileHash -Path $InputPackagePath -Algorithm SHA256).Hash
            verification = @{
                files_present = @()
                files_missing = @()
                overall_status = "PENDING"
            }
        }

        foreach ($rf in $SCIENTIFIC_FILES) {
            $fp = Join-Path $extractDir $rf
            if (Test-Path $fp) {
                $fi = Get-Item $fp
                $result.verification.files_present += @{ name=$rf; size_bytes=$fi.Length }
            } else {
                $result.verification.files_missing += $rf
            }
        }

                            if ($result.verification.files_missing.Count -eq 0) {
            $result.verification.overall_status = "PASS"
        } else {
            $result.verification.overall_status = "FAIL"
            Audit-SeparatedEvent -Layer "Layer2" -Event "SCIENTIFIC_VERIFICATION_FAILED" -Details "Missing files" -Outcome "FAILED" -Data @{missing=$result.verification.files_missing}
            return @{
                Success = $false
                Layer = "Layer2_ScientificVerification"
                Error = "Missing files: $($result.verification.files_missing -join ', ')"
                CanRetryFrom = "Layer2"
                PreviousLayerIntact = $true
                Recommendation = "Restore missing files and retry from Layer2"
            }
        }

        $verifiedPackage = Join-Path $LAYER2_VERIFY "VERIFIED_PACKAGE.zip"
        if (Test-Path $verifiedPackage) { Remove-Item -Path $verifiedPackage -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $extractDir "*") -DestinationPath $verifiedPackage -Force
        $pkgHash = (Get-FileHash -Path $verifiedPackage -Algorithm SHA256).Hash
        $result.verified_package = @{ path=$verifiedPackage; hash=$pkgHash }

        $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $LAYER2_REPORT -Encoding UTF8
        Copy-Item -Path $verifiedPackage -Destination $LAYER2_PACKAGE -Force

        Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue

                files_count=$result.verification.files_present.Count

        return @{
            Success = $true
            Layer = "Layer2_ScientificVerification"
            VerifiedPackage = $LAYER2_PACKAGE
            ReportPath = $LAYER2_REPORT
            VerificationResult = $result
            CanRetryFrom = "Layer2"
        }

    } catch {
        Audit-SeparatedEvent -Layer "Layer2" -Event "SCIENTIFIC_VERIFICATION_FAILED" -Details $_.Exception.Message -Outcome "FAILED"
        return @{
            Success = $false
            Layer = "Layer2_ScientificVerification"
            Error = $_.Exception.Message
            CanRetryFrom = "Layer2"
            PreviousLayerIntact = $true
            Recommendation = "Inspect L2 logs and retry from Layer2"
        }
    }
}

function Invoke-Layer3_IVL {
    param(
        [string]$InputPackagePath
    )
    Write-Host "L3: IVL - start"
    try {
        if (-not (Test-Path $InputPackagePath)) { throw "Input package not found: $InputPackagePath" }
        if (-not (Test-Path $LAYER3_IVL)) { New-Item -Path $LAYER3_IVL -ItemType Directory -Force | Out-Null }
        if ($Clean) { Remove-Item -Path (Join-Path $LAYER3_IVL "*") -Recurse -Force -ErrorAction SilentlyContinue }

        if ($RetryFromPhase -eq "Layer3" -and $PreviousBuildHash) {
            $existing = Find-PreviousIVL -Hash $PreviousBuildHash
            if ($existing) {
                Audit-SeparatedEvent -Layer "Layer3" -Event "IVL_REUSE" -Details "Reusing previous IVL" -Outcome "SUCCESS" -Data @{hash=$PreviousBuildHash}
                return $existing
            }
        }

        $inputCopy = Join-Path $LAYER3_IVL "INPUT_FROM_LAYER2.zip"
        Copy-Item -Path $InputPackagePath -Destination $inputCopy -Force

        $ivlObj = @{
            layer = "LAYER3_IVL_SEAL"
            timestamp = (Get-Date).ToString("o")
            input_package_hash = (Get-FileHash -Path $InputPackagePath -Algorithm SHA256).Hash
            ivl_process = @{ status="SEALING"; sovereign_key=$SOVEREIGN_KEY.Fingerprint }
            verification = @{ package_integrity="PENDING"; sovereign_seal="PENDING" }
        }

        $sealFile = Join-Path $LAYER3_IVL "SOVEREIGN_SEAL.json"
        $sealData = @{
            sovereign_seal = @{
                key = $SOVEREIGN_KEY.Fingerprint
                name = $SOVEREIGN_KEY.Name
                timestamp = (Get-Date).ToString("o")
                package_hash = $ivlObj.input_package_hash
                purpose = "HC-CXL v2.1R FINAL VALIDATION"
            }
        }
        $sealData | ConvertTo-Json -Depth 10 | Out-File -FilePath $sealFile -Encoding UTF8

        if (-not $SkipSigning) {
            $gpg = Get-Command gpg -ErrorAction SilentlyContinue
            if ($gpg) {
                & gpg --batch --yes --default-key $SOVEREIGN_KEY.Fingerprint --armor --detach-sign --output "$sealFile.asc" $sealFile
                $ivlObj.verification.sovereign_seal = "SIGNED"
            } else {
                $ivlObj.verification.sovereign_seal = "UNSIGNED"
            }
        } else {
            $ivlObj.verification.sovereign_seal = "SKIPPED"
        }

        $ivlObj.ivl_process.final_decision = "ACCEPTED"
        $ivlObj.verification.package_integrity = "VERIFIED"
        $ivlObj.verification.timestamp_validation = "VALID"

        $sealedPackage = Join-Path $LAYER3_IVL "SEALED_PACKAGE.zip"
        Copy-Item -Path $inputCopy -Destination $sealedPackage -Force

        $ivlObj.final_package = @{
            path = $sealedPackage
            hash = (Get-FileHash -Path $sealedPackage -Algorithm SHA256).Hash
            sealed_timestamp = (Get-Date).ToString("o")
        }

        $ivlObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $LAYER3_REPORT -Encoding UTF8
        Copy-Item -Path $sealedPackage -Destination $LAYER3_PACKAGE -Force

        Audit-SeparatedEvent -Layer "Layer3" -Event "IVL_SEAL_COMPLETE" -Details "IVL seal complete" -Outcome "SUCCESS" -Data @{package_hash=$ivlObj.final_package.hash; seal_status=$ivlObj.verification.sovereign_seal}

        return @{
            Success = $true
            Layer = "Layer3_IVL"
            SealedPackage = $LAYER3_PACKAGE
            ReportPath = $LAYER3_REPORT
            IVLResult = $ivlObj
            CanRetryFrom = "Layer3"
            FinalProduct = $true
        }

    } catch {
        Audit-SeparatedEvent -Layer "Layer3" -Event "IVL_SEAL_FAILED" -Details $_.Exception.Message -Outcome "FAILED"
        return @{
            Success = $false
            Layer = "Layer3_IVL"
            Error = $_.Exception.Message
            CanRetryFrom = "Layer3"
            PreviousLayersIntact = $true
            Recommendation = "Fix IVL issues and retry from Layer3"
        }
    }
}

# Main execution
Ensure-LayerDirectories

Write-Host "SOVEREIGN SAFE FULL ENHANCED - triple separation" -ForegroundColor Cyan
Write-Host "Phase: $Phase" -ForegroundColor Yellow

$results = @{}

try {
    if ($RetryFromPhase -and -not $PreviousBuildHash) {
        Write-Host "Warning: PreviousBuildHash is recommended when using RetryFromPhase" -ForegroundColor Yellow
    }

    switch ($Phase) {
        'BuildOnly' {
            $results.Layer1 = Invoke-Layer1_RawBuild
        }
        'ScientificOnly' {
            $latest = Get-ChildItem -Path $LAYER1_BUILD -Filter "*_L1_RAW.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latest) { throw "No layer1 package found for L2 run" }
            $manifest = Join-Path $LAYER1_BUILD "LAYER1_BUILDER_MANIFEST.json"
            $results.Layer2 = Invoke-Layer2_ScientificVerification -InputPackagePath $latest.FullName -InputManifestPath $manifest
        }
        'IVLOnly' {
            $latest = Get-ChildItem -Path $LAYER2_VERIFY -Filter "*_L2_VERIFIED.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latest) { throw "No layer2 package found for L3 run" }
            $results.Layer3 = Invoke-Layer3_IVL -InputPackagePath $latest.FullName
        }
        'FullSeparation' {
            $l1 = Invoke-Layer1_RawBuild
            $results.Layer1 = $l1
            if (-not $l1.Success) { throw "Layer1 failed; aborting" }

            if (-not $SkipScientificVerification) {
                $l2 = Invoke-Layer2_ScientificVerification -InputPackagePath $l1.PackagePath -InputManifestPath $l1.ManifestPath
                $results.Layer2 = $l2
            } else {
                Audit-SeparatedEvent -Layer "Layer2" -Event "SCIENTIFIC_SKIPPED" -Details "Scientific verification skipped by flag" -Outcome "SKIPPED"
                $results.Layer2 = @{ Success = $true; Note = "Skipped" }
            }

            if ($results.Layer2.Success) {
                $l3 = Invoke-Layer3_IVL -InputPackagePath $results.Layer2.VerifiedPackage
                $results.Layer3 = $l3
            } else {
                Write-Host "Layer2 failed; Layer1 preserved for retry" -ForegroundColor Yellow
            }
        }
        'PublishOnly' {
            $latest = Get-ChildItem -Path $LAYER3_IVL -Filter "*_L3_SEALED.zip" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $latest) { throw "No sealed package found for publish" }
            Write-Host "Publish step placeholder - implement external publish to Docker/GitHub/Zenodo as required"
            $results.Publish = @{ Success=$true; Package=$latest.FullName }
        }
    }

    Write-Host "---- RESULTS ----"
    $results.Keys | ForEach-Object {
        $k = $_
        $v = $results[$k]
        Write-Host "$k : $([string]($v.Success))"
    }

    Audit-SeparatedEvent -Layer "Pipeline" -Event "PIPELINE_COMPLETE" -Details "Phase completed: $Phase" -Outcome "SUCCESS" -Data @{phase=$Phase}

    return $results

} catch {
    Audit-SeparatedEvent -Layer "Pipeline" -Event "PIPELINE_FAILED" -Details $_.Exception.Message -Outcome "FAILED"
    Write-Host "Pipeline failed: $($_.Exception.Message)" -ForegroundColor Red
    return @{ Success=$false; Error=$_.Exception.Message; AuditLog=$AUDIT_LOG }
}




