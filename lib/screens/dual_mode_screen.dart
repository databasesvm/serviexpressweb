// lib/screens/dual_mode_screen.dart
//
// PANTALLA DUAL — Central + Móvil en paralelo (IndexedStack)
// ============================================================
// Solo para cuentas con es_dual = true (ej. Master id=1).
// Ambas pantallas se mantienen vivas simultáneamente:
//   - CentralScreen (índice 0): recibe cotizaciones, gestiona flota
//   - MovilScreen   (índice 1): recibe servicios, acepta como Móvil 00
//
// Un FAB flotante permite cambiar de modo sin destruir ninguna pantalla.
// Badge naranja en el FAB indica servicios SE pendientes sin asignar
// cuando el usuario está en vista Central.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'central_screen.dart';
import 'movil_screen.dart';

class DualModeScreen extends StatefulWidget {
  final Map<String, dynamic> usuario;
  /// 'central' o 'movil' — modo que se muestra al arrancar
  final String modoInicial;

  const DualModeScreen({
    super.key,
    required this.usuario,
    this.modoInicial = 'central',
  });

  @override
  State<DualModeScreen> createState() => _DualModeScreenState();
}

class _DualModeScreenState extends State<DualModeScreen> {
  // 0 = CentralScreen, 1 = MovilScreen
  late int _modoActual;

  // Contador liviano de servicios SE pendientes (para el badge del FAB)
  int _pendientesSE = 0;
  StreamSubscription? _subPendientes;

  @override
  void initState() {
    super.initState();
    _modoActual = widget.modoInicial == 'movil' ? 1 : 0;
    _suscribirPendientesSE();
  }

  /// Stream liviano: servicios SE pendientes sin asignar.
  /// Solo cuenta — no carga datos pesados.
  void _suscribirPendientesSE() {
    _subPendientes = Supabase.instance.client
        .from('servicios')
        .stream(primaryKey: ['id'])
        .eq('estado', 'pendiente')
        .listen((rows) {
          if (!mounted) return;
          final count = rows.where((s) =>
              s['tipo_fn'] != true && s['movil_id'] == null).length;
          setState(() => _pendientesSE = count);
        });
  }

  @override
  void dispose() {
    _subPendientes?.cancel();
    super.dispose();
  }

  void _cambiarModo() {
    setState(() => _modoActual = _modoActual == 0 ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Ambas pantallas activas simultáneamente ──────────────────────
        IndexedStack(
          index: _modoActual,
          children: [
            CentralScreen(usuario: widget.usuario),
            MovilScreen(usuario: widget.usuario),
          ],
        ),

        // ── FAB flotante de cambio de modo ───────────────────────────────
        Positioned(
          right: 16,
          bottom: 90,
          child: _ToggleModoFab(
            enCentral: _modoActual == 0,
            pendientesSE: _pendientesSE,
            onTap: _cambiarModo,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAB DE CAMBIO DE MODO
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleModoFab extends StatelessWidget {
  final bool enCentral;
  final int pendientesSE;
  final VoidCallback onTap;

  const _ToggleModoFab({
    required this.enCentral,
    required this.pendientesSE,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool mostrarBadge = enCentral && pendientesSE > 0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Botón principal
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: enCentral
                  ? const Color(0xFF3AF500)   // verde: ir a Móvil
                  : const Color(0xFF7C3AED),  // violeta: ir a Central
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (enCentral
                      ? const Color(0xFF3AF500)
                      : const Color(0xFF7C3AED)).withValues(alpha: 0.45),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              enCentral
                  ? Icons.motorcycle_rounded
                  : Icons.dashboard_rounded,
              color: enCentral ? Colors.black : Colors.white,
              size: 26,
            ),
          ),

          // Badge: servicios pendientes mientras está en Central
          if (mostrarBadge)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  '$pendientesSE',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Etiqueta inferior
          Positioned(
            bottom: -18,
            left: 0,
            right: 0,
            child: Text(
              enCentral ? 'Móvil 00' : 'Central',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
