# Windows Builder: powershell -ExecutionPolicy Bypass -File bootloader.ps1

$ProgressPreference = 'SilentlyContinue'
if (-not (Test-Path ".model")) {
    Write-Host "[ ERROR ] .model file is missing."
    exit 1
}

$MODEL_ID = (Get-Content ".model").Trim()
$MANIFEST_PATH = "manifest/$MODEL_ID"

if (-not (Test-Path $MANIFEST_PATH)) {
    Write-Host "[ ERROR ] Manifest file not found at $MANIFEST_PATH"
    exit 1
}

$ENGINE_URL = "https://github.com/mozilla-ai/llamafile/releases/download/0.9.3/llamafile-0.9.3"

Clear-Host
Write-Host "------------------------------------------------------------"
Write-Host " LlamaPorter: $MODEL_ID"
Write-Host "------------------------------------------------------------"
Write-Host "Please select the target Operating System for deployment:"
Write-Host " 1) Microsoft Windows (.bat format)"
Write-Host " 2) Linux or macOS (.sh format)"
$OS_CHOICE = Read-Host " Selection (1-2)"
Write-Host "------------------------------------------------------------"

if ($OS_CHOICE -eq "1") {
    $OS_SUFFIX = "win"
    $TARGET_ENGINE = "llamafile.exe"
    Write-Host "[ INFO ] Target environment set to Windows."
} elseif ($OS_CHOICE -eq "2") {
    $OS_SUFFIX = "unix"
    $TARGET_ENGINE = "llamafile"
    Write-Host "[ INFO ] Target environment set to Linux/macOS."
} else {
    Write-Host "[ ERROR ] Invalid selection. Please restart the builder and select 1 or 2."
    exit 1
}

$REL = "${MODEL_ID}_${OS_SUFFIX}"
if (-not (Test-Path $REL)) { New-Item -ItemType Directory -Path $REL | Out-Null }

if (Test-Path "llamafile") {
    Write-Host "[ INFO ] Found local 'llamafile' binary. It will be copied to the target folder."
} else {
    if (-not (Test-Path "$REL/$TARGET_ENGINE")) {
        Write-Host "[ INFO ] No local engine found. Initiating download..."
        Start-Job -Name "EngineDownload" -ScriptBlock {
            param($url, $out) Invoke-WebRequest -Uri $url -OutFile $out
        } -ArgumentList $ENGINE_URL, "llamafile" | Out-Null
    }
    else {
        Write-Host "[ INFO ] Engine binary already exists in the target folder."
    }
}

$urls = Get-Content $MANIFEST_PATH | Where-Object { $_ -and -not $_.StartsWith("#") }
$firstModelFile = ""

foreach ($url in $urls) {
    $url = $url.Trim()
    $fileName = Split-Path $url -Leaf
    if ([string]::IsNullOrEmpty($firstModelFile)) { $firstModelFile = $fileName }
    if (-not (Test-Path "$REL/$fileName")) {
        Write-Host "[ INFO ] Queuing Download: $fileName"
        Start-Job -Name "Download-$fileName" -ScriptBlock {
            param($u, $p) 
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $u -OutFile $p
        } -ArgumentList $url, "$REL/$fileName" | Out-Null
    } else {
        Write-Host "[ INFO ] File already exists: $fileName (Skipping)"
    }
}


Write-Host "[ INFO ] Monitoring background download tasks..."
while ($true) {
    $jobs = Get-Job | Where-Object { $_.State -eq "Running" }
    $aliveCount = ($jobs).Count

    $engSize = "0B"
    $engFile = Get-Item "llamafile" -ErrorAction SilentlyContinue
    if ($engFile) { $engSize = "$(([math]::Round($engFile.Length / 1MB, 1)))M" }

    $totalMdlBytes = (Get-ChildItem "$REL/*.gguf" -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
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
Write-Host "[ SUCCESS ] All resources are ready."

if (-not (Test-Path "$REL/$TARGET_ENGINE")) {
    if (Test-Path "llamafile") {
        Write-Host "`n[ INFO ] Copying engine binary to $REL..."
        Copy-Item "llamafile" "$REL/$TARGET_ENGINE"
    }
}

Write-Host "[ INFO ] Generating runtime executable script (Ignite)..."
if ($OS_CHOICE -eq "1") {
    $batContent = "@echo off`ntitle LlamaPorter - $MODEL_ID`nchcp 65001 > nul`ncd /d ""%~dp0""`necho Starting Local LLM...`n$TARGET_ENGINE -m $firstModelFile`npause"
    [System.IO.File]::WriteAllText("$PSScriptRoot/$REL/ignite.bat", $batContent, [System.Text.Encoding]::ASCII)
    Write-Host "[ SUCCESS ] Windows batch file 'ignite.bat' has been generated."
} else {
    $shContent = "#!/bin/bash`ncd ""$(dirname ""$0"")""`nchmod +x ./$TARGET_ENGINE`necho ""Starting Local LLM...""`n./$TARGET_ENGINE -m $firstModelFile"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$PSScriptRoot/$REL/ignite.sh", $shContent, $utf8NoBom)
    Write-Host "[ SUCCESS ] Unix shell script 'ignite.sh' has been generated."
}

Write-Host "[ SUCCESS ] BUILD COMPLETE AT ./${REL}/"
