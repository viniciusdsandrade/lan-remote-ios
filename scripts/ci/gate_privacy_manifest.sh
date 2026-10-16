#!/usr/bin/env bash
set -euo pipefail

echo "==> [Gate Privacy Manifest] Validando PrivacyInfo.xcprivacy..."

PRIVACY_FILE="LanRemote/Resources/PrivacyInfo.xcprivacy"

if [ ! -f "$PRIVACY_FILE" ]; then
    echo "FALHA: PrivacyInfo.xcprivacy não encontrado em $PRIVACY_FILE"
    exit 1
fi

# Validar formato XML Plist válido
if command -v plutil &> /dev/null; then
    plutil -lint "$PRIVACY_FILE"
fi

# Validar chaves obrigatórias
if ! grep -q "<key>NSPrivacyTracking</key>" "$PRIVACY_FILE"; then
    echo "FALHA: NSPrivacyTracking ausente no manifesto de privacidade."
    exit 1
fi

if ! grep -q "<key>NSPrivacyCollectedDataTypes</key>" "$PRIVACY_FILE"; then
    echo "FALHA: NSPrivacyCollectedDataTypes ausente no manifesto de privacidade."
    exit 1
fi

echo "SUCESSO: PrivacyInfo.xcprivacy aprovado segundo diretrizes da Apple."
