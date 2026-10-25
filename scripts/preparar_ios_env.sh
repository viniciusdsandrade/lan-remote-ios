#!/usr/bin/env bash
# Prepara ~/.config/lan-remote/ios.env (0600) com o time de assinatura e o iPhone, lidos deste Mac:
# o perfil mais recente que o Xcode criou e o primeiro iPhone pareado. Os valores não são mostrados e
# nunca entram no repositório.
#
# Antes: entre com o seu Apple ID no Xcode (Settings > Accounts) e pareie o iPhone uma vez (cabo,
# "Confiar neste computador", Modo de Desenvolvedor ligado no iPhone).
set -euo pipefail

PASTA="$HOME/.config/lan-remote"
ARQUIVO="$PASTA/ios.env"
PERFIS="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$PASTA"
chmod 700 "$PASTA"

TIME=""
mais_novo=""
if [[ -d "$PERFIS" ]]; then
  while IFS= read -r -d '' p; do
    plist=$(security cms -D -i "$p" 2>/dev/null) || continue
    criado=$(plutil -extract CreationDate raw -o - - <<<"$plist" 2>/dev/null) || continue
    if [[ -z "$mais_novo" || "$criado" > "$mais_novo" ]]; then
      mais_novo="$criado"
      TIME=$(plutil -extract TeamIdentifier.0 raw -o - - <<<"$plist" 2>/dev/null || true)
    fi
  done < <(find "$PERFIS" -name '*.mobileprovision' -print0)
fi
[[ -n "$TIME" ]] || { echo "nenhum perfil do Xcode encontrado: rode o app uma vez pelo Xcode com o seu time, ou preencha TEAM= em $ARQUIVO" >&2; exit 1; }

JSON=$(mktemp)
trap 'rm -f "$JSON"' EXIT
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
APARELHO=$(python3 -I - "$JSON" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit()
for a in d:
    h = a.get("hardwareProperties", {})
    if h.get("reality") == "physical" and h.get("platform") == "iOS" \
            and a.get("connectionProperties", {}).get("pairingState") == "paired":
        print(h.get("udid", "")); break
PY
)
[[ -n "$APARELHO" ]] || { echo "nenhum iPhone pareado com este Mac (xcrun devicectl list devices)" >&2; exit 1; }

umask 077
{
  echo "# Gerado por preparar_ios_env.sh. Fica fora do repositório: não copie para lá."
  echo "TEAM=$TIME"
  echo "UDID=$APARELHO"
  echo "# BUNDLE_ID=com.lanremote.ios   (troque pelo de uma instalação antiga para manter os pareamentos dela,"
  echo "#                                ou se a Apple disser que o identificador já está em uso)"
} > "$ARQUIVO"
chmod 600 "$ARQUIVO"
echo "ok: $ARQUIVO (time e iPhone guardados; os valores não são mostrados)"
