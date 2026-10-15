#!/usr/bin/env bash
# latest.json do atualizador do TokenBar (Tauri v2, formato estático) para o Windows.
# Uso: scripts/windows-updater-manifest.sh <versão> <caminho/TokenBar_X_x64-setup.exe.sig> > latest.json
# O .exe vai para a release v<versão> com o nome TokenBar-Windows-setup.exe, e o latest.json junto.
set -euo pipefail
[ $# -eq 2 ] || { echo "uso: $0 <versão> <setup.exe.sig>" >&2; exit 1; }
version="${1#v}"; sig_file="$2"
[ -s "$sig_file" ] || { echo "assinatura não encontrada: $sig_file" >&2; exit 1; }
VERSION="$version" SIG="$(cat "$sig_file")" python3 -c '
import json, os, datetime
v = os.environ["VERSION"]
print(json.dumps({
  "version": v,
  "notes": f"TokenBar {v}",
  "pub_date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "platforms": {"windows-x86_64": {
    "signature": os.environ["SIG"].strip(),
    "url": f"https://github.com/ChaconLucas/tokenbar/releases/download/v{v}/TokenBar-Windows-setup.exe",
  }},
}, indent=2))'
