// lib/screens/registro_screen.dart
//
// REGISTRO COMPLETO — REDISEÑO
// ==============================
// Antes: un formulario largo, 4 campos, sentía "básico". Ahora: un
// asistente de varios pasos (estilo Rappi/Uber) con progreso visible,
// validación por paso, fecha de nacimiento real (no "edad" suelta),
// correo obligatorio, confirmación de contraseña, y aceptación
// explícita de Términos y Política de Privacidad (exigido por Google
// Play y App Store para cualquier app que recoja datos personales).
//
// DIFERIDO A FUTURO (perfil del móvil, pendiente de construir):
// foto de perfil, foto de cédula, foto de licencia, placa de la moto,
// SOAT, antecedentes (condicional según nacionalidad), comprobante de
// domicilio (no aplica si vive en Venezuela), referencias personales,
// verificación KYC. Por ahora opcional; pasan a obligatorio cuando la
// app esté consolidada (excepto licencia/SOAT/antecedentes, que
// quedan condicionales según disponibilidad real del repartidor).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/auth_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:serviexpress_app/utils/sonido_manager.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';

// Página temporal de Términos y Política de Privacidad.
const String _kUrlTerminos = 'https://serviexpressapp.netlify.app/#terminos';
const String _kUrlPrivacidad = 'https://serviexpressapp.netlify.app/#privacidad';

class RegistroScreen extends StatefulWidget {
  const RegistroScreen({super.key});

  @override
  State<RegistroScreen> createState() => _RegistroScreenState();
}

// Rango amplio de emojis comunes — bloquea emojis sin afectar acentos.
final RegExp _kRegexEmoji = RegExp(
  r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{2700}-\u{27BF}]',
  unicode: true,
);

final RegExp _kRegexCorreo = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

class _RegistroScreenState extends State<RegistroScreen> {
  // --- Controladores ---
  final _nombreCtrl = TextEditingController();
  final _usuarioCtrl = TextEditingController();
  final _numeroMovilCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmarPasswordCtrl = TextEditingController();

  // Solo para rol 'local'
  final _nombreResponsableCtrl = TextEditingController();
  final _direccionLocalCtrl = TextEditingController();
  String _tipoNegocio = 'Restaurante';
  // Coordenadas fijas del local (opcionales — el local puede dejar en blanco)
  double? _localLat;
  double? _localLng;
  bool _obteniendoUbicacion = false;

  String _rolSeleccionado = 'cliente';
  DateTime? _fechaNacimiento;
  bool _terminosAceptados = false;
  bool _procesando = false;
  bool _verPassword = false;
  bool _verConfirmarPassword = false;

  // 0=Rol, 1=Datos, 2=Cuenta, 3=Términos+Confirmar
  int _pasoActual = 0;
  static const int _totalPasos = 4;

  // Reconocedores de toque para los enlaces dentro del checkbox de
  // Términos — un TextSpan con onTap necesita uno de estos, y debe
  // crearse una sola vez y liberarse en dispose() para no filtrar
  // memoria. _tapToggleCheckbox es para el texto plano (no los
  // enlaces) — toca ese tramo y activa/desactiva el check, igual que
  // tocar el checkbox mismo.
  late final TapGestureRecognizer _tapTerminos;
  late final TapGestureRecognizer _tapPrivacidad;
  late final TapGestureRecognizer _tapToggleCheckbox;

  @override
  void initState() {
    super.initState();
    _tapTerminos = TapGestureRecognizer()
      ..onTap = () => _abrirEnlace(_kUrlTerminos);
    _tapPrivacidad = TapGestureRecognizer()
      ..onTap = () => _abrirEnlace(_kUrlPrivacidad);
    _tapToggleCheckbox = TapGestureRecognizer()
      ..onTap = () => setState(() => _terminosAceptados = !_terminosAceptados);
  }

  Future<void> _abrirEnlace(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Si falla (dispositivo sin navegador), no interrumpimos el flujo.
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _usuarioCtrl.dispose();
    _numeroMovilCtrl.dispose();
    _telefonoCtrl.dispose();
    _correoCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmarPasswordCtrl.dispose();
    _nombreResponsableCtrl.dispose();
    _direccionLocalCtrl.dispose();
    _tapTerminos.dispose();
    _tapPrivacidad.dispose();
    _tapToggleCheckbox.dispose();
    super.dispose();
  }

  // =========================================================================
  // VALIDACIÓN POR PASO
  // =========================================================================
  bool _esCorreoValido(String correo) => _kRegexCorreo.hasMatch(correo.trim());

  int _calcularEdad(DateTime nacimiento) {
    final hoy = DateTime.now();
    int edad = hoy.year - nacimiento.year;
    if (hoy.month < nacimiento.month ||
        (hoy.month == nacimiento.month && hoy.day < nacimiento.day)) {
      edad--;
    }
    return edad;
  }

  String? _errorPasoDatos() {
    if (_rolSeleccionado == 'local') {
      if (_nombreCtrl.text.trim().isEmpty) return 'Escribe el nombre del negocio.';
      if (_kRegexEmoji.hasMatch(_nombreCtrl.text)) return 'El nombre no puede contener emojis.';
      if (_nombreResponsableCtrl.text.trim().isEmpty) {
        return 'Escribe el nombre de quién responde por la cuenta.';
      }
      if (_telefonoCtrl.text.trim().isEmpty) return 'Escribe un teléfono de contacto.';
      if (_correoCtrl.text.trim().isEmpty || !_esCorreoValido(_correoCtrl.text)) {
        return 'Escribe un correo electrónico válido.';
      }
      if (_direccionLocalCtrl.text.trim().isEmpty) {
        return 'Escribe la dirección del local.';
      }
      return null;
    }

    // movil o cliente
    if (_nombreCtrl.text.trim().isEmpty) return 'Escribe tu nombre completo.';
    if (_kRegexEmoji.hasMatch(_nombreCtrl.text)) return 'El nombre no puede contener emojis.';
    if (_telefonoCtrl.text.trim().isEmpty) return 'Escribe tu número de teléfono.';
    if (_correoCtrl.text.trim().isEmpty || !_esCorreoValido(_correoCtrl.text)) {
      return 'Escribe un correo electrónico válido.';
    }
    if (_fechaNacimiento == null) return 'Selecciona tu fecha de nacimiento.';

    if (_rolSeleccionado == 'movil' && _calcularEdad(_fechaNacimiento!) < 18) {
      return 'Debes ser mayor de 18 años para registrarte como móvil.';
    }
    return null;
  }

  String? _errorPasoCuenta() {
    if (_rolSeleccionado == 'movil') {
      if (_numeroMovilCtrl.text.trim().isEmpty) {
        return 'Escribe tu número de móvil asignado por Central.';
      }
    } else {
      if (_usuarioCtrl.text.trim().isEmpty) return 'Escribe un usuario.';
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_usuarioCtrl.text.trim())) {
        return 'El usuario solo puede tener letras sin tilde, números y guión bajo.';
      }
    }
    if (_passwordCtrl.text.length < 4) {
      return 'La contraseña debe tener mínimo 4 caracteres.';
    }
    if (_passwordCtrl.text != _confirmarPasswordCtrl.text) {
      return 'Las contraseñas no coinciden.';
    }
    return null;
  }

  void _avanzarPaso() {
    String? error;
    if (_pasoActual == 1) error = _errorPasoDatos();
    if (_pasoActual == 2) error = _errorPasoCuenta();
    if (_pasoActual == 3 && !_terminosAceptados) {
      error = 'Debes aceptar los Términos y la Política de Privacidad.';
    }

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    if (_pasoActual == _totalPasos - 1) {
      _ejecutarRegistro();
    } else {
      setState(() => _pasoActual++);
    }
  }

  void _retrocederPaso() {
    if (_pasoActual == 0) {
      Navigator.pop(context);
    } else {
      setState(() => _pasoActual--);
    }
  }

  Future<void> _seleccionarFechaNacimiento() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: DateTime(ahora.year - 18, ahora.month, ahora.day),
      firstDate: DateTime(ahora.year - 100),
      lastDate: DateTime(ahora.year - 13, ahora.month, ahora.day),
      helpText: 'FECHA DE NACIMIENTO',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Colors.black,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (fecha != null) setState(() => _fechaNacimiento = fecha);
  }

  // =========================================================================
  // ENVÍO FINAL
  // =========================================================================
  Future<void> _ejecutarRegistro() async {
    final usuarioText = _rolSeleccionado == 'movil'
        ? 'movil${_numeroMovilCtrl.text.trim()}'
        : _usuarioCtrl.text.trim().toLowerCase();
    final telefono = _telefonoCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final correo = _correoCtrl.text.trim().toLowerCase();
    final nombre = _nombreCtrl.text.trim();

    setState(() => _procesando = true);

    try {
      // 1. Verificar duplicados — comprobaciones separadas para evitar
      // que un OR con .maybeSingle() falle si hay más de un match.
      final existeTel = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('telefono', telefono)
          .limit(1);
      if ((existeTel as List).isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Este teléfono ya está registrado.'), backgroundColor: Colors.orange),
          );
        }
        setState(() => _procesando = false);
        return;
      }

      final existeUsuario = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('usuario', usuarioText)
          .limit(1);
      if ((existeUsuario as List).isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_rolSeleccionado == 'movil'
                  ? 'Ese número de móvil ya está en uso. Pregúntale a Central cuál te corresponde.'
                  : 'El usuario "$usuarioText" ya está en uso. Por favor, elige otro.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _procesando = false);
        return;
      }

      final existeCorreo = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('correo', correo)
          .limit(1);
      if ((existeCorreo as List).isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ese correo ya está registrado.'), backgroundColor: Colors.orange),
          );
        }
        setState(() => _procesando = false);
        return;
      }

      final bool entraActivo = _rolSeleccionado == 'cliente';
      final passwordHash = hashContrasena(password);

      final Map<String, dynamic> datosInsert = {
        'nombre': nombre.toUpperCase(),
        'usuario': usuarioText,
        'telefono': telefono,
        'correo': correo,
        'contrasena': passwordHash,
        'rol': _rolSeleccionado,
        'activo': entraActivo,
        'terminos_aceptados_at': DateTime.now().toUtc().toIso8601String(),
      };

      if (_rolSeleccionado == 'local') {
        datosInsert['nombre_responsable'] = _nombreResponsableCtrl.text.trim();
        datosInsert['direccion_local'] = _direccionLocalCtrl.text.trim();
        datosInsert['tipo_negocio'] = _tipoNegocio;
        datosInsert['estado_local'] = 'pendiente'; // Requiere aprobación de Central
        if (_localLat != null) {
          datosInsert['lat_fija'] = _localLat;
          datosInsert['lng_fija'] = _localLng;
        }
      } else {
        datosInsert['fecha_nacimiento'] =
            _fechaNacimiento!.toIso8601String().split('T').first;
      }

      final filaInsertada = await Supabase.instance.client
          .from('usuarios')
          .insert(datosInsert)
          .select()
          .single();

      if (mounted) {
        if (entraActivo) {
          // SESIÓN REAL desde el primer uso — mismo modelo que
          // login_screen.dart (Instagram/Facebook/TikTok): guardamos
          // el usuario completo, no credenciales. Próxima apertura,
          // entra al instante sin tocar la red.
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'sesion_usuario_json',
            jsonEncode(filaInsertada),
          );
          await prefs.setBool('auto_login', true);
          await prefs.remove('saved_phone');
          await prefs.remove('saved_hash');
          await prefs.remove('saved_password');

          // LOCALES: redirigir a pantalla de espera de aprobación
          if (_rolSeleccionado == 'local') {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => _LocalPendienteScreen(
                  nombreLocal: filaInsertada['nombre']?.toString() ?? '',
                ),
              ),
              (route) => false,
            );
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Bienvenido! Cuenta creada con éxito.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
        } else {
          // Notificar a Central que hay un usuario pendiente de activación
          try {
            final centralUsers = await Supabase.instance.client
                .from('usuarios')
                .select('id')
                .inFilter('rol', ['central', 'master'])
                .eq('en_linea', true);
            final centralIds = (centralUsers as List)
                .map<String>((u) => u['id'].toString())
                .toList();
            if (centralIds.isNotEmpty) {
              final rolLabel = _rolSeleccionado == 'local' ? 'Local' : 'Móvil';
              await MotorNotificaciones.dispararRafa(
                idsDestinos: centralIds,
                titulo: '👤 NUEVO $rolLabel POR ACTIVAR',
                mensaje: '${filaInsertada['nombre'] ?? 'Nuevo usuario'} está esperando activación. Ve a Gestión → Usuarios.',
                urgente: true,
                sonido: Sonidos.centralRadar,
              );
            }
          } catch (_) {}

          final String usuarioMostrar = filaInsertada['usuario']?.toString() ?? usuarioText;
          final String telefonoPwd   = filaInsertada['telefono']?.toString() ?? telefono;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: const Text(
                '✅ REGISTRO EXITOSO',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xff3AF500)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tu cuenta está en revisión. La Central te activará pronto.',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xff3AF500), width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TUS DATOS DE ACCESO',
                            style: TextStyle(color: Color(0xff3AF500), fontSize: 10,
                                fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Text('USUARIO: ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          Text(usuarioMostrar,
                              style: const TextStyle(color: Color(0xff3AF500), fontSize: 22,
                                  fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Text('CLAVE:   ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          Text(telefonoPwd,
                              style: const TextStyle(color: Colors.white, fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ Guarda tu usuario y contraseña. No uses tu correo para ingresar.',
                    style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                  },
                  child: const Text(
                    'ENTENDIDO',
                    style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final eStr = e.toString();
        String mensaje;
        if (eStr.contains('duplicate') || eStr.contains('unique')) {
          mensaje = 'Ya existe una cuenta con ese teléfono, correo o usuario.';
        } else if (eStr.contains('violates') || eStr.contains('constraint')) {
          mensaje = 'Error de validación en los datos. Revisa tu información.';
        } else {
          mensaje = 'No se pudo completar el registro. Intenta de nuevo.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // =========================================================================
  // UI — DECORACIÓN COMPARTIDA
  // =========================================================================
  InputDecoration _decoracion(String label, IconData icono, {String? helper}) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      prefixIcon: Icon(icono, color: Colors.black54),
      helperText: helper,
      helperStyle: const TextStyle(fontSize: 11),
      helperMaxLines: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            _buildBarraProgreso(),
            Expanded(
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.08, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(_pasoActual),
                        child: _construirPaso(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
            _buildBarraNavegacion(),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraProgreso() {
    const titulos = ['Tu rol', 'Tus datos', 'Tu cuenta', 'Confirmar'];
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                titulos[_pasoActual],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Paso ${_pasoActual + 1} de $_totalPasos',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(_totalPasos, (i) {
              final activo = i <= _pasoActual;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i == _totalPasos - 1 ? 0 : 4),
                  height: 4,
                  decoration: BoxDecoration(
                    color: activo ? const Color(0xff3AF500) : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildBarraNavegacion() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            OutlinedButton(
              onPressed: _procesando ? null : _retrocederPaso,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                side: const BorderSide(color: Colors.black26),
              ),
              child: Text(
                _pasoActual == 0 ? 'CANCELAR' : 'ATRÁS',
                style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _procesando ? null : _avanzarPaso,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _procesando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Color(0xff3AF500),
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _pasoActual == _totalPasos - 1 ? 'CREAR CUENTA' : 'SIGUIENTE',
                        style: const TextStyle(
                          color: Color(0xff3AF500),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirPaso() {
    switch (_pasoActual) {
      case 0:
        return _pasoRol();
      case 1:
        return _pasoDatos();
      case 2:
        return _pasoCuenta();
      case 3:
        return _pasoTerminos();
      default:
        return const SizedBox.shrink();
    }
  }

  // =========================================================================
  // PASO 0 — ROL
  // =========================================================================
  Widget _pasoRol() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Cómo vas a usar ServiExpress?',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        _opcionRol(
          'CLIENTE FRECUENTE',
          'Cuenta rápida. Pide servicios de inmediato.',
          'cliente',
          Icons.person,
        ),
        _opcionRol(
          'MÓVIL / DOMICILIARIO',
          'Requiere validación de Central para operar.',
          'movil',
          Icons.motorcycle,
        ),
        _opcionRol(
          'LOCAL / NEGOCIO',
          'Requiere validación de Central para despachos.',
          'local',
          Icons.storefront,
        ),
      ],
    );
  }

  Widget _opcionRol(String titulo, String subtitulo, String valorRol, IconData icono) {
    final bool seleccionado = _rolSeleccionado == valorRol;
    return GestureDetector(
      onTap: () => setState(() {
        _rolSeleccionado = valorRol;
        // Limpiamos para que no quede dato de otro rol pegado.
        _usuarioCtrl.clear();
        _numeroMovilCtrl.clear();
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: seleccionado ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionado ? const Color(0xff3AF500) : Colors.black12,
            width: 2,
          ),
          boxShadow: seleccionado ? [] : const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            Icon(icono, color: seleccionado ? const Color(0xff3AF500) : Colors.black54, size: 28),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: seleccionado ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitulo,
                    style: TextStyle(fontSize: 11, color: seleccionado ? Colors.white70 : Colors.black54),
                  ),
                ],
              ),
            ),
            if (seleccionado) const Icon(Icons.check_circle, color: Color(0xff3AF500)),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PASO 1 — DATOS
  // =========================================================================
  Widget _pasoDatos() {
    if (_rolSeleccionado == 'local') return _pasoDatosLocal();
    return _pasoDatosPersona();
  }

  Widget _pasoDatosPersona() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nombreCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: _decoracion('Nombre completo', Icons.badge),
          inputFormatters: [FilteringTextInputFormatter.deny(_kRegexEmoji)],
        ),
        const SizedBox(height: 15),
        InkWell(
          onTap: _seleccionarFechaNacimiento,
          child: InputDecorator(
            decoration: _decoracion(
              'Fecha de nacimiento',
              Icons.cake_outlined,
              helper: _rolSeleccionado == 'movil' ? 'Debes ser mayor de 18 años' : null,
            ),
            child: Text(
              _fechaNacimiento == null
                  ? 'Toca para seleccionar'
                  : '${_fechaNacimiento!.day.toString().padLeft(2, '0')}/'
                    '${_fechaNacimiento!.month.toString().padLeft(2, '0')}/'
                    '${_fechaNacimiento!.year}',
              style: TextStyle(
                color: _fechaNacimiento == null ? Colors.black38 : Colors.black87,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _telefonoCtrl,
          keyboardType: TextInputType.phone,
          decoration: _decoracion('Teléfono (WhatsApp)', Icons.phone),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _correoCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoracion(
            'Correo electrónico',
            Icons.email_outlined,
            helper: 'Lo usamos para recuperar tu cuenta y enviarte novedades',
          ),
        ),
      ],
    );
  }

  Widget _pasoDatosLocal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nombreCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: _decoracion('Nombre del negocio', Icons.storefront),
          inputFormatters: [FilteringTextInputFormatter.deny(_kRegexEmoji)],
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _nombreResponsableCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: _decoracion('Nombre de quien responde por la cuenta', Icons.badge),
          inputFormatters: [FilteringTextInputFormatter.deny(_kRegexEmoji)],
        ),
        const SizedBox(height: 15),
        DropdownButtonFormField<String>(
          initialValue: _tipoNegocio,
          decoration: _decoracion('Tipo de negocio', Icons.category_outlined),
          items: const [
            DropdownMenuItem(value: 'Restaurante', child: Text('Restaurante')),
            DropdownMenuItem(value: 'Farmacia', child: Text('Farmacia')),
            DropdownMenuItem(value: 'Tienda', child: Text('Tienda')),
            DropdownMenuItem(value: 'Supermercado', child: Text('Supermercado')),
            DropdownMenuItem(value: 'Otro', child: Text('Otro')),
          ],
          onChanged: (val) => setState(() => _tipoNegocio = val ?? 'Otro'),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _telefonoCtrl,
          keyboardType: TextInputType.phone,
          decoration: _decoracion('Teléfono de contacto', Icons.phone),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _correoCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoracion(
            'Correo electrónico',
            Icons.email_outlined,
            helper: 'Lo usamos para recuperar tu cuenta y enviarte novedades',
          ),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _direccionLocalCtrl,
          decoration: _decoracion('Dirección del local', Icons.location_on_outlined),
        ),
        const SizedBox(height: 8),
        // Botones para fijar ubicación del local
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: _obteniendoUbicacion ? null : _usarUbicacionActual,
                icon: _obteniendoUbicacion
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(
                  _localLat != null ? '📍 Ubicación fijada' : 'Usar mi ubicación',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black54),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _abrirSelectorMapa(),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Fijar en mapa', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        if (_localLat != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '📍 ${_localLat!.toStringAsFixed(5)}, ${_localLng!.toStringAsFixed(5)}',
              style: TextStyle(fontSize: 11, color: Colors.green[700]),
            ),
          ),
      ],
    );
  }

  // --- Obtiene la ubicación actual del GPS ---
  Future<void> _usarUbicacionActual() async {
    if (kIsWeb) {
      // En web, Geolocator funciona vía browser API
      // Pedimos permiso igual que en nativo
    }
    setState(() => _obteniendoUbicacion = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Se necesita permiso de ubicación.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      setState(() {
        _localLat = pos.latitude;
        _localLng = pos.longitude;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo obtener la ubicación: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _obteniendoUbicacion = false);
    }
  }

  // --- Abre un mapa de pantalla completa para que el local fije su pin ---
  Future<void> _abrirSelectorMapa() async {
    // Centro inicial: Cúcuta, Colombia
    LatLng centroInicial = LatLng(
      _localLat ?? 7.8939,
      _localLng ?? -72.5078,
    );

    LatLng? puntoPinchado = _localLat != null
        ? LatLng(_localLat!, _localLng!)
        : null;

    final MapController mapCtrl = MapController();

    final resultado = await showDialog<LatLng>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setMapState) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: Column(
              children: [
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.map, color: Color(0xff3AF500)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Toca el mapa para fijar la ubicación del local',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    mapController: mapCtrl,
                    options: MapOptions(
                      initialCenter: centroInicial,
                      initialZoom: 15.0,
                      onTap: (tapPos, point) {
                        setMapState(() => puntoPinchado = point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.serviexpress.express',
                      ),
                      if (puntoPinchado != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: puntoPinchado!,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_pin,
                                color: Colors.red,
                                size: 40,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (puntoPinchado != null)
                        Expanded(
                          child: Text(
                            '${puntoPinchado!.latitude.toStringAsFixed(5)}, '
                            '${puntoPinchado!.longitude.toStringAsFixed(5)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        ),
                        onPressed: puntoPinchado == null
                            ? null
                            : () => Navigator.pop(ctx, puntoPinchado),
                        child: const Text(
                          'CONFIRMAR',
                          style: TextStyle(
                            color: Color(0xff3AF500),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (resultado != null && mounted) {
      setState(() {
        _localLat = resultado.latitude;
        _localLng = resultado.longitude;
      });
    }
  }

  // =========================================================================
  // PASO 2 — CUENTA
  // =========================================================================
  Widget _pasoCuenta() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_rolSeleccionado == 'movil')
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: const Text(
                  'movil',
                  style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _numeroMovilCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _decoracion(
                    'Tu número',
                    Icons.tag,
                    helper: 'Pregúntale a Central tu número asignado',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          )
        else
          TextField(
            controller: _usuarioCtrl,
            decoration: _decoracion(
              _rolSeleccionado == 'local' ? 'Usuario del local (Ej: localcentro)' : 'Usuario (para iniciar sesión)',
              Icons.account_circle,
              helper: 'Solo letras sin tilde, números y guión bajo',
            ),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))],
          ),
        const SizedBox(height: 15),
        TextField(
          controller: _passwordCtrl,
          obscureText: !_verPassword,
          decoration: _decoracion('Contraseña (mínimo 4 caracteres)', Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility, color: Colors.black38),
              onPressed: () => setState(() => _verPassword = !_verPassword),
            ),
          ),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _confirmarPasswordCtrl,
          obscureText: !_verConfirmarPassword,
          decoration: _decoracion('Confirmar contraseña', Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(_verConfirmarPassword ? Icons.visibility_off : Icons.visibility, color: Colors.black38),
              onPressed: () => setState(() => _verConfirmarPassword = !_verConfirmarPassword),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // PASO 3 — TÉRMINOS Y RESUMEN
  // =========================================================================
  Widget _pasoTerminos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Revisa tus datos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              _filaResumen('Rol', _rolSeleccionado == 'movil' ? 'Móvil' : _rolSeleccionado == 'local' ? 'Local' : 'Cliente'),
              _filaResumen('Nombre', _nombreCtrl.text.trim()),
              if (_rolSeleccionado != 'local')
                _filaResumen(
                  'Usuario',
                  _rolSeleccionado == 'movil' ? 'movil${_numeroMovilCtrl.text.trim()}' : _usuarioCtrl.text.trim(),
                ),
              _filaResumen('Teléfono', _telefonoCtrl.text.trim()),
              _filaResumen('Correo', _correoCtrl.text.trim()),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _terminosAceptados,
              activeColor: Colors.black,
              onChanged: (val) => setState(() => _terminosAceptados = val ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.4),
                    children: [
                      TextSpan(
                        text: 'He leído y acepto los ',
                        // Mismo recognizer que el checkbox — antes esto
                        // vivía dentro de un InkWell exterior que se
                        // comía el toque antes de que llegara a los
                        // enlaces. Ahora cada tramo de texto maneja su
                        // propio toque, sin un ancestro que compita.
                        recognizer: _tapToggleCheckbox,
                      ),
                      TextSpan(
                        text: 'Términos y Condiciones',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          color: Colors.black,
                        ),
                        recognizer: _tapTerminos,
                      ),
                      TextSpan(text: ' y la ', recognizer: _tapToggleCheckbox),
                      TextSpan(
                        text: 'Política de Privacidad',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          color: Colors.black,
                        ),
                        recognizer: _tapPrivacidad,
                      ),
                      TextSpan(
                        text: ' de ServiExpress.',
                        recognizer: _tapToggleCheckbox,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _filaResumen(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(etiqueta, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(
              valor.isEmpty ? '—' : valor,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


// ============================================================
// PANTALLA DE ESPERA — LOCAL PENDIENTE DE APROBACIÓN
// ============================================================
class _LocalPendienteScreen extends StatelessWidget {
  final String nombreLocal;
  const _LocalPendienteScreen({required this.nombreLocal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: Colors.amber[800]!.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber[600]!, width: 2),
                ),
                child: Icon(Icons.hourglass_top_rounded,
                    size: 44, color: Colors.amber[400]),
              ),
              const SizedBox(height: 28),
              Text(
                nombreLocal.isNotEmpty ? nombreLocal : 'Tu local',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tu solicitud está en revisión',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xff3AF500),
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Text(
                'El equipo de Serviexpress verificará tu información y zona de cobertura. '
                'Recibirás una notificación cuando tu cuenta sea activada.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(children: [
                  _estadoFila(Icons.check_circle_outline, '¡Registro completado!', Colors.green[400]!),
                  const SizedBox(height: 10),
                  _estadoFila(Icons.pending_outlined, 'Verificación por Central', Colors.amber[400]!),
                  const SizedBox(height: 10),
                  _estadoFila(Icons.rocket_launch_outlined, 'Activación de cuenta', Colors.grey[600]!),
                ]),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () =>
                      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
                  child: const Text('Volver al inicio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _estadoFila(IconData ico, String texto, Color color) {
    return Row(children: [
      Icon(ico, size: 18, color: color),
      const SizedBox(width: 10),
      Text(texto, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}
