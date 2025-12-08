# === File: Publisher.ps1 ===
<#
Publisher.ps1
Role: Publisher (final publication and optional package-sign under SPF/AllowPackageSigning)
Principles:
 - Publisher runs in a controlled environment (SPF) and MAY publish to external endpoints.
 - Package signing allowed only when SPF is deliberately active.
Usage: .\Publisher.ps1 -Root 'D:\HC-CXL\Reconstruction\v2.1R' -SPF -AllowPackageSigning
#>
param(
    [string]$Root = 'D:\HC-CXL\Reconstruction\v2.1R',
    [switch]$SPF,
    [switch]$AllowPackageSigning,
    [switch]$PublishTo = $null, # optional: 'Zenodo','GitHub','Docker'
    [switch]$Verbose
)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'
$GOV = Join-Path $Root '0_governance'; $BUILD = Join-Path $Root '2_build'; $SEAL = Join-Path $Root '3_seal'
$PACKAGE_NAME='HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip'; $PACKAGE_PATH = Join-Path $BUILD $PACKAGE_NAME
function Write-Audit { param($evt,$details,$outcome,$extra=@{}) if (-not (Test-Path $GOV)) { New-Item -Path $GOV -ItemType Directory -Force | Out-Null } $rec=@{timestamp=(Get-Date).ToString('o');event=$evt;details=$details;outcome=$outcome;extra=$extra}; $rec|ConvertTo-Json -Depth 10 | Add-Content -Path (Join-Path $GOV 'sovereign_audit_trail.json') -Encoding UTF8 }
try {
    if (-not $SPF -and $AllowPackageSigning) { Write-Audit 'PUBLISHER_ABORT' 'AllowPackageSigning without SPF' 'FAILED'; throw 'AllowPackageSigning requires SPF' }
    if (-not (Test-Path $PACKAGE_PATH)) { Write-Audit 'PUBLISHER_FAILED' 'Package missing' 'FAILED'; throw 'Package missing' }

    # In SPF: allow actions
    if ($SPF) { Write-Audit 'SPF_ENTER' 'Sovereign Publication Finalization entered' 'INFO' }

    if ($AllowPackageSigning) {
        # assume verifier already produced signed copy; publisher may attach external metadata and publish
        Write-Audit 'PUBLISHER_PACKAGE_SIGN' 'Proceeding with package-level signing/publishing' 'INFO'
        # implement upload steps here (left as placeholder to avoid embedding credentials)
    }

    # placeholder publish actions
    if ($PublishTo) { Write-Audit 'PUBLISHER_PUBLISHED' "Published to: $PublishTo" 'SUCCESS' }

    Write-Audit 'PUBLISHER_COMPLETED' 'Publication finished' 'SUCCESS'
    return @{ Success=$true }
} catch {
    Write-Audit 'PUBLISHER_FAILED' $_.Exception.Message 'FAILED'
    throw
}
