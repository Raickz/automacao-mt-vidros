# Auditorias do app "Digitalizar molde"

Rotina automática (segunda e quinta) que audita o app — precisão da medição, segurança, desempenho e
qualidade —, corrige o que for erro confirmado (sempre com teste) e registra tudo aqui, um arquivo por
execução (`AAAA-MM-DD.md`). Cada execução trabalha numa branch `auditoria/AAAA-MM-DD` e abre um PR para
`main`; o merge só acontece com o CI do PR verde e a suíte completa rodada localmente.

## Pendências abertas

Consolidado de todas as auditorias. Atualize ao abrir ou fechar um item.

| Desde | Gravidade | Item | Onde |
|---|---|---|---|
| 2026-11-26 | Baixa (precisão) | O contorno bruto (tela de resultado e "Baixar DXF" direto) sai ~1 mm maior por lado por causa dos degraus de pixel. O editor já usa as retas ajustadas. Falta decidir se o DXF direto passa a usá-las também. | `services/contour_extractor.dart`, `screens/mold_scan_kit_screen_web.dart` |
| 2026-11-26 | Informativo | O `image_picker` redimensiona e recomprime a foto no navegador antes da checagem de 64 MP do app. Trocar só com teste em navegador (orientação da calibração manual). | `screens/mold_scan_kit_screen_web.dart` |
| 2026-11-24 | Média | O pipeline roda na thread da interface: a tela congela ~1-3 s em celular fraco (já ficou 2-2,6x mais rápido no #5). Avaliar Web Worker (o pipeline é Dart puro). | `services/mold_scan_service_web.dart` |
| 2026-11-24 | Processo | Conferir no início de cada execução se já existe branch `auditoria/<data>` ou PR aberto, e partir dele (feito em 2026-11-26). | rotina agendada |
| 2026-11-24 | Informativo | osv.dev bloqueado pela rede da rotina; DXF ainda não aberto no software de CAM da loja; distorção da lente não corrigida (já citado no README do projeto). | — |

## Execuções

- [2026-11-24](2026-11-24.md) — primeira execução: CI em todo PR, SVG em UTF-8, "Meus moldes" à prova de
  registro corrompido, fotos 16 bits/cinza, limite de dimensões da foto, NaN nos campos numéricos.
  Segunda execução no mesmo dia: espessura digitada errada não encolhe mais o molde em silêncio; PNG/WebP
  animado e formatos que celular não produz recusados.
- [2026-11-26](2026-11-26.md) — editor não estica mais as retas ajustadas de volta aos degraus da foto
  (a peça saía 1-3 mm maior); histórico à prova de data inválida; orçamento não derruba o editor.
