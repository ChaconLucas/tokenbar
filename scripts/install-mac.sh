#!/bin/sh
# Instala o TokenBar no Mac sem Xcode:
#   curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-mac.sh | sh
#
# Baixa o app pronto dos Releases, põe em /Applications e abre. Baixado pelo terminal, o macOS
# não marca o arquivo como "da internet", então não aparece o aviso de desenvolvedor não identificado.
set -eu

REPO="ChaconLucas/tokenbar"
URL="${TB_ZIP_URL:-https://github.com/$REPO/releases/latest/download/TokenBar-macOS.zip}"
DEST="${TB_DEST:-/Applications}"

say() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Este instalador é só para Mac. Windows/Linux: veja o README."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 15 ] || fail "O TokenBar precisa do macOS 15 ou mais novo (este Mac tem $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "Baixando o TokenBar…"
curl -fL --progress-bar "$URL" -o "$tmp/TokenBar.zip" || fail "Não consegui baixar $URL"
ditto -x -k "$tmp/TokenBar.zip" "$tmp" || fail "O arquivo baixado está corrompido."
[ -d "$tmp/TokenBar.app" ] || fail "O pacote não tem o TokenBar.app."

if pgrep -qf "$DEST/TokenBar.app/Contents/MacOS/"; then
  say "Fechando o TokenBar aberto…"
  osascript -e 'quit app "TokenBar"' >/dev/null 2>&1 || pkill -x TokenBar || true
  sleep 1
fi

say "Instalando em ${DEST}…"
mkdir -p "$DEST" 2>/dev/null || true
if [ -w "$DEST" ]; then
  rm -rf "$DEST/TokenBar.app" && ditto "$tmp/TokenBar.app" "$DEST/TokenBar.app"
else
  sudo rm -rf "$DEST/TokenBar.app" && sudo ditto "$tmp/TokenBar.app" "$DEST/TokenBar.app"
fi
xattr -dr com.apple.quarantine "$DEST/TokenBar.app" 2>/dev/null || true
codesign --verify --deep --strict "$DEST/TokenBar.app" 2>/dev/null || fail "A assinatura do app não confere. Não abra; avise em github.com/$REPO/issues."

if [ -z "${TB_NO_OPEN:-}" ]; then
  say "Abrindo…"
  open "$DEST/TokenBar.app"
fi

cat <<'EOF'

✓ TokenBar instalado.

Próximos passos:
  1. Claude Code: no TokenBar, EDITAR → Mais ajustes → Conectar Claude Code.
     Os números chegam na próxima vez que uma sessão do Claude Code atualizar.
  2. Codex: nada a fazer — aparece se você usou o Codex recentemente.
  3. Se o macOS perguntar sobre "conexões de entrada", responda Permitir
     (é assim que o celular e o relógio leem o Mac pelo Wi-Fi).
  4. Celular Android: baixe o TokenBar-Android.apk em
     https://github.com/ChaconLucas/tokenbar/releases e escaneie o QR em Mais ajustes.
EOF
