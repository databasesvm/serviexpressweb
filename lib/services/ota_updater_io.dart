import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

      if (codigoNuevo <= codigoActual || apkUrl.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final versionInstalando = prefs.getInt('ota_version_instalando') ?? 0;
      if (codigoNuevo <= versionInstalando) return;

      if (!context.mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _DialogoOta(
          versionName: (resp['version_name'] as String?) ?? '',
          apkUrl: apkUrl,
          changelog: (resp['changelog'] as String?) ?? '',
          codigoNuevo: codigoNuevo,
        ),
      );
    } catch (_) {}
  }
}

class _DialogoOta extends StatefulWidget {
  final String versionName;
  final String apkUrl;
  final String changelog;
  final int codigoNuevo;

  const _DialogoOta({
    required this.versionName,
    required this.apkUrl,
    required this.changelog,
    required this.codigoNuevo,
  });

  @override
  State<_DialogoOta> createState() => _DialogoOtaState();
}

class _DialogoOtaState extends State<_DialogoOta> {
  double _progreso = 0;
  bool _descargando = false;
  String? _error;

  Future<void> _descargarEInstalar() async {
    setState(() { _descargando = true; _error = null; _progreso = 0; });
    try {
      final dir = await getTemporaryDirectory();
      final destino = '${dir.path}/serviexpress_update.apk';
      await Dio().download(
        widget.apkUrl,
        destino,
        onReceiveProgress: (recibido, total) {
          if (total > 0 && mounted) setState(() => _progreso = recibido / total);
        },
      );
      final resultado = await OpenFilex.open(destino);
      if (resultado.type == ResultType.done && mounted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('ota_version_instalando', widget.codigoNuevo);
        if (mounted) Navigator.of(context).pop();
      } else if (mounted) {
        setState(() {
          _error = 'No se pudo abrir el instalador. Verifica que tengas habilitada la instalación desde fuentes desconocidas.';
          _descargando = false;
        });
      }
    } on DioException catch (e) {
      if (mounted) setState(() { _error = 'Error de red: ${e.message ?? "intenta de nuevo"}'; _descargando = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Error inesperado. Intenta de nuevo.'; _descargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        const Text('🚀 ', style: TextStyle(fontSize: 22)),
        Expanded(child: Text('Versión ${widget.versionName} disponible',
            style: const TextStyle(color: Color(0xFF3AF500), fontWeight: FontWeight.bold, fontSize: 16))),
      ]),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.changelog.isNotEmpty) ...[
            Flexible(
              child: SingleChildScrollView(
                child: Text(widget.changelog,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_descargando) ...[
            ClipRRect(borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: _progreso > 0 ? _progreso : null,
                minHeight: 8, backgroundColor: Colors.grey[800], color: const Color(0xFF3AF500))),
            const SizedBox(height: 8),
            Center(child: Text(
              _progreso > 0 ? 'Descargando... ${(_progreso * 100).toStringAsFixed(0)}%' : 'Conectando...',
              style: const TextStyle(color: Colors.white54, fontSize: 12))),
          ],
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
        ]),
      ),
      actions: _descargando ? const [] : [
        TextButton(onPressed: () => Navigator.of(context).pop(),
          child: const Text('Más tarde', style: TextStyle(color: Colors.white38))),
        ElevatedButton(
          onPressed: _descargarEInstalar,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3AF500),
            foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          child: const Text('Actualizar ahora', style: TextStyle(fontWeight: FontWeight.bold))),
      ],
    );
  }
}
