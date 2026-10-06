# Emballe le bundle déjà produit par `flutter build linux --release`.
# Lancer depuis la racine du repo :
#   rpmbuild -bb linux/macgram.spec --define "_topdir $PWD/build/rpm" --define "src $PWD" \
#     --define "ver $(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"

Name:           macgram
Version:        %{ver}
Release:        1%{?dist}
Summary:        Éditeur de MCD (Merise)
License:        GPL-3.0-or-later
URL:            https://github.com/redyd/macgram

# Binaires Flutter déjà strippés ; les .so du bundle sont privés.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global __provides_exclude_from ^%{_libdir}/%{name}/.*$
%global __requires_exclude ^lib(app|flutter_linux_gtk|.*_plugin)\\.so.*$

%description
Éditeur de modèles conceptuels de données pour le bureau, avec MLD généré,
réarrangement automatique et export PNG/SVG.

%install
cp %{src}/LICENSE .
mkdir -p %{buildroot}%{_libdir}/%{name} %{buildroot}%{_bindir} \
  %{buildroot}%{_datadir}/applications %{buildroot}%{_datadir}/icons/hicolor/256x256/apps
cp -r %{src}/build/linux/x64/release/bundle/. %{buildroot}%{_libdir}/%{name}/
ln -s %{_libdir}/%{name}/%{name} %{buildroot}%{_bindir}/%{name}
magick %{src}/logo.png -resize 256x256 \
  %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/%{name}.png
# Le nom du .desktop reprend l'APPLICATION_ID pour que Wayland associe la fenêtre à l'icône.
cat > %{buildroot}%{_datadir}/applications/dev.macgram.macgram.desktop <<EOF
[Desktop Entry]
Type=Application
Name=macgram
Comment=Éditeur de MCD
Exec=macgram %f
Icon=macgram
Categories=Development;
EOF

%files
%license LICENSE
%{_libdir}/%{name}
%{_bindir}/%{name}
%{_datadir}/applications/dev.macgram.macgram.desktop
%{_datadir}/icons/hicolor/256x256/apps/%{name}.png
