import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';

/// Maneja deep links (`serviexpress://pedido?local=42`) y textos
/// compartidos desde otras apps (WhatsApp, etc.).
///
/// Uso típico:
///   1. Llamar [DeeplinkService.init] en main() antes de runApp.
///   2. Suscribirse a [DeeplinkService.stream] en la pantalla adecuada
///      (o consultar [DeeplinkService.consumePending] después del login).
class DeeplinkService {
  DeeplinkService._();

  static final _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream de deep links ya parseados. Emite cuando llega un link
  /// mientras la app está en primer plano.
  static Stream<Map<String, dynamic>> get stream => _controller.stream;

  static String? _pendingLink;
  static AppLinks? _appLinks;

  static const _shareChannel =
      MethodChannel('com.serviexpress.app/shareintent');

  // ── Init ──────────────────────────────────────────────────────────

  static Future<void> init() async {
    if (kIsWeb) return;
    _appLinks = AppLinks();

    // Cold-start: link que abrió la app
    try {
      final initial = await _appLinks!.getInitialLink();
      if (initial != null) _handleUri(initial.toString());
    } catch (_) {}

    // Warm-start: link mientras la app ya estaba corriendo
    _appLinks!.uriLinkStream.listen(
      (uri) => _handleUri(uri.toString()),
      onError: (_) {},
    );

    // Share intent via MethodChannel (Android ACTION_SEND)
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        final text = call.arguments as String?;
        if (text != null) _handleText(text);
      }
    });

    // Leer texto compartido en cold-start desde ACTION_SEND
    try {
      final shared =
          await _shareChannel.invokeMethod<String>('getSharedText');
      if (shared != null && shared.isNotEmpty) _handleText(shared);
    } catch (_) {}
  }

  // ── Handlers internos ─────────────────────────────────────────────

  static void _handleUri(String raw) {
    final parsed = parse(raw);
    if (parsed == null) return;
    if (!_controller.isClosed) {
      _controller.add(parsed);
    }
    _pendingLink = raw;
  }

  static void _handleText(String text) {
    // Extraer URL serviexpress:// embebida en el texto
    final regex = RegExp(r'serviexpress://pedido\?[^\s\n]+');
    final match = regex.firstMatch(text);
    if (match != null) _handleUri(match.group(0)!);
  }

  // ── API pública ───────────────────────────────────────────────────

  /// Almacena un link pendiente (para resolverlo después del login).
  static void setPending(String link) => _pendingLink = link;

  /// Retorna y borra el link pendiente.
  static Map<String, dynamic>? consumePending() {
    final l = _pendingLink;
    _pendingLink = null;
    if (l == null) return null;
    return parse(l);
  }

  static bool get hasPending => _pendingLink != null;

  /// Parsea `serviexpress://pedido?local=42[&items=Prod:1,Prod2:2]`
  /// o cualquier texto que contenga esa URL.
  /// Retorna `{'local_id': int, 'items': List<Map>}` o `null`.
  static Map<String, dynamic>? parse(String input) {
    try {
      final regex = RegExp(r'serviexpress://pedido\?[^\s\n]+');
      final match = regex.firstMatch(input);
      final urlStr = match?.group(0) ??
          (input.startsWith('serviexpress://pedido') ? input : null);
      if (urlStr == null) return null;

      final uri = Uri.parse(urlStr);
      final localId = int.tryParse(uri.queryParameters['local'] ?? '');
      if (localId == null) return null;

      final itemsStr = uri.queryParameters['items'];
      final items = <Map<String, dynamic>>[];
      if (itemsStr != null && itemsStr.isNotEmpty) {
        for (final part in itemsStr.split(',')) {
          final colon = part.lastIndexOf(':');
          if (colon > 0) {
            items.add({
              'nombre': Uri.decodeComponent(part.substring(0, colon)),
              'cantidad': int.tryParse(part.substring(colon + 1)) ?? 1,
            });
          }
        }
      }
      return {'local_id': localId, 'items': items};
    } catch (_) {
      return null;
    }
  }

  /// Genera `serviexpress://pedido?local=42`
  static String linkParaLocal(int localId) =>
      'serviexpress://pedido?local=$localId';

  /// Genera texto listo para compartir por WhatsApp.
  static String textoCompartible(
    String nombreLocal,
    int localId, {
    List<Map<String, dynamic>> items = const [],
  }) {
    var url = linkParaLocal(localId);
    if (items.isNotEmpty) {
      final itemsStr = items
          .map((i) =>
              '${Uri.encodeComponent(i['nombre'].toString())}:${i['cantidad']}')
          .join(',');
      url += '&items=$itemsStr';
    }
    return '🛵 Pide en *$nombreLocal* por ServiExpress:\n$url\n\n🌐 También desde el navegador:\nhttps://databasesvm.github.io/serviexpressweb/';
  }

  static void dispose() {
    _controller.close();
  }
}
