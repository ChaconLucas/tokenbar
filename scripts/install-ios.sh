#!/bin/sh
# Instala o TokenBar no iPhone conectado, sem abrir o Xcode (mas ele precisa estar instalado):
#   curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-ios.sh | sh
#
# Rodar de novo atualiza e renova os 7 dias da conta gratuita da Apple.
# Antes, uma vez só: Xcode → Ajustes → Contas → entrar com o seu Apple ID.
#
#   … | sh -s -- --auto   instala e agenda o Mac para atualizar/renovar sozinho (pelo Wi-Fi, depois da 1ª vez no cabo)
set -eu

AUTO_SETUP=""
for a in "$@"; do [ "$a" = "--auto" ] && AUTO_SETUP=1; done
STAMP="$HOME/.tokenbar/ios-last-install"

# Execução agendada: só trabalha se saiu versão nova ou se faltam ~2 dias para vencer (instalado há 5+ dias).
if [ -n "${TB_SCHEDULED:-}" ] && [ -f "$STAMP" ]; then
  read -r LAST_T LAST_V < "$STAMP" || true
  LATEST=$(curl -fsSL https://api.github.com/repos/ChaconLucas/tokenbar/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
  AGE=$(( $(date +%s) - ${LAST_T:-0} ))
  if [ "$AGE" -lt 432000 ] && [ "$LATEST" = "${LAST_V:-}" ]; then exit 0; fi
fi

say() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Precisa de um Mac (a Apple só deixa instalar no iPhone pelo Xcode)."
XCODE=$(xcode-select -p 2>/dev/null || true)
case "$XCODE" in
  *Xcode*.app*) ;;
  *) fail "Instale o Xcode pela App Store, abra uma vez e rode: sudo xcode-select -s /Applications/Xcode.app" ;;
esac

DIR="${TB_DIR:-$HOME/.tokenbar/src}"
command -v xcodegen >/dev/null || {
  command -v brew >/dev/null || fail "Falta o Homebrew (https://brew.sh) para instalar o xcodegen."
  say "Instalando o xcodegen…"; brew install -q xcodegen
}

say "Baixando o código…"
if [ -d "$DIR/.git" ]; then git -C "$DIR" pull -q --ff-only; else git clone -q --depth 1 https://github.com/ChaconLucas/tokenbar.git "$DIR"; fi
cd "$DIR"

# Time de desenvolvimento: do certificado que o Xcode cria ao entrar com o Apple ID.
TEAM="${TB_TEAM:-}"
if [ -z "$TEAM" ]; then
  TEAM=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
fi
[ -n "$TEAM" ] || fail "Não achei a sua conta Apple. No Xcode: Ajustes → Contas → + → Apple ID. Depois rode de novo."

# Prefixo único por pessoa (a conta gratuita não aceita o mesmo identificador de outra pessoa). Fica guardado.
PREFIX_FILE="$HOME/.tokenbar/ios-prefix"
if [ -n "${TB_PREFIX:-}" ]; then PREFIX="$TB_PREFIX"
elif [ -f "$PREFIX_FILE" ]; then PREFIX=$(cat "$PREFIX_FILE")
else
  PREFIX="io.tokenbar.$(whoami | tr -cd 'a-z0-9' | cut -c1-12)$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
  mkdir -p "$HOME/.tokenbar" && printf '%s' "$PREFIX" > "$PREFIX_FILE"
fi
printf 'DEVELOPMENT_TEAM = %s\nTB_BUNDLE_PREFIX = %s\n' "$TEAM" "$PREFIX" > Config/Signing.local.xcconfig

# iPhone conectado (cabo ou mesma rede depois de parear uma vez pelo cabo).
UDID="${TB_DEVICE:-}"
if [ -z "$UDID" ]; then
  UDID=$(xcrun devicectl list devices 2>/dev/null | grep -i "iphone" | grep -v -i "simulat" | grep -i "available" \
    | grep -o '[0-9A-F]\{8\}-[0-9A-F]\{16\}' | head -1)
fi
[ -n "$UDID" ] || { [ -n "${TB_SCHEDULED:-}" ] && exit 0; true; }
[ -n "$UDID" ] || fail "Nenhum iPhone encontrado. Conecte por cabo, desbloqueie, toque em Confiar e ligue Ajustes → Privacidade e Segurança → Modo de Desenvolvedor."

say "Montando o app (a primeira vez leva alguns minutos)…"
xcodegen generate -q
LOG=$(mktemp)
if ! xcodebuild -project TokenBar.xcodeproj -scheme TokenBar -configuration Release \
     -destination "id=$UDID" -derivedDataPath build-ios -allowProvisioningUpdates build >"$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -5 >&2
  fail "Não consegui montar. Abra o Xcode uma vez com o iPhone conectado (Window → Devices) e rode de novo."
fi

[ -n "${TB_NO_INSTALL:-}" ] && { say "Montado (sem instalar)."; exit 0; }
say "Instalando no iPhone…"
APP=build-ios/Build/Products/Release-iphoneos/TokenBar.app
# iPhone com iOS beta pede o devicectl do Xcode beta.
xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null 2>&1 \
  || { [ -d /Applications/Xcode-beta.app ] && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
       xcrun devicectl device install app --device "$UDID" "$APP" >/dev/null 2>&1; } \
  || fail "Não consegui instalar. O iPhone está desbloqueado e com o Modo de Desenvolvedor ligado?"
TAG=$(curl -fsSL https://api.github.com/repos/ChaconLucas/tokenbar/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)
printf '%s %s\n' "$(date +%s)" "$TAG" > "$STAMP"

if [ -n "$AUTO_SETUP" ]; then
  PLIST="$HOME/Library/LaunchAgents/io.tokenbar.ios-renew.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.tokenbar.ios-renew</string>
  <key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string>
    <string>curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-ios.sh | sh</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>TB_SCHEDULED</key><string>1</string>
    <key>TB_DIR</key><string>$DIR</string>
    <key>TB_PREFIX</key><string>$PREFIX</string>
    <key>TB_TEAM</key><string>$TEAM</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StartInterval</key><integer>86400</integer>
  <key>StandardOutPath</key><string>$HOME/.tokenbar/ios-renew.log</string>
  <key>StandardErrorPath</key><string>$HOME/.tokenbar/ios-renew.log</string>
</dict></plist>
PL
  launchctl bootout "gui/$(id -u)/io.tokenbar.ios-renew" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" && say "Agendado: o Mac atualiza e renova o app do iPhone sozinho (1x por dia confere; só reinstala quando precisa)."
fi
[ -n "${TB_SCHEDULED:-}" ] && exit 0

cat <<'EOF'

✓ TokenBar instalado no iPhone.

Na primeira vez:
  1. No iPhone: Ajustes → Geral → VPN e Gerenciamento de Dispositivos → o seu Apple ID → Confiar.
  2. Abra o TokenBar → Escanear QR → aponte para o QR do computador (Primeiros passos → Celular e relógio).
  3. Permita a Rede Local quando ele pedir.

A conta gratuita da Apple faz o app vencer em 7 dias: rode este mesmo comando de novo para renovar e atualizar.
EOF
