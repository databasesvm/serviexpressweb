// lib/utils/campo_tarifa_inteligente.dart
//
// CAMPO DE TARIFA INTELIGENTE
// ============================
// Reemplaza el TextField de tarifa simple en los diálogos de Central.
// Integra tres componentes en un solo widget:
//
//   1. SUGERENCIA — llama a sugerir_tarifa() en Supabase con un debounce
//      de 800ms desde que el usuario deja de escribir el origen/destino.
//      Muestra precio sugerido, nivel de confianza y los últimos precios.
//
//   2. RECARGOS — el RecargosPanel embebido (lluvia, nocturno, sobrecarga).
//      El recargo se suma automáticamente al precio sugerido.
//
//   3. CAMPO FINAL — el precio editable que Central confirma o modifica.
//      Pre-llenado con (sugerido + recargo). Central siempre tiene control.
//
// USO:
//   CampoTarifaInteligente(
//     origenController: origenCtrl,
//     destinoController: destinoCtrl,
//     tarifaController: tarifaCtrl,  // el que ya usas para insertar en BD
//   )

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/widgets_compartidos.dart';
import 'package:serviexpress_app/utils/recargos_panel.dart';

class CampoTarifaInteligente extends StatefulWidget {
  /// Controladores de origen y destino — el widget los escucha con listener.
  final TextEditingController origenController;
  final TextEditingController destinoController;

  /// El controlador de tarifa que ya usas para insertar en la BD.
  /// El widget lo pre-llena con (sugerido + recargo) pero Central puede
  /// cambiarlo libremente.
  final TextEditingController tarifaController;

  /// GPS del origen (opcional) — si está disponible mejora la coincidencia.
  final double? origenLat;
  final double? origenLng;

  /// GPS del destino (opcional).
  final double? destinoLat;
  final double? destinoLng;

  /// Tipo de servicio — CRÍTICO para que el motor no mezcle precios entre
  /// MOTOTAXI, PAQUETERÍA, COMIDA, COMPRAS. Sin esto el aprendizaje se
  /// contamina y los precios sugeridos son incorrectos para todos los tipos.
  final String? tipoServicio;

  /// Callback con el desglose completo del precio cada vez que cambia.
  /// Permite al padre capturar {base, lluvia, nocturno, sobrecarga,
  /// recargo, total, fuente} en el momento del dispatch.
  final void Function(Map<String, dynamic> detalle)? onDetalleChanged;

  const CampoTarifaInteligente({
    super.key,
    required this.origenController,
    required this.destinoController,
    required this.tarifaController,
    this.origenLat,
    this.origenLng,
    this.destinoLat,
    this.destinoLng,
    this.tipoServicio,
    this.onDetalleChanged,
  });

  @override
  State<CampoTarifaInteligente> createState() => _CampoTarifaInteligenteState();
}

class _CampoTarifaInteligenteState extends State<CampoTarifaInteligente> {
  // --- Sugerencia del motor ---
  int? _precioSugerido;
  int _precioMinimo = 0;
  int _precioMaximo = 0;
  int _numPrecedentes = 0;
  String _confianza = 'sin_historial'; // 'sin_historial' | 'media' | 'alta'
  List<int> _preciosRecientes = [];
  bool _consultando = false;

  // --- Recargos activos ---
  int _recargo = 0;
  bool _conRecargos = false;

  // --- Debounce para no disparar RPC en cada tecla ---
  Timer? _debounce;
  static const Duration _dDebounce = Duration(milliseconds: 800);

  // --- Control para no sobreescribir lo que Central ya escribió a mano ---
  bool _centralModificoManualmente = false;

  // --- Último estado de recargos (para incluirlo en el desglose) ---
  EstadoRecargos? _ultimoEstadoRecargos;

  @override
  void initState() {
    super.initState();
    widget.origenController.addListener(_onRutaCambio);
    widget.destinoController.addListener(_onRutaCambio);
    widget.tarifaController.addListener(_detectarEdicionManual);
    // Consulta inicial si ya vienen con datos
    if (widget.origenController.text.isNotEmpty &&
        widget.destinoController.text.isNotEmpty) {
      _consultarSugerencia();
    }
  }

  @override
  void dispose() {
    widget.origenController.removeListener(_onRutaCambio);
    widget.destinoController.removeListener(_onRutaCambio);
    widget.tarifaController.removeListener(_detectarEdicionManual);
    _debounce?.cancel();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // ESCUCHAS
  // -----------------------------------------------------------------------
  void _onRutaCambio() {
    // Si Central ya escribió un precio propio, no sobreescribimos
    _centralModificoManualmente = false;

    _debounce?.cancel();
    _debounce = Timer(_dDebounce, () {
      if (widget.origenController.text.trim().length >= 3 &&
          widget.destinoController.text.trim().length >= 3) {
        _consultarSugerencia();
      } else {
        setState(() {
          _precioSugerido = null;
          _confianza = 'sin_historial';
          _numPrecedentes = 0;
        });
      }
    });
  }

  void _detectarEdicionManual() {
    // Si el texto del campo ya no coincide con lo que el motor puso,
    // es porque Central lo cambió manualmente — respetamos esa decisión.
    final valorActual = _parsePeso(widget.tarifaController.text);
    final valorMotor = (_precioSugerido ?? 0) + _recargo;
    if (valorActual != valorMotor && valorActual > 0) {
      _centralModificoManualmente = true;
      _emitirDetalle();
    }
  }

  // -----------------------------------------------------------------------
  // CONSULTA AL MOTOR
  // -----------------------------------------------------------------------
  Future<void> _consultarSugerencia() async {
    if (!mounted) return;
    setState(() => _consultando = true);

    try {
      final params = {
        'p_origen': widget.origenController.text.trim(),
        'p_destino': widget.destinoController.text.trim(),
        'p_origen_lat': widget.origenLat,
        'p_origen_lng': widget.origenLng,
        'p_destino_lat': widget.destinoLat,
        'p_destino_lng': widget.destinoLng,
        // CRÍTICO: sin el tipo, MOTOTAXI y PAQUETERÍA contaminan su historial
        if (widget.tipoServicio != null)
          'p_tipo_servicio': widget.tipoServicio,
      };

      // Eliminamos los nulls para no confundir a la función SQL
      params.removeWhere((k, v) => v == null);

      final resultado = await Supabase.instance.client.rpc(
        'sugerir_tarifa',
        params: params,
      );

      if (!mounted) return;

      if (resultado == null || (resultado as List).isEmpty) {
        setState(() {
          _precioSugerido = null;
          _confianza = 'sin_historial';
          _numPrecedentes = 0;
          _preciosRecientes = [];
        });
        return;
      }

      final row = resultado[0] as Map<String, dynamic>;
      final sugerido = (row['precio_sugerido'] as num?)?.toInt();
      final minimo = (row['precio_minimo'] as num?)?.toInt() ?? 0;
      final maximo = (row['precio_maximo'] as num?)?.toInt() ?? 0;
      final num precedentes = (row['num_precedentes'] as num?) ?? 0;
      final confianza = row['confianza']?.toString() ?? 'sin_historial';
      final recientes =
          (row['precios_recientes'] as List?)
              ?.map((p) => (p as num).toInt())
              .toList() ??
          [];

      setState(() {
        _precioSugerido = sugerido;
        _precioMinimo = minimo;
        _precioMaximo = maximo;
        _numPrecedentes = precedentes.toInt();
        _confianza = confianza;
        _preciosRecientes = recientes;
      });

      // Pre-llenamos solo si Central no ha escrito nada a mano
      if (!_centralModificoManualmente && sugerido != null) {
        _preLlenarCampo(sugerido + _recargo);
      }
      _emitirDetalle();
    } catch (e) {
      debugPrint('CampoTarifaInteligente: RPC error → $e');
    } finally {
      if (mounted) setState(() => _consultando = false);
    }
  }

  void _preLlenarCampo(int valor) {
    if (valor <= 0) return;
    final texto = _formatearPeso(valor);
    if (widget.tarifaController.text != texto) {
      widget.tarifaController.text = texto;
      widget.tarifaController.selection = TextSelection.collapsed(
        offset: texto.length,
      );
    }
  }

  // -----------------------------------------------------------------------
  // CALLBACK DE RECARGOS
  // -----------------------------------------------------------------------
  void _onRecargosChanged(EstadoRecargos estado) {
    final nuevoRecargo = estado.recargo;
    _ultimoEstadoRecargos = estado;

    if (nuevoRecargo == _recargo) return;

    setState(() {
      _recargo = nuevoRecargo;
      _conRecargos = nuevoRecargo > 0;
    });

    // Actualiza el campo si el motor ya tiene una sugerencia
    // Y Central no lo ha tocado manualmente
    if (!_centralModificoManualmente && _precioSugerido != null) {
      _preLlenarCampo(_precioSugerido! + nuevoRecargo);
    }
    _emitirDetalle();
  }

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------
  String _formatearPeso(int valor) {
    // Formato con punto de miles: 8000 → $8.000
    final s = valor.toString();
    final buffer = StringBuffer('\$');
    final inicio = s.length % 3;
    if (inicio > 0) buffer.write(s.substring(0, inicio));
    for (int i = inicio; i < s.length; i += 3) {
      if (i > 0) buffer.write('.');
      buffer.write(s.substring(i, i + 3));
    }
    return buffer.toString();
  }

  int _parsePeso(String texto) {
    final limpio = texto
        .replaceAll('\$', '')
        .replaceAll('.', '')
        .replaceAll(',', '')
        .trim();
    return int.tryParse(limpio) ?? 0;
  }

  /// Emite el desglose completo al padre cada vez que el precio cambia.
  void _emitirDetalle() {
    if (widget.onDetalleChanged == null) return;
    final int total = _parsePeso(widget.tarifaController.text);
    final int base = _precioSugerido ?? (total - _recargo).clamp(0, total);
    final int ajusteManual = _centralModificoManualmente
        ? (total - base - _recargo).clamp(0, total)
        : 0;
    final String fuente = _centralModificoManualmente
        ? 'manual'
        : (_precioSugerido != null ? 'motor_$_confianza' : 'sin_historial');
    widget.onDetalleChanged!({
      'base': base,
      'lluvia': _ultimoEstadoRecargos?.lluvia ?? false,
      'nocturno': _ultimoEstadoRecargos?.nocturno ?? false,
      'sobrecarga': _ultimoEstadoRecargos?.sobrecarga ?? false,
      'recargo': _recargo,
      'ajuste_manual': ajusteManual,
      'total': total,
      'fuente': fuente,
    });
  }

  Color get _colorConfianza {
    switch (_confianza) {
      case 'alta':
        return Colors.green[700]!;
      case 'media':
        return Colors.orange[700]!;
      default:
        return Colors.grey;
    }
  }

  String get _etiquetaConfianza {
    switch (_confianza) {
      case 'alta':
        return '● Alta confianza';
      case 'media':
        return '● Confianza media';
      default:
        return '';
    }
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SUGERENCIA (solo si hay resultado)
        if (_consultando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black38,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Consultando historial...',
                  style: TextStyle(color: Colors.black38, fontSize: 12),
                ),
              ],
            ),
          )
        else if (_precioSugerido != null && _numPrecedentes >= 3) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _colorConfianza.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _colorConfianza.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Precio sugerido: ${_formatearPeso(_precioSugerido!)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _etiquetaConfianza,
                      style: TextStyle(
                        color: _colorConfianza,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Basado en $_numPrecedentes servicios similares'
                  '${_precioMinimo != _precioMaximo ? '  ·  Rango: ${_formatearPeso(_precioMinimo)} – ${_formatearPeso(_precioMaximo)}' : ''}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                if (_preciosRecientes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: _preciosRecientes
                        .map(
                          (p) => Chip(
                            label: Text(
                              _formatearPeso(p),
                              style: const TextStyle(fontSize: 10),
                            ),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.black12,
                            side: BorderSide.none,
                          ),
                        )
                        .toList(),
                  ),
                ],
                // Botón de aplicar si Central cambió el valor manualmente
                if (_centralModificoManualmente)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        _centralModificoManualmente = false;
                        _preLlenarCampo(_precioSugerido! + _recargo);
                      },
                      child: const Text(
                        '↺ Aplicar sugerencia',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ] else if (_numPrecedentes < 3 &&
            widget.origenController.text.trim().length >= 3 &&
            widget.destinoController.text.trim().length >= 3 &&
            !_consultando)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Sin historial para esta ruta · El sistema aprenderá con el tiempo.',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),

        // RECARGOS
        RecargosPanel(onCambio: _onRecargosChanged),
        const SizedBox(height: 10),

        // CAMPO FINAL — editable, siempre bajo el control de Central
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: widget.tarifaController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [CurrencyInputFormatter()],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Tarifa final (dejar vacío = cotización)',
                hintText: 'Ej: \$8.000',
                border: const OutlineInputBorder(),
                isDense: true,
                prefixIcon: const Icon(Icons.attach_money, size: 18),
                // Si hay recargo activo, lo mostramos como sufijo informativo
                suffix: _conRecargos
                    ? Text(
                        '+\$${_formatearPeso(_recargo)} de recargo',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange[700],
                        ),
                      )
                    : null,
              ),
            ),
            if (_conRecargos && _precioSugerido != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Base ${_formatearPeso(_precioSugerido!)} + '
                  'recargo ${_formatearPeso(_recargo)} = '
                  '${_formatearPeso(_precioSugerido! + _recargo)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            // Advertencia si la tarifa está bajo la mínima nocturna
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.tarifaController,
              builder: (_, val, __) {
                final int minima =
                    _ultimoEstadoRecargos?.minimaActual ?? 0;
                if (minima <= 0) return const SizedBox.shrink();
                final int total = _parsePeso(val.text);
                if (total <= 0 || total >= minima) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 5, left: 2),
                  child: Row(
                    children: [
                      Icon(Icons.nights_stay,
                          size: 13, color: Colors.indigo[400]),
                      const SizedBox(width: 4),
                      Text(
                        'Bajo mínima nocturna (\$${_formatearPeso(minima)})',
                        style: TextStyle(
                            fontSize: 11, color: Colors.indigo[600]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
