# LlamaPorter
LlamaPorter is a lightweight tool to build Ready-to-Use Local LLM packages specifically for **GGUF** format models. It bundles everything you need into a single folder so you can run AI anywhere—including offline and air-gapped environments.

## Quick Start
1. Build
    Run the builder appropriate for your Operating System:
    - macOS / Linux:
        ```bash
        chmod +x bootloader.sh
        ./bootloader.sh
        ```
    - Windows:
        ```PowerShell
        # Run in PowerShell
        powershell -ExecutionPolicy Bypass -File bootloader.ps1
        ```
    Once the build is complete, a folder like Phi-3-mini..._win or _unix will be created.

2. Run
    To start the AI, simply run `ignite.bat` (Windows) or `./ignite.sh` (Linux/macOS) inside the generated folder.

3. Customizing (Optional)
    If you want to package a different model:
    - Update ID: Change the name in `.model` (e.g., qwen2.5-7b-instruct-q4_0).
    - Add Manifest: Create `manifest/{Your-Model-ID}` and list GGUF URLs (See `manifest/qwen2.5-7b-instruct-q4_0`).
