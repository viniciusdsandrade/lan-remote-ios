#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo "  LanRemote iOS - Build & Validation Script"
echo "=========================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo "[1/3] Gerando projeto XcodeGen..."
if command -v xcodegen &> /dev/null; then
    xcodegen generate
else
    echo "Aviso: xcodegen não encontrado no PATH. Utilizando LanRemote.xcodeproj existente."
fi

echo "[2/3] Compilando target do aplicativo LanRemote (iOS Simulator)..."
xcodebuild \
    -project LanRemote.xcodeproj \
    -scheme LanRemote \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build | xcbeautify 2>/dev/null || xcodebuild \
    -project LanRemote.xcodeproj \
    -scheme LanRemote \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build

echo "[3/3] Compilando target de testes LanRemoteTests..."
xcodebuild \
    -project LanRemote.xcodeproj \
    -scheme LanRemote \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing | xcbeautify 2>/dev/null || xcodebuild \
    -project LanRemote.xcodeproj \
    -scheme LanRemote \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing

echo "=========================================================="
echo "  SUCESSO: LanRemote iOS compilado e validado com êxito!"
echo "=========================================================="
