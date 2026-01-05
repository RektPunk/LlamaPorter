# Windows Builder: powershell -ExecutionPolicy Bypass -File bootloader.ps1

$ProgressPreference = 'SilentlyContinue'

$ENGINE_URL = "https://github.com/mozilla-ai/llamafile/releases/download/0.9.3/llamafile-0.9.3"
$MANIFEST_BASE = "manifest"
if (-not (Test-Path "$MANIFEST_BASE")) {
    Write-Host "[ ERROR ] $MANIFEST_BASE/ folder not found."; 
    exit 1 
}
$models = Get-ChildItem "$MANIFEST_BASE" | Select-Object -ExpandProperty Name
if ($null -eq $models -or $models.Count -eq 0) {
    Write-Host "[ ERROR ] No manifest files found in $MANIFEST_BASE/ folder."
    exit 1
}
$ASSETS_BASE = "assets"
if (-not (Test-Path "$ASSETS_BASE/")) { New-Item -ItemType Directory -Path "$ASSETS_BASE/" | Out-Null }

$DISTS_BASE = "dists"
if (-not (Test-Path "$DISTS_BASE/")) { New-Item -ItemType Directory -Path "$DISTS_BASE/" | Out-Null }

Clear-Host
Write-Host "------------------------------------------------------------"
Write-Host "LlamaPorter"
Write-Host "------------------------------------------------------------"
Write-Host "Please select the target Operating System for deployment:"
Write-Host " 1) Microsoft Windows (.bat format)"
Write-Host " 2) Linux or macOS (.sh format)"
$OS_CHOICE = Read-Host " Selection (1-2)"

if ($OS_CHOICE -eq "1") {
    $OS_SUFFIX = "win"
    $TARGET_ENGINE = "llamafile.exe"
} elseif ($OS_CHOICE -eq "2") {
    $OS_SUFFIX = "unix"
    $TARGET_ENGINE = "llamafile"
} else {
    Write-Host "[ ERROR ] Invalid Operating System selection. Please restart the builder."
    exit 1
}
Write-Host "[ INFO ] Target Operating System set to $OS_SUFFIX"
Write-Host "------------------------------------------------------------"

if (-not (Test-Path ".model")) {
    Write-Host "Please select the llm model for deployment:"
    for ($i=0; $i -lt $models.Count; $i++) {
        Write-Host " $($i+1)) $($models[$i])"
    }
    $choice = Read-Host "Select a model (1-$($models.Count))"
    if (-not ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $models.Count)) {
        Write-Host "[ ERROR ] Invalid Model selection. Please restart the builder."
        exit 1
    }
    $MODEL_ID = $models[[int]$choice-1]
    $MANIFEST_PATH = Join-Path $MANIFEST_BASE $MODEL_ID
} else {
    $MODEL_ID = (Get-Content ".model").Trim()
    $MANIFEST_PATH = Join-Path $MANIFEST_BASE $MODEL_ID
}
Write-Host "[ INFO ] Target LLM model set to $MODEL_ID"
Write-Host "------------------------------------------------------------"

if (-not (Test-Path $MANIFEST_PATH)) {
    Write-Host "[ ERROR ] Manifest file not found at $MANIFEST_PATH"
    exit 1
}

$REL = Join-Path $DISTS_BASE "${MODEL_ID}_${OS_SUFFIX}"
if (-not (Test-Path $REL)) { New-Item -ItemType Directory -Path $REL | Out-Null }

if (Test-Path (Join-Path $ASSETS_BASE "llamafile")) {
    Write-Host "[ INFO ] Found local 'llamafile' binary."
} else {
    if (-not (Test-Path (Join-Path $REL $TARGET_ENGINE))) {
        Write-Host "[ INFO ] No local engine found. Initiating download..."
        Start-Job -Name "EngineDownload" -ScriptBlock {
            param($url, $p, $root) 
            Set-Location $root
            try {
                Invoke-WebRequest -Uri $url -OutFile $p
            } catch {
                if (Test-Path $p) { Remove-Item $p }
                throw "[ Error ] Download failed for $url"
            }
        } -ArgumentList $ENGINE_URL, Join-Path $ASSETS_BASE "llamafile",  $PSScriptRoot | Out-Null
    } else {
        Write-Host "[ INFO ] Engine binary already exists in the target folder."
    }
}


$urls = Get-Content $MANIFEST_PATH | Where-Object { $_ -and -not $_.StartsWith("#") }
$MODEL_CACHE_DIR = Join-Path $ASSETS_BASE $MODEL_ID
if (-not (Test-Path $MODEL_CACHE_DIR)) { New-Item -ItemType Directory -Path $MODEL_CACHE_DIR | Out-Null }

$firstModelFile = ""
foreach ($url in $urls) {
    $url = $url.Trim()
    $fileName = Split-Path $url -Leaf
    $targetFilePath = Join-Path $MODEL_CACHE_DIR $fileName

    if ([string]::IsNullOrEmpty($firstModelFile)) { $firstModelFile = $fileName }
    if (-not (Test-Path $targetFilePath)) {
        Write-Host "[ INFO ] Queuing Download: $fileName"
        Start-Job -Name "Download-$fileName" -ScriptBlock {
            param($u, $p, $root) 
            Set-Location $root
            $ProgressPreference = 'SilentlyContinue'
            try {
                Invoke-WebRequest -Uri $u -OutFile $p
            } catch {
                if (Test-Path $p) { Remove-Item $p }
                throw "[ Error ] Download failed for $u"
            }
        } -ArgumentList $url, $targetFilePath, $PSScriptRoot | Out-Null
    } else {
        Write-Host "[ INFO ] File already exists: $fileName (Skipping)"
    }
}

Write-Host "[ INFO ] Monitoring background download tasks..."
while ($true) {
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
    $aliveCount = ($jobs).Count

    $engSize = "0B"
    $engFile = Get-Item (Join-Path $ASSETS_BASE "llamafile") -ErrorAction SilentlyContinue
    if ($engFile) { $engSize = "$(([math]::Round($engFile.Length / 1MB, 1)))M" }

    $totalMdlBytes = (Get-ChildItem (Join-Path $MODEL_CACHE_DIR "*.gguf") -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $mdlSize = "0B"
    if ($totalMdlBytes -gt 0) { 
        $mdlSize = "$(([math]::Round($totalMdlBytes / 1GB, 2)))G" 
    }

    $statusLine = "`r[ PROGRESS ] Engine: $engSize | Models: $mdlSize | Active Tasks: $aliveCount"
    Write-Host -NoNewline ($statusLine.PadRight(80))

    if ($aliveCount -eq 0) { break }
    Start-Sleep -Milliseconds 500
}
$jobs = Get-Job
$failedJobs = $jobs | Where-Object { $_.State -eq "Failed" }

if ($failedJobs) {
    Write-Host ""
    Write-Host "------------------------------------------------------------"
    Write-Host "[ ERROR ] Some downloads failed."
    Write-Host "[ REASON ] It might be a network issue or a restricted model."
    Write-Host "------------------------------------------------------------"

    foreach ($job in $failedJobs) {
        Write-Host "[ ERROR ] Failed Task: $($job.Name)"
        $job | Receive-Job -ErrorAction SilentlyContinue | Out-String
    }
    Write-Host "[ INFO ] Stopping build process."
    $jobs | Remove-Job
    exit 1
}

$jobs | Remove-Job
Write-Host ""
Write-Host "[ SUCCESS ] All resources are ready."

if (-not (Test-Path (Join-Path $REL $TARGET_ENGINE))) {
    if (Test-Path (Join-Path $ASSETS_BASE "llamafile")) {
        Write-Host "`n[ INFO ] Copying engine binary to $REL..."
        Copy-Item (Join-Path $ASSETS_BASE "llamafile") (Join-Path $REL $TARGET_ENGINE)
    }
}
Write-Host "[ INFO ] Copying LLM model to $REL..."
Copy-Item (Join-Path $MODEL_CACHE_DIR "*") -Destination "$REL/" -Force -ErrorAction SilentlyContinue

Write-Host "[ INFO ] Creating runtime executable script (ignite)."
if ($OS_CHOICE -eq "1") {
    $batContent = "@echo off`ntitle LlamaPorter - $MODEL_ID`nchcp 65001 > nul`ncd /d ""%~dp0""`necho Starting Local LLM...`n$TARGET_ENGINE -m $firstModelFile`npause"
    [System.IO.File]::WriteAllText("$PSScriptRoot/$REL/ignite.bat", $batContent, [System.Text.Encoding]::ASCII)
    Write-Host "[ SUCCESS ] Windows batch file 'ignite.bat' has been created."
} else {
$shContent = "#!/bin/bash`ncd ""`$(dirname ""`$0"")""`nchmod +x ./$TARGET_ENGINE`necho ""Starting Local LLM...""`n./$TARGET_ENGINE -m $firstModelFile"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$PSScriptRoot/$REL/ignite.sh", $shContent, $utf8NoBom)
    Write-Host "[ SUCCESS ] Unix shell script 'ignite.sh' has been created."
}

Write-Host "[ SUCCESS ] BUILD COMPLETE AT ${REL}"
