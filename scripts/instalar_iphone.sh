#!/usr/bin/env bash
# Compila assinado com o seu time e instala no iPhone pareado (pela rede ou pelo cabo).
# Com a conta Apple gratuita a assinatura vale 7 dias: depois disso o iPhone se recusa a abrir o app
# ("perfil não confiável") e é só rodar este script de novo.
#
#   ./scripts/instalar_iphone.sh              instala e abre o app
#   ./scripts/instalar_iphone.sh --sem-abrir  só instala
#
# Time e iPhone vêm de ~/.config/lan-remote/ios.env (./scripts/preparar_ios_env.sh).
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$HOME/.config/lan-remote/ios.env"
abrir=1
for arg in "$@"; do
  case "$arg" in
    --sem-abrir) abrir=0 ;;
    *) echo "opção desconhecida: $arg" >&2; exit 2 ;;
  esac
done

[[ -f "$CONFIG" ]] || { echo "rode antes: ./scripts/preparar_ios_env.sh" >&2; exit 1; }
TEAM="" UDID="" BUNDLE_ID=""
# shellcheck disable=SC1090
source "$CONFIG"
[[ -n "$TEAM" && -n "$UDID" ]] || { echo "faltam TEAM ou UDID em $CONFIG" >&2; exit 1; }
BUNDLE="${BUNDLE_ID:-com.lanremote.ios}"

cd "$RAIZ"
# como o build.sh e o CI: o projeto do Xcode sai do project.yml
if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

APP="build/DerivedData-iphone/Build/Products/Release-iphoneos/LanRemote.app"
# Sem fonte alterado, o build incremental copia o perfil renovado para dentro do .app mas não reassina:
# o selo fica inválido ("a sealed resource is missing or invalid") e o iPhone não abre o app. Apagar o
# .app força o Xcode a montá-lo e assiná-lo de novo, reaproveitando a compilação dos fontes.
rm -rf "$APP"

echo "==> Compilando (Release, assinado)..."
# o project.yml desliga a assinatura (para o simulador e o CI); aqui ela é ligada só nesta compilação
xcodebuild -project LanRemote.xcodeproj -scheme LanRemote -configuration Release \
  -destination "id=$UDID" -derivedDataPath build/DerivedData-iphone \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" -quiet build

codesign --verify --deep --strict "$APP" 2>/dev/null \
  || { echo "a assinatura do app compilado não confere: nada foi instalado" >&2; exit 1; }
vence=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null || true)
if [[ -n "$vence" ]]; then
  segundos=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$vence" +%s 2>/dev/null || true)
  [[ -n "$segundos" ]] && vence=$(date -r "$segundos" "+%d/%m às %H:%M")
fi

echo "==> Instalando no iPhone..."
xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null
echo "    instalado${vence:+; a assinatura vale até $vence}."

if [[ $abrir -eq 1 ]]; then
  if xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE" >/dev/null 2>&1; then
    echo "==> Aberto no iPhone."
  else
    echo "    não abriu sozinho (o iPhone pode estar bloqueado): desbloqueie e toque no app."
  fi
fi
