#!/bin/bash
# Optional native visual QA builds; the production binary ignores QA appearance metadata.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -D QA_PREVIEW -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path "$PWD/build/module-cache" Sources/Core.swift Sources/Container.swift Sources/CompressedContent.swift Sources/Utility.swift Sources/FileOperations.swift Sources/Workflow.swift Sources/WorkflowModel.swift Sources/UtilityView.swift Sources/App.swift build/NativeCompression.o Vendor/zstd-1.5.7/lib/libzstd.a -lz -o build/AppearancePreview -framework SwiftUI -framework AppKit
python3 - <<'PY'
from pathlib import Path
import plistlib,subprocess,shutil
root=Path.cwd()
for label,appearance in [('Light','NSAppearanceNameAqua'),('HighContrastLight','NSAppearanceNameAccessibilityAqua'),('HighContrastDark','NSAppearanceNameAccessibilityDarkAqua')]:
 target=root/'build'/('SwitchBench-QA-'+label+'.app')
 if target.exists():shutil.rmtree(target)
 subprocess.run(['ditto','--norsrc','--noextattr',str(root/'build/SwitchBench.app'),str(target)],check=True)
 shutil.copy2(root/'build/AppearancePreview',target/'Contents/MacOS/SwitchBench')
 path=target/'Contents/Info.plist';info=plistlib.loads(path.read_bytes());info['CFBundleIdentifier']='local.switchbench.qa.'+label.lower();info['CFBundleName']='SwitchBench QA '+label;info['CFBundleDisplayName']='SwitchBench QA '+label;info['SwitchBenchQAAppearance']=appearance
 path.write_bytes(plistlib.dumps(info))
 subprocess.run(['codesign','--force','--sign','-',str(target)],check=True)
 subprocess.run(['codesign','--verify','--deep','--strict',str(target)],check=True)
 print(target)
PY
