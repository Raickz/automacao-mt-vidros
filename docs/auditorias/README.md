# Auditorias do app "Digitalizar molde"

Rotina automática (segunda e quinta) que audita o app — precisão da medição, segurança, desempenho e
qualidade —, corrige o que for erro confirmado (sempre com teste) e registra tudo aqui, um arquivo por
execução (`AAAA-MM-DD.md`). Cada execução trabalha numa branch `auditoria/AAAA-MM-DD` e abre um PR para
`main`; o merge só acontece com o CI do PR verde e a suíte completa rodada localmente.

## Pendências abertas

Consolidado de todas as auditorias. Atualize ao abrir ou fechar um item.

| Desde | Gravidade | Item | Onde |
|---|---|---|---|
| 2026-11-24 | Média | O pipeline roda na thread da interface: com a foto de 3200 px a tela congela ~1-3 s em celulares fracos. Avaliar Web Worker (o pipeline é Dart puro). | `services/mold_scan_service_web.dart` |
| 2026-11-24 | Baixa | Sem Content-Security-Policy (o GitHub Pages não deixa mandar cabeçalhos; seria por `<meta>`). Precisa de teste no navegador antes: o Flutter usa WebAssembly, `blob:` nos downloads e estilos inline. | `web/index.html` |
| 2026-11-24 | Baixa | Dependências desatualizadas (`image` 4.10.1 → 4.13.1, `web` 1.1.1 → 1.1.2, `image_picker` 1.2.3 → 1.2.4). Não foi possível consultar osv.dev (bloqueado pela rede da rotina). | `pubspec.yaml` |
| 2026-11-24 | Baixa | Quando faltar um glifo (emoji no nome do projeto), o PDF busca fonte de reserva em `fonts.gstatic.com`. Só acontece nesse caso; o resto do site não chama terceiros. | `cut_report_pdf_builder.dart` |
| 2026-11-24 | Processo | Duas execuções da rotina rodaram em paralelo no mesmo dia e duplicaram o trabalho. Cada execução deve conferir no início se já há branch `auditoria/<data>` ou PR aberto e partir dele. | rotina agendada |
| 2026-11-24 | Informativo | DXF ainda não aberto no software de CAM da loja; distorção da lente não corrigida (já citado no README do projeto). | — |

## Execuções

- [2026-11-24](2026-11-24.md) — primeira execução: CI em todo PR, SVG em UTF-8, "Meus moldes" à prova de
  registro corrompido, fotos 16 bits/cinza, limite de dimensões da foto, NaN nos campos numéricos.
  Segunda execução no mesmo dia: espessura digitada errada não encolhe mais o molde em silêncio; PNG/WebP
  animado e formatos que celular não produz recusados.
