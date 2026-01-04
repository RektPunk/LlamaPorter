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
        ```powershell
        powershell -ExecutionPolicy Bypass -File bootloader.ps1
        ```
    Note: Once the build is complete, a distribution folder `{modelID}_{os}/` will be created.

2. Run

    To start the AI, simply run the ignite script inside the generated folder:
    -  Windows: `ignite.bat`
    - macOS / Linux: `./ignite.sh`

3. Customizing (Optional)

    If you want to package a different model:
    - Change ID: Change the name in `.model` (e.g., qwen2.5-7b-instruct-q4_0).
    - Add Manifest: Create `manifest/{modelID}` and list GGUF URLs.
