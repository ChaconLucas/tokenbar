#!/bin/sh
# Empacota o servidor MCP (cli/mcp.mjs) como extensão do Claude Desktop (.mcpb):
#   sh mcpb/build.sh [pasta de saída]     → <pasta>/TokenBar.mcpb (padrão: build/)
# mcpb/server/ é gerado aqui a cada build (está no .gitignore).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${1:-$ROOT/build}"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
rm -rf "$ROOT/mcpb/server"
mkdir -p "$ROOT/mcpb/server"
cp "$ROOT/cli/mcp.mjs" "$ROOT/mcpb/server/mcp.mjs"
cp -R "$ROOT/cli/lib" "$ROOT/mcpb/server/lib"
cd "$ROOT"
npx --yes @anthropic-ai/mcpb validate mcpb/manifest.json >/dev/null
npx --yes @anthropic-ai/mcpb pack mcpb "$OUT/TokenBar.mcpb" >/dev/null
echo "$OUT/TokenBar.mcpb"
