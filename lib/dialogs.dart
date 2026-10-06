import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'autolayout.dart';
import 'controller.dart';
import 'model.dart';
import 'scene.dart';

// Every form is a popup whose fields write straight into the document:
// clicking outside (or Esc) closes it and nothing is lost.

const _help = '''
• Entité, Note : choisir l'outil puis cliquer sur le canevas.
• Enums : panneau de droite, + pour en créer, clic pour modifier.
• Association : cliquer deux entités pour les relier (ou le vide pour une association seule).
• Lier : ajouter une patte à une association existante, ou entité + enum → attribut de ce type.
• Flèche : cliquer la source puis la cible.

• Double-clic sur un élément : ouvrir son formulaire.
• Clic sur un lien : cardinalité. Double-clic : note le long du lien.
• Clic droit sur un lien ou une flèche : ajouter un point de cassure, déplaçable.
  Clic droit sur le point : le retirer.
• Coin bas-droit d'une note : la redimensionner.

• Attributs : Entrée ajoute une ligne, Tab passe du nom au type,
  Retour arrière sur un nom vide supprime la ligne, a|b|c dans le type crée un enum.
• Réarranger (baguette) : replace les boîtes pour limiter les croisements ; Ctrl+Z pour revenir.
• Molette : zoom. Glisser le fond : déplacer la vue. Suppr : supprimer la sélection.''';

const _dense = InputDecoration();
const _gap = SizedBox(height: 12);

Future<void> showHelp(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const AlertDialog(title: Text('Aide'), content: Text(_help)),
);

Future<void> _popup(
  BuildContext context,
  Controller c,
  List<Widget> Function(BuildContext) body, {
  double width = 640,
}) => showDialog<void>(
  context: context,
  builder: (_) => Dialog(
    child: SizedBox(
      width: width,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ListenableBuilder(
          listenable: c,
          builder: (ctx, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: body(ctx),
          ),
        ),
      ),
    ),
  ),
);

/// Edit form of an entity, association, enum, note or arrow.
Future<void> showItemDialog(
  BuildContext context,
  Controller c,
  String id,
) async {
  final item = c.doc.item(id);
  if (item == null) return;
  Widget name(
    String label,
    String value,
    void Function(String) set,
    BuildContext ctx,
  ) => _Input(
    label: label,
    value: value,
    autofocus: true,
    onChanged: (v) => c.change(() => set(v), 'name:$id'),
    onEnter: () => FocusScope.of(ctx).nextFocus(),
  );
  await _popup(
    context,
    c,
    (ctx) => [
      ...switch (item) {
        Entity e => [
          name('Entité', e.name, (v) => e.name = v, ctx),
          _gap,
          AttributeTable(c, e.attributes),
        ],
        Association a => [
          name('Association', a.name, (v) => a.name = v, ctx),
          _gap,
          for (final l in a.legs)
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.doc.entities.firstWhere((e) => e.id == l.entityId).name,
                  ),
                ),
                _cards(c, l),
                Tooltip(
                  message: 'Identifiant relatif (entité faible)',
                  child: Checkbox(
                    value: l.relative,
                    onChanged: (v) => c.change(() => l.relative = v!),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Retirer la patte',
                  onPressed: () => c.change(() => a.legs.remove(l)),
                ),
              ],
            ),
          _gap,
          AttributeTable(c, a.attributes),
        ],
        EnumType t => [
          name('Enum', t.name, (v) => t.name = v, ctx),
          _gap,
          _Input(
            label: 'Valeurs (une par ligne)',
            value: t.values.join('\n'),
            lines: 10,
            onChanged: (v) => c.change(
              () => t.values = [
                for (final l in v.split('\n'))
                  if (l.trim().isNotEmpty) l.trim(),
              ],
              'values:$id',
            ),
          ),
        ],
        Note n => [
          _Input(
            label: 'Note',
            value: n.text,
            lines: 8,
            autofocus: true,
            onChanged: (v) => c.change(() => n.text = v, 'text:$id'),
          ),
        ],
        Arrow r => [
          _Input(
            label: 'Libellé de la flèche',
            value: r.label,
            autofocus: true,
            onChanged: (v) => c.change(() => r.label = v, 'text:$id'),
            onEnter: () => Navigator.pop(ctx),
          ),
        ],
      },
      _gap,
      Row(
        children: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              c.change(() {
                c.doc.remove(id);
                c.selected = null;
              });
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Supprimer'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fermer'),
          ),
        ],
      ),
    ],
  );
  // Rows left blank during keyboard entry are not attributes.
  final attrs = switch (item) {
    Entity e => e.attributes,
    Association a => a.attributes,
    _ => null,
  };
  if (attrs != null && attrs.any((a) => a.name.trim().isEmpty)) {
    c.change(() => attrs.removeWhere((a) => a.name.trim().isEmpty));
  }
}

/// Cardinality, relative identifier and note of one link. [link] is `leg:<association>:<index>`.
Future<void> showLegDialog(
  BuildContext context,
  Controller c,
  String link, {
  bool focusNote = false,
}) async {
  final found = c.leg(link);
  if (found == null) return;
  final (a, l) = found;
  final entity = c.doc.entities.firstWhere((e) => e.id == l.entityId).name;
  await _popup(
    context,
    c,
    width: 420,
    (ctx) => [
      Text('$entity — ${a.name}', style: Theme.of(ctx).textTheme.titleMedium),
      _gap,
      _cards(c, l),
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Identifiant relatif (entité faible)'),
        value: l.relative,
        onChanged: (v) => c.change(() => l.relative = v!),
      ),
      _Input(
        label: 'Note le long du lien',
        value: l.note,
        autofocus: focusNote,
        onChanged: (v) => c.change(() => l.note = v, 'note:$link'),
        onEnter: () => Navigator.pop(ctx),
      ),
    ],
  );
}

Widget _cards(Controller c, Leg l) => SegmentedButton<String>(
  showSelectedIcon: false,
  segments: [for (final x in cards) ButtonSegment(value: x, label: Text(x))],
  selected: {l.card},
  onSelectionChanged: (s) => c.change(() => l.card = s.first),
);

/// Text field that starts with its content selected, so typing replaces it.
class _Input extends StatefulWidget {
  final String label, value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onEnter;
  final bool autofocus;
  final int lines;
  const _Input({
    required this.label,
    required this.value,
    required this.onChanged,
    this.onEnter,
    this.autofocus = false,
    this.lines = 1,
  });

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  late final _ctl = TextEditingController(text: widget.value)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.lines == 1 ? widget.value.length : 0,
    );

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _ctl,
    autofocus: widget.autofocus,
    maxLines: widget.lines,
    decoration: _dense.copyWith(labelText: widget.label),
    onChanged: widget.onChanged,
    onSubmitted: (_) => widget.onEnter?.call(),
  );
}

/// Keeps mouse-only controls out of the Tab order, so Tab goes name → type → next row.
Widget _noTab(Widget child) => Focus(
  canRequestFocus: false,
  skipTraversal: true,
  descendantsAreTraversable: false,
  child: child,
);

/// Keyboard-first attribute editor: Enter adds a row, Backspace on an empty name removes it, drag to reorder.
class AttributeTable extends StatefulWidget {
  final Controller c;
  final List<Attribute> attrs;
  const AttributeTable(this.c, this.attrs, {super.key});

  @override
  State<AttributeTable> createState() => _AttributeTableState();
}

class _AttributeTableState extends State<AttributeTable> {
  final _nameFocus = <Attribute, FocusNode>{};

  Controller get c => widget.c;
  List<Attribute> get attrs => widget.attrs;
  FocusNode _node(Attribute a) => _nameFocus.putIfAbsent(a, FocusNode.new);

  void _focusLater(Attribute a) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _node(a).requestFocus();
      });

  void _insertAfter(int i) {
    final a = Attribute(name: '');
    c.change(() => attrs.insert(i + 1, a));
    _focusLater(a);
  }

  void _remove(Attribute a) {
    final i = attrs.indexOf(a);
    c.change(() => attrs.remove(a));
    if (attrs.isNotEmpty) _focusLater(attrs[i == 0 ? 0 : i - 1]);
  }

  @override
  void dispose() {
    for (final n in _nameFocus.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget head(String t, double w) => SizedBox(
      width: w,
      child: Center(
        child: Text(t, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 28),
            Expanded(
              flex: 3,
              child: Text(
                'Attribut',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: Text(
                'Type',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            head('ID', 40),
            head('Null', 40),
            head('Unique', 52),
            const SizedBox(width: 32),
          ],
        ),
        const SizedBox(height: 4),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) =>
              c.change(() => attrs.insert(to, attrs.removeAt(from))),
          children: [
            for (final (i, a) in attrs.indexed)
              _AttrRow(
                key: ObjectKey(a),
                c: c,
                a: a,
                index: i,
                nameFocus: _node(a),
                onEnter: () => _insertAfter(i),
                onRemove: () => _remove(a),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _insertAfter(attrs.length - 1),
            icon: const Icon(Icons.add),
            label: const Text('Attribut'),
          ),
        ),
      ],
    );
  }
}

class _AttrRow extends StatefulWidget {
  final Controller c;
  final Attribute a;
  final int index;
  final FocusNode nameFocus;
  final VoidCallback onEnter, onRemove;
  const _AttrRow({
    super.key,
    required this.c,
    required this.a,
    required this.index,
    required this.nameFocus,
    required this.onEnter,
    required this.onRemove,
  });

  @override
  State<_AttrRow> createState() => _AttrRowState();
}

class _AttrRowState extends State<_AttrRow> {
  late final _name = TextEditingController(text: widget.a.name);
  late final _type = TextEditingController(
    text: widget.c.doc.typeName(widget.a.type),
  );
  final _typeFocus = FocusNode();

  Controller get c => widget.c;
  Attribute get a => widget.a;

  @override
  void initState() {
    super.initState();
    _typeFocus.addListener(_onTypeFocus);
  }

  @override
  void dispose() {
    _typeFocus
      ..removeListener(_onTypeFocus)
      ..dispose();
    _name.dispose();
    _type.dispose();
    super.dispose();
  }

  void _onTypeFocus() {
    if (!_typeFocus.hasFocus) _commitType();
  }

  /// Stores the typed type, resolving an enum name or an `a|b|c` shortcut, and shows the result.
  void _commitType() {
    final t = _type.text.trim();
    if (c.doc.typeName(a.type) != t) {
      c.change(() => a.type = t.isEmpty ? 'string' : t);
    }
    c.normalizeType(a);
    final shown = c.doc.typeName(a.type);
    if (_type.text != shown) _type.text = shown;
  }

  Widget _check(double width, bool value, void Function(bool) set) => SizedBox(
    width: width,
    child: _noTab(
      Checkbox(value: value, onChanged: (v) => c.change(() => set(v!))),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: const MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox(
                width: 28,
                child: Icon(Icons.drag_indicator, size: 18, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (_, e) {
                if (e is KeyDownEvent &&
                    e.logicalKey == LogicalKeyboardKey.backspace &&
                    _name.text.isEmpty) {
                  widget.onRemove();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _name,
                focusNode: widget.nameFocus,
                decoration: _dense.copyWith(hintText: 'nom'),
                onChanged: (v) =>
                    c.change(() => a.name = v, 'name:${identityHashCode(a)}'),
                onSubmitted: (_) => widget.onEnter(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: RawAutocomplete<String>(
              textEditingController: _type,
              focusNode: _typeFocus,
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                return [
                  ...primitiveTypes,
                  for (final e in c.doc.enums) e.name,
                ].where((o) => o.toLowerCase().startsWith(q));
              },
              onSelected: (_) => _commitType(),
              fieldViewBuilder: (_, ctl, focus, onFieldSubmitted) => TextField(
                controller: ctl,
                focusNode: focus,
                decoration: _dense.copyWith(hintText: 'type ou a|b|c'),
                onSubmitted: (_) {
                  onFieldSubmitted(); // takes the highlighted suggestion, if any
                  _commitType();
                  widget.onEnter();
                },
              ),
              optionsViewBuilder: (ctx, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 220,
                      maxWidth: 200,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final (i, o) in options.indexed)
                          InkWell(
                            onTap: () => onSelected(o),
                            child: Container(
                              color: AutocompleteHighlightedOption.of(ctx) == i
                                  ? Theme.of(ctx).focusColor
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Text(o),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _check(40, a.isId, (v) => a.isId = v),
          _check(40, a.nullable, (v) => a.nullable = v),
          _check(52, a.unique, (v) => a.unique = v),
          SizedBox(
            width: 32,
            child: _noTab(
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Supprimer l\'attribut',
                padding: EdgeInsets.zero,
                onPressed: widget.onRemove,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rearranges the diagram to minimise link crossings. The search runs in an
/// isolate so the window stays responsive; cancelling changes nothing.
Future<void> showRearrangeDialog(BuildContext context, Controller c) async {
  // Box sizes come from the Merise scene, where every association has a box.
  final boxes = <LBox>[
    for (final (id, r) in buildScene(c.doc).hits)
      if (c.doc.layout.containsKey(id))
        (id: id, x: r.left, y: r.top, w: r.width, h: r.height),
  ];
  final edges = [
    for (final a in c.doc.associations)
      for (final l in a.legs) (a.id, l.entityId),
    for (final r in c.doc.arrows) (r.from, r.to),
  ];
  if (boxes.length < 2) return;
  final messenger = ScaffoldMessenger.of(context);
  final result = await showDialog<LayoutResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RearrangeDialog(boxes, edges),
  );
  if (result == null) return;
  if (result.improved) c.applyLayout(result.pos);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        result.improved
            ? 'Schéma réarrangé — croisements : ${result.before} → ${result.after}. Ctrl+Z pour revenir.'
            : 'Aucun meilleur placement trouvé (croisements : ${result.before}).',
      ),
    ),
  );
}

class _RearrangeDialog extends StatefulWidget {
  final List<LBox> boxes;
  final List<(String, String)> edges;
  const _RearrangeDialog(this.boxes, this.edges);

  @override
  State<_RearrangeDialog> createState() => _RearrangeDialogState();
}

class _RearrangeDialogState extends State<_RearrangeDialog> {
  final _port = ReceivePort();
  Isolate? _isolate;
  double _progress = 0;
  int? _from, _best;
  String? _error;

  @override
  void initState() {
    super.initState();
    _port.listen((message) {
      if (!mounted) return;
      switch (message) {
        case (final double p, final int crossings):
          setState(() {
            _progress = p;
            _from ??= crossings;
            _best = crossings;
          });
        case final LayoutResult result:
          Navigator.pop(context, result);
        default: // [error, stack] from the isolate's error port
          setState(() => _error = '$message');
      }
    });
    Isolate.spawn(layoutIsolate, (
      _port.sendPort,
      widget.boxes,
      widget.edges,
    ), onError: _port.sendPort).then((isolate) {
      if (mounted) {
        _isolate = isolate;
      } else {
        isolate.kill(priority: Isolate.immediate);
      }
    });
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _port.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Réarrangement du schéma'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _error == null ? _progress : 0),
          _gap,
          Text(
            _error ??
                (_best == null
                    ? 'Recherche du meilleur placement…'
                    : 'Croisements : $_from → $_best   (${(_progress * 100).round()} %)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_error == null ? 'Annuler' : 'Fermer'),
      ),
    ],
  );
}
