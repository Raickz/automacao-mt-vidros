# MT Vidros — Digitalizar molde

App da Marabá Temper. O vendedor coloca o molde do cliente (papelão, MDF, formato irregular) sobre o
quadro de referência, tira uma foto, e o app mede o contorno e gera um arquivo **DXF** (em milímetros)
para a mesa de corte CNC.

Roda como site (GitHub Pages, upload de foto), instalável na tela inicial como PWA: no iPhone, Safari →
Compartilhar → "Adicionar à Tela de Início"; no Android, menu do Chrome → "Instalar app". O código do app
Android (câmera ao vivo) continua no repositório, mas não é mais mantido; o workflow do APK é só manual.

## Como usar

1. **Marcadores.** Gere o PDF dos 4 marcadores no app ("Baixar marcadores em PDF"). Imprima em A4, a
   **100%**, recorte na **linha tracejada** e cole um em cada canto do quadro, com a **borda do papel a
   50 mm das bordas** do quadro. Cada folha diz de que canto é.
2. **Escala (essencial para precisão).** Cole as folhas **lisas e bem coladas** (folha ondulada engana).
   Meça com a trena, uma vez, a distância **de fora a fora dos quadrados pretos** — da borda de fora de um
   quadrado preto até a borda de fora do outro, não da folha: os dois de cima para a horizontal, os dois da
   esquerda para a vertical — e digite em "Escala". Fica salvo no aparelho. A distância digitada sempre vale
   (o app só avisa se os QR discordarem mais de 3%, e só a ignora acima de 8%, quando foi medida de outro
   jeito). Sem ela, a escala sai do tamanho dos QR na foto: num teste real com folhas onduladas isso errou
   3,7% na horizontal (72,4 cm para um papelão de 70 cm); com a trena deu 69,8 cm. Confira também se a
   impressão saiu a 100%: o quadrado preto deve medir 18,0 cm.
3. **Foto.** O molde precisa estar **inteiro no mesmo plano dos QR**: deitado no chão com os 4 QR colados no
   chão em volta, ou encostado inteiro num quadro que tem os QR. Molde apoiado na parede com o pé afastado (ou
   sobre calço) não está no plano: a parte de baixo fica mais perto da câmera e sai maior (num teste real, 45 cm
   no topo viraram 48 cm embaixo). O app avisa quando o contorno alarga para um lado. Molde sobre o quadro, 2 a 3 m de distância, de frente, com os 4 marcadores inteiros na foto.
   Use a foto original da câmera, não a enviada por WhatsApp. O molde deve ficar a pelo menos 5 cm das
   bordas do quadro e fora dos 4 cantos.
4. **Resultado.** Confira a linha rosa na prévia (ela deve acompanhar a borda externa do molde) e as
   medidas. Informe a **espessura do molde**: o topo de um molde grosso fica mais perto da câmera que o
   quadro e aparece maior (uma porta de 35 mm a 2,6 m aparece 2 cm maior). O app desconta isso. Baixe o DXF.
   Material, espessura e instruções de corte vão como comentários dentro do DXF e no nome do arquivo.

Se o app não achar os 4 marcadores, use **"Marcar os 4 marcadores à mão"**: arraste os pontos 1 a 4 para o
centro dos quadrados pretos (há uma lupa) e digite a distância entre os marcadores em "Escala". Na tela de
resultado, **Antes/Depois** alterna entre a foto original e a vista de cima com o contorno.

## Editor do molde

Abre por **"Ajustar medida, margem, PDF e orçamento"** (molde digitalizado) ou por um molde da **Biblioteca**:

- **Medida final**: largura e altura em mm, com proporção travada ou livre; girar 90°, espelhar, restaurar.
- **Curva e margem**: polilinha ou spline; para molde digitalizado, suavizar (tira os degraus da foto) e
  simplificar (menos segmentos, até 0,3 mm de desvio); margem de corte positiva ou negativa.
- **Medir** (dois toques no desenho) e **grade de 10 cm**.
- **Orçamento rápido**: vidro por m² do retângulo (largura × altura) + borda por metro de linha de corte, ×
  quantidade. Os preços ficam salvos no aparelho.
- **Exportar**: DXF 1:1, SVG, relatório de corte em PDF (desenho cotado, dados técnicos, orçamento) e
  etiqueta 100 × 60 mm com QR (código do serviço, nome, medida, material).

## Biblioteca

41 formas prontas geradas pelo app (código MT-001 em diante: círculos, ovais, pílulas, arcos, trapézios,
polígonos, coração, gota, escudo, orgânicos), com busca, filtros (altos, largos, redondos), favoritos e
**Meus** (moldes salvos). Favoritos, "Meus" e preços ficam no navegador deste aparelho: em outro aparelho ou
em janela privada começam vazios.

Antes de confiar em peças grandes, meça uma peça conhecida (por exemplo 50 × 30 cm) e compare com a trena.

## Desenvolvimento

```
flutter pub get
flutter analyze
flutter test        # inclui testes de ponta a ponta e de precisão com fotos sintéticas (~5 min)
```

Um push em `main` roda os testes e publica o site (workflow `Deploy Web`) 
(o APK de debug só é gerado manualmente, workflow `Build APK`). A versão do Flutter é fixada nos dois workflows.

Código em `lib/features/mold_scan/`:

- `services/mold_scan_pipeline.dart` — foto → contorno: acha os 4 marcadores QR, corrige a perspectiva,
  mede o contorno do molde.
- `services/marker_scale.dart` — mede a escala pelos QR (centros dos padrões e bordas do quadrado preto).
- `services/camera_pose.dart` — estima onde a câmera estava e desconta a espessura do molde.
- `services/background_model.dart`, `mask_ops.dart`, `contour_extractor.dart` — cor do fundo, limpeza da
  máscara e traçado do contorno.
- `services/dxf_writer.dart` — escreve o DXF (um `LINE` por segmento, eixo Y já invertido).
- `services/mold_board_pdf_builder.dart` — PDF dos marcadores.
- `services/mold_outline.dart` — operações no contorno (redimensionar, girar, espelhar, spline, margem).
- `services/mold_catalog.dart`, `mold_store.dart` — formas da biblioteca e moldes salvos (localStorage).
- `services/cut_report_pdf_builder.dart`, `quote.dart`, `svg_writer.dart` — relatório, etiqueta, orçamento, SVG.
- `widgets/mold_editor.dart`, `widgets/corner_picker.dart` — editor do molde e calibração manual.
- `screens/`, `widgets/`, `theme/` — telas (web e Android) e visual.

## Não verificado

O DXF foi lido com a biblioteca `ezdxf`, mas ainda não foi aberto no software de CAM da loja. A distorção
da lente do celular não é corrigida, e a distância da câmera (para descontar a espessura) assume a lente
principal do celular: com lente ultra-wide ou zoom o desconto sai menos exato.
