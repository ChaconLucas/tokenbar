#!/bin/sh
# Publica uma versão nova de tudo, e os apps instalados se atualizam sozinhos:
#   scripts/release.sh 0.3.1 "o que mudou"
#
# Mac (zip), Android e Wear OS (apk, assinados com ~/.tokenbar-keys/release.jks) e Windows
# (instalador + assinatura do atualizador, ~/.tokenbar-keys/tauri-updater.key). As chaves ficam
# fora do repo: sem elas os apps instalados recusam a atualização.
set -eu

V="${1:?uso: scripts/release.sh 0.3.1 \"o que mudou\"}"
NOTES="${2:-Versão $V}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/release-$V"
cd "$ROOT"

say() { printf '\033[1;35m▸\033[0m %s\n' "$1"; }
fail() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

echo "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "Versão no formato 1.2.3"
[ -z "$(git status --porcelain)" ] || fail "Há mudanças sem commit. Faça o commit antes de publicar."
[ "$(git branch --show-current)" = "main" ] || fail "Publique a partir da branch main."
git rev-parse "v$V" >/dev/null 2>&1 && fail "A versão v$V já existe."
[ -f "$HOME/.tokenbar-keys/tauri-updater.key" ] || fail "Falta ~/.tokenbar-keys/tauri-updater.key"

say "Versão $V em todos os apps"
build=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml)
sed -i '' -e "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$V\"/" \
          -e "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$((build + 1))\"/" project.yml
for f in android/app/build.gradle.kts android/wear/build.gradle.kts; do
  code=$(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' "$f")
  sed -i '' -e "s/versionCode = [0-9]*/versionCode = $((code + 1))/" -e "s/versionName = \"[^\"]*\"/versionName = \"$V\"/" "$f"
done
sed -i '' "s/\"version\": \"[^\"]*\"/\"version\": \"$V\"/" desktop/src-tauri/tauri.conf.json desktop/package.json
sed -i '' "1,/^version = /s/^version = \"[^\"]*\"/version = \"$V\"/" desktop/src-tauri/Cargo.toml

mkdir -p "$OUT"

say "Mac"
xcodegen generate -q
xcodebuild -project TokenBar.xcodeproj -scheme TokenBarMac -configuration Release -derivedDataPath build/release-mac build -quiet
ditto -c -k --keepParent build/release-mac/Build/Products/Release/TokenBar.app "$OUT/TokenBar-macOS.zip"

say "Android e Wear OS"
(cd android && JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null || echo /opt/homebrew/opt/openjdk@17) \
  ./gradlew -q :app:assembleRelease :wear:assembleRelease)
cp android/app/build/outputs/apk/release/app-release.apk "$OUT/TokenBar-Android.apk"
cp android/wear/build/outputs/apk/release/wear-release.apk "$OUT/TokenBar-WearOS.apk"

say "Windows"
(cd desktop && TAURI_SIGNING_PRIVATE_KEY="$(cat "$HOME/.tokenbar-keys/tauri-updater.key")" TAURI_SIGNING_PRIVATE_KEY_PASSWORD="" \
  PATH="/opt/homebrew/opt/llvm/bin:$HOME/.cargo/bin:$PATH" \
  npx tauri build --runner cargo-xwin --target x86_64-pc-windows-msvc >/dev/null)
nsis=desktop/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis
cp "$nsis/TokenBar_${V}_x64-setup.exe" "$OUT/TokenBar-Windows-setup.exe"
cp "$nsis/TokenBar_${V}_x64-setup.exe.sig" "$OUT/TokenBar-Windows-setup.exe.sig"
sh scripts/windows-updater-manifest.sh "$V" "$OUT/TokenBar-Windows-setup.exe.sig" > "$OUT/latest.json"

say "Commit, tag e Release no GitHub"
git add -A
git commit -q -m "Versão $V"
git tag "v$V"
git push -q origin main "v$V"
gh release create "v$V" --title "TokenBar $V" --notes "$NOTES" \
  "$OUT/TokenBar-macOS.zip" "$OUT/TokenBar-Android.apk" "$OUT/TokenBar-WearOS.apk" \
  "$OUT/TokenBar-Windows-setup.exe" "$OUT/TokenBar-Windows-setup.exe.sig" "$OUT/latest.json"

printf '\n✓ TokenBar %s publicado. Mac, Windows e Android avisam a atualização em até 6 horas.\n' "$V"
