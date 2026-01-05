# Windows Builder: powershell -ExecutionPolicy Bypass -File bootloader.ps1

$ProgressPreference = 'SilentlyContinue'
$ENGINE_URL = "https://github.com/mozilla-ai/llamafile/releases/download/0.9.3/llamafile-0.9.3"
if (-not (Test-Path "manifest")) {
    Write-Host "[ ERROR ] manifest/ folder not found."; 
    exit 1 
}
if (-not (Test-Path "assets/")) { New-Item -ItemType Directory -Path "assets/" | Out-Null }

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
    $models = Get-ChildItem "manifest" | Select-Object -ExpandProperty Name
    for ($i=0; $i -lt $models.Count; $i++) {
        Write-Host " $($i+1)) $($models[$i])"
    }
    $choice = Read-Host " Select a model (1-$($models.Count))"
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $models.Count) {
        $MODEL_ID = $models[[int]$choice-1]
        $MANIFEST_PATH = "manifest/$MODEL_ID"
    } else {
        Write-Host "[ ERROR ] Invalid Model selection. Please restart the builder."
        exit 1
    }
} else {
    $MODEL_ID = (Get-Content ".model").Trim()
    $MANIFEST_PATH = "manifest/$MODEL_ID"
}
Write-Host "[ INFO ] Target LLM model set to $MODEL_ID"
Write-Host "------------------------------------------------------------"

if (-not (Test-Path $MANIFEST_PATH)) {
    Write-Host "[ ERROR ] Manifest file not found at $MANIFEST_PATH"
    exit 1
}

$REL = "${MODEL_ID}_${OS_SUFFIX}"
if (-not (Test-Path $REL)) { New-Item -ItemType Directory -Path $REL | Out-Null }

if (Test-Path "assets/llamafile") {
    Write-Host "[ INFO ] Found local 'llamafile' binary."
} else {
    if (-not (Test-Path "$REL/$TARGET_ENGINE")) {
        Write-Host "[ INFO ] No local engine found. Initiating download..."
        Start-Job -Name "EngineDownload" -ScriptBlock {
            param($url, $root) 
            Set-Location $root
            Invoke-WebRequest -Uri $url -OutFile "assets/llamafile"
        } -ArgumentList $ENGINE_URL, $PSScriptRoot | Out-Null
    } else {
        Write-Host "[ INFO ] Engine binary already exists in the target folder."
    }
}


$urls = Get-Content $MANIFEST_PATH | Where-Object { $_ -and -not $_.StartsWith("#") }
$MODEL_CACHE_DIR = "assets/$MODEL_ID"
if (-not (Test-Path $MODEL_CACHE_DIR)) { New-Item -ItemType Directory -Path $MODEL_CACHE_DIR | Out-Null }

$firstModelFile = ""
foreach ($url in $urls) {
    $url = $url.Trim()
    $fileName = Split-Path $url -Leaf
    if ([string]::IsNullOrEmpty($firstModelFile)) { $firstModelFile = $fileName }
    if (-not (Test-Path "$MODEL_CACHE_DIR/$fileName")) {
        Write-Host "[ INFO ] Queuing Download: $fileName"
        Start-Job -Name "Download-$fileName" -ScriptBlock {
            param($u, $p, $root) 
            Set-Location $root
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $u -OutFile $p
        } -ArgumentList $url, "$MODEL_CACHE_DIR/$fileName", $PSScriptRoot | Out-Null
    } else {
        Write-Host "[ INFO ] File already exists: $fileName (Skipping)"
    }
}

Write-Host "[ INFO ] Monitoring background download tasks..."
while ($true) {
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
    $aliveCount = ($jobs).Count

    $engSize = "0B"
    $engFile = Get-Item "assets/llamafile" -ErrorAction SilentlyContinue
    if ($engFile) { $engSize = "$(([math]::Round($engFile.Length / 1MB, 1)))M" }

    $totalMdlBytes = (Get-ChildItem "$MODEL_CACHE_DIR/*.gguf" -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $mdlSize = "0B"
    if ($totalMdlBytes -gt 0) { 
        $mdlSize = "$(([math]::Round($totalMdlBytes / 1GB, 2)))G" 
    }

    $statusLine = "`r[ PROGRESS ] Engine: $engSize | Models: $mdlSize | Active Tasks: $aliveCount"
    Write-Host -NoNewline ($statusLine.PadRight(80))

    if ($aliveCount -eq 0) { break }
    Start-Sleep -Milliseconds 500
}
Get-Job | Remove-Job
Write-Host ""
Write-Host "[ SUCCESS ] All resources are ready."

if (-not (Test-Path "$REL/$TARGET_ENGINE")) {
    if (Test-Path "assets/llamafile") {
        Write-Host "`n[ INFO ] Copying engine binary to $REL..."
        Copy-Item "assets/llamafile" "$REL/$TARGET_ENGINE"
    }
}
Write-Host "[ INFO ] Copying LLM model to $REL..."
Copy-Item "$MODEL_CACHE_DIR/*" -Destination "$REL/" -ErrorAction SilentlyContinue

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

Write-Host "[ SUCCESS ] BUILD COMPLETE AT ./${REL}/"
