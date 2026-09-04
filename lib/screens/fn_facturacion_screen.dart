// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../utils/web_downloader.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FnFacturacionScreen
// Historial de facturación FN — filtros, agrupación, exportación CSV/HTML
// Uso: Navigator.push(context, MaterialPageRoute(builder: (_) =>
//        FnFacturacionScreen(sedeId: null)));          // supervisor / central
//      FnFacturacionScreen(sedeId: 42)                 // sede específica
// ─────────────────────────────────────────────────────────────────────────────

class FnFacturacionScreen extends StatefulWidget {
  /// Si null → ve todas las sedes (supervisor / central).
  /// Si != null → filtra por esa sede.
  final int? sedeId;
  final String titulo;
  /// Si true, no envuelve en Scaffold (para usar como contenido de tab).
  final bool embedded;

  const FnFacturacionScreen({
    super.key,
    this.sedeId,
    this.titulo = 'Facturación FN',
    this.embedded = false,
  });

  @override
  State<FnFacturacionScreen> createState() => _FnFacturacionScreenState();
}

enum _Agrupacion { ninguna, dia, sede }

class _FnFacturacionScreenState extends State<FnFacturacionScreen> {
  final _db = Supabase.instance.client;

  List<Map<String, dynamic>> _lista = [];
  List<Map<String, dynamic>> _sedes = [];
  Set<int> _editados = {}; // IDs de servicios con auditoría de factura

  bool _cargando = true;
  bool _exportando = false;

  // Filtros
  DateTimeRange? _rango;
  String _filtroSede = 'todas';
  String _filtroEstado = 'todos';
  String _filtroFactura = '';
  String _filtroMovil = '';
  _Agrupacion _agrupacion = _Agrupacion.ninguna;

  // Controllers
  final _facturaCtrl = TextEditingController();
  final _movilCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarSedes();
    _cargar();
  }

  @override
  void dispose() {
    _facturaCtrl.dispose();
    _movilCtrl.dispose();
    super.dispose();
  }

  // ── Carga sedes ────────────────────────────────────────────────────────────
  Future<void> _cargarSedes() async {
    try {
      final data = await _db.from('fn_sedes').select('id, tipo, numero, nombre');
      final lista = List<Map<String, dynamic>>.from(data);
      lista.sort((a, b) {
        final na = int.tryParse(a['numero']?.toString() ?? '') ?? 999;
        final nb = int.tryParse(b['numero']?.toString() ?? '') ?? 999;
        return na.compareTo(nb);
      });
      if (mounted) setState(() => _sedes = lista);
    } catch (_) {}
  }

  // ── Carga historial ────────────────────────────────────────────────────────
  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      var q = _db.from('servicios').select(
        'id, fn_consecutivo, estado, destino, tarifa, fn_factura_numero, '
        'fn_factura_valor, fn_sede_solicitante_id, fn_movil_asignado_at, '
        'accepted_at, created_at, fn_alta_demanda, recogidas, metodo_pago, '
        'fn_rechazo_motivo, instrucciones_especiales, '
        'movil_data:usuarios!servicios_movil_id_fkey(usuario)',
      ).eq('fn_origen', 'sede').not(
        'estado', 'in',
        '("cotizacion","cotizada","pendiente","en_ruta_origen","en_origen","en_ruta_destino","fn_renegociando")',
      );

      // Filtro fijo por sede (si es panel de una sede)
      if (widget.sedeId != null) {
        q = q.eq('fn_sede_solicitante_id', widget.sedeId!);
      } else if (_filtroSede != 'todas') {
        q = q.eq('fn_sede_solicitante_id', int.tryParse(_filtroSede) ?? 0);
      }

      if (_filtroEstado != 'todos') q = q.eq('estado', _filtroEstado);

      if (_rango != null) {
        q = q
            .gte('created_at', _rango!.start.toUtc().toIso8601String())
            .lte('created_at',
                _rango!.end.add(const Duration(days: 1)).toUtc().toIso8601String());
      }

      final data = await q.order('created_at', ascending: false).limit(500);
      final lista = List<Map<String, dynamic>>.from(data);

      // IDs de servicios con auditoría de factura
      Set<int> editados = {};
      try {
        final ids = lista.map((s) => s['id']).whereType<int>().toList();
        if (ids.isNotEmpty) {
          final audits = await _db
              .from('fn_auditorias_factura')
              .select('servicio_id')
              .inFilter('servicio_id', ids);
          editados = Set<int>.from(
              List<Map<String, dynamic>>.from(audits)
                  .map((a) => a['servicio_id'])
                  .whereType<int>());
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _lista = lista;
          _editados = editados;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ── Filtrado cliente ───────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtrados {
    return _lista.where((s) {
      if (_filtroFactura.isNotEmpty) {
        final fac = s['fn_factura_numero']?.toString().toLowerCase() ?? '';
        if (!fac.contains(_filtroFactura.toLowerCase())) return false;
      }
      if (_filtroMovil.isNotEmpty) {
        final mov = _movilNumero(s).toLowerCase();
        if (!mov.contains(_filtroMovil.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  // ── Agrupación ─────────────────────────────────────────────────────────────
  Map<String, List<Map<String, dynamic>>> _agrupar(
      List<Map<String, dynamic>> lista) {
    if (_agrupacion == _Agrupacion.ninguna) return {'': lista};

    final Map<String, List<Map<String, dynamic>>> grupos = {};
    for (final s in lista) {
      String clave;
      if (_agrupacion == _Agrupacion.dia) {
        try {
          final dt = DateTime.parse(s['created_at'].toString()).toLocal();
          clave =
              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        } catch (_) {
          clave = 'Sin fecha';
        }
      } else {
        // por sede
        clave = _codigoSede(s['fn_sede_solicitante_id']);
      }
      grupos.putIfAbsent(clave, () => []).add(s);
    }
    return grupos;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _movilNumero(Map<String, dynamic> s) {
    final u = s['movil_data']?['usuario']?.toString();
    if (u == null) return '—';
    final n = RegExp(r'\d+').firstMatch(u)?.group(0);
    return n != null ? 'Móvil $n' : u;
  }

  String _codigoSede(dynamic sedeId) {
    if (sedeId == null) return 'Sin sede';
    final sede = _sedes.firstWhere(
      (s) => s['id'].toString() == sedeId.toString(),
      orElse: () => {},
    );
    if (sede.isEmpty) return 'Sede $sedeId';
    final num = sede['numero']?.toString() ?? '';
    return num.isNotEmpty ? 'FN$num' : (sede['nombre'] ?? 'Sede $sedeId');
  }

  String _recogidas(Map<String, dynamic> s) {
    final r = s['recogidas'];
    if (r is! List || r.isEmpty) return '—';
    return r.cast<Map<String, dynamic>>().map((rec) {
      if (rec['es_manual'] == true) {
        return rec['nombre']?.toString().isNotEmpty == true
            ? rec['nombre'].toString()
            : 'Dir. libre';
      }
      final tipo = rec['tipo']?.toString() ?? '';
      final num = rec['numero']?.toString() ?? '';
      return tipo == 'FN' && num.isNotEmpty ? 'FN$num' : (rec['nombre'] ?? '');
    }).join(', ');
  }

  String _miles(int v) {
    final str = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  String _fecha(String? raw, {bool corta = false}) {
    if (raw == null) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      if (corta) {
        return '${dt.day.toString().padLeft(2, '0')}/'
            '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _llegada(Map<String, dynamic> s) {
    final asig = s['fn_movil_asignado_at'];
    final acep = s['accepted_at'];
    if (asig == null || acep == null) return '—';
    try {
      final t1 = DateTime.parse(acep.toString());
      final t2 = DateTime.parse(asig.toString());
      final min = t2.difference(t1).inMinutes;
      return '${min}min';
    } catch (_) {
      return '—';
    }
  }

  String _labelEstado(String e) {
    const m = {
      'finalizado': 'Entregado',
      'cancelado': 'Cancelado',
      'fn_rechazado': 'Rechazado',
      'caducado': 'Caducado',
      'finalizado_con_problema': 'Fin+Prob',
    };
    return m[e] ?? e;
  }

  // ── Botón de exportación compacto ─────────────────────────────────────────
  Widget _btnExport(String label, IconData icon, Color color, VoidCallback? onPressed) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: onPressed == null ? Colors.grey[800] : color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
      icon: Icon(icon, size: 15),
      label: Text(label),
      onPressed: onPressed,
    );
  }

  // ── Exportar CSV ───────────────────────────────────────────────────────────
  Future<void> _exportarCSV() async {
    setState(() => _exportando = true);
    try {
      final rows = <List<String>>[
        [
          'Fecha/Hora', 'Sede', 'Consecutivo', 'N° Factura',
          'Valor domicilio', 'Valor producto', 'Recogidas',
          'Móvil', 'Llegada a sede', 'Estado', 'Editado',
        ],
      ];

      for (final s in _filtrados) {
        final estado = s['estado']?.toString() ?? '';
        final tarifa = (s['tarifa'] as num?)?.toInt() ?? 0;
        final valProd = s['fn_factura_valor'] != null
            ? (s['fn_factura_valor'] as num).toInt()
            : 0;
        final editado = _editados.contains(s['id']) ? 'Sí' : 'No';
        rows.add([
          _fecha(s['created_at']?.toString()),
          _codigoSede(s['fn_sede_solicitante_id']),
          s['fn_consecutivo']?.toString() ?? '#${s['id']}',
          s['fn_factura_numero']?.toString() ?? '',
          tarifa > 0 ? '\$${_miles(tarifa)}' : '',
          valProd > 0 ? '\$${_miles(valProd)}' : '',
          _recogidas(s),
          _movilNumero(s),
          _llegada(s),
          _labelEstado(estado),
          editado,
        ]);
      }

      // Totales al final
      final totalDom = _filtrados
          .where((s) => s['estado'] == 'finalizado')
          .fold<int>(0, (sum, s) => sum + ((s['tarifa'] as num?)?.toInt() ?? 0));
      rows.add([]);
      rows.add(['', '', '', 'TOTAL ENTREGADOS', '\$${_miles(totalDom)}', '', '', '', '', '', '']);

      final csv = rows
          .map((r) => r.map((c) => '"${c.replaceAll('"', '""')}"').join(';'))
          .join('\n');

      final fecha = _fecha(DateTime.now().toIso8601String(), corta: true)
          .replaceAll('/', '-');
      final csvBytes = utf8.encode('﻿$csv'); // BOM para Excel
      final nombreArchivo = 'facturacion_fn_$fecha.csv';

      if (kIsWeb) {
        descargarArchivosWeb(csvBytes, nombreArchivo, 'text/csv');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$nombreArchivo');
        await file.writeAsBytes(csvBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Facturación FN — $fecha',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error exportando: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── Exportar Excel (.xlsx) ─────────────────────────────────────────────────
  Future<void> _exportarExcel() async {
    setState(() => _exportando = true);
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Facturación FN'];
      excel.delete('Sheet1'); // quitar hoja por defecto si existe

      // Estilo encabezado
      final hStyle = CellStyle(
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      );

      final headers = [
        'Fecha/Hora', 'Sede', 'Consecutivo', 'N° Factura',
        'Domicilio', 'Valor producto', 'Recogidas',
        'Móvil', 'Llegada a sede', 'Estado', 'Editado',
      ];

      // Fila de encabezados
      for (var col = 0; col < headers.length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
        cell.value = TextCellValue(headers[col]);
        cell.cellStyle = hStyle;
      }

      int rowIdx = 1;
      for (final s in _filtrados) {
        final estado = s['estado']?.toString() ?? '';
        final tarifa = (s['tarifa'] as num?)?.toInt() ?? 0;
        final valProd = s['fn_factura_valor'] != null
            ? (s['fn_factura_valor'] as num).toInt()
            : 0;
        final editado = _editados.contains(s['id']) ? 'Sí' : 'No';

        // Color de fila según estado
        String? bgHex;
        if (estado == 'cancelado' || estado == 'fn_rechazado') bgHex = '#FFEBEE';
        else if (estado != 'finalizado') bgHex = '#FFF8E1';

        final rowValues = [
          TextCellValue(_fecha(s['created_at']?.toString())),
          TextCellValue(_codigoSede(s['fn_sede_solicitante_id'])),
          TextCellValue(s['fn_consecutivo']?.toString() ?? '#${s['id']}'),
          TextCellValue(s['fn_factura_numero']?.toString() ?? ''),
          IntCellValue(tarifa),
          IntCellValue(valProd),
          TextCellValue(_recogidas(s)),
          TextCellValue(_movilNumero(s)),
          TextCellValue(_llegada(s)),
          TextCellValue(_labelEstado(estado)),
          TextCellValue(editado),
        ];

        for (var col = 0; col < rowValues.length; col++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx));
          cell.value = rowValues[col];
          if (bgHex != null) {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.fromHexString(bgHex));
          }
        }
        rowIdx++;
      }

      // Fila de totales
      rowIdx++;
      final totalDom = _filtrados
          .where((s) => s['estado'] == 'finalizado')
          .fold<int>(0, (sum, s) => sum + ((s['tarifa'] as num?)?.toInt() ?? 0));

      final tStyle = CellStyle(bold: true, backgroundColorHex: ExcelColor.fromHexString('#E8EAF6'));
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
        ..value = TextCellValue('TOTAL ENTREGADOS')
        ..cellStyle = tStyle;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
        ..value = IntCellValue(totalDom)
        ..cellStyle = tStyle;

      // Anchos de columna aproximados
      final anchos = [18, 8, 12, 14, 12, 14, 18, 10, 12, 14, 8];
      for (var i = 0; i < anchos.length; i++) {
        sheet.setColumnWidth(i, anchos[i].toDouble());
      }

      final Uint8List bytes = Uint8List.fromList(excel.encode()!);
      final fecha = _fecha(DateTime.now().toIso8601String(), corta: true)
          .replaceAll('/', '-');
      const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      final nombreArchivo = 'facturacion_fn_$fecha.xlsx';

      if (kIsWeb) {
        descargarArchivosWeb(bytes, nombreArchivo, mime);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$nombreArchivo');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: mime)],
          subject: 'Facturación FN — $fecha',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error exportando Excel: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── Exportar Relación de cobro (HTML → imprimible como PDF) ───────────────
  Future<void> _exportarRelacion() async {
    setState(() => _exportando = true);
    try {
      final grupos = _agrupar(_filtrados);
      final totalDom = _filtrados
          .where((s) => s['estado'] == 'finalizado')
          .fold<int>(0, (sum, s) => sum + ((s['tarifa'] as num?)?.toInt() ?? 0));
      final fechaDoc = _fecha(DateTime.now().toIso8601String());
      final rangoLabel = _rango != null
          ? '${_fecha(_rango!.start.toIso8601String(), corta: true)} — ${_fecha(_rango!.end.toIso8601String(), corta: true)}'
          : 'Todos los registros';

      final buf = StringBuffer();
      buf.write('''<!DOCTYPE html><html lang="es"><head>
<meta charset="UTF-8">
<title>Relación de cobro FN</title>
<style>
  body{font-family:Arial,sans-serif;font-size:11px;margin:20px;color:#111}
  h1{font-size:16px;margin-bottom:2px}
  .sub{color:#555;margin-bottom:14px;font-size:11px}
  table{width:100%;border-collapse:collapse;margin-bottom:16px}
  th{background:#1A237E;color:#fff;padding:5px 6px;text-align:left;font-size:10px}
  td{border-bottom:1px solid #ddd;padding:4px 6px;vertical-align:top}
  tr:nth-child(even) td{background:#f5f5f5}
  .grupo{background:#e8eaf6;font-weight:bold;padding:4px 6px;margin-top:10px;border-left:3px solid #1A237E}
  .totales{text-align:right;font-weight:bold;margin-top:4px;font-size:12px}
  .editado{color:#c62828;font-size:9px}
  @media print{button{display:none}}
</style></head><body>
<button onclick="window.print()" style="float:right;padding:6px 14px;background:#1A237E;color:#fff;border:none;border-radius:4px;cursor:pointer">🖨 Imprimir / Guardar PDF</button>
<h1>Relación de cobro — Farmanorte</h1>
<div class="sub">Generado: $fechaDoc &nbsp;|&nbsp; Período: $rangoLabel &nbsp;|&nbsp; Registros: ${_filtrados.length}</div>
''');

      for (final entry in grupos.entries) {
        final grupo = entry.key;
        final items = entry.value;
        final totalGrupo = items
            .where((s) => s['estado'] == 'finalizado')
            .fold<int>(0, (sum, s) => sum + ((s['tarifa'] as num?)?.toInt() ?? 0));

        if (grupo.isNotEmpty) {
          buf.write('<div class="grupo">$grupo — ${items.length} servicios &nbsp;|&nbsp; Entregados: \$${_miles(totalGrupo)}</div>');
        }

        buf.write('''<table>
<tr>
  <th>Fecha/Hora</th><th>Sede</th><th>Consec.</th><th>N° Factura</th>
  <th>Domicilio</th><th>Producto</th><th>Recogidas</th>
  <th>Móvil</th><th>Llegada</th><th>Estado</th>
</tr>''');

        for (final s in items) {
          final estado = s['estado']?.toString() ?? '';
          final tarifa = (s['tarifa'] as num?)?.toInt() ?? 0;
          final valProd = s['fn_factura_valor'] != null
              ? (s['fn_factura_valor'] as num).toInt()
              : 0;
          final editado = _editados.contains(s['id']);
          final colorFila = estado == 'finalizado'
              ? ''
              : estado == 'cancelado' || estado == 'fn_rechazado'
                  ? 'style="color:#b71c1c"'
                  : 'style="color:#555"';

          buf.write('''<tr $colorFila>
  <td>${_fecha(s['created_at']?.toString())}</td>
  <td>${_codigoSede(s['fn_sede_solicitante_id'])}</td>
  <td>${s['fn_consecutivo']?.toString() ?? '#${s['id']}'}</td>
  <td>${s['fn_factura_numero']?.toString() ?? '—'}${editado ? ' <span class="editado">✎</span>' : ''}</td>
  <td>${tarifa > 0 ? '\$${_miles(tarifa)}' : '—'}</td>
  <td>${valProd > 0 ? '\$${_miles(valProd)}' : '—'}</td>
  <td>${_recogidas(s)}</td>
  <td>${_movilNumero(s)}</td>
  <td>${_llegada(s)}</td>
  <td>${_labelEstado(estado)}</td>
</tr>''');
        }
        buf.write('</table>');
      }

      buf.write('''<div class="totales">
Total entregados período: <strong>\$${_miles(totalDom)}</strong>
</div>
</body></html>''');

      final fecha = _fecha(DateTime.now().toIso8601String(), corta: true)
          .replaceAll('/', '-');
      final htmlBytes = utf8.encode(buf.toString());
      final nombreArchivo = 'relacion_cobro_fn_$fecha.html';

      if (kIsWeb) {
        descargarArchivosWeb(htmlBytes, nombreArchivo, 'text/html');
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$nombreArchivo');
        await file.writeAsBytes(htmlBytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/html')],
          subject: 'Relación de cobro FN — $fecha',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error exportando: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ── Exportar Tirillas (PDF) ────────────────────────────────────────────────
  Future<void> _exportarTirillas() async {
    // Capturar el listado ANTES de cambiar estado — evita que un setState
    // durante la exportación (p.ej. _exportando = true) vacíe _filtrados.
    final servicios = List<Map<String, dynamic>>.from(_filtrados);
    if (servicios.isEmpty) return;

    setState(() => _exportando = true);
    try {
      final fecha = _fecha(DateTime.now().toIso8601String(), corta: true);
      final fechaArchivo = fecha.replaceAll('/', '-');

      // Logo de la empresa
      final logoData = await rootBundle.load('assets/logo.png');
      final logoImg = pw.MemoryImage(logoData.buffer.asUint8List());

      // Formato tirilla: 80 mm × 200 mm
      const pageFormat = PdfPageFormat(
        226.77,  // 80 mm en puntos
        566.93,  // 200 mm en puntos
        marginAll: 8.50, // 3 mm
      );

      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: await PdfGoogleFonts.robotoRegular(),
          bold: await PdfGoogleFonts.robotoBold(),
        ),
      );

      const dasher = '- - - - - - - - - - - - - - -';
      const cuerpo = 7.5;
      const chico = 6.5;
      const titulo = 9.5;

      for (final s in servicios) {
        final consecutivo = s['fn_consecutivo']?.toString() ?? '#${s['id']}';
        final facturaNum = s['fn_factura_numero']?.toString() ?? '—';
        final movil = _movilNumero(s);
        final destino = s['destino']?.toString() ?? '—';
        final tarifa = (s['tarifa'] as num?)?.toInt() ?? 0;
        final metodo = _labelMetodo(s['metodo_pago']?.toString() ?? '');
        final fechaTirilla = _fecha(s['created_at']?.toString(), corta: true);

        // Sede
        final sede = _sedes.firstWhere(
          (sd) => sd['id'].toString() == s['fn_sede_solicitante_id']?.toString(),
          orElse: () => <String, dynamic>{},
        );
        final sedeNombre = sede['nombre']?.toString() ?? '';
        final sedeCodigo = _codigoSede(s['fn_sede_solicitante_id']);

        pdfDoc.addPage(pw.Page(
          pageFormat: pageFormat,
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // ─ Fecha
              pw.Text(fechaTirilla,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey600)),
              pw.SizedBox(height: 3),

              // ─ Cabecera empresa
              pw.Text('SERVIMOTO EXPRESS 24/7',
                  style: pw.TextStyle(fontSize: titulo, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.Text('Logística de Última Milla y Mensajería Continua',
                  style: pw.TextStyle(fontSize: chico), textAlign: pw.TextAlign.center),
              pw.Text('Cúcuta, Los Patios y V. del Rosario',
                  style: pw.TextStyle(fontSize: chico), textAlign: pw.TextAlign.center),
              pw.Text('NIT / RUT: 700449117-3',
                  style: pw.TextStyle(fontSize: chico), textAlign: pw.TextAlign.center),
              pw.Text('servimotoexpress247@gmail.com',
                  style: pw.TextStyle(fontSize: chico), textAlign: pw.TextAlign.center),
              pw.Text('3025901085',
                  style: pw.TextStyle(fontSize: chico), textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 4),

              pw.Text(dasher,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey500)),
              pw.SizedBox(height: 4),

              // ─ Consecutivo + Factura
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(consecutivo,
                      style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Factura #:  $facturaNum',
                      style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),

              pw.Text(dasher,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey500)),
              pw.SizedBox(height: 4),

              // ─ Móvil
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Móvil Asignado:',
                      style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold)),
                  pw.Text(movil, style: pw.TextStyle(fontSize: cuerpo)),
                ],
              ),
              pw.SizedBox(height: 4),

              pw.Text(dasher,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey500)),
              pw.SizedBox(height: 4),

              // ─ Punto de recogida
              pw.Text('Punto de Recogida:',
                  style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(sedeNombre.isNotEmpty ? sedeNombre : sedeCodigo,
                      style: pw.TextStyle(fontSize: cuerpo)),
                  pw.Text(sedeCodigo,
                      style: pw.TextStyle(fontSize: cuerpo)),
                ],
              ),
              if (metodo.isNotEmpty)
                pw.Text(metodo,
                    style: pw.TextStyle(fontSize: cuerpo),
                    textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 4),

              pw.Text(dasher,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey500)),
              pw.SizedBox(height: 4),

              // ─ Dirección de entrega
              pw.Text('Dirección de Entrega:',
                  style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.Text(destino,
                  style: pw.TextStyle(fontSize: cuerpo),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 4),

              pw.Text(dasher,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey500)),
              pw.SizedBox(height: 4),

              // ─ Total
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('[FOTO]',
                      style: pw.TextStyle(fontSize: cuerpo, color: PdfColors.blue800)),
                  pw.Text('Total:  \$ ${_miles(tarifa)}',
                      style: pw.TextStyle(
                          fontSize: cuerpo + 1, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),

              pw.Text(dasher,
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey500)),
              pw.SizedBox(height: 6),

              // ─ Footer
              pw.Text('SERVIMOTOEXPRESS',
                  style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.Text('DOMICILIOS 24/7',
                  style: pw.TextStyle(fontSize: cuerpo, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center),
              pw.Text('Nit: 700449173-3',
                  style: pw.TextStyle(fontSize: chico, color: PdfColors.grey600),
                  textAlign: pw.TextAlign.center),
              pw.SizedBox(height: 6),
              pw.Image(logoImg, width: 55),
            ],
          ),
        ));
      }

      final pdfBytes = await pdfDoc.save();

      if (kIsWeb) {
        descargarArchivosWeb(pdfBytes, 'tirillas_fn_$fechaArchivo.pdf', 'application/pdf');
      } else {
        await Printing.sharePdf(
          bytes: pdfBytes,
          filename: 'tirillas_fn_$fechaArchivo.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error generando tirillas: $e')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  String _labelMetodo(String m) {
    switch (m.toLowerCase()) {
      case 'datafono':
      case 'datáfono': return 'Datáfono';
      case 'efectivo':  return 'Efectivo';
      case 'transferencia': return 'Transferencia';
      default: return m;
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final totalDom = filtrados
        .where((s) => s['estado'] == 'finalizado')
        .fold<int>(0, (sum, s) => sum + ((s['tarifa'] as num?)?.toInt() ?? 0));
    final entregados = filtrados.where((s) => s['estado'] == 'finalizado').length;
    final cancelados = filtrados
        .where((s) => s['estado'] == 'cancelado' || s['estado'] == 'fn_rechazado')
        .length;

    final grupos = _agrupar(filtrados);

    final body = Column(
      children: [
        _buildFiltros(),
        _buildKpis(filtrados.length, entregados, cancelados, totalDom),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
              : filtrados.isEmpty
                  ? const Center(
                      child: Text('Sin registros', style: TextStyle(color: Colors.white38)))
                  : RefreshIndicator(
                      color: Colors.indigo,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(10),
                        children: [
                          for (final entry in grupos.entries) ...[
                            if (entry.key.isNotEmpty) _buildCabeceraGrupo(entry.key, entry.value),
                            for (final s in entry.value) _buildCard(s),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );

    // Barra de exportación — compartida por modo embebido y standalone
    Widget barraExportacion = Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: _exportando
            ? [const SizedBox(width: 22, height: 22,
                child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2))]
            : [
                _btnExport('CSV', Icons.grid_on, const Color(0xFF4B5563),
                    filtrados.isEmpty ? null : _exportarCSV),
                const SizedBox(width: 8),
                _btnExport('Excel', Icons.table_chart, const Color(0xFF15803D),
                    filtrados.isEmpty ? null : _exportarExcel),
                const SizedBox(width: 8),
                _btnExport('Relación', Icons.picture_as_pdf_outlined, const Color(0xFFB91C1C),
                    filtrados.isEmpty ? null : _exportarRelacion),
                const SizedBox(width: 8),
                _btnExport('Tirillas (${filtrados.length})', Icons.receipt_long, const Color(0xFF7C3AED),
                    filtrados.isEmpty ? null : _exportarTirillas),
              ],
      ),
    );

    // Modo embebido (tab): sin Scaffold propio
    if (widget.embedded) {
      return Column(
        children: [
          barraExportacion,
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.titulo,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          barraExportacion,
          Expanded(child: body),
        ],
      ),
    );
  }

  // ── Filtros ────────────────────────────────────────────────────────────────
  Widget _buildFiltros() {
    return Container(
      color: const Color(0xFF0F0F0F),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: estado + fecha + agrupación
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (v, l) in [
                        ('todos', 'Todos'),
                        ('finalizado', 'Entregados'),
                        ('cancelado', 'Cancelados'),
                        ('fn_rechazado', 'Rechazados'),
                        ('caducado', 'Caducados'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ChoiceChip(
                            label: Text(l,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: _filtroEstado == v ? Colors.white : Colors.white54)),
                            selected: _filtroEstado == v,
                            onSelected: (_) { setState(() => _filtroEstado = v); _cargar(); },
                            selectedColor: Colors.indigo[800],
                            backgroundColor: const Color(0xFF1A1A1A),
                            side: BorderSide.none,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Fecha
              IconButton(
                icon: Icon(Icons.date_range,
                    color: _rango != null ? Colors.indigo[300] : Colors.white38, size: 20),
                onPressed: () async {
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                    initialDateRange: _rango,
                  );
                  if (r != null) { setState(() => _rango = r); _cargar(); }
                },
              ),
              if (_rango != null)
                GestureDetector(
                  onTap: () { setState(() => _rango = null); _cargar(); },
                  child: const Icon(Icons.close, color: Colors.white38, size: 16),
                ),
              // Agrupación
              PopupMenuButton<_Agrupacion>(
                icon: const Icon(Icons.group_work_outlined, color: Colors.white54, size: 20),
                tooltip: 'Agrupación',
                color: const Color(0xFF1A1A2E),
                onSelected: (v) => setState(() => _agrupacion = v),
                itemBuilder: (_) => [
                  _menuItem(_Agrupacion.ninguna, 'Sin agrupar'),
                  _menuItem(_Agrupacion.dia, 'Agrupar por día'),
                  _menuItem(_Agrupacion.sede, 'Agrupar por sede'),
                ],
              ),
            ],
          ),

          // Fila 2: filtro sede (solo si no tiene sedeId fijo)
          if (widget.sedeId == null && _sedes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chipSede('todas', 'Todas'),
                    ..._sedes.map((s) => _chipSede(
                        s['id'].toString(), 'FN${s['numero']}')),
                  ],
                ),
              ),
            ),

          // Fila 3: filtros de texto (factura y móvil)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _facturaCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'N° factura…',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                        prefixIcon: const Icon(Icons.receipt_long, color: Colors.white30, size: 16),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => _filtroFactura = v),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _movilCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Móvil…',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
                        prefixIcon: const Icon(Icons.two_wheeler, color: Colors.white30, size: 16),
                        filled: true,
                        fillColor: const Color(0xFF1A1A1A),
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none),
                      ),
                      onChanged: (v) => setState(() => _filtroMovil = v),
                    ),
                  ),
                ),
                if (_filtroFactura.isNotEmpty || _filtroMovil.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () {
                        _facturaCtrl.clear();
                        _movilCtrl.clear();
                        setState(() { _filtroFactura = ''; _filtroMovil = ''; });
                      },
                      child: const Icon(Icons.close, color: Colors.white38, size: 16),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_Agrupacion> _menuItem(_Agrupacion v, String label) =>
      PopupMenuItem(
        value: v,
        child: Row(children: [
          if (_agrupacion == v)
            const Icon(Icons.check, color: Colors.indigo, size: 16)
          else
            const SizedBox(width: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );

  Widget _chipSede(String id, String label) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ChoiceChip(
          label: Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: _filtroSede == id ? Colors.white : Colors.white54)),
          selected: _filtroSede == id,
          onSelected: (_) { setState(() => _filtroSede = id); _cargar(); },
          selectedColor: Colors.indigo[800],
          backgroundColor: const Color(0xFF1A1A1A),
          side: BorderSide.none,
        ),
      );

  // ── KPIs ───────────────────────────────────────────────────────────────────
  Widget _buildKpis(int total, int entregados, int cancelados, int totalDom) {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _kpi('Total', '$total', Colors.white70),
          const SizedBox(width: 16),
          _kpi('Entregados', '$entregados', Colors.green),
          const SizedBox(width: 16),
          _kpi('Cancelados/Rec.', '$cancelados', Colors.red[300]!),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Recaudado', style: TextStyle(color: Colors.white38, fontSize: 10)),
              Text('\$${_miles(totalDom)}',
                  style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ],
          ),
          if (_rango != null) ...[
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Período', style: TextStyle(color: Colors.white38, fontSize: 9)),
                Text(
                  '${_fecha(_rango!.start.toIso8601String(), corta: true)}\n${_fecha(_rango!.end.toIso8601String(), corta: true)}',
                  style: TextStyle(color: Colors.indigo[200], fontSize: 9),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      );

  // ── Cabecera de grupo ──────────────────────────────────────────────────────
  Widget _buildCabeceraGrupo(String titulo, List<Map<String, dynamic>> items) {
    final totalGrupo = items
        .where((s) => s['estado'] == 'finalizado')
        .fold<int>(0, (sum, s) => sum + ((s['tarifa'] as num?)?.toInt() ?? 0));
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: const Border(left: BorderSide(color: Color(0xFF3949AB), width: 3)),
      ),
      child: Row(
        children: [
          Text(titulo,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 8),
          Text('${items.length} serv.',
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const Spacer(),
          Text('\$${_miles(totalGrupo)}',
              style: const TextStyle(
                  color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // ── Card de servicio ───────────────────────────────────────────────────────
  Widget _buildCard(Map<String, dynamic> s) {
    final estado = s['estado']?.toString() ?? '';
    final tarifa = (s['tarifa'] as num?)?.toInt();
    final valProd = s['fn_factura_valor'] != null
        ? (s['fn_factura_valor'] as num).toInt()
        : 0;
    final editado = _editados.contains(s['id']);

    Color borde = estado == 'finalizado'
        ? Colors.green[800]!
        : estado == 'cancelado' || estado == 'fn_rechazado'
            ? Colors.red[800]!
            : Colors.grey[700]!;

    return Card(
      color: const Color(0xFF111111),
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borde.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fila 1: consecutivo + estado + fecha
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: borde.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: borde.withValues(alpha: 0.5), width: 0.7),
                  ),
                  child: Text(_labelEstado(estado),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: borde)),
                ),
                const SizedBox(width: 6),
                Text(
                  s['fn_consecutivo']?.toString() ?? '#${s['id']}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                if (s['fn_alta_demanda'] == true) ...[
                  const SizedBox(width: 4),
                  const Text('🔥', style: TextStyle(fontSize: 10)),
                ],
                const Spacer(),
                Text(_fecha(s['created_at']?.toString()),
                    style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),

            // Fila 2: sede + factura
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.indigo[900],
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _codigoSede(s['fn_sede_solicitante_id']),
                      style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (s['fn_factura_numero'] != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.receipt_long, size: 11, color: Colors.blueGrey[300]),
                    const SizedBox(width: 3),
                    Text(
                      'Fac. ${s['fn_factura_numero']}',
                      style: TextStyle(color: Colors.blueGrey[300], fontSize: 11),
                    ),
                    if (editado) ...[
                      const SizedBox(width: 4),
                      const Text('✎',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                    ],
                  ],
                ],
              ),
            ),

            // Fila 3: recogidas
            if (s['recogidas'] is List)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    const Icon(Icons.local_pharmacy, size: 11, color: Colors.white38),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _recogidas(s),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Fila 4: destino
            if (s['destino'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 11, color: Colors.white24),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(s['destino'].toString(),
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),

            // Fila 5: valores + móvil + llegada
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  if (tarifa != null && tarifa > 0) ...[
                    const Icon(Icons.payments_outlined, size: 11, color: Colors.green),
                    const SizedBox(width: 3),
                    Text('\$${_miles(tarifa)}',
                        style: const TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                  if (valProd > 0) ...[
                    const SizedBox(width: 8),
                    Text('+ \$${_miles(valProd)} prod.',
                        style: TextStyle(color: Colors.indigo[200], fontSize: 10)),
                  ],
                  const Spacer(),
                  if (_movilNumero(s) != '—') ...[
                    const Icon(Icons.two_wheeler, size: 11, color: Colors.white38),
                    const SizedBox(width: 3),
                    Text(_movilNumero(s),
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                  if (_llegada(s) != '—') ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.timer_outlined, size: 11, color: Colors.white24),
                    const SizedBox(width: 2),
                    Text(_llegada(s),
                        style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
