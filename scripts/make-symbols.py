# Gera símbolos próprios (formato SF Symbols) do anel de 12 pontos: tb.ring.0 … tb.ring.12.
# Uso: python3 scripts/make-symbols.py Widget/Assets.xcassets
import math, os, sys, json
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
json.dump({"info": {"version": 1, "author": "xcode"}}, open(f"{out}/Contents.json", "w"))

def circle(cx, cy, r, ccw=False):
    # Dois arcos; sentido anti-horário cria furo (regra nonzero).
    s = 0 if ccw else 1
    return f"M{cx - r:.2f} {cy:.2f}A{r} {r} 0 1 {s} {cx + r:.2f} {cy:.2f}A{r} {r} 0 1 {s} {cx - r:.2f} {cy:.2f}Z"

W = 92          # largura do símbolo (unidades do template)
C = (W / 2, -35.2)   # centro alinhado à metade da altura de maiúscula
R, DOT, RING, HOLE = 36, 9.0, 8.0, 4.4

def paths(lit):
    d = []
    for i in range(12):
        a = i / 12 * 2 * math.pi - math.pi / 2
        x, y = C[0] + R * math.cos(a), C[1] + R * math.sin(a)
        if i < lit:
            d.append(circle(x, y, DOT))
        else:
            d.append(circle(x, y, RING) + circle(x, y, HOLE, ccw=True))
    return "".join(d)

for lit in range(13):
    left = 1391.3
    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">
 <g id="Notes">
  <text id="template-version" x="0" y="0">Template v.3.0</text>
 </g>
 <g id="Guides">
  <line id="Baseline-S" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
  <line id="left-margin-Regular-M" x1="{left}" x2="{left}" y1="1030.79" y2="1150.12"/>
  <line id="right-margin-Regular-M" x1="{left + W}" x2="{left + W}" y1="1030.79" y2="1150.12"/>
 </g>
 <g id="Symbols">
  <g id="Regular-M" transform="matrix(1 0 0 1 {left} 1126)">
   <path d="{paths(lit)}"/>
  </g>
 </g>
</svg>
'''
    d = f"{out}/tb.ring.{lit}.symbolset"
    os.makedirs(d, exist_ok=True)
    open(f"{d}/tb.ring.{lit}.svg", "w").write(svg)
    json.dump({"info": {"version": 1, "author": "xcode"},
               "symbols": [{"idiom": "universal", "filename": f"tb.ring.{lit}.svg"}]}, open(f"{d}/Contents.json", "w"))
print("ok")
