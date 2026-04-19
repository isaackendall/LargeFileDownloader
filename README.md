# Large File Downloader

Native macOS SwiftUI utility for downloading large files with `aria2c`.

## What It Does

- Paste a download URL
- Choose a destination folder
- Optionally set an output filename
- Resolve redirects before download
- Keep the Mac awake during long transfers
- Stream live `aria2c` logs
- Copy the generated command or resolved URL

## Requirements

- macOS
- Swift toolchain / Xcode command line tools
- `aria2c` installed, usually via Homebrew:

```bash
brew install aria2
```

## Run Locally

From this folder:

```bash
./script/build_and_run.sh
```

## Project Layout

- `Package.swift`: SwiftPM executable package
- `Sources/LargeFileDownloader/`: native macOS app source
- `script/build_and_run.sh`: one-stop build and launch script
- `.codex/environments/environment.toml`: Codex Run button wiring

## Notes

- The app stages a proper `.app` bundle in `dist/` before launching.
- The previous Python prototype is left in the repo as a reference while the new SwiftUI app takes over.
