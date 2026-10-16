#!/usr/bin/env bash
set -euo pipefail

echo "==> [Gate Sensitive Files] Verificando ausência de arquivos e chaves sensíveis rastreadas..."

PROHIBITED_EXTENSIONS=("*.p8" "*.p12" "*.mobileprovision" "*.cer" "*.keystore" "*.jks")

for pattern in "${PROHIBITED_EXTENSIONS[@]}"; do
    FOUND=$(git ls-files "$pattern" 2>/dev/null || true)
    if [ -n "$FOUND" ]; then
        echo "FALHA DE SEGURANÇA: Arquivo sensível rastreado no Git: $FOUND"
        exit 1
    fi
done

echo "SUCESSO: Nenhum arquivo de credencial sensível detectado no repositório."
