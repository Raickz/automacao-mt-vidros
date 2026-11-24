{{flutter_js}}
{{flutter_build_config}}

// Sem serviceWorkerSettings: o cache do app é o web/sw.js (registrado em
// web/boot.js), não o service worker padrão do Flutter.
_flutter.loader.load();
