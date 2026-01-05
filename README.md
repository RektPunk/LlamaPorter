# LlamaPorter
LlamaPorter is a lightweight tool to build Ready-to-Use Local LLM specifically for **GGUF** format models. Powered by [mozilla-ai/llamafile](https://github.com/mozilla-ai/llamafile), it bundles everything into a single portable folder so you can run AI anywhere—even in completely offline or air-gapped environments.

## Quick Start
### Build
Run the builder appropriate for your Operating System:
- macOS / Linux:
    ```bash
    chmod +x bootloader.sh
    ./bootloader.sh
    ```
    (Note: macOS users may need Xcode Command Line Tools. Run xcode-select --install if prompted.)
- Windows:
    ```powershell
    powershell -ExecutionPolicy Bypass -File bootloader.ps1
    ```
Once the build is complete, a distribution folder named `dists/{modelID}_{os}/` will be created.

### Run
To start the AI, simply run the ignite script inside the generated folder:
-  Windows: `ignite.bat`
- macOS / Linux: `./ignite.sh`

### Customizing (Optional)

1. Add New Models:

    To package a different model, simply create a new manifest file:
    - Create a file at `manifest/{your-model-name}`.
    - List the GGUF download URLs inside (one per line).

2. Pre-set Model: 
    
    To bypass the selection menu, create a `.model` file containing the specific manifest name as:
    ```bash
    echo Phi-3-mini-4k-instruct-q4 >> .model
    ```
