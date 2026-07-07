// lib/utils/panico_widgets.dart
//
// BOTÓN DE PÁNICO — WIDGETS COMPARTIDOS
// =======================================
// BotonPanico        → núcleo: anillo de progreso + hold para activar.
//                       Tamaño configurable vía `tamano`.
//
// PanicoConfirmDialog → diálogo central con el botón GRANDE + instrucciones
//                       visibles permanentemente (no depende de tooltips).
//
// BotonPanicoTrigger  → ícono pequeño (AppBar / tarjetas). Un tap abre
//                       PanicoConfirmDialog. Evita activaciones accidentales
//                       porque el hold real ocurre en el diálogo, a pantalla
//                       completa, con instrucciones siempre visibles.
//
// PanicoOverlay       → pantalla pulsante que ven los RECEPTORES de la
//                       alerta. Auto-cierre de seguridad a los 60s si nadie
//                       presiona "Entendido".
//
// mostrarConfirmacionDiscreta → toast pequeño y neutral para QUIEN DISPARA.
//                       Sin colores de alarma, sin sonido. Confirma que la
//                       señal salió sin delatar al usuario frente a terceros.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/sonido_manager.dart';

// =========================================================================
// BOTÓN DE PÁNICO — Núcleo: anillo de progreso + hold para activar
// =========================================================================
class BotonPanico extends StatefulWidget {
  final VoidCallback onActivado;
  final double segundos;
  final bool esCompacto;
  final IconData icono;
  final double? tamano;

  const BotonPanico({
    super.key,
    required this.onActivado,
    this.segundos = 2.0,
    this.esCompacto = false,
    this.icono = Icons.shield_rounded,
    this.tamano,
  });

  @override
  State<BotonPanico> createState() => _BotonPanicoState();
}

class _BotonPanicoState extends State<BotonPanico>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _completado = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.segundos * 1000).toInt()),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_completado) {
        _completado = true;
        _ctrl.reset();
        widget.onActivado();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _completado = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _iniciar(dynamic _) {
    if (!_completado) _ctrl.forward();
  }

  void _cancelar(dynamic _) {
    if (!_completado) _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final double size = widget.tamano ?? (widget.esCompacto ? 38.0 : 58.0);
    final double iconSize = size * 0.42;
    final double stroke = (size * 0.07).clamp(2.5, 10.0);

    return Listener(
      onPointerDown: _iniciar,
      onPointerUp: _cancelar,
      onPointerCancel: _cancelar,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: _ctrl.value,
                  color: Colors.red,
                  backgroundColor: Colors.red.withValues(alpha: 0.2),
                  strokeWidth: stroke,
                ),
              ),
              Container(
                width: size - 8,
                height: size - 8,
                decoration: BoxDecoration(
                  color: _completado ? Colors.grey : Colors.red[800],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: _ctrl.value * 0.6),
                      blurRadius: 12,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(widget.icono, color: Colors.white, size: iconSize),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =========================================================================
// DIÁLOGO DE CONFIRMACIÓN — Botón grande + instrucciones siempre visibles
// =========================================================================
class PanicoConfirmDialog extends StatelessWidget {
  final VoidCallback onActivado;
  /// Si se provee, muestra un botón "Detener alerta activa" en el diálogo.
  final VoidCallback? onDetener;
  final double segundos;
  final IconData icono;
  final String titulo;
  final String descripcion;
  final Color colorAcento;

  const PanicoConfirmDialog({
    super.key,
    required this.onActivado,
    this.onDetener,
    required this.titulo,
    required this.descripcion,
    this.segundos = 2.0,
    this.icono = Icons.shield_rounded,
    this.colorAcento = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, color: colorAcento, size: 36),
            const SizedBox(height: 12),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              descripcion,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            BotonPanico(
              segundos: segundos,
              icono: icono,
              tamano: 110,
              onActivado: () {
                Navigator.of(context).pop();
                onActivado();
              },
            ),
            const SizedBox(height: 18),
            Text(
              'Mantén presionado ${segundos.toInt()} segundos',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 20),

            // DETENER ALERTA — solo si hay una activa (callback provisto)
            if (onDetener != null) ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[300],
                  side: BorderSide(color: Colors.red[300]!),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onDetener!();
                },
                icon: const Icon(Icons.notifications_off_rounded, size: 16),
                label: const Text(
                  'DETENER ALERTA ACTIVA',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            // HISTORIAL DE ALERTAS — debajo del botón grande
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop(); // cierra el diálogo
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PanicoHistorialScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.history, size: 16, color: Colors.white54),
              label: const Text(
                'Ver historial de alertas',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),

            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'CANCELAR',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================================================================
// BOTÓN LANZADOR — Ícono pequeño (AppBar/tarjetas). Un tap abre el diálogo.
// =========================================================================
class BotonPanicoTrigger extends StatelessWidget {
  final VoidCallback onActivado;
  /// Si se provee, muestra "Detener alerta activa" dentro del diálogo.
  final VoidCallback? onDetener;
  final String titulo;
  final String descripcion;
  final double segundos;
  final bool esCompacto;
  final IconData icono;
  final Color colorAcento;

  const BotonPanicoTrigger({
    super.key,
    required this.onActivado,
    this.onDetener,
    required this.titulo,
    required this.descripcion,
    this.segundos = 2.0,
    this.esCompacto = false,
    this.icono = Icons.shield_rounded,
    this.colorAcento = Colors.red,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icono, color: colorAcento, size: esCompacto ? 20 : 24),
      tooltip: titulo,
      onPressed: () {
        showDialog(
          context: context,
          builder: (_) => PanicoConfirmDialog(
            onActivado: onActivado,
            onDetener: onDetener,
            segundos: segundos,
            icono: icono,
            titulo: titulo,
            descripcion: descripcion,
            colorAcento: colorAcento,
          ),
        );
      },
    );
  }
}

// =========================================================================
// OVERLAY DE PÁNICO — Lo ven los RECEPTORES. Auto-cierre a los 60s.
// =========================================================================
class PanicoOverlay extends StatefulWidget {
  final String disparadoPor;
  /// MOVIL## o usuario del disparador (opcional — null para central/master)
  final String? usuarioDisparador;
  final String rolDisparador;

  /// ID del evento en eventos_panico — necesario para abrir el mapa en vivo.
  final int? eventoId;

  /// true si rolDisparador == 'movil' Y hay ubicación vigente (no expirada).
  final bool tieneUbicacion;

  const PanicoOverlay({
    super.key,
    required this.disparadoPor,
    this.usuarioDisparador,
    required this.rolDisparador,
    this.eventoId,
    this.tieneUbicacion = false,
  });

  @override
  State<PanicoOverlay> createState() => _PanicoOverlayState();
}

class _PanicoOverlayState extends State<PanicoOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulso;
  late Animation<double> _opacidad;
  Timer? _autoDescarte;

  static const Duration _duracionMaxima = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();

    _pulso = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _opacidad = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SonidoManager().reproducirPanico();
      // Activar pantalla sobre bloqueo (solo Android/iOS, no web)
      if (!kIsWeb) {
        const MethodChannel('com.serviexpress.app/panico')
            .invokeMethod('activarPantalla')
            .catchError((_) {});
      }
    });

    _autoDescarte = Timer(_duracionMaxima, () {
      if (mounted) Navigator.of(context).pop();
    });

    // CIERRE REMOTO: cuando el móvil presiona "Ya estoy bien",
    // actualiza ubicacion_expira_at al pasado. Este canal lo detecta
    // y cierra el overlay en todos los dispositivos que lo están viendo.
    if (widget.eventoId != null) {
      Supabase.instance.client
          .channel('panico_overlay_${widget.eventoId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'eventos_panico',
            callback: (payload) {
              final doc = payload.newRecord;
              if (doc.isEmpty || !mounted) return;
              if (doc['id'].toString() != widget.eventoId.toString()) return;
              final expiraStr = doc['ubicacion_expira_at']?.toString();
              if (expiraStr == null) return;
              final expira = DateTime.tryParse(expiraStr)?.toUtc();
              if (expira != null && DateTime.now().toUtc().isAfter(expira)) {
                // El móvil ya está bien — cerramos el overlay silenciosamente
                _autoDescarte?.cancel();
                SonidoManager().detenerPanico();
                if (mounted) Navigator.of(context).pop();
              }
            },
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    _autoDescarte?.cancel();
    SonidoManager().detenerPanico();
    // Liberar flags de pantalla de bloqueo (solo Android/iOS, no web)
    if (!kIsWeb) {
      const MethodChannel('com.serviexpress.app/panico')
          .invokeMethod('desactivarPantalla')
          .catchError((_) {});
    }
    if (widget.eventoId != null) {
      Supabase.instance.client
          .channel('panico_overlay_${widget.eventoId}')
          .unsubscribe();
    }
    super.dispose();
  }

  bool get _esLlamadoCentral {
    final rol = widget.rolDisparador.toLowerCase();
    return rol == 'central' || rol == 'master';
  }

  String _etiquetaRol(String rol) {
    switch (rol.toLowerCase()) {
      case 'master':
        return 'MAESTRO';
      case 'central':
        return 'CENTRAL';
      case 'movil':
        return 'MÓVIL';
      default:
        return rol.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final IconData icono = _esLlamadoCentral
        ? Icons.campaign_rounded
        : Icons.warning_rounded;

    final Color colorBase = _esLlamadoCentral
        ? Colors.orange[800]!
        : Colors.red[900]!;

    final Color colorAcento = _esLlamadoCentral
        ? Colors.orange[700]!
        : Colors.red[700]!;

    final Color colorBoton = _esLlamadoCentral
        ? Colors.orange[900]!
        : Colors.red[900]!;

    final String titulo = _esLlamadoCentral
        ? '📢 LA CENTRAL TE SOLICITA'
        : '⚠️  ALERTA DE PÁNICO';

    final String etiquetaQuien = _esLlamadoCentral
        ? 'TE LLAMA'
        : 'DISPARADO POR';

    final String textoCuerpo = _esLlamadoCentral
        ? 'Estás siendo requerido de forma urgente.\nResponde o dirígete a la app de inmediato.'
        : 'Verifica la situación.\nInforma a los demás si estás a salvo.';

    return Dialog.fullscreen(
      child: AnimatedBuilder(
        animation: _opacidad,
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Color.lerp(colorBase, Colors.black, 1 - _opacidad.value)!,
                  Colors.black,
                ],
                radius: 1.4,
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Opacity(
                    opacity: _opacidad.value,
                    child: Icon(icono, size: 90, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      children: [
                        Text(
                          etiquetaQuien,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.disparadoPor,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.usuarioDisparador != null &&
                            widget.usuarioDisparador!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.usuarioDisparador!.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorAcento,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _etiquetaRol(widget.rolDisparador),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      textoCuerpo,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Esta alerta se cerrará automáticamente.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // UBICACIÓN EN VIVO — solo si rolDisparador == movil
                  // y la ventana de 24h sigue vigente
                  if (widget.tieneUbicacion && widget.eventoId != null) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () {
                        // Apagamos la alarma: en la pantalla del mapa se
                        // necesita silencio para pensar/comunicarse.
                        SonidoManager().detenerPanico();
                        // Cancelamos el auto-cierre: si el usuario está
                        // viendo el mapa, no queremos que el overlay se
                        // cierre solo "por debajo" mientras navega.
                        _autoDescarte?.cancel();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PanicoMapaScreen(
                              eventoId: widget.eventoId!,
                              nombrePersona: widget.disparadoPor,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.location_on, size: 18),
                      label: const Text(
                        'VER UBICACIÓN EN VIVO',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D0D0D),
                      foregroundColor: colorBoton,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: () {
                      SonidoManager().detenerPanico();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'ENTENDIDO — CERRAR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =========================================================================
// CONFIRMACIÓN DISCRETA — La ve SOLO quien dispara la alerta.
// Sin colores de alarma, sin sonido. Confirma que la señal salió sin
// delatar al usuario frente a terceros que puedan estar mirando su pantalla.
// =========================================================================
void mostrarConfirmacionDiscreta(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
          SizedBox(width: 8),
          Text(
            'Señal enviada',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF333333),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      width: 150,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
    ),
  );
}

// =========================================================================
// MAPA EN VIVO — Ubicación del disparador, vigente 24h desde el disparo.
// Solo aplica a alertas con rolDisparador == 'movil'.
// =========================================================================
class PanicoMapaScreen extends StatefulWidget {
  final int eventoId;
  final String nombrePersona;

  const PanicoMapaScreen({
    super.key,
    required this.eventoId,
    required this.nombrePersona,
  });

  @override
  State<PanicoMapaScreen> createState() => _PanicoMapaScreenState();
}

class _PanicoMapaScreenState extends State<PanicoMapaScreen> {
  final MapController _mapController = MapController();

  double? _lat;
  double? _lng;
  DateTime? _actualizadoAt;
  DateTime? _expiraAt;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarInicial();
    _suscribir();
  }

  @override
  void dispose() {
    Supabase.instance.client
        .channel('panico_mapa_${widget.eventoId}')
        .unsubscribe();
    super.dispose();
  }

  Future<void> _cargarInicial() async {
    try {
      final row = await Supabase.instance.client
          .from('eventos_panico')
          .select(
            'ultima_lat, ultima_lng, ubicacion_actualizada_at, ubicacion_expira_at',
          )
          .eq('id', widget.eventoId)
          .single();
      _actualizarDesde(row);
    } catch (e) {
      debugPrint('PanicoMapaScreen carga inicial: $e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _suscribir() {
    Supabase.instance.client
        .channel('panico_mapa_${widget.eventoId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'eventos_panico',
          callback: (payload) {
            final doc = payload.newRecord;
            if (doc.isEmpty) return;
            if (doc['id'] == widget.eventoId) {
              _actualizarDesde(doc);
            }
          },
        )
        .subscribe();
  }

  void _actualizarDesde(Map<String, dynamic> row) {
    if (!mounted) return;
    final nuevaLat = (row['ultima_lat'] as num?)?.toDouble();
    final nuevaLng = (row['ultima_lng'] as num?)?.toDouble();

    setState(() {
      _lat = nuevaLat;
      _lng = nuevaLng;
      _actualizadoAt = row['ubicacion_actualizada_at'] != null
          ? DateTime.parse(row['ubicacion_actualizada_at'].toString()).toLocal()
          : null;
      _expiraAt = row['ubicacion_expira_at'] != null
          ? DateTime.parse(row['ubicacion_expira_at'].toString()).toLocal()
          : null;
    });

    // Recentramos el mapa cuando llega una nueva posición
    if (nuevaLat != null && nuevaLng != null) {
      try {
        _mapController.move(
          LatLng(nuevaLat, nuevaLng),
          _mapController.camera.zoom,
        );
      } catch (_) {
        // El controller puede no estar listo aún en el primer frame
      }
    }
  }

  String _formatRelativo(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'hace ${diff.inSeconds}s';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return 'hace ${diff.inDays} d';
  }

  String _formatHora(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bool expirado =
        _expiraAt != null && DateTime.now().isAfter(_expiraAt!);
    final bool tieneUbicacion = _lat != null && _lng != null && !expirado;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Ubicación: ${widget.nombrePersona}',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : !tieneUbicacion
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_off, size: 48, color: Colors.grey[400]),
                    const SizedBox(height: 12),
                    Text(
                      expirado
                          ? 'La ubicación de esta alerta ya expiró (24h).'
                          : 'No hay ubicación disponible para esta alerta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(_lat!, _lng!),
                    initialZoom: 16.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.serviexpress.express',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_lat!, _lng!),
                          width: 50,
                          height: 50,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 44,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.my_location,
                          color: Color(0xff3AF500),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Actualizado ${_formatRelativo(_actualizadoAt)}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          'Vence ${_formatHora(_expiraAt)}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// =========================================================================
// HISTORIAL DE ALERTAS — Quién ha disparado pánico, cuándo, y de qué tipo.
// Accesible desde Central y Móvil (lectura habilitada vía RLS para todos).
// =========================================================================
class PanicoHistorialScreen extends StatefulWidget {
  const PanicoHistorialScreen({super.key});

  @override
  State<PanicoHistorialScreen> createState() => _PanicoHistorialScreenState();
}

class _PanicoHistorialScreenState extends State<PanicoHistorialScreen> {
  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Supabase.instance.client
        .from('eventos_panico')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100);
  }

  String _formatFecha(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Justo ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool _esCentral(Map<String, dynamic> ev) {
    final rol = (ev['rol_disparador'] ?? '').toString().toLowerCase();
    return rol == 'central' || rol == 'master';
  }

  bool _tieneUbicacionVigente(Map<String, dynamic> ev) {
    if (_esCentral(ev)) return false; // Central nunca comparte ubicación
    if (ev['ultima_lat'] == null || ev['ubicacion_expira_at'] == null) {
      return false;
    }
    final expira = DateTime.parse(ev['ubicacion_expira_at'].toString()).toUtc();
    return DateTime.now().toUtc().isBefore(expira);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: Text(
          'Historial de Alertas',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.black),
            );
          }

          final eventos = snapshot.data ?? [];
          if (eventos.isEmpty) {
            return const Center(
              child: Text(
                'Sin alertas registradas.',
                style: TextStyle(color: Colors.white38),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: eventos.length,
            itemBuilder: (context, index) {
              final ev = eventos[index];
              final bool esCentral = _esCentral(ev);
              final bool esIndividual = ev['tipo'] == 'individual';
              final bool tieneUbicacion = _tieneUbicacionVigente(ev);

              final String subtitulo = esCentral
                  ? (esIndividual
                        ? 'Llamó a ${ev['destino_nombre'] ?? '—'}'
                        : 'Convocatoria General')
                  : 'Alerta de Pánico';

              final Color color = esCentral ? Colors.orange : Colors.red;
              final IconData icono = esCentral
                  ? Icons.campaign_rounded
                  : Icons.warning_rounded;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icono, color: color, size: 20),
                  ),
                  title: Row(children: [
                    Flexible(
                      child: Text(
                        (ev['disparado_por_nombre'] ?? 'Desconocido').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (ev['disparado_por_usuario'] != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '#${ev['disparado_por_usuario']}',
                        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ]),
                  subtitle: Text(
                    '$subtitulo · ${_formatFecha(ev['created_at'].toString())}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: tieneUbicacion
                      ? IconButton(
                          icon: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                          ),
                          tooltip: 'Ver ubicación en vivo',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PanicoMapaScreen(
                                eventoId: ev['id'] as int,
                                nombrePersona:
                                    (ev['disparado_por_nombre'] ?? '')
                                        .toString(),
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
