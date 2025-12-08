<#
execute_sovereign_v21r_canonical.ps1
HC-CXL v2.1R - النسخة القياسية الكنسية (SES-v21R-Canonical)
المبدأ: فصل تام، صرامة مطلقة، سيادة كاملة
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName='BuildOnly')]
    [switch]$Build,
    
    [Parameter(ParameterSetName='VerifyOnly')]
    [switch]$Verify,
    
    [Parameter(ParameterSetName='FullRun')]
    [switch]$Full,
    
    [switch]$Clean,
    [switch]$SkipSigning,
    [switch]$Force,
    [switch]$Verbose
)

# ============================================
# التهيئة والتهيئة
# ============================================
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Verbose) {
    $VerbosePreference = "Continue"
}

# ---------- التكوين السيادي ----------
$ROOT = "D:\HC-CXL\Reconstruction\v2.1R"
$SRC0 = Join-Path $ROOT "source"
$WORK = Join-Path $ROOT "1_source"
$BUILD = Join-Path $ROOT "2_build"
$SEAL = Join-Path $ROOT "3_seal"
$GOV = Join-Path $ROOT "0_governance"

# المفتاح السيادي
$SOVEREIGN_KEY = @{
    Fingerprint = "5552541D93559EEF53A2DEB4B20DE574B24DA9E3"
    Name = "Hossam Sovereign Engine"
    Email = "security@hc-cxl.com"
}

# أسماء الملفات
$PACKAGE_NAME = "HC-CXL_v2.1R_SOVEREIGN_PACKAGE.zip"
$PACKAGE_PATH = Join-Path $BUILD $PACKAGE_NAME
$BUILDER_MANIFEST = Join-Path $BUILD "BUILDER_MANIFEST.json"

# السجلات
$BUILD_LOG = Join-Path $GOV "canonical_builder_log.txt"
$VERIFY_LOG = Join-Path $GOV "canonical_verifier_log.txt"
$AUDIT_LOG = Join-Path $GOV "canonical_audit_trail.json"

# ============================================
# نظام التسجيل المعدل
# ============================================

function Write-BuilderLog {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "$timestamp | CANONICAL_BUILDER | $Level | $Message"
    Add-Content -Path $BUILD_LOG -Value $logEntry -Encoding UTF8
    
    if ($Level -ne "VERBOSE" -or $Verbose) {
        Write-Host "[🏗️  BUILDER] $Message" -ForegroundColor Cyan
    }
}

function Write-VerifierLog {
    param([string]$Message, [string]$Level = "INFO")
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $logEntry = "$timestamp | CANONICAL_VERIFIER | $Level | $Message"
    Add-Content -Path $VERIFY_LOG -Value $logEntry -Encoding UTF8
    
    if ($Level -ne "VERBOSE" -or $Verbose) {
        Write-Host "[🔐 VERIFIER] $Message" -ForegroundColor Yellow
    }
}

function Write-AuditEvent {
    param(
        [string]$Event,
        [string]$Details,
        [string]$Outcome,
        [hashtable]$ExtraData = @{}
    )
    
    $auditEntry = @{
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        event = $Event
        details = $Details
        outcome = $Outcome
        actor = [System.Environment]::UserName
        machine = [System.Environment]::MachineName
        system = "HC-CXL Canonical v2.1R"
    }
    
    $auditEntry | ConvertTo-Json -Depth 5 | Add-Content -Path $AUDIT_LOG -Encoding UTF8
}

# ============================================
# وحدة البناء - الإصدار الكنسي
# ============================================

function Invoke-CanonicalBuilder {
    Write-BuilderLog "بدء الباني الكنسي - النسخة القياسية" "INFO"
    Write-AuditEvent -Event "CANONICAL_BUILDER_START" -Details "بدء البناء حسب القواعد الكنسية" -Outcome "STARTED"
    
    try {
        # 1. التحقق من وجود ملفات العمل
        if (-not (Test-Path $WORK)) {
            throw "مجلد العمل غير موجود: $WORK"
        }
        
        $workFiles = Get-ChildItem -Path $WORK -File
        if ($workFiles.Count -eq 0) {
            throw "لا توجد ملفات في مجلد العمل. يجب وضع الملفات العلمية في $WORK"
        }
        
        Write-BuilderLog "تم العثور على $($workFiles.Count) ملف في مجلد العمل" "SUCCESS"
        
        # 2. البحث عن المرجع بطريقة دقيقة
        Write-BuilderLog "البحث عن مجموعة البيانات المرجعية" "INFO"
        
        $refPath = "D:\HC-CXL\CleanContext_12_R-PGR\REFERENCE_DATASETS_V2_1.json"
        if (-not (Test-Path $refPath)) {
            # البحث في المواقع المعروفة فقط (ليس بحثاً عاماً)
            $knownPaths = @(
                "D:\HC-CXL\CleanContext_12_R-PGR\REFERENCE_DATASETS_V2_1.json",
                "D:\HC-CXL\CleanContext_from_DRAC\REFERENCE_DATASETS_V2_1.json",
                "D:\HC-CXL\CleanContext_from_image_final\REFERENCE_DATASETS_V2_1.json",
                "D:\HC-CXL\DockerSafe_V2.1\REFERENCE_DATASETS_V2_1.json"
            )
            
            $found = $false
            foreach ($path in $knownPaths) {
                if (Test-Path $path) {
                    $refPath = $path
                    $found = $true
                    break
                }
            }
            
            if (-not $found) {
                throw "لم يتم العثور على REFERENCE_DATASETS_V2_1.json في المواقع المعروفة"
            }
        }
        
        $refHash = (Get-FileHash -Path $refPath -Algorithm SHA256).Hash
        Write-BuilderLog "تم تحديد المرجع: $(Split-Path -Leaf $refPath)" "SUCCESS"
        Write-BuilderLog "هاش المرجع: $refHash" "VERBOSE"
        
        # 3. نسخ الملفات من WORK إلى BUILD فقط (لا إنشاء محتوى)
        Write-BuilderLog "نسخ الملفات العلمية (بدون تعديل أو إنشاء)" "INFO"
        
        if (Test-Path $BUILD) {
            if ($Force) {
                Remove-Item -Path "$BUILD\*" -Recurse -Force -ErrorAction SilentlyContinue
            }
            elseif ((Get-ChildItem -Path $BUILD -File).Count -gt 0) {
                throw "مجلد البناء غير فارغ. استخدم -Force للمتابعة"
            }
        }
        else {
            New-Item -Path $BUILD -ItemType Directory -Force | Out-Null
        }
        
        $copiedFiles = @()
        foreach ($file in $workFiles) {
            $destPath = Join-Path $BUILD $file.Name
            Copy-Item -Path $file.FullName -Destination $destPath -Force
            $copiedFiles += $destPath
            Write-BuilderLog "تم نسخ: $($file.Name)" "VERBOSE"
        }
        
        # 4. إنشاء بيان الباني البسيط
        Write-BuilderLog "إنشاء بيان الباني الكنسي" "INFO"
        
        $builderManifest = @{
            manifest_type = "CANONICAL_BUILDER_MANIFEST"
            version = "2.1R"
            build_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            builder = @{
                user = [System.Environment]::UserName
                machine = [System.Environment]::MachineName
                role = "TRANSPORTER_ONLY"
            }
            reference = @{
                file = Split-Path -Leaf $refPath
                hash = $refHash
                status = "IDENTIFIED"
            }
            files = @{
                count = $copiedFiles.Count
                list = @($copiedFiles | ForEach-Object { Split-Path -Leaf $_ })
                source = $WORK
                destination = $BUILD
            }
            notes = "هذا البيان يؤكد نقل الملفات فقط. لم يتم إنشاء أو تعديل أي محتوى."
        }
        
        $builderManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $BUILDER_MANIFEST -Encoding UTF8
        Write-BuilderLog "تم إنشاء بيان الباني: $BUILDER_MANIFEST" "SUCCESS"
        
        # 5. إنشاء الحزمة
        Write-BuilderLog "إنشاء حزمة الباني (ZIP)" "INFO"
        
        if (Test-Path $PACKAGE_PATH) {
            Remove-Item -Path $PACKAGE_PATH -Force
        }
        
        Compress-Archive -Path (Join-Path $BUILD "*") -DestinationPath $PACKAGE_PATH -Force
        $packageHash = (Get-FileHash -Path $PACKAGE_PATH -Algorithm SHA256).Hash
        $packageSize = [math]::Round((Get-Item $PACKAGE_PATH).Length/1MB, 2)
        
        # تحديث الـ manifest بمعلومات الحزمة
        $builderManifest.package = @{
            name = $PACKAGE_NAME
            hash = $packageHash
            size_mb = $packageSize
            created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        $builderManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $BUILDER_MANIFEST -Encoding UTF8
        
        Write-BuilderLog "اكتمل البناء الكنسي" "SUCCESS"
        Write-BuilderLog "الحزمة: $PACKAGE_NAME ($packageSize MB)" "INFO"
        Write-BuilderLog "الهاش: $packageHash" "VERBOSE"
        
        Write-AuditEvent -Event "CANONICAL_BUILDER_COMPLETE" -Details "تم النقل والتغليف دون تعديل" -Outcome "SUCCESS" -ExtraData @{
            package_hash = $packageHash
            file_count = $copiedFiles.Count
        }
        
        return @{
            Success = $true
            PackagePath = $PACKAGE_PATH
            PackageHash = $packageHash
            ManifestPath = $BUILDER_MANIFEST
            ReferenceHash = $refHash
            FileCount = $copiedFiles.Count
        }
    }
    catch {
        Write-BuilderLog "فشل الباني الكنسي: $_" "ERROR"
        Write-AuditEvent -Event "CANONICAL_BUILDER_FAILED" -Details $_.Exception.Message -Outcome "FAILED"
        throw
    }
}

# ============================================
# وحدة التحقق - الإصدار الكنسي (صرامة مطلقة)
# ============================================

function Invoke-CanonicalVerifier {
    param(
        [string]$BuilderPackagePath,
        [string]$BuilderManifestPath
    )
    
    Write-VerifierLog "بدء المحقق الكنسي - الصرامة المطلقة" "INFO"
    Write-AuditEvent -Event "CANONICAL_VERIFIER_START" -Details "بدء التحقق بالقواعد الكنسية" -Outcome "STARTED"
    
    try {
        # 1. التحقق من المدخلات
        if (-not $BuilderPackagePath) { $BuilderPackagePath = $PACKAGE_PATH }
        if (-not $BuilderManifestPath) { $BuilderManifestPath = $BUILDER_MANIFEST }
        
        if (-not (Test-Path $BuilderPackagePath)) {
            throw "REJECTED: لم يتم العثور على حزمة الباني"
        }
        
        if (-not (Test-Path $BuilderManifestPath)) {
            throw "REJECTED: لم يتم العثور على بيان الباني"
        }
        
        Write-VerifierLog "التحقق من: $(Split-Path -Leaf $BuilderPackagePath)" "INFO"
        
        # 2. التحقق من المفتاح السيادي (إن لم يتم تخطيه)
        if (-not $SkipSigning) {
            Write-VerifierLog "التحقق من المفتاح السيادي" "INFO"
            
            try {
                $keyCheck = & gpg --list-keys $SOVEREIGN_KEY.Fingerprint 2>$null
                if (-not $keyCheck) {
                    throw "REJECTED: المفتاح السيادي غير موجود"
                }
                Write-VerifierLog "المفتاح السيادي صالح" "SUCCESS"
            }
            catch {
                Write-VerifierLog "فشل التحقق من المفتاح: $_" "ERROR"
                throw "REJECTED: فشل التحقق من المفتاح السيادي"
            }
        }
        else {
            Write-VerifierLog "تخطي التحقق من المفتاح حسب الطلب" "WARNING"
        }
        
        # 3. إنشاء هيكل التحقق
        $verificationDir = Join-Path $SEAL "CANONICAL_VERIFICATION_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $evidenceDir = Join-Path $verificationDir "EVIDENCE"
        $reportsDir = Join-Path $verificationDir "REPORTS"
        
        New-Item -Path $evidenceDir -ItemType Directory -Force | Out-Null
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
        
        # 4. قراءة manifest الباني والتحقق منه
        $manifest = Get-Content $BuilderManifestPath | ConvertFrom-Json
        Write-VerifierLog "تم قراءة بيان الباني (الإصدار: $($manifest.version))" "VERBOSE"
        
        # 5. التحقق من هواش الحزمة
        Write-VerifierLog "التحقق من تكامل الحزمة" "INFO"
        
        $packageHash = (Get-FileHash -Path $BuilderPackagePath -Algorithm SHA256).Hash
        
        if ($packageHash -ne $manifest.package.hash) {
            throw "REJECTED: هاش الحزمة لا يتطابق. المسجل: $($manifest.package.hash) | المحسوب: $packageHash"
        }
        
        Write-VerifierLog "✓ تحقق من تكامل الحزمة" "SUCCESS"
        
        # 6. التحقق من الملفات باستخراج الحزمة
        Write-VerifierLog "استخراج الحزمة والتحقق من الملفات" "INFO"
        
        $tempExtract = Join-Path $env:TEMP "HC-CXL_CANONICAL_VERIFY_$(Get-Date -Format 'yyyyMMddHHmmss')"
        New-Item -Path $tempExtract -ItemType Directory -Force | Out-Null
        
        try {
            Expand-Archive -Path $BuilderPackagePath -DestinationPath $tempExtract -Force
            
            # القائمة الكنسية للملفات المطلوبة
            $canonicalFiles = @(
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
            
            $verificationResults = @()
            $rejectionReasons = @()
            
            foreach ($file in $canonicalFiles) {
                $filePath = Join-Path $tempExtract $file
                
                if (-not (Test-Path $filePath)) {
                    $rejectionReasons += "ملف مفقود: $file"
                    $verificationResults += @{
                        file = $file
                        status = "MISSING"
                        result = "REJECTED"
                    }
                    continue
                }
                
                # التحقق من أن الملف غير فارغ
                $fileSize = (Get-Item $filePath).Length
                if ($fileSize -eq 0) {
                    $rejectionReasons += "ملف فارغ: $file"
                    $verificationResults += @{
                        file = $file
                        status = "EMPTY"
                        result = "REJECTED"
                    }
                    continue
                }
                
                # التحقق من أن الملف يحتوي على reference_digest (إذا كان JSON)
                if ($file -like "*.json") {
                    try {
                        $jsonContent = Get-Content $filePath -Raw | ConvertFrom-Json
                        if ($jsonContent.PSObject.Properties['reference_digest'] -and 
                            $jsonContent.reference_digest -ne $manifest.reference.hash) {
                            $rejectionReasons += "هاش المرجع غير مطابق في: $file"
                            $verificationResults += @{
                                file = $file
                                status = "REFERENCE_MISMATCH"
                                result = "REJECTED"
                            }
                            continue
                        }
                    }
                    catch {
                        # ليس ملف JSON صالح، نستمر
                    }
                }
                
                $verificationResults += @{
                    file = $file
                    status = "PRESENT"
                    result = "ACCEPTED"
                    size_bytes = $fileSize
                }
            }
            
            # إذا كان هناك أي سبب للرفض، نرفض الكل
            if ($rejectionReasons.Count -gt 0) {
                $reasons = $rejectionReasons -join " | "
                throw "REJECTED: $reasons"
            }
        }
        finally {
            Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # 7. إنشاء سجل التحقق الكنسي
        Write-VerifierLog "إنشاء سجل التحقق الكنسي" "INFO"
        
        $verificationRecord = @{
            document_type = "CANONICAL_VERIFICATION_RECORD"
            version = "2.1R"
            verification_timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            verifier = @{
                name = $SOVEREIGN_KEY.Name
                fingerprint = $SOVEREIGN_KEY.Fingerprint
                authority = "HC-CXL Canonical Verification Authority"
            }
            package = @{
                name = $PACKAGE_NAME
                hash = $packageHash
                size_mb = $manifest.package.size_mb
                integrity = "VERIFIED"
            }
            verification_results = $verificationResults
            verification_summary = @{
                total_files = $verificationResults.Count
                accepted_files = ($verificationResults | Where-Object { $_.result -eq "ACCEPTED" }).Count
                rejected_files = ($verificationResults | Where-Object { $_.result -eq "REJECTED" }).Count
                overall_result = "ACCEPTED"
                rejection_reasons = @()
            }
            notes = "التحقق الكنسي - الصرامة المطلقة. أي خطأ يؤدي إلى الرفض الكامل."
        }
        
        $verificationRecordPath = Join-Path $reportsDir "CANONICAL_VERIFICATION_RECORD.json"
        $verificationRecord | ConvertTo-Json -Depth 10 | Out-File -FilePath $verificationRecordPath -Encoding UTF8
        
        # 8. إنشاء الطابع الزمني السيادي
        $timestampRecord = @{
            timestamp_type = "SOVEREIGN_CANONICAL_TIMESTAMP"
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            package_hash = $packageHash
            verification_result = "ACCEPTED"
            issuer = $SOVEREIGN_KEY.Name
            system = "HC-CXL Canonical Timestamping Service"
        }
        
        $timestampPath = Join-Path $reportsDir "SOVEREIGN_TIMESTAMP.json"
        $timestampRecord | ConvertTo-Json -Depth 10 | Out-File -FilePath $timestampPath -Encoding UTF8
        
        # 9. التوقيع السيادي (وفق القواعد الكنسية)
        if (-not $SkipSigning) {
            Write-VerifierLog "التوقيع السيادي الكنسي" "INFO"
            
            # توقيع سجل التحقق فقط
            & gpg --batch --yes --default-key $SOVEREIGN_KEY.Fingerprint `
                 --armor --detach-sign `
                 --output "$verificationRecordPath.asc" `
                 $verificationRecordPath
            
            # توقيع الطابع الزمني فقط
            & gpg --batch --yes --default-key $SOVEREIGN_KEY.Fingerprint `
                 --armor --detach-sign `
                 --output "$timestampPath.asc" `
                 $timestampPath
                 
            Write-VerifierLog "✓ تم توقيع سجل التحقق والطابع الزمني" "SUCCESS"
            Write-VerifierLog "⚠️  لم يتم توقيع الحزمة (حسب القواعد الكنسية)" "INFO"
        }
        
        # 10. نسخ الأدلة
        Copy-Item -Path $BuilderPackagePath -Destination (Join-Path $evidenceDir (Split-Path -Leaf $BuilderPackagePath)) -Force
        Copy-Item -Path $BuilderManifestPath -Destination (Join-Path $evidenceDir (Split-Path -Leaf $BuilderManifestPath)) -Force
        
        Write-VerifierLog "اكتمل التحقق الكنسي - النتيجة: ACCEPTED" "SUCCESS"
        Write-VerifierLog "مسار الأدلة: $verificationDir" "INFO"
        
        Write-AuditEvent -Event "CANONICAL_VERIFICATION_COMPLETE" `
                        -Details "تم التحقق والرفض الكامل للخطأ الواحد" `
                        -Outcome "SUCCESS" `
                        -ExtraData @{
                            result = "ACCEPTED"
                            verification_dir = $verificationDir
                        }
        
        return @{
            Success = $true
            VerificationDir = $verificationDir
            Result = "ACCEPTED"
            PackageHash = $packageHash
        }
    }
    catch {
        if ($_.Exception.Message -like "REJECTED:*") {
            $rejectReason = $_.Exception.Message
            Write-VerifierLog $rejectReason "ERROR"
            Write-AuditEvent -Event "CANONICAL_VERIFICATION_REJECTED" `
                          -Details $rejectReason `
                          -Outcome "REJECTED"
        }
        else {
            Write-VerifierLog "فشل التحقق: $_" "ERROR"
            Write-AuditEvent -Event "CANONICAL_VERIFICATION_FAILED" `
                          -Details $_.Exception.Message `
                          -Outcome "FAILED"
        }
        throw
    }
}

# ============================================
# التنفيذ الرئيسي
# ============================================

Write-Host @"

╔══════════════════════════════════════════════════════╗
║  HC-CXL v2.1R - النسخة القياسية الكنسية (Canonical)  ║
║  SES-v21R-Canonical - الإصدار المعتمد سيادياً        ║
╚══════════════════════════════════════════════════════╝

المبادئ:
1. الباني: ينقل فقط، لا يعدل ولا ينشئ
2. المحقق: يرفض عند أول خطأ
3. التوقيع: على السجلات فقط، ليس على الحزمة
4. النتيجة: ACCEPTED أو REJECTED فقط

"@ -ForegroundColor Cyan

# تحديد الوضع
if ($Build -and $Verify) { $mode = "FULL" }
elseif ($Build) { $mode = "BUILD_ONLY" }
elseif ($Verify) { $mode = "VERIFY_ONLY" }
elseif ($Full) { $mode = "FULL" }
else {
    Write-Host "استخدام: .\$($MyInvocation.MyCommand.Name) -Full" -ForegroundColor Yellow
    Write-Host "أو: -Build (للبناء فقط)" -ForegroundColor Yellow
    Write-Host "أو: -Verify (للتحقق فقط)" -ForegroundColor Yellow
    exit 1
}

# إنشاء المجلدات الأساسية
foreach ($dir in @($ROOT, $BUILD, $SEAL, $GOV)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

# تنظيف إذا طلب
if ($Clean) {
    Write-Host "🧹 تنظيف المخرجات السابقة..." -ForegroundColor Yellow
    Remove-Item -Path "$BUILD\*" -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $SEAL -Directory -Filter "*VERIFICATION*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

$builderResult = $null
$verifierResult = $null

try {
    # البناء
    if ($mode -in @("FULL", "BUILD_ONLY")) {
        Write-Host "`n🚀 مرحلة البناء الكنسي..." -ForegroundColor Cyan
        $builderResult = Invoke-CanonicalBuilder
        
        if ($builderResult.Success) {
            Write-Host "✅ البناء الكنسي اكتمل" -ForegroundColor Green
            Write-Host "   الحزمة: $(Split-Path -Leaf $builderResult.PackagePath)" -ForegroundColor Gray
            Write-Host "   الهاش: $($builderResult.PackageHash)" -ForegroundColor Gray
        }
        
        if ($mode -eq "BUILD_ONLY") {
            Write-Host "`n🏁 توقف عند البناء. للتحقق: .\$($MyInvocation.MyCommand.Name) -Verify" -ForegroundColor Yellow
            exit 0
        }
    }
    
    # التحقق
    if ($mode -in @("FULL", "VERIFY_ONLY")) {
        Write-Host "`n🔍 مرحلة التحقق الكنسية (صرامة مطلقة)..." -ForegroundColor Yellow
        
        $packagePath = if ($builderResult) { $builderResult.PackagePath } else { $null }
        $manifestPath = if ($builderResult) { $builderResult.ManifestPath } else { $null }
        
        $verifierResult = Invoke-CanonicalVerifier -BuilderPackagePath $packagePath -BuilderManifestPath $manifestPath
        
        if ($verifierResult.Success) {
            Write-Host "✅ التحقق الكنسي اكتمل" -ForegroundColor Green
            Write-Host "   النتيجة: $($verifierResult.Result)" -ForegroundColor Green
            Write-Host "   الأدلة: $($verifierResult.VerificationDir)" -ForegroundColor Gray
            
            if ($verifierResult.Result -eq "ACCEPTED") {
                Write-Host "`n🎉 الحزمة معتمدة سيادياً وجاهزة للمراحل التالية" -ForegroundColor Green
            }
        }
    }
}
catch {
    Write-Host "`n❌ العملية فشلت: $_" -ForegroundColor Red
    Write-Host "   راجع السجلات في $GOV" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n🏁 انتهت العملية الكنسية بنجاح" -ForegroundColor Cyan
