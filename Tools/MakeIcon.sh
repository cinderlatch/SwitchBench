#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Assets build/module-cache
swift -module-cache-path "$PWD/build/module-cache" Tools/MakeIcon.swift Assets
