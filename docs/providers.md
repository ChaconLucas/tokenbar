# Acrescentar outra IA ao TokenBar

O TokenBar mostra **qualquer IA** que tenha um arquivo JSON em `~/.tokenbar/providers/`
(no Windows: `%USERPROFILE%\.tokenbar\providers\`). Um arquivo por IA. Quem escreve o arquivo
pode ser um script seu, uma extensão, um cron — o TokenBar só lê.

```json
{
  "id": "gemini",
  "name": "Gemini CLI",
  "color": "#4285F4",
  "windows": [
    { "id": "day",   "label": "1d",  "usedPercent": 42, "resetsAt": 1792000000 },
    { "id": "month", "label": "30d", "usedPercent": 11, "resetsAt": 1794000000 }
  ]
}
```

| Campo | Obrigatório | O que é |
|---|---|---|
| `id` | sim | identificador curto, sem espaços (`claude` e `codex` são reservados) |
| `name` | não | nome mostrado (as teclas usam as 2 primeiras letras quando há 3+ IAs) |
| `color` | não | cor `#RRGGBB`; sem ela, o app escolhe uma fixa pela `id` |
| `windows` | sim | até 2 janelas de limite (a primeira é a "curta", a segunda a "longa") |
| `windows[].usedPercent` | sim | 0–100 (pode passar de 100) |
| `windows[].label` | não | texto curto: `5h`, `1d`, `7d`, `30d`… |
| `windows[].resetsAt` | não | quando a janela zera, em segundos desde 1970 (Unix) |
| `observedAt` | não | quando o número foi lido; sem ele, vale a data do arquivo |

A IA nova aparece no Mac, no Windows/Linux, no iPhone, no Apple Watch, no Android e no Wear OS,
nos widgets e na Central de Controle, já ligada. Para esconder, toque na tecla dela no aparelho.

**Dica:** escreva o arquivo de forma atômica (grave num `.tmp` e renomeie), para o TokenBar
nunca ler um JSON pela metade.
