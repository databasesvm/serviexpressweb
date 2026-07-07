// lib/utils/recargos_panel.dart
//
// PANEL DE RECARGOS — Central controla lluvia y nocturno desde aquí.
// ===================================================================
// Estado compartido: usa config_sistema (Supabase Realtime) para que
// todos los dispositivos de Central vean el mismo estado simultáneamente.
//
// Lluvia: detecta automáticamente vía API del clima (OpenWeatherMap)
//   cada 10 minutos. Botón manual siempre disponible como override.
//
// Nocturno: se activa/desactiva automáticamente según la hora local
//   de Colombia (UTC-5). No requiere acción de nadie.
//
// Sobrecarga: checkbox manual — no tiene precio fijo, Central lo suma
//   por criterio cuando el pedido excede el estándar del bolso.
//
// SETUP REQUERIDO:
//   1. Registrarte gratis en https://openweathermap.org/api
//   2. Copiar tu API key en config_sistema.api_key_clima (Supabase).
//   3. Esperar ~10 min para que tu key quede activa en sus servidores.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// =========================================================================
// ⚙️  API KEY DE CLIMA — se carga dinámicamente desde config_sistema.api_key_clima
// Para activar la detección automática de lluvia, inserta tu clave de
// OpenWeatherMap (https://openweathermap.org/api) en esa columna.
// =========================================================================

// Ciudades del área de cobertura a monitorear.
// Si llueve en CUALQUIERA, se activa lluvia_activa (recargo general).
// Trapiches se monitorea por separado para lluvia_trapiches.
const List<String> _kCiudades = [
  'Cucuta,CO',
  'Los Patios,CO',
  'Villa del Rosario,CO',
];
// Ciudad exclusiva para locales con zona_lluvia = 'trapiches'
const String _kCiudadTrapiches = 'Bocono,CO'; // Bocono = zona Trapiches

// Intervalo de consulta al clima (en modo automático)
const Duration _kIntervaloClima = Duration(minutes: 10);

// =========================================================================
// CALLBACK — lo que devuelve el panel al padre
// =========================================================================
class EstadoRecargos {
  final bool lluvia;
  final bool nocturno;
  final bool sobrecarga;
  final int recargo; // total en pesos
  final int minimaActual; // mínima efectiva considerando recargos

  const EstadoRecargos({
    required this.lluvia,
    required this.nocturno,
    required this.sobrecarga,
    required this.recargo,
    required this.minimaActual,
  });
}

// =========================================================================
// WIDGET PRINCIPAL
// =========================================================================
class RecargosPanel extends StatefulWidget {
  /// Se llama cada vez que cambia algún recargo.
  /// Úsalo en central_screen para aplicar los recargos a la tarifa.
  final void Function(EstadoRecargos estado) onCambio;

  /// Si true, muestra el panel expandido siempre.
  /// Si false (default), es compacto con un chevron para expandir.
  final bool siempreExpandido;

  const RecargosPanel({
    super.key,
    required this.onCambio,
    this.siempreExpandido = false,
  });

  @override
  State<RecargosPanel> createState() => _RecargosPanelState();
}

class _RecargosPanelState extends State<RecargosPanel> {
  // --- Estado desde Supabase ---
  bool _lluvia = false;
  bool _lluviaTrapiches = false; // solo para locales con zona_lluvia='trapiches'
  String _modoLluvia = 'auto'; // 'auto' | 'manual'
  int _recargoLluvia = 1000;
  int _recargoNocturno = 2000;
  int _minimaBase = 8000;
  int _horaInicioNocturno = 0;
  int _horaFinNocturno = 6;

  // --- Estado local ---
  bool _nocturno = false;
  bool _sobrecarga = false;
  bool _expandido = false;
  bool _guardando = false;
  // API key cargada dinámicamente desde config_sistema.api_key_clima
  bool _apiActiva = false;
  String? _apiKey;

  // --- Timers ---
  Timer? _timerClima;
  Timer? _timerNocturno;
  RealtimeChannel? _canalConfig;

  @override
  void initState() {
    super.initState();
    _expandido = widget.siempreExpandido;
    _cargarConfigInicial(); // también activa timer clima si hay clave
    _iniciarTimerNocturno();
  }

  @override
  void dispose() {
    _timerClima?.cancel();
    _timerNocturno?.cancel();
    _canalConfig?.unsubscribe();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // CARGA INICIAL Y STREAM DE SUPABASE
  // -----------------------------------------------------------------------
  Future<void> _cargarConfigInicial() async {
    try {
      final row = await Supabase.instance.client
          .from('config_sistema')
          .select()
          .eq('id', 1)
          .single();
      if (mounted) _aplicarConfigDesde(row);
    } catch (e) {
      debugPrint('RecargosPanel: error carga inicial → $e');
    }

    // Suscripción Realtime — todos los dispositivos de Central sincronizan
    _canalConfig = Supabase.instance.client
        .channel('config_recargos')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'config_sistema',
          callback: (payload) {
            if (payload.newRecord.isNotEmpty && mounted) {
              _aplicarConfigDesde(payload.newRecord);
            }
          },
        )
        .subscribe();
  }

  void _aplicarConfigDesde(Map<String, dynamic> row) {
    // Evaluar si el API key cambió
    final String? nuevaClave = row['api_key_clima'] as String?;
    final bool apiAhora =
        nuevaClave != null && nuevaClave.trim().isNotEmpty;

    setState(() {
      _lluvia = row['lluvia_activa'] as bool? ?? false;
      _lluviaTrapiches = row['lluvia_trapiches'] as bool? ?? false;
      _modoLluvia = row['lluvia_modo'] as String? ?? 'auto';
      _recargoLluvia = row['recargo_lluvia'] as int? ?? 1000;
      _recargoNocturno = row['recargo_nocturno'] as int? ?? 2000;
      _minimaBase = row['minima_nocturna'] as int? ?? 8000;
      _horaInicioNocturno = (row['hora_inicio_nocturno'] as num?)?.toInt() ?? 0;
      _horaFinNocturno = (row['hora_fin_nocturno'] as num?)?.toInt() ?? 6;
      _apiKey = nuevaClave?.trim();
      _apiActiva = apiAhora;
    });

    // Iniciar o detener timer de clima según si hay clave válida
    if (apiAhora && _timerClima == null) {
      _iniciarTimerClima();
    } else if (!apiAhora) {
      _timerClima?.cancel();
      _timerClima = null;
    }

    _actualizarNocturno();
    _notificarPadre();
  }

  // -----------------------------------------------------------------------
  // NOCTURNO — automático por hora (Colombia UTC-5)
  // -----------------------------------------------------------------------
  void _iniciarTimerNocturno() {
    _actualizarNocturno();
    // Re-evalúa cada minuto para detectar el cambio exacto de hora
    _timerNocturno = Timer.periodic(const Duration(minutes: 1), (_) {
      _actualizarNocturno();
    });
  }

  void _actualizarNocturno() {
    final hora = DateTime.now().toUtc().subtract(const Duration(hours: 5)).hour;
    final esNocturno = hora >= _horaInicioNocturno && hora < _horaFinNocturno;
    if (esNocturno != _nocturno) {
      setState(() => _nocturno = esNocturno);
      _notificarPadre();
    }
  }

  // -----------------------------------------------------------------------
  // LLUVIA — API automática + override manual
  // -----------------------------------------------------------------------
  void _iniciarTimerClima() {
    _verificarClimaApi(); // inmediato al arrancar
    _timerClima = Timer.periodic(_kIntervaloClima, (_) {
      if (_modoLluvia == 'auto') _verificarClimaApi();
    });
  }

  Future<void> _verificarClimaApi() async {
    if (!_apiActiva || _modoLluvia != 'auto' || _apiKey == null) return;
    final String clave = _apiKey!;
    try {
      bool llueveEnAlgunaZona = false;

      // --- Verificar zonas generales ---
      for (final ciudad in _kCiudades) {
        final url = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather'
          '?q=$ciudad&appid=$clave&units=metric',
        );
        final resp = await http.get(url);
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final weatherId =
              (data['weather']?[0]?['id'] as num?)?.toInt() ?? 800;
          // IDs 200-622: thunderstorm, drizzle, rain, snow — todo lo que moje
          if (weatherId < 700) {
            llueveEnAlgunaZona = true;
            break; // basta con que llueva en una zona general
          }
        }
      }

      // --- Verificar Trapiches por separado (para locales zona 'trapiches') ---
      bool llueveEnTrapiches = false;
      try {
        final urlT = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather'
          '?q=$_kCiudadTrapiches&appid=$clave&units=metric',
        );
        final respT = await http.get(urlT);
        if (respT.statusCode == 200) {
          final dataT = jsonDecode(respT.body);
          final idT = (dataT['weather']?[0]?['id'] as num?)?.toInt() ?? 800;
          llueveEnTrapiches = idT < 700;
        }
      } catch (_) {}

      // Actualizamos si algo cambió
      final bool cambioPrincipal = llueveEnAlgunaZona != _lluvia;
      final bool cambioTrapiches = llueveEnTrapiches != _lluviaTrapiches;

      if (cambioPrincipal || cambioTrapiches) {
        await _guardarLluvia(
          llueveEnAlgunaZona,
          modo: 'auto',
          lluviaTrapiches: llueveEnTrapiches,
        );
      }
    } catch (e) {
      debugPrint('RecargosPanel: API clima falló → $e (sin cambio)');
    }
  }

  Future<void> _guardarLluvia(
    bool activa, {
    String modo = 'manual',
    bool? lluviaTrapiches,
  }) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      await Supabase.instance.client
          .from('config_sistema')
          .update({
            'lluvia_activa': activa,
            'lluvia_modo': modo,
            'lluvia_activada_at': activa
                ? DateTime.now().toUtc().toIso8601String()
                : null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
            // Actualizar lluvia_trapiches si viene del API automático
            if (lluviaTrapiches != null)
              'lluvia_trapiches': lluviaTrapiches,
            // Al activar manualmente, Trapiches se asume igual que el global
            if (lluviaTrapiches == null && modo == 'manual')
              'lluvia_trapiches': activa,
          })
          .eq('id', 1);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // -----------------------------------------------------------------------
  // CÁLCULOS
  // -----------------------------------------------------------------------
  int get _recargoTotal =>
      (_lluvia ? _recargoLluvia : 0) + (_nocturno ? _recargoNocturno : 0);

  int get _minimaActual => _nocturno ? _minimaBase : 0;

  void _notificarPadre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onCambio(
          EstadoRecargos(
            lluvia: _lluvia,
            nocturno: _nocturno,
            sobrecarga: _sobrecarga,
            recargo: _recargoTotal,
            minimaActual: _minimaActual,
          ),
        );
      }
    });
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _recargoTotal > 0 ? Colors.orange[300]! : Colors.black12,
          width: _recargoTotal > 0 ? 1.5 : 1,
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CABECERA — siempre visible
          _buildCabecera(),

          // DETALLE — expandible
          if (_expandido || widget.siempreExpandido) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _buildFilaLluvia(),
                  const SizedBox(height: 8),
                  _buildFilaNocturno(),
                  const SizedBox(height: 8),
                  _buildFilaSobrecarga(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCabecera() {
    return InkWell(
      onTap: widget.siempreExpandido
          ? null
          : () => setState(() => _expandido = !_expandido),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Indicadores rápidos
            if (_lluvia) ...[
              const Icon(Icons.water_drop, color: Colors.blue, size: 16),
              const SizedBox(width: 4),
            ],
            if (_nocturno) ...[
              const Icon(Icons.nights_stay, color: Colors.indigo, size: 16),
              const SizedBox(width: 4),
            ],
            if (_sobrecarga) ...[
              const Icon(Icons.inventory_2, color: Colors.brown, size: 16),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                _recargoTotal > 0 ? 'Recargos activos' : 'Sin recargos activos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _recargoTotal > 0
                      ? Colors.orange[800]
                      : Colors.black54,
                ),
              ),
            ),
            if (_recargoTotal > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Text(
                  '+\$${_formatPeso(_recargoTotal)}',
                  style: TextStyle(
                    color: Colors.orange[800],
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            if (!widget.siempreExpandido) ...[
              const SizedBox(width: 8),
              Icon(
                _expandido ? Icons.expand_less : Icons.expand_more,
                color: Colors.black38,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilaLluvia() {
    return Row(
      children: [
        Icon(
          Icons.water_drop,
          color: _lluvia ? Colors.blue : Colors.black26,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lluvia (+\$${_formatPeso(_recargoLluvia)})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _modoLluvia == 'auto'
                    ? (_apiActiva
                          ? 'Automático · API clima activa'
                          : 'Sin API — toggle manual disponible')
                    : 'Activado manualmente',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        // Toggle manual (siempre disponible)
        GestureDetector(
          onTap: _guardando
              ? null
              : () => _guardarLluvia(!_lluvia, modo: 'manual'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 24,
            decoration: BoxDecoration(
              color: _lluvia ? Colors.blue : Colors.black12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: _lluvia ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(3),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilaNocturno() {
    return Row(
      children: [
        Icon(
          Icons.nights_stay,
          color: _nocturno ? Colors.indigo : Colors.black26,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nocturno (+\$${_formatPeso(_recargoNocturno)})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Automático · ${_horaInicioNocturno.toString().padLeft(2, '0')}:00 – '
                '${_horaFinNocturno.toString().padLeft(2, '0')}:00',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              if (_nocturno)
                Text(
                  'Mínima: \$${_formatPeso(_minimaBase)}',
                  style: const TextStyle(fontSize: 10, color: Colors.indigo),
                ),
            ],
          ),
        ),
        // Indicador (no modificable, es automático)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _nocturno ? Colors.indigo[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _nocturno ? 'ACTIVO' : 'INACTIVO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _nocturno ? Colors.indigo : Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilaSobrecarga() {
    return Row(
      children: [
        Icon(
          Icons.inventory_2,
          color: _sobrecarga ? Colors.brown : Colors.black26,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Carga sobredimensionada',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                'Precio libre — Central define el monto',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        Checkbox(
          value: _sobrecarga,
          activeColor: Colors.brown,
          onChanged: (val) {
            setState(() => _sobrecarga = val ?? false);
            _notificarPadre();
          },
        ),
      ],
    );
  }

  String _formatPeso(int valor) {
    if (valor >= 1000) {
      return '${(valor / 1000).toStringAsFixed(valor % 1000 == 0 ? 0 : 1)}k';
    }
    return valor.toString();
  }
}
