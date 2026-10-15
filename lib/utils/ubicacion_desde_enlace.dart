// Ubicación del cliente desde un ENLACE (pin de WhatsApp / Google Maps) o
// coordenadas sueltas. Se guarda en el servicio como la ubicación exacta del
// destino, igual que "Pedir ubicación por WhatsApp" (destino_lat/lng +
// destino_gps_at), así el móvil la ve en VER MAPA.
//
// Acepta:
//   • https://maps.app.goo.gl/xxxx  y  https://goo.gl/maps/xxxx (cortos)
//   • https://maps.google.com/?q=7.86,-72.47  (y con %2C)
//   • https://www.google.com/maps/@7.86,-72.47,17z  /  !3d…!4d…
//   • 7.863951, -72.479263  (coordenadas sueltas)
//   • Texto de WhatsApp que contenga cualquiera de los anteriores

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef Coordenadas = ({double lat, double lng});

Coordenadas? _validas(String a, String b) {
  final lat = double.tryParse(a);
  final lng = double.tryParse(b);
  if (lat == null || lng == null) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  if (lat == 0 && lng == 0) return null;
  return (lat: lat, lng: lng);
}

Coordenadas? _buscar(String texto, List<RegExp> patrones) {
  for (final p in patrones) {
    final m = p.firstMatch(texto);
    if (m != null) {
      final c = _validas(m.group(1)!, m.group(2)!);
      if (c != null) return c;
    }
  }
  return null;
}

final _patronesUrl = [
  RegExp(r'/@(-?\d+\.\d+),(-?\d+\.\d+)'),
  RegExp(r'[?&](?:q|query|ll|destination|daddr)=(-?\d+\.\d+),\s*(-?\d+\.\d+)'),
  RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
  RegExp(r'(-?\d{1,2}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})'),
];

final _patronesHtml = [
  RegExp(r'"latitude"\s*:\s*(-?\d+\.\d+)\s*,\s*"longitude"\s*:\s*(-?\d+\.\d+)'),
  RegExp(r'"lat"\s*:\s*(-?\d+\.\d+)\s*,\s*"lng"\s*:\s*(-?\d+\.\d+)'),
  RegExp(r'@(-?\d+\.\d{4,}),(-?\d+\.\d{4,}),\d+'),
  RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)'),
  RegExp(r'\[(-?\d{1,3}\.\d{5,}),(-?\d{1,3}\.\d{5,})\]'),
];

/// Saca las coordenadas de un enlace o texto. null si no encuentra.
Future<Coordenadas?> coordenadasDesdeEnlace(String entrada) async {
  var raw = entrada.trim();
  if (raw.isEmpty) return null;
  // %2C → , y demás escapes (los enlaces de WhatsApp vienen codificados)
  try {
    raw = Uri.decodeFull(raw);
  } catch (_) {}

  // 1) Directo en el texto/URL
  final directo = _buscar(raw, _patronesUrl);
  if (directo != null) return directo;

  // 2) Enlace corto: seguir la redirección y leer la página
  final urlMatch = RegExp(r'https?://\S+').firstMatch(raw);
  if (urlMatch == null) return null;
  final url = urlMatch.group(0)!;
  String urlFinal = url;
  String? body;
  try {
    if (kIsWeb) {
      // En el navegador hay CORS: se usa un proxy (igual que en FN)
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ));
      final resp = await dio.get<Map<String, dynamic>>(
          'https://api.allorigins.win/get?url=${Uri.encodeComponent(url)}');
      urlFinal = (resp.data?['status']?['url'] as String?) ?? url;
      body = resp.data?['contents'] as String?;
    } else {
      final dio = Dio(BaseOptions(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
        followRedirects: true,
        maxRedirects: 10,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 12),
      ));
      final resp = await dio.get<String>(
        url,
        options: Options(
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      );
      urlFinal = resp.realUri.toString();
      body = resp.data;
    }
  } catch (_) {}

  try {
    urlFinal = Uri.decodeFull(urlFinal);
  } catch (_) {}
  final enUrl = _buscar(urlFinal, _patronesUrl);
  if (enUrl != null) return enUrl;
  if (body != null && body.isNotEmpty) {
    final muestra = body.length > 80000 ? body.substring(0, 80000) : body;
    return _buscar(muestra, _patronesHtml);
  }
  return null;
}

/// Diálogo "Pegar ubicación": devuelve las coordenadas o null si se cancela.
Future<Coordenadas?> dialogoPegarUbicacion(BuildContext context) async {
  final ctrl = TextEditingController();
  bool buscando = false;
  String? error;
  return showDialog<Coordenadas>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('📍 Pegar ubicación del cliente',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pega el enlace de la ubicación que mandó el cliente por WhatsApp '
              '(o de Google Maps), o las coordenadas.\n'
              'En el celular: abre el pin → Compartir → Copiar.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                hintText: 'https://maps.app.goo.gl/…  ó  7.8639, -72.4792',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: error,
              ),
              onChanged: (_) => setD(() => error = null),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: buscando ? null : () => Navigator.pop(ctx),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: buscando
                ? null
                : () async {
                    setD(() => buscando = true);
                    final c = await coordenadasDesdeEnlace(ctrl.text);
                    if (!ctx.mounted) return;
                    if (c == null) {
                      setD(() {
                        buscando = false;
                        error = 'No se encontraron coordenadas en ese enlace';
                      });
                      return;
                    }
                    Navigator.pop(ctx, c);
                  },
            child: buscando
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('USAR UBICACIÓN'),
          ),
        ],
      ),
    ),
  );
}

/// Campos que guardan la ubicación exacta del destino en un servicio.
Map<String, dynamic> camposUbicacionDestino(Coordenadas c) => {
      'destino_lat': c.lat,
      'destino_lng': c.lng,
      'destino_gps_at': DateTime.now().toUtc().toIso8601String(),
    };

/// Pega la ubicación en un servicio ya creado. true si se guardó.
Future<bool> pegarUbicacionEnServicio(
    BuildContext context, Map<String, dynamic> servicio) async {
  final c = await dialogoPegarUbicacion(context);
  if (c == null) return false;
  try {
    await Supabase.instance.client
        .from('servicios')
        .update(camposUbicacionDestino(c))
        .eq('id', servicio['id']);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('📍 Ubicación guardada en el servicio #${servicio['id']}'),
        backgroundColor: Colors.green[700],
      ));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo guardar la ubicación: $e'),
        backgroundColor: Colors.red,
      ));
    }
    return false;
  }
}
