<img src="logo.png" alt="macgram" width="128">

# macgram

Éditeur de MCD (modèle conceptuel de données, méthode Merise) pour le bureau : Linux, Windows et macOS. Une alternative à Looping dont les fichiers se versionnent proprement avec git.

## Fonctionnalités

- Entités, associations (binaires, n-aires ou seules), cardinalités, enums, notes et flèches d'annotation.
- MLD généré en direct sous le schéma (`_x_` clé primaire, `#x` clé étrangère).
- Réarrangement automatique du schéma pour limiter les croisements de liens.
- Export PNG et SVG, fidèle au thème courant, avec les enums en légende.
- Thèmes clair et sombre.
- Annuler / rétablir, et proposition d'enregistrer avant de quitter.

## Lancer

Il faut le [SDK Flutter](https://docs.flutter.dev/get-started/install) (Dart ≥ 3.13.5) avec le support desktop de ton OS.

```bash
flutter pub get
flutter run -d linux        # ou windows, macos
```

Un fichier peut être passé en argument pour l'ouvrir au démarrage :

```bash
macgram modele.mcd.json
```

## Utilisation

| Outil | Geste |
|---|---|
| Entité, Note | choisir l'outil, puis cliquer sur le canevas |
| Enum | panneau de droite : `+` pour créer, clic pour modifier |
| Association | cliquer deux entités pour les relier, ou le vide pour une association seule |
| Lier | ajouter une patte à une association, ou entité + enum pour créer un attribut de ce type |
| Flèche | cliquer la source, puis la cible |

- Double-clic sur un élément : ouvrir son formulaire. Cliquer en dehors ou `Échap` le ferme, les saisies sont déjà enregistrées.
- Clic sur un lien : changer la cardinalité. Double-clic : ajouter une note le long du lien.
- Clic droit sur un lien ou une flèche : ajouter un point de cassure déplaçable. Clic droit sur le point : le retirer.
- Coin bas-droit d'une note : la redimensionner.
- Dans la liste d'attributs : `Entrée` ajoute une ligne, `Tab` passe du nom au type, `Retour arrière` sur un nom vide supprime la ligne, et `a|b|c` dans le type crée un enum.

### Navigation et raccourcis

| Action | Raccourci |
|---|---|
| Déplacer la vue | glisser au clic droit, molette (vertical), `Maj`+molette (horizontal) |
| Zoomer | `Ctrl`+molette |
| Enregistrer / Ouvrir | `Ctrl+S` / `Ctrl+O` |
| Annuler / Rétablir | `Ctrl+Z` / `Ctrl+Y` ou `Ctrl+Maj+Z` |
| Supprimer la sélection | `Suppr` ou `Retour arrière` |
| Annuler l'outil en cours | `Échap` |

Sur macOS, `Cmd` remplace `Ctrl` pour les raccourcis clavier.

## Format de fichier

Les schémas sont enregistrés en JSON (`.mcd.json`), pensé pour git :

- les identifiants sont aléatoires (`e-` entité, `a-` association, `t-` enum, `n-` note, `r-` flèche), donc deux branches qui ajoutent des éléments n'entrent pas en collision ;
- les listes sont triées par identifiant, donc les ajouts tombent sur des lignes différentes ;
- chaque élément tient sur une ligne, donc les diffs restent lisibles.

## Build

```bash
flutter build linux --release      # build/linux/x64/release/bundle/
flutter build windows --release    # build\windows\x64\runner\Release\
flutter build macos --release      # build/macos/Build/Products/Release/macgram.app
```

Flutter ne cross-compile pas : chaque cible se build sur son OS. Le dossier produit est l'application entière, à distribuer tel quel (le binaire a besoin des dossiers `lib/` et `data/` voisins) :

```bash
tar -czf macgram-linux-x64.tar.gz -C build/linux/x64/release/bundle .
```

### Paquet RPM (Fedora)

```bash
flutter build linux --release
rpmbuild -bb linux/macgram.spec --define "_topdir $PWD/build/rpm" --define "src $PWD" \
  --define "ver $(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
sudo dnf install build/rpm/RPMS/x86_64/macgram-*.rpm
```

Le build du paquet demande `rpm-build` et ImageMagick (pour redimensionner `logo.png`). `dnf` installe GTK 3 si besoin, ajoute `macgram` au `PATH` et au menu d'applications. Pour désinstaller : `sudo dnf remove macgram`.

### Publier une version

```bash
git tag v1.2.0 && git push origin v1.2.0
```

Le workflow `.github/workflows/release.yml` lance les tests, build Linux et Windows, et publie une release GitHub avec l'installeur Windows, le zip portable, le `.tar.gz` Linux et le RPM. Le numéro de version vient du tag.

## Développement

```bash
flutter analyze
flutter test
```

| Fichier | Rôle |
|---|---|
| `lib/model.dart` | document, sérialisation JSON |
| `lib/controller.dart` | état, sélection, annuler / rétablir |
| `lib/scene.dart` | rendu du schéma, export SVG |
| `lib/canvas.dart` | interactions souris et clavier, export PNG |
| `lib/dialogs.dart` | formulaires et aide |
| `lib/mld.dart` | génération du MLD |
| `lib/autolayout.dart` | réarrangement automatique |
| `lib/theme.dart` | thèmes clair et sombre |
| `lib/main.dart` | fenêtre, barre d'outils, fichiers |

## Licence

[GPL-3.0-or-later](LICENSE) : tu peux utiliser, modifier et redistribuer macgram, à condition que les versions dérivées restent sous la même licence et que leur code source soit fourni.

[VIBECODED]
