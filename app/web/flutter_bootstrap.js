{{flutter_js}}
{{flutter_build_config}}

// TriCoach: nichts von Google-Servern laden (Datenschutz).
// CanvasKit kommt aus der App selbst (flutter build web --no-web-resources-cdn), Roboto ist eingebaut,
// und Ersatzschriften (z. B. für Emojis) werden nicht von fonts.gstatic.com nachgeladen.
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: 'assets/no-font-fallback/',
  },
});
