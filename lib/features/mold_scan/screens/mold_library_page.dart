import 'package:flutter/material.dart';

import '../services/mold_catalog.dart';
import '../services/mold_outline.dart';
import '../services/mold_store.dart';
import '../theme/mold_scan_colors.dart';
import '../theme/mold_scan_theme.dart';
import '../widgets/mold_editor.dart';

enum _Filter { todos, altos, largos, redondos, favoritos, meus }

const _filterLabels = {
  _Filter.todos: 'Todos',
  _Filter.altos: 'Altos',
  _Filter.largos: 'Largos',
  _Filter.redondos: 'Redondos',
  _Filter.favoritos: 'Favoritos',
  _Filter.meus: 'Meus',
};

/// One entry of the grid: a catalog shape or a saved one.
class _Item {
  final String key; // catalog code or saved id
  final String code;
  final String name;
  final bool saved;
  final MoldOutline Function() outline;
  final bool tall, wide, round;

  _Item({
    required this.key,
    required this.code,
    required this.name,
    required this.saved,
    required this.outline,
    required this.tall,
    required this.wide,
    required this.round,
  });
}

/// Library of ready-made and saved molds. Opening one lets the worker type
/// the real width and height, flip/rotate it, pick spline or straight
/// segments, add a cut margin, and download DXF or SVG at that exact size.
class MoldLibraryPage extends StatefulWidget {
  /// Outline of the last scan, offered as "Salvar o molde digitalizado".
  final MoldOutline? scanned;

  const MoldLibraryPage({super.key, this.scanned});

  @override
  State<MoldLibraryPage> createState() => _MoldLibraryPageState();
}

class _MoldLibraryPageState extends State<MoldLibraryPage> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.todos;
  final Set<String> _favs = MoldStore.favorites();
  List<SavedMold> _saved = MoldStore.load();
  _Item? _open;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_Item> get _items {
    final items = <_Item>[
      for (final s in _saved)
        _Item(
          key: s.id,
          code: 'MEU',
          name: s.name,
          saved: true,
          outline: () => s.outline,
          tall: s.outline.height / s.outline.width >= 1.3,
          wide: s.outline.width / s.outline.height >= 1.3,
          round: false,
        ),
      for (final c in MoldCatalog.all)
        _Item(
          key: c.code,
          code: c.code,
          name: c.name,
          saved: false,
          outline: c.outline,
          tall: c.tall,
          wide: c.wide,
          round: c.round,
        ),
    ];
    final q = _search.text.trim().toLowerCase();
    return items.where((i) {
      if (q.isNotEmpty && !('${i.code} ${i.name}'.toLowerCase().contains(q))) {
        return false;
      }
      return switch (_filter) {
        _Filter.todos => true,
        _Filter.altos => i.tall,
        _Filter.largos => i.wide,
        _Filter.redondos => i.round,
        _Filter.favoritos => _favs.contains(i.key),
        _Filter.meus => i.saved,
      };
    }).toList();
  }

  void _toggleFav(String key) {
    setState(() => _favs.contains(key) ? _favs.remove(key) : _favs.add(key));
    MoldStore.setFavorites(_favs);
  }

  /// Opens [item] in the editor (null = back to the grid), from the top.
  void _show(_Item? item) {
    setState(() => _open = item);
    _scrollToTop(context);
  }

  void _refreshSaved() => setState(() => _saved = MoldStore.load());

  @override
  Widget build(BuildContext context) {
    final open = _open;
    if (open != null) {
      return MoldEditor(
        key: ValueKey(open.key),
        original: open.outline,
        initialName: open.saved ? open.name : '${open.code} ${open.name}',
        backLabel: 'Biblioteca',
        onBack: () => _show(null),
        onSaved: _refreshSaved,
        onDelete: open.saved
            ? () {
                MoldStore.remove(open.key);
                _refreshSaved();
                _show(null);
              }
            : null,
      );
    }
    final items = _items;
    final scanned = widget.scanned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Biblioteca de moldes', style: MoldScanType.headline(34)),
        const SizedBox(height: 8),
        const Text(
          'Escolha uma forma pronta, digite a largura e a altura que o cliente pediu e baixe o DXF no tamanho exato.',
          style: TextStyle(
            color: MoldScanColors.textSecondary,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        if (scanned != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: OutlinedButton.icon(
              onPressed: () {
                final ok = MoldStore.add('Molde digitalizado', scanned);
                _refreshSaved();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Salvo em "Meus".'
                          : 'O navegador não deixou salvar (janela privada?).',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Salvar o molde digitalizado em "Meus"'),
            ),
          ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Buscar por código ou nome',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _Filter.values)
              ChoiceChip(
                label: Text(_filterLabels[f]!),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Nenhum molde encontrado.',
              style: TextStyle(color: MoldScanColors.textSecondary),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 190).floor().clamp(2, 6);
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
                children: [
                  for (final i in items)
                    _Card(
                      item: i,
                      fav: _favs.contains(i.key),
                      onFav: () => _toggleFav(i.key),
                      onTap: () => _show(i),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final _Item item;
  final bool fav;
  final VoidCallback onFav, onTap;

  const _Card({
    required this.item,
    required this.fav,
    required this.onFav,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: MoldScanColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: MoldScanColors.border),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  item.code,
                  style: const TextStyle(
                    color: MoldScanColors.accentAlt,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: fav ? 'Tirar dos favoritos' : 'Favoritar',
                  onPressed: onFav,
                  icon: Icon(
                    fav ? Icons.star : Icons.star_border,
                    size: 20,
                    color: fav
                        ? MoldScanColors.warning
                        : MoldScanColors.textSecondary,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _Thumb(outline: item.outline()),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final MoldOutline outline;
  const _Thumb({required this.outline});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: OutlinePainter(outline), size: Size.infinite);
}

/// The page lives inside the main screen's ListView: switching views
/// should start at the top, not where the grid was scrolled to.
void _scrollToTop(BuildContext context) {
  final pos = Scrollable.maybeOf(context)?.position;
  if (pos != null && pos.hasPixels) pos.jumpTo(0);
}
