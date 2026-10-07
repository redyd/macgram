import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'canvas.dart';
import 'controller.dart';
import 'dialogs.dart';
import 'mld.dart';
import 'scene.dart';
import 'theme.dart';

void main(List<String> args) {
  final c = Controller();
  if (args.isNotEmpty) {
    try {
      c.load(File(args.first).absolute.path);
    } catch (e) {
      stderr.writeln('macgram: ${args.first}: $e');
    }
  }
  runApp(App(c));
}

class App extends StatelessWidget {
  final Controller c;
  const App(this.c, {super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: themeMode,
    builder: (_, mode, _) => MaterialApp(
      title: 'macgram',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      themeMode: mode,
      home: Home(c),
    ),
  );
}

class Home extends StatefulWidget {
  final Controller c;
  const Home(this.c, {super.key});

  @override
  State<Home> createState() => _HomeState();
}

const _json = XTypeGroup(label: 'MCD (.mcd.json)', extensions: ['json']);

const _tools = [
  (Tool.select, Icons.near_me_outlined, 'Sélection'),
  (Tool.entity, Icons.crop_square, 'Entité'),
  (Tool.association, Icons.circle_outlined, 'Association'),
  (Tool.note, Icons.sticky_note_2_outlined, 'Note'),
  (Tool.link, Icons.linear_scale, 'Lier'),
  (Tool.arrow, Icons.north_east, 'Flèche'),
];

class _HomeState extends State<Home> {
  late final AppLifecycleListener _lifecycle;
  Controller get c => widget.c;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async => await _discardOk('Enregistrer et quitter')
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  /// Asks what to do with unsaved changes; true means it is safe to go on.
  /// Saving only counts if it really happened (the file dialog can be cancelled).
  Future<bool> _discardOk([String saveLabel = 'Enregistrer']) async {
    if (!c.dirty) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifications non enregistrées'),
        content: const Text('Que faire des modifications en cours ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Abandonner'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(saveLabel),
          ),
        ],
      ),
    );
    if (choice != 'save') return choice == 'discard';
    await _save();
    return !c.dirty;
  }

  /// Right-hand panel listing the enums, which are not drawn on the canvas.
  Widget _enumPanel() {
    final theme = Theme.of(context);
    final pal = theme.brightness == Brightness.dark
        ? Palette.dark
        : Palette.light;
    final enums = [...c.doc.enums]..sort((a, b) => a.name.compareTo(b.name));
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Enums', style: theme.textTheme.titleSmall),
                ),
                _btn(
                  Icons.add,
                  'Nouvel enum',
                  () => showItemDialog(context, c, c.addEnum()),
                ),
              ],
            ),
          ),
          if (enums.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Aucun enum.\nCréez-en un ici, ou tapez\na|b|c comme type d\'attribut.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                for (final e in enums)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    // The ink is drawn on this Material, so hovering shows.
                    child: Material(
                      color: Color(pal.enumType),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: BorderSide(
                          color: c.selected == e.id
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outline,
                          width: c.selected == e.id ? 1.5 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          c.select(e.id);
                          showItemDialog(context, c, e.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                              fontFamily: monoFont,
                              fontSize: fontSize,
                              color: Color(pal.ink),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                for (final v in e.values) Text(v),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _new() async {
    if (await _discardOk()) c.newDocument();
  }

  Future<void> _open() => _guard(() async {
    if (!await _discardOk()) return;
    final f = await openFile(acceptedTypeGroups: const [_json]);
    if (f != null) c.load(f.path);
  });

  Future<void> _save() => _guard(() async {
    if (c.path != null) return c.save();
    final loc = await getSaveLocation(
      suggestedName: 'modele.mcd.json',
      acceptedTypeGroups: const [_json],
    );
    if (loc != null) c.save(loc.path);
  });

  Future<void> _export(String ext) => _guard(() async {
    // Exports look like the screen: current theme, plus the enums as a legend.
    final scene = buildScene(
      c.doc,
      uml: c.uml,
      handles: false,
      legend: true,
      pal: Theme.of(context).brightness == Brightness.dark
          ? Palette.dark
          : Palette.light,
    );
    final loc = await getSaveLocation(suggestedName: 'diagramme.$ext');
    if (loc == null) return;
    if (ext == 'svg') {
      File(loc.path).writeAsStringSync(toSvg(scene));
    } else {
      File(loc.path).writeAsBytesSync(await toPng(scene));
    }
  });

  Widget _btn(IconData icon, String tooltip, VoidCallback? onTap) =>
      IconButton(icon: Icon(icon), tooltip: tooltip, onPressed: onTap);

  /// Flat toolbar toggle: tinted when on.
  Widget _toggle(String label, bool on, VoidCallback onTap, [IconData? icon]) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: on ? accent : null,
          backgroundColor: on ? accent.withValues(alpha: 0.18) : null,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 6),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    const sep = SizedBox(height: 24, child: VerticalDivider(width: 20));
    final hint = switch (c.tool) {
      Tool.select => '',
      Tool.link || Tool.arrow =>
        c.pending == null
            ? 'Cliquer le premier élément'
            : 'Cliquer le second élément',
      Tool.association =>
        c.pending == null
            ? 'Cliquer une entité (ou le vide)'
            : 'Cliquer la seconde entité',
      _ => 'Cliquer sur le canevas pour placer',
    };
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        width: double.infinity,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _btn(Icons.note_add_outlined, 'Nouveau', _new),
              _btn(Icons.folder_open, 'Ouvrir (Ctrl+O)', _open),
              _btn(Icons.save_outlined, 'Enregistrer (Ctrl+S)', _save),
              _btn(Icons.undo, 'Annuler (Ctrl+Z)', c.canUndo ? c.undo : null),
              _btn(Icons.redo, 'Rétablir (Ctrl+Y)', c.canRedo ? c.redo : null),
              sep,
              for (final (tool, icon, label) in _tools)
                _toggle(label, c.tool == tool, () => c.setTool(tool), icon),
              sep,
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Merise')),
                  ButtonSegment(value: true, label: Text('UML')),
                ],
                selected: {c.uml},
                onSelectionChanged: (_) => c.toggleUml(),
              ),
              const SizedBox(width: 8),
              _toggle('MLD', c.showMld, c.toggleMld),
              _btn(
                Icons.account_tree_outlined,
                'Réarranger (moins de croisements)',
                () => showRearrangeDialog(context, c),
              ),
              PopupMenuButton<String>(
                tooltip: 'Exporter',
                icon: const Icon(Icons.file_download_outlined),
                onSelected: _export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'png', child: Text('Exporter en PNG')),
                  PopupMenuItem(value: 'svg', child: Text('Exporter en SVG')),
                ],
              ),
              _btn(
                dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                dark ? 'Thème clair' : 'Thème sombre',
                () => themeMode.value = dark ? ThemeMode.light : ThemeMode.dark,
              ),
              _btn(Icons.help_outline, 'Aide', () => showHelp(context)),
              sep,
              Text(
                c.path?.split(Platform.pathSeparator).last ?? 'sans titre',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (c.dirty)
                Tooltip(
                  message: 'Modifications non enregistrées',
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              const SizedBox(width: 16),
              Text(hint, style: TextStyle(color: theme.colorScheme.primary)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => CallbackShortcuts(
        bindings: {
          // Ctrl on Linux/Windows, Cmd on macOS.
          for (final meta in [false, true]) ...{
            SingleActivator(
              LogicalKeyboardKey.keyS,
              control: !meta,
              meta: meta,
            ): _save,
            SingleActivator(
              LogicalKeyboardKey.keyO,
              control: !meta,
              meta: meta,
            ): _open,
            SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: !meta,
              meta: meta,
            ): c.undo,
            SingleActivator(
              LogicalKeyboardKey.keyY,
              control: !meta,
              meta: meta,
            ): c.redo,
            SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: !meta,
              meta: meta,
              shift: true,
            ): c.redo,
          },
        },
        child: Scaffold(
          body: Column(
            children: [
              _toolbar(),
              if (c.changedOnDisk)
                MaterialBanner(
                  content: const Text(
                    'Le fichier a changé sur disque (git ?) alors que vous avez des modifications locales.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => _guard(() async => c.load(c.path!)),
                      child: const Text('Recharger le disque'),
                    ),
                    TextButton(
                      onPressed: _save,
                      child: const Text('Écraser avec ma version'),
                    ),
                  ],
                ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: DiagramCanvas(c)),
                          if (c.showMld)
                            Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLowest,
                                border: Border(
                                  top: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outline,
                                  ),
                                ),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  mld(c.doc),
                                  style: const TextStyle(
                                    fontFamily: monoFont,
                                    fontSize: fontSize,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _enumPanel(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
