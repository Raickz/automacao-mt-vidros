# MT Vidros — Digitalizar molde

App da Marabá Temper. O vendedor coloca o molde do cliente (papelão, MDF, formato irregular) sobre o
quadro de referência, tira uma foto, e o app mede o contorno e gera um arquivo **DXF** (em milímetros)
para a mesa de corte CNC.

Roda como site (GitHub Pages, upload de foto) e como app Android (câmera ao vivo).

## Como usar

1. **Marcadores.** Gere o PDF dos 4 marcadores no app ("Baixar marcadores em PDF"). Imprima em A4, a
   **100%**, recorte na **linha tracejada** e cole um em cada canto do quadro, com a **borda do papel a
   50 mm das bordas** do quadro. Cada folha diz de que canto é.
2. **Quadro.** Informe a largura e a altura reais do quadro, em cm. O quadro da loja é 250 × 150 cm.
   Qualquer tamanho serve (lados de 60 cm ou mais, área até 8 m²).
3. **Foto.** Molde sobre o quadro, 2 a 3 m de distância, de frente, com os 4 marcadores inteiros na foto.
   Use a foto original da câmera, não a enviada por WhatsApp. O molde deve ficar a pelo menos 5 cm das
   bordas do quadro e fora dos 4 cantos.
4. **Resultado.** Confira a linha rosa na prévia (ela deve acompanhar a borda externa do molde) e as
   medidas. Baixe o DXF. Material, espessura e instruções de corte vão como comentários dentro do DXF e no
   nome do arquivo.

Antes de confiar em peças grandes, meça uma peça conhecida (por exemplo 50 × 30 cm) e compare com a trena.

## Desenvolvimento

```
flutter pub get
flutter analyze
flutter test        # inclui testes de ponta a ponta com fotos sintéticas (~2,5 min)
```

Um push em `main` roda os testes e publica o site (workflow `Deploy Web`) e gera o APK de debug
(workflow `Build APK`). A versão do Flutter é fixada nos dois workflows.

Código em `lib/features/mold_scan/`:

- `services/mold_scan_pipeline.dart` — foto → contorno: acha os 4 marcadores QR, corrige a perspectiva,
  mede o contorno do molde.
- `services/background_model.dart`, `mask_ops.dart`, `contour_extractor.dart` — cor do fundo, limpeza da
  máscara e traçado do contorno.
- `services/dxf_writer.dart` — escreve o DXF (um `LINE` por segmento, eixo Y já invertido).
- `services/mold_board_pdf_builder.dart` — PDF dos marcadores.
- `screens/`, `widgets/`, `theme/` — telas (web e Android) e visual.

## Não verificado

O DXF foi lido com a biblioteca `ezdxf`, mas ainda não foi aberto no software de CAM da loja. A distorção
da lente do celular não é corrigida.
