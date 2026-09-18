// lib/utils/permisos_criticos.dart
//
// VERIFICACIÓN ESTRICTA DE PERMISOS — Pantalla de entrada condicional
// =====================================================================
// Sin estos permisos activos, las notificaciones y el GPS fallan en
// segundo plano — la causa #1 de "no me llegó la alerta" reportada en
// la prueba piloto.
//
// CONFIGURABLE POR ROL: en vez de duplicar esta pantalla para cada
// rol, recibe QUÉ permisos exigir vía `permisosRequeridos`:
//   - Móvil: los 3 (gate completo — depende de GPS continuo)
//   - Local: solo Notificaciones + Batería (opera la app por horas
//     largas esperando cotizaciones y chat, pero no necesita GPS
//     siempre)
//
// El chequeo SIEMPRE corre en SEGUNDO PLANO primero
// (hayPermisosPendientes, método estático) — la pantalla solo se
// muestra si de verdad falta algo del set pedido para ESE rol.
//
// 3 verificaciones, todas automáticas vía API:
//   1. Notificaciones
//   2. Ubicación "Permitir siempre"
//   3. Batería sin restricción
//
// REQUIERE EL PAQUETE permission_handler.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

// =========================================================================
// RECORDATORIO SUAVE DE NOTIFICACIONES — para roles de baja fricción
// (Cliente). A diferencia de PermisosCriticosScreen, esto NUNCA
// bloquea: es un aviso completamente descartable. Se vuelve a mostrar
// la PRÓXIMA VEZ que abran la app si para entonces siguen sin
// activarlas, pero jamás impide usar la app en el momento.
// =========================================================================
Future<void> verificarNotificacionesSuave(BuildContext context) async {
  try {
    final estado = await Permission.notification.status;
    if (estado.isGranted) return;

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: Colors.orange[800]),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Notificaciones desactivadas',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: const Text(
          'Sin notificaciones no sabrás cuándo cambia el estado de tu '
          'pedido a menos que abras la app a revisar. ¿Quieres activarlas?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ahora no', style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () async {
              Navigator.pop(ctx);
              await Permission.notification.request();
            },
            child: const Text(
              'ACTIVAR',
              style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  } catch (_) {
    // Si falla la consulta, no interrumpimos al cliente por esto.
  }
}

// =========================================================================
// QUÉ PERMISOS EXISTEN — cada rol pide un subconjunto de estos.
// =========================================================================
enum TipoPermiso {
  notificaciones,
  ubicacionSiempre,
  bateria,
}

// Set BLOQUEANTE — el gate fuerte que usa Móvil.
const Set<TipoPermiso> kPermisosCompletosMovil = {
  TipoPermiso.notificaciones,
  TipoPermiso.ubicacionSiempre,
  TipoPermiso.bateria,
};

// Set liviano — el gate de Local: solo lo que de verdad necesita para
// operar horas largas esperando cotizaciones y chat. No necesita GPS
// "siempre" (su ubicación es fija).
const Set<TipoPermiso> kPermisosLocal = {
  TipoPermiso.notificaciones,
  TipoPermiso.bateria,
};

class PermisosCriticosScreen extends StatefulWidget {
  final Set<TipoPermiso> permisosRequeridos;

  const PermisosCriticosScreen({
    super.key,
    this.permisosRequeridos = kPermisosCompletosMovil,
  });

  // =========================================================================
  // CHEQUEO SILENCIOSO — sin UI. Llamar ANTES de decidir si hace falta
  // mostrar la pantalla completa. Devuelve true solo si falta algo del
  // set de permisos pedido para ESE rol.
  // =========================================================================
  static Future<bool> hayPermisosPendientes({
    Set<TipoPermiso> permisosRequeridos = kPermisosCompletosMovil,
  }) async {
    if (kIsWeb) return false;
    try {
      if (permisosRequeridos.contains(TipoPermiso.notificaciones)) {
        if (!(await Permission.notification.status).isGranted) return true;
      }
      if (permisosRequeridos.contains(TipoPermiso.ubicacionSiempre)) {
        if (!(await Permission.locationAlways.status).isGranted) return true;
      }
      if (permisosRequeridos.contains(TipoPermiso.bateria)) {
        if (!(await Permission.ignoreBatteryOptimizations.status).isGranted) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return true;
    }
  }

  @override
  State<PermisosCriticosScreen> createState() =>
      _PermisosCriticosScreenState();
}

class _PermisosCriticosScreenState extends State<PermisosCriticosScreen>
    with WidgetsBindingObserver {
  bool _notificaciones = false;
  bool _ubicacionSiempre = false;
  bool _bateriaSinRestriccion = false;
  bool _verificando = true;

  bool _pide(TipoPermiso t) => widget.permisosRequeridos.contains(t);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verificarTodo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarTodo();
    }
  }

  Future<void> _verificarTodo() async {
    if (!mounted) return;
    if (kIsWeb) { setState(() => _verificando = false); return; }
    setState(() => _verificando = true);

    final notif = await Permission.notification.status;
    final ubic = await Permission.locationAlways.status;
    final bateria = await Permission.ignoreBatteryOptimizations.status;

    if (!mounted) return;
    setState(() {
      _notificaciones = notif.isGranted;
      _ubicacionSiempre = ubic.isGranted;
      _bateriaSinRestriccion = bateria.isGranted;
      _verificando = false;
    });
  }

  bool get _todoListo {
    if (_pide(TipoPermiso.notificaciones) && !_notificaciones) return false;
    if (_pide(TipoPermiso.ubicacionSiempre) && !_ubicacionSiempre) return false;
    if (_pide(TipoPermiso.bateria) && !_bateriaSinRestriccion) return false;
    return true;
  }

  Future<void> _pedirNotificaciones() async {
    await Permission.notification.request();
    _verificarTodo();
  }

  Future<void> _pedirUbicacion() async {
    await Permission.locationWhenInUse.request();
    if (!mounted) return;
    await Permission.locationAlways.request();
    _verificarTodo();
  }

  Future<void> _pedirBateria() async {
    await Permission.ignoreBatteryOptimizations.request();
    _verificarTodo();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Icon(Icons.shield_rounded, color: Color(0xff3AF500), size: 56),
                const SizedBox(height: 16),
                const Text(
                  'ACCESO DESDE NAVEGADOR',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Estás usando la app desde el navegador. Los permisos de GPS y '
                  'notificaciones en segundo plano no están disponibles en web.\n\n'
                  'Para mejor rendimiento, usa la app instalada en tu teléfono.',
                  style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3AF500)),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      'CONTINUAR DE TODAS FORMAS',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _todoListo,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Icon(
                  Icons.shield_rounded,
                  color: Color(0xff3AF500),
                  size: 56,
                ),
                const SizedBox(height: 16),
                const Text(
                  'PERMISOS CRÍTICOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sin esto, las alertas pueden no llegarte con el teléfono '
                  'guardado o la pantalla apagada. Esta pantalla solo '
                  'aparece si falta algo por activar.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (_pide(TipoPermiso.notificaciones))
                          _filaPermiso(
                            icono: Icons.notifications_active,
                            titulo: 'Notificaciones',
                            descripcion: 'Para recibir alertas de servicios nuevos',
                            concedido: _notificaciones,
                            onActivar: _pedirNotificaciones,
                          ),
                        if (_pide(TipoPermiso.ubicacionSiempre))
                          _filaPermiso(
                            icono: Icons.location_on,
                            titulo: 'Ubicación: "Permitir siempre"',
                            descripcion:
                                'No "solo mientras se usa" — el radar '
                                'necesita tu GPS aunque la pantalla esté '
                                'apagada',
                            concedido: _ubicacionSiempre,
                            onActivar: _pedirUbicacion,
                          ),
                        if (_pide(TipoPermiso.bateria))
                          _filaPermiso(
                            icono: Icons.battery_charging_full,
                            titulo: 'Batería sin restricción',
                            descripcion:
                                'Evita que Android cierre la app sola en '
                                'segundo plano',
                            concedido: _bateriaSinRestriccion,
                            onActivar: _pedirBateria,
                          ),
                      ],
                    ),
                  ),
                ),

                if (!_todoListo && !_verificando)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () => openAppSettings(),
                        icon: const Icon(Icons.settings, color: Colors.white38, size: 16),
                        label: const Text(
                          '¿Algo no se activa? Abrir ajustes de la app',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _todoListo
                          ? const Color(0xff3AF500)
                          : Colors.grey[800],
                    ),
                    onPressed: _todoListo
                        ? () => Navigator.of(context).pop(true)
                        : null,
                    child: Text(
                      _todoListo ? 'CONTINUAR' : 'Activa los 3 permisos para continuar',
                      style: TextStyle(
                        color: _todoListo ? Colors.black : Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaPermiso({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required bool concedido,
    required VoidCallback onActivar,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: concedido ? const Color(0xff3AF500) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icono,
            color: concedido ? const Color(0xff3AF500) : Colors.white38,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  descripcion,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (concedido)
            const Icon(Icons.check_circle, color: Color(0xff3AF500))
          else
            TextButton(
              onPressed: onActivar,
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xff3AF500),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text(
                'ACTIVAR',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
