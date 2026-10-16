#!/usr/bin/env bash
set -euo pipefail

echo "==> [Gate ATS] Verificando configuração de App Transport Security..."

INFO_PLIST="LanRemote/App/Info.plist"

if [ ! -f "$INFO_PLIST" ]; then
    echo "ERRO: Info.plist não encontrado em $INFO_PLIST"
    exit 1
fi

# 1. Proibir NSAllowsArbitraryLoads = true
if grep -q "<key>NSAllowsArbitraryLoads</key>" "$INFO_PLIST"; then
    if grep -A 1 "<key>NSAllowsArbitraryLoads</key>" "$INFO_PLIST" | grep -q "<true/>"; then
        echo "FALHA DE SEGURANÇA: NSAllowsArbitraryLoads=true não é permitido!"
        exit 1
    fi
fi

# 2. Exigir NSAllowsLocalNetworking = true para operação na rede LAN da TV
if ! grep -q "<key>NSAllowsLocalNetworking</key>" "$INFO_PLIST"; then
    echo "FALHA: NSAllowsLocalNetworking deve estar habilitado para controle na rede local."
    exit 1
fi

echo "SUCESSO: Configuração ATS em conformidade com OWASP MASVS-NETWORK."
