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
//   - Móvil: los 5 (gate completo — depende de GPS continuo)
//   - Local: solo Notificaciones + Batería (opera la app por horas
//     largas esperando cotizaciones y chat, pero no necesita GPS
//     siempre ni superposición)
//
// El chequeo SIEMPRE corre en SEGUNDO PLANO primero
// (hayPermisosPendientes, método estático) — la pantalla solo se
// muestra si de verdad falta algo del set pedido para ESE rol.
//
// 5 verificaciones posibles, 4 automáticas + 1 de confirmación manual:
//   1. Notificaciones — verificable por API
//   2. Ubicación "Permitir siempre" — verificable por API
//   3. Batería sin restricción — verificable por API
//   4. Superposición sobre otras apps — verificable por API
//   5. "Pausar app si no se usa" — Android NO expone una API para que
//      una app consulte el estado de este ajuste específico. Se pide
//      una confirmación manual del usuario, que se recuerda para
//      siempre (no se vuelve a pedir una vez confirmada).
//
// REQUIERE LOS PAQUETES permission_handler y shared_preferences.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kPrefAppsNoUsadas = 'confirmo_apps_no_usadas_desactivado';

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
    if (estado.isGranted) return; // todo bien, no molestamos a nadie

    if (!context.mounted) return;
    await showDialog(
      context: context,
      // Sin barrierDismissible:false — se puede cerrar tocando fuera,
      // a propósito: este aviso nunca debe sentirse como un bloqueo.
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
  superposicion,
  appsNoUsadas,
}

// Set BLOQUEANTE — el gate fuerte que usa Móvil. Default del widget
// para no romper los call sites que ya existían antes de esto.
//
// 'superposicion' NO está aquí a propósito: en algunos teléfonos viene
// como un ajuste restringido del fabricante que un usuario sin
// conocimientos técnicos no logra desbloquear por su cuenta (probado
// en campo). No tiene sentido dejar a alguien sin poder usar la app
// por un permiso que ni siquiera depende de él resolver fácil.
const Set<TipoPermiso> kPermisosCompletosMovil = {
  TipoPermiso.notificaciones,
  TipoPermiso.ubicacionSiempre,
  TipoPermiso.bateria,
  TipoPermiso.appsNoUsadas,
};

// Superposición es opcional: mejora las alertas si el teléfono lo permite,
// pero no bloquea el acceso — algunos fabricantes lo restringen por hardware.
const Set<TipoPermiso> kPermisosOpcionalesMovil = {
  TipoPermiso.superposicion,
};

// Set liviano — el gate de Local: solo lo que de verdad necesita para
// operar horas largas esperando cotizaciones y chat. No necesita GPS
// "siempre" (su ubicación es fija) ni superposición.
const Set<TipoPermiso> kPermisosLocal = {
  TipoPermiso.notificaciones,
  TipoPermiso.bateria,
};

class PermisosCriticosScreen extends StatefulWidget {
  final Set<TipoPermiso> permisosRequeridos;
  // Se muestran en la lista con su botón de activar, pero su ausencia
  // NUNCA impide tocar "CONTINUAR".
  final Set<TipoPermiso> permisosOpcionales;

  const PermisosCriticosScreen({
    super.key,
    this.permisosRequeridos = kPermisosCompletosMovil,
    this.permisosOpcionales = const {},
  });

  // =========================================================================
  // CHEQUEO SILENCIOSO — sin UI. Llamar ANTES de decidir si hace falta
  // mostrar la pantalla completa. Devuelve true solo si falta algo del
  // set de permisos pedido para ESE rol.
  // =========================================================================
  static Future<bool> hayPermisosPendientes({
    Set<TipoPermiso> permisosRequeridos = kPermisosCompletosMovil,
  }) async {
    // En web los APIs de permisos nativos no existen — skip total.
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
      if (permisosRequeridos.contains(TipoPermiso.superposicion)) {
        if (!(await Permission.systemAlertWindow.status).isGranted) return true;
      }
      if (permisosRequeridos.contains(TipoPermiso.appsNoUsadas)) {
        final prefs = await SharedPreferences.getInstance();
        if (!(prefs.getBool(_kPrefAppsNoUsadas) ?? false)) return true;
      }
      return false;
    } catch (_) {
      // Si algo falla al consultar, preferimos mostrar la pantalla a
      // arriesgarnos a que falten permisos sin que nadie se entere.
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
  bool _sinSuperposicionBloqueada = false;
  bool _appsNoUsadasConfirmado = false;
  bool _verificando = true;

  bool _pide(TipoPermiso t) => widget.permisosRequeridos.contains(t);
  bool _esOpcional(TipoPermiso t) => widget.permisosOpcionales.contains(t);
  // Se MUESTRA si está en cualquiera de los dos sets — requerido u
  // opcional. Solo lo requerido bloquea _todoListo.
  bool _seMuestra(TipoPermiso t) => _pide(t) || _esOpcional(t);

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
    // El usuario suele conceder estos permisos desde Ajustes del sistema,
    // no desde un diálogo in-app. Al volver a la app, re-verificamos solo.
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
    final overlay = await Permission.systemAlertWindow.status;

    final prefs = await SharedPreferences.getInstance();
    final appsNoUsadas = prefs.getBool(_kPrefAppsNoUsadas) ?? false;

    if (!mounted) return;
    setState(() {
      _notificaciones = notif.isGranted;
      _ubicacionSiempre = ubic.isGranted;
      _bateriaSinRestriccion = bateria.isGranted;
      _sinSuperposicionBloqueada = overlay.isGranted;
      _appsNoUsadasConfirmado = appsNoUsadas;
      _verificando = false;
    });
  }

  // Solo exige los puntos que ESTE rol realmente pidió — los demás ni
  // se evalúan para decidir si puede continuar.
  bool get _todoListo {
    if (_pide(TipoPermiso.notificaciones) && !_notificaciones) return false;
    if (_pide(TipoPermiso.ubicacionSiempre) && !_ubicacionSiempre) {
      return false;
    }
    if (_pide(TipoPermiso.bateria) && !_bateriaSinRestriccion) return false;
    if (_pide(TipoPermiso.superposicion) && !_sinSuperposicionBloqueada) {
      return false;
    }
    if (_pide(TipoPermiso.appsNoUsadas) && !_appsNoUsadasConfirmado) {
      return false;
    }
    return true;
  }

  Future<void> _pedirNotificaciones() async {
    await Permission.notification.request();
    _verificarTodo();
  }

  Future<void> _pedirUbicacion() async {
    // Android exige pedir "mientras se usa" PRIMERO; "siempre" es un
    // segundo diálogo separado que el sistema no deja combinar en uno.
    await Permission.locationWhenInUse.request();
    if (!mounted) return;
    await Permission.locationAlways.request();
    _verificarTodo();
  }

  Future<void> _pedirBateria() async {
    await Permission.ignoreBatteryOptimizations.request();
    _verificarTodo();
  }

  Future<void> _pedirSuperposicion() async {
    await Permission.systemAlertWindow.request();
    _verificarTodo();
  }

  // Android no expone una API para consultar este ajuste — solo
  // podemos llevar al usuario a la pantalla correcta y confiar en su
  // confirmación. Una vez confirmado, se recuerda para siempre.
  Future<void> _confirmarAppsNoUsadas() async {
    await openAppSettings();
    if (!mounted) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('¿Ya lo desactivaste?'),
        content: const Text(
          'Busca "Aplicaciones no utilizadas frecuentemente" o "Pausar '
          'actividad de la app si no se usa" (el nombre exacto varía según '
          'tu teléfono, suele estar en Batería o Permisos) y desactívalo '
          'para ServiExpress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Todavía no'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'SÍ, YA LO DESACTIVÉ',
              style: TextStyle(color: Color(0xff3AF500)),
            ),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefAppsNoUsadas, true);
      _verificarTodo();
    }
  }

  @override
  Widget build(BuildContext context) {
    // En web no existen los permisos nativos — mostrar aviso y permitir
    // continuar de inmediato sin bloquear.
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
      // Siempre se puede salir: el botón OMITIR y el botón Atrás cierran la
      // pantalla. Si faltan permisos requeridos, la pantalla reaparecerá
      // automáticamente en el próximo inicio de sesión.
      canPop: true,
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
                        if (_seMuestra(TipoPermiso.notificaciones))
                          _filaPermiso(
                            icono: Icons.notifications_active,
                            titulo: 'Notificaciones',
                            descripcion:
                                'Para recibir alertas de servicios nuevos',
                            concedido: _notificaciones,
                            onActivar: _pedirNotificaciones,
                          ),
                        if (_seMuestra(TipoPermiso.ubicacionSiempre))
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
                        if (_seMuestra(TipoPermiso.bateria))
                          _filaPermiso(
                            icono: Icons.battery_charging_full,
                            titulo: 'Batería sin restricción',
                            descripcion:
                                'Evita que Android cierre la app sola en '
                                'segundo plano',
                            concedido: _bateriaSinRestriccion,
                            onActivar: _pedirBateria,
                          ),
                        if (_seMuestra(TipoPermiso.superposicion))
                          _filaPermiso(
                            icono: Icons.picture_in_picture_alt,
                            titulo: _esOpcional(TipoPermiso.superposicion)
                                ? 'Superposición sobre otras apps (opcional)'
                                : 'Superposición sobre otras apps',
                            descripcion: _esOpcional(TipoPermiso.superposicion)
                                ? 'Mejora las alertas críticas si tu '
                                  'teléfono lo permite — algunos modelos '
                                  'lo restringen y no es necesario para '
                                  'seguir usando la app'
                                : 'Deja que las alertas críticas se '
                                  'muestren sin importar qué estés usando',
                            concedido: _sinSuperposicionBloqueada,
                            onActivar: _pedirSuperposicion,
                          ),
                        if (_seMuestra(TipoPermiso.appsNoUsadas))
                          _filaPermiso(
                            icono: Icons.layers_clear,
                            titulo: '"Pausar app si no se usa" — desactivado',
                            descripcion:
                                'Android no nos deja verificar esto solos '
                                '— confírmalo tú una vez y no se vuelve a '
                                'pedir',
                            concedido: _appsNoUsadasConfirmado,
                            onActivar: _confirmarAppsNoUsadas,
                            esManual: true,
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
                        icon: const Icon(
                          Icons.settings,
                          color: Colors.white38,
                          size: 16,
                        ),
                        label: const Text(
                          '¿Algo no se activa? Abrir ajustes de la app',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
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
                      _todoListo
                          ? 'CONTINUAR'
                          : 'Activa todo para continuar',
                      style: TextStyle(
                        color: _todoListo ? Colors.black : Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                // Omitir — solo visible cuando faltan permisos. No guarda ningún
                // flag: la pantalla reaparece en el próximo inicio de sesión.
                if (!_todoListo && !_verificando)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'OMITIR — se pedirá de nuevo al iniciar sesión',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
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
    bool esManual = false,
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
              child: Text(
                esManual ? 'CONFIRMAR' : 'ACTIVAR',
                style: const TextStyle(
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
