# SwitchBench for Windows

The Windows preview runs on Windows 11 with an x64 Intel or AMD processor. Extract the whole download, open the SwitchBench folder and double-click **SwitchBench.exe**. Keep the Engine folder beside it. The portable download includes the processing helpers and Swift runtime.

Choose a tool on the left. Add files, add a folder or drag files into the window. Use **Preview** to see the planned result, then start. Select a result to read its details or open the saved location. **Stop** lets the current task clean up. SwitchBench reads originals and saves checked copies.

Update Games, Check Files, Combine Files and Compress Files use the prod.keys file you already use with your emulator. Choose it in the app. The additional key button appears when a task needs title.keys. Key processing stays on your computer.

The app remembers save folders and the production key file's location in your local Windows profile. It keeps the additional key file's location for the current session.

**Compress Files** creates NSZ from NSP or XCZ from XCI. Savings vary by game. Use **Convert to NSP** when you need to expand the compressed game content.

## Build from source

Use Windows 11 x64, Swift 6.3.3, Visual Studio 2022 C++ tools and MSYS2 UCRT64. The GitHub workflow shows the exact setup. Run the following from the repository root:

1. In a UCRT64 shell with make, GCC and zlib installed, run `bash Windows/build-native.sh`.
2. In PowerShell with Swift available, run `./Windows/build.ps1 -Test`.
3. Run `./Windows/package.ps1` to package and smoke-test the app. The ZIP is in `build/windows`.

The Windows interface uses WinForms. The app shares its processing engine with the macOS version and uses the same helpers. The Windows package includes upstream license notices.
