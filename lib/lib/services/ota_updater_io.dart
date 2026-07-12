import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// VERSIONES ATRÁS PARA OBLIGAR ACTUALIZACIÓN
const int _versionesObligatorias = 3;

// Tamaño mínimo para considerar un APK "completo" (5 MB)
const int _tamanoMinimoApk = 5 * 1024 * 1024;

class OtaUpdater {
  static Future<void> verificar(BuildContext context) async {
    if (!Platform.isAndroid) return;

    try {
      final info = await PackageInfo.fromPlatform();
      final codigoActual = int.tryParse(info.buildNumber) ?? 0;

      final resp = await Supabase.instance.client
          .from('app_config')
          .select('version_code, version_name, apk_url, changelog')
          .single();

      final codigoNuevo = (resp['version_code'] as int?) ?? 0;
      final apkUrl = (resp['apk_url'] as String?) ?? '';

      // Ya estamos al día — saltar silenciosamente
      if (codigoNuevo <= codigoActual || apkUrl.isEmpty) return;

      final int versionesAtras = codigoNuevo - codigoActual;
      final bool obligatoria = versionesAtras >= _versionesObligatorias;

      // Verificar si el APK ya fue descargado (interrupción previa o descarga
      // terminada pero instalación pendiente).
      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/serviexpress_v${codigoNuevo}_update.apk';
      final apkFile = File(apkPath);
      final int tamanoExistente =
          await apkFile.exists() ? await apkFile.length() : 0;
      final bool apkCompleto = tamanoExistente >= _tamanoMinimoApk;

      if (!context.mounted) return;

      await showDialog(
        context: context,
        // Solo bloqueable con toque si NO es obligatoria
        barrierDismissible: false,
        builder: (_) => _DialogoOta(
          versionName: (resp['version_name'] as String?) ?? '',
          apkUrl: apkUrl,
          apkPath: apkPath,
          tamanoExistente: tamanoExistente,
          changelog: (resp['changelog'] as String?) ?? '',
          codigoNuevo: codigoNuevo,
          obligatoria: obligatoria,
          apkCompleto: apkCompleto,
        ),
      );
    } catch (_) {}
  }
}

class _DialogoOta extends StatefulWidget {
  final String versionName;
  final String apkUrl;
  final String apkPath;
  final int tamanoExistente;
  final String changelog;
  final int codigoNuevo;
  final bool obligatoria;
  final bool apkCompleto;

  const _DialogoOta({
    required this.versionName,
    required this.apkUrl,
    required this.apkPath,
    required this.tamanoExistente,
    required this.changelog,
    required this.codigoNuevo,
    required this.obligatoria,
    required this.apkCompleto,
  });

  @override
  State<_DialogoOta> createState() => _DialogoOtaState();
}

class _DialogoOtaState extends State<_DialogoOta> {
  double _progreso = 0;
  bool _descargando = false;
  bool _instalando = false;
  String? _error;

  // Si el APK ya está completo, ofrecemos instalar directamente.
  // Si está parcial, retomamos desde donde quedó.
  // Si no existe, descargamos desde cero.
  Future<void> _descargarEInstalar() async {
    setState(() {
      _descargando = true;
      _error = null;
      _progreso = 0;
    });

    try {
      final archivoApk = File(widget.apkPath);

      if (!widget.apkCompleto) {
        // Intentar reanudar si existe parte del archivo, o descargar de cero
        final int byteDesde =
            await archivoApk.exists() ? await archivoApk.length() : 0;

        final dio = Dio();

        if (byteDesde > 0) {
          // Verificar si el servidor soporta Range requests
          final headResp = await dio
              .head(widget.apkUrl)
              .catchError((_) => Response(requestOptions: RequestOptions()));
          final acceptsRange =
              (headResp.headers.value('accept-ranges') ?? '') == 'bytes';

          if (acceptsRange) {
            // Descarga con reanudación (append al archivo existente)
            final response = await dio.get<ResponseBody>(
              widget.apkUrl,
              options: Options(
                headers: {'Range': 'bytes=$byteDesde-'},
                responseType: ResponseType.stream,
              ),
            );

            final contentLength =
                int.tryParse(
                  response.headers.value('content-range')?.split('/').last ??
                      '',
                ) ??
                0;

            final raf = await archivoApk.open(mode: FileMode.append);
            int recibido = byteDesde;
            await for (final chunk in response.data!.stream) {
              await raf.writeFrom(chunk);
              recibido += chunk.length;
              if (contentLength > 0 && mounted) {
                setState(() => _progreso = recibido / contentLength);
              }
            }
            await raf.close();
          } else {
            // Servidor no soporta Range → descarga completa desde cero
            await archivoApk.delete().catchError((_) => archivoApk);
            await _descargarCompleto(dio, archivoApk);
          }
        } else {
          // No hay archivo previo → descarga completa
          await _descargarCompleto(dio, archivoApk);
        }
      }

      // Abrir instalador
      setState(() {
        _descargando = false;
        _instalando = true;
      });

      final resultado = await OpenFilex.open(widget.apkPath);

      if (resultado.type == ResultType.done && mounted) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(() {
          _instalando = false;
          _error =
              'No se pudo abrir el instalador.\n'
              'Verifica que tengas habilitada la instalación '
              'desde fuentes desconocidas.';
        });
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Error de red: ${e.message ?? "intenta de nuevo"}';
          _descargando = false;
          _instalando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Error inesperado. Intenta de nuevo.';
          _descargando = false;
          _instalando = false;
        });
      }
    }
  }

  Future<void> _descargarCompleto(Dio dio, File destino) async {
    await dio.download(
      widget.apkUrl,
      destino.path,
      deleteOnError: false,
      onReceiveProgress: (recibido, total) {
        if (total > 0 && mounted) {
          setState(() => _progreso = recibido / total);
        }
      },
    );
  }

  String get _labelBotonPrincipal {
    if (widget.apkCompleto) return 'Instalar ahora';
    if (widget.tamanoExistente > 0) return 'Reanudar descarga';
    return 'Descargar ahora';
  }

  @override
  Widget build(BuildContext context) {
    final bool ocupado = _descargando || _instalando;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Text(
            widget.obligatoria ? '🔒 ' : '🚀 ',
            style: const TextStyle(fontSize: 22),
          ),
          Expanded(
            child: Text(
              'Versión ${widget.versionName} disponible',
              style: const TextStyle(
                color: Color(0xFF3AF500),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.obligatoria)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: const Text(
                  '⚠️ Actualización obligatoria — la app no funcionará '
                  'correctamente sin esta versión.',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (widget.changelog.isNotEmpty) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    widget.changelog,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_descargando) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progreso > 0 ? _progreso : null,
                  minHeight: 8,
                  backgroundColor: Colors.grey[800],
                  color: const Color(0xFF3AF500),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _progreso > 0
                      ? 'Descargando... ${(_progreso * 100).toStringAsFixed(0)}%'
                      : widget.tamanoExistente > 0
                      ? 'Reanudando descarga...'
                      : 'Conectando...',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            if (_instalando)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Abriendo instalador...',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: ocupado
          ? const []
          : [
              // "Más tarde" solo aparece si la actualización NO es obligatoria
              if (!widget.obligatoria)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Más tarde',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              ElevatedButton(
                onPressed: _descargarEInstalar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3AF500),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  _error != null ? 'Reintentar' : _labelBotonPrincipal,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
    );
  }
}
