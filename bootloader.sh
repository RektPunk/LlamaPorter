#!/bin/bash

if [ ! -f ".model" ]; then
    echo "[ ERROR ] .model file is missing."
    exit 1
fi

MODEL_ID=$(cat .model | xargs)
MANIFEST_PATH="manifest/${MODEL_ID}"

if [ ! -f "$MANIFEST_PATH" ]; then
    echo "[ ERROR ] Manifest file not found at $MANIFEST_PATH"
    exit 1
fi

ENGINE_URL="https://github.com/mozilla-ai/llamafile/releases/download/0.9.3/llamafile-0.9.3"

clear
echo "------------------------------------------------------------"
echo "LlamaPorter: $MODEL_ID"
echo "------------------------------------------------------------"
echo "Please select the target Operating System for deployment:"
echo " 1) Microsoft Windows (.bat format)"
echo " 2) Linux or macOS (.sh format)"
read -p " Selection (1-2): " OS_CHOICE
echo "------------------------------------------------------------"

if [ "$OS_CHOICE" == "1" ]; then
    OS_SUFFIX="win"
    TARGET_ENGINE="llamafile.exe"
    echo "[ INFO ] Target environment set to Windows."
elif [ "$OS_CHOICE" == "2" ]; then
    OS_SUFFIX="unix"
    TARGET_ENGINE="llamafile"
    echo "[ INFO ] Target environment set to Linux/macOS."
else
    echo "[ ERROR ] Invalid selection. Please restart the builder and select 1 or 2."
    exit 1
fi

REL="${MODEL_ID}_${OS_SUFFIX}"
mkdir -p "$REL"

PID_ENG=""
if [ -f "llamafile" ]; then
    echo "[ INFO ] Found local 'llamafile' binary."
else
    if [ ! -f "$REL/$TARGET_ENGINE" ]; then
        echo "[ INFO ] No local engine found. Initiating download..."
        curl -sL -o "llamafile" "$ENGINE_URL" &
        PID_ENG=$!
    else
        echo "[ INFO ] Engine binary already exists in the target folder."
    fi
fi

URL_ARRAY=()
PIDS=()
FIRST_MODEL_FILE=""

echo "[ INFO ] Reading manifest and preparing downloads..."
while IFS= read -r line || [[ -n "$line" ]]; do
    URL=$(echo "$line" | xargs)
    [[ -z "$URL" || "$URL" == \#* ]] && continue

    URL_ARRAY+=("$URL")
    FILE_NAME=$(basename "$URL")

    if [ ! -f "$REL/$FILE_NAME" ]; then
        echo "[ INFO ] Queuing Download: $FILE_NAME"
        curl -sL -o "$REL/$FILE_NAME" "$URL" &
        PIDS+=($!)
    else
        echo "[ INFO ] File already exists: $FILE_NAME (Skipping)"
    fi
    
    if [ -z "$FIRST_MODEL_FILE" ]; then
        FIRST_MODEL_FILE=$FILE_NAME
    fi
done < "$MANIFEST_PATH"

echo "[ INFO ] Total files detected in manifest: ${#URL_ARRAY[@]}"
echo "[ INFO ] Monitoring background download tasks..."
while :; do
    ALIVE_COUNT=0
    [ -n "$PID_ENG" ] && kill -0 $PID_ENG 2>/dev/null && ((ALIVE_COUNT++))
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then ((ALIVE_COUNT++)); fi
    done

    if [ -f "llamafile" ]; then
        ENG_SIZE=$(du -h "llamafile" | awk '{print $1}')
    elif [ -f "$REL/$TARGET_ENGINE" ]; then
        ENG_SIZE=$(du -h "$REL/$TARGET_ENGINE" | awk '{print $1}')
    fi

    MDL_SIZE=$(du -hc "$REL"/*.gguf 2>/dev/null | tail -1 | awk '{print $1}')
    echo -ne "\r\033[K[ PROGRESS ] Engine: ${ENG_SIZE:-0B} | Models: ${MDL_SIZE:-0B} | Active Tasks: $ALIVE_COUNT"

    [ $ALIVE_COUNT -eq 0 ] && break
    sleep 0.5
done
wait
echo
echo "[ SUCCESS ] All resources are ready."

if [ ! -f "$REL/$TARGET_ENGINE" ]; then
    if [ -f "llamafile" ]; then
        echo "[ INFO ] Copying engine binary to $REL..."
        cp "llamafile" "$REL/$TARGET_ENGINE"
    fi
fi

echo "[ INFO ] Generating runtime executable script (Ignite)..."
if [ "$OS_CHOICE" == "1" ]; then
    cat << EOF > "$REL/ignite.bat"
@echo off
title LlamaPorter - $MODEL_ID
chcp 65001 > nul
cd /d "%~dp0"
echo Starting Local LLM...
$TARGET_ENGINE -m $FIRST_MODEL_FILE
pause
EOF
    echo "[ SUCCESS ] Windows batch file 'ignite.bat' has been generated."
else
    cat << EOF > "$REL/ignite.sh"
#!/bin/bash
cd "\$(dirname "\$0")"
chmod +x ./$TARGET_ENGINE
echo "Starting Local LLM..."
./$TARGET_ENGINE -m $FIRST_MODEL_FILE
EOF
    chmod +x "$REL/ignite.sh"
    echo "[ SUCCESS ] Unix shell script 'ignite.sh' has been generated."
fi

echo "[ SUCCESS ] BUILD COMPLETE AT ./${REL}/"
