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
import 'dart:io';
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
import 'package:image_picker/image_picker.dart';

// Página temporal de Términos y Política de Privacidad.
const String _kUrlTerminos = 'https://serviexpressapp.netlify.app/#terminos';
const String _kUrlPrivacidad =
    'https://serviexpressapp.netlify.app/#privacidad';

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
  // Solo para rol 'movil': 'suscripcion' | 'prediario' | 'postdia'
  String? _tipoMovil;

  DateTime? _fechaNacimiento;
  bool _terminosAceptados = false;
  bool _procesando = false;
  bool _verPassword = false;
  bool _verConfirmarPassword = false;

  // Documentación para prediario/postdia
  final _picker = ImagePicker();
  XFile? _fotoCedula;
  XFile? _fotoLicencia;
  XFile? _fotoSoat;
  XFile? _fotoPerfil;

  // Suscripción:    0=Rol, 1=Plan, 2=Datos, 3=Selfie, 4=Cuenta, 5=Confirmar (6 pasos)
  // Prediario/Post: 0=Rol, 1=Plan, 2=Datos, 3=Docs,   4=Cuenta, 5=Confirmar (6 pasos)
  // Otros:          0=Rol,         1=Datos, 2=Cuenta,            3=Confirmar (4 pasos)
  int _pasoActual = 0;
  bool get _esPrePost =>
      _rolSeleccionado == 'movil' && _tipoMovil != null && _tipoMovil != 'suscripcion';
  int get _totalPasos {
    if (_rolSeleccionado != 'movil') return 4;
    // Cuando aún no se eligió plan, mostramos 5 como placeholder
    return _tipoMovil != null ? 6 : 5;
  }

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
      if (_nombreCtrl.text.trim().isEmpty)
        return 'Escribe el nombre del negocio.';
      if (_kRegexEmoji.hasMatch(_nombreCtrl.text))
        return 'El nombre no puede contener emojis.';
      if (_nombreResponsableCtrl.text.trim().isEmpty) {
        return 'Escribe el nombre de quién responde por la cuenta.';
      }
      if (_telefonoCtrl.text.trim().isEmpty)
        return 'Escribe un teléfono de contacto.';
      if (_correoCtrl.text.trim().isEmpty ||
          !_esCorreoValido(_correoCtrl.text)) {
        return 'Escribe un correo electrónico válido.';
      }
      if (_direccionLocalCtrl.text.trim().isEmpty) {
        return 'Escribe la dirección del local.';
      }
      return null;
    }

    // movil o cliente
    if (_nombreCtrl.text.trim().isEmpty) return 'Escribe tu nombre completo.';
    if (_kRegexEmoji.hasMatch(_nombreCtrl.text))
      return 'El nombre no puede contener emojis.';
    if (_telefonoCtrl.text.trim().isEmpty)
      return 'Escribe tu número de teléfono.';
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
      // Solo suscripción requiere número manual
      if (_tipoMovil == 'suscripcion') {
        final raw = _numeroMovilCtrl.text.trim();
        if (raw.isEmpty) return 'Escribe el número que quieres usar (1-100).';
        final n = int.tryParse(raw);
        if (n == null || n < 1 || n > 100) {
          return 'El número de suscripción debe estar entre 01 y 100.';
        }
      }
      // Prediario y Postdia: número auto-asignado, no se valida aquí
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

    if (_rolSeleccionado == 'movil') {
      if (_pasoActual == 1 && (_tipoMovil == null || _tipoMovil!.isEmpty)) {
        error = 'Selecciona tu plan de trabajo.';
      }
      if (_pasoActual == 2) error = _errorPasoDatos();
      if (_esPrePost) {
        // prediario/postdia: docs=3 (cédula req, selfie req), cuenta=4, confirmar=5
        if (_pasoActual == 3) {
          if (_fotoPerfil == null) error = 'La selfie de verificación es obligatoria.';
          else if (_fotoCedula == null) error = 'La foto de la cédula es obligatoria.';
        }
        if (_pasoActual == 4) error = _errorPasoCuenta();
        if (_pasoActual == 5 && !_terminosAceptados) {
          error = 'Debes aceptar los Términos y la Política de Privacidad.';
        }
      } else {
        // suscripcion: selfie=3 (req), cuenta=4, confirmar=5
        if (_pasoActual == 3 && _fotoPerfil == null) {
          error = 'La selfie de verificación es obligatoria.';
        }
        if (_pasoActual == 4) error = _errorPasoCuenta();
        if (_pasoActual == 5 && !_terminosAceptados) {
          error = 'Debes aceptar los Términos y la Política de Privacidad.';
        }
      }
    } else {
      // cliente/local: 4 pasos
      if (_pasoActual == 1) error = _errorPasoDatos();
      if (_pasoActual == 2) error = _errorPasoCuenta();
      if (_pasoActual == 3 && !_terminosAceptados) {
        error = 'Debes aceptar los Términos y la Política de Privacidad.';
      }
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
      if (_rolSeleccionado == 'movil' && _pasoActual == 1) {
        // Volver al paso de rol y limpiar tipo seleccionado
        setState(() {
          _pasoActual--;
          _tipoMovil = null;
        });
      } else {
        setState(() => _pasoActual--);
      }
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
    final telefono = _telefonoCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final correo = _correoCtrl.text.trim().toLowerCase();
    final nombre = _nombreCtrl.text.trim();

    setState(() => _procesando = true);

    try {
      // ── Auto-asignar número para prediario/postdia ──────────────────────
      int numMovilRegistro = 0;
      if (_rolSeleccionado == 'movil') {
        if (_tipoMovil == 'suscripcion') {
          numMovilRegistro = int.tryParse(_numeroMovilCtrl.text.trim()) ?? 0;
        } else {
          // Encontrar siguiente número libre en 200-299
          final tomados = await Supabase.instance.client
              .from('usuarios')
              .select('numero_movil')
              .gte('numero_movil', 200)
              .lte('numero_movil', 299)
              .or('eliminado.is.null,eliminado.eq.false');
          final tomadosSet = tomados
              .map<int>((u) => (u['numero_movil'] as num).toInt())
              .toSet();
          numMovilRegistro = 200;
          while (tomadosSet.contains(numMovilRegistro) &&
              numMovilRegistro <= 299) {
            numMovilRegistro++;
          }
          if (numMovilRegistro > 299) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'No hay números disponibles (200-299). Contacta a la central.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            setState(() => _procesando = false);
            return;
          }
        }
      }

      final usuarioText = _rolSeleccionado == 'movil'
          ? 'movil${numMovilRegistro.toString().padLeft(2, '0')}'
          : _usuarioCtrl.text.trim().toLowerCase();

      // 1. Verificar duplicados
      final existeTel = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('telefono', telefono)
          .or('eliminado.is.null,eliminado.eq.false')
          .limit(1);
      if (existeTel.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Este teléfono ya está registrado.'),
                backgroundColor: Colors.orange),
          );
        }
        setState(() => _procesando = false);
        return;
      }

      // Verificar unicidad de número de móvil para suscripción
      if (_rolSeleccionado == 'movil' && _tipoMovil == 'suscripcion') {
        final existeNumero = await Supabase.instance.client
            .from('usuarios')
            .select('id')
            .eq('numero_movil', numMovilRegistro)
            .or('eliminado.is.null,eliminado.eq.false')
            .limit(1);
        if (existeNumero.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Ese número ya está en uso. Elige otro del 01 al 100.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _procesando = false);
          return;
        }
      } else if (_rolSeleccionado != 'movil') {
        final existeUsuario = await Supabase.instance.client
            .from('usuarios')
            .select('id')
            .eq('usuario', usuarioText)
            .limit(1);
        if (existeUsuario.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    'El usuario "$usuarioText" ya está en uso. Por favor, elige otro.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          setState(() => _procesando = false);
          return;
        }
      }

      final existeCorreo = await Supabase.instance.client
          .from('usuarios')
          .select('id')
          .eq('correo', correo)
          .or('eliminado.is.null,eliminado.eq.false')
          .limit(1);
      if (existeCorreo.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Ese correo ya está registrado.'),
                backgroundColor: Colors.orange),
          );
        }
        setState(() => _procesando = false);
        return;
      }

      // Clientes: activos de inmediato.
      // Prediario/Postdia: activos de inmediato (auto-registro).
      // Suscripción: requiere verificación de Central.
      final bool entraActivo = _rolSeleccionado == 'cliente' ||
          (_rolSeleccionado == 'movil' && _tipoMovil != 'suscripcion');
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
        datosInsert['estado_local'] =
            'pendiente'; // Requiere aprobación de Central
        if (_localLat != null) {
          datosInsert['lat_fija'] = _localLat;
          datosInsert['lng_fija'] = _localLng;
        }
      } else {
        datosInsert['fecha_nacimiento'] =
            _fechaNacimiento!.toIso8601String().split('T').first;
        if (_rolSeleccionado == 'movil') {
          datosInsert['numero_movil'] = numMovilRegistro;
          datosInsert['tipo_plan'] = _tipoMovil ?? 'suscripcion';
        }
      }

      final filaInsertada = await Supabase.instance.client
          .from('usuarios')
          .insert(datosInsert)
          .select()
          .single();

      // ── Subir documentos para móviles ──────────────────────────────────────
      if (_rolSeleccionado == 'movil' && _fotoPerfil != null) {
        final userId = filaInsertada['id'].toString();
        final docUrls = <String, String>{};

        Future<void> subirDoc(XFile? file, String campo) async {
          if (file == null) return;
          try {
            final ext = file.path.split('.').last.toLowerCase();
            final path = 'docs/$userId/$campo.$ext';
            final bytes = await file.readAsBytes();
            await Supabase.instance.client.storage
                .from('movil-docs')
                .uploadBinary(path, bytes,
                    fileOptions: FileOptions(upsert: true));
            final url = Supabase.instance.client.storage
                .from('movil-docs')
                .getPublicUrl(path);
            docUrls[campo] = url;
          } catch (_) {}
        }

        await subirDoc(_fotoPerfil, 'perfil');
        await subirDoc(_fotoCedula, 'cedula');
        await subirDoc(_fotoLicencia, 'licencia');
        await subirDoc(_fotoSoat, 'soat');

        if (docUrls.isNotEmpty) {
          final Map<String, dynamic> urlsMap = {};
          if (docUrls.containsKey('perfil')) urlsMap['doc_perfil_url'] = docUrls['perfil'];
          if (docUrls.containsKey('cedula')) urlsMap['doc_cedula_url'] = docUrls['cedula'];
          if (docUrls.containsKey('licencia')) urlsMap['doc_licencia_url'] = docUrls['licencia'];
          if (docUrls.containsKey('soat')) urlsMap['doc_soat_url'] = docUrls['soat'];
          try {
            await Supabase.instance.client
                .from('usuarios')
                .update(urlsMap)
                .eq('id', filaInsertada['id']);
          } catch (_) {}
        }
      }

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
            if (!mounted) return;
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

          if (!mounted) return;
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
                .inFilter('rol', ['central', 'master']).eq('en_linea', true);
            final centralIds =
                centralUsers.map<String>((u) => u['id'].toString()).toList();
            if (centralIds.isNotEmpty) {
              final rolLabel = _rolSeleccionado == 'local' ? 'Local' : 'Móvil';
              await MotorNotificaciones.dispararRafa(
                idsDestinos: centralIds,
                titulo: '👤 NUEVO $rolLabel POR ACTIVAR',
                mensaje:
                    '${filaInsertada['nombre'] ?? 'Nuevo usuario'} está esperando activación. Ve a Gestión → Usuarios.',
                urgente: true,
                sonido: Sonidos.centralRadar,
              );
            }
          } catch (_) {}

          final String usuarioMostrar =
              filaInsertada['usuario']?.toString() ?? usuarioText;
          final String telefonoPwd =
              filaInsertada['telefono']?.toString() ?? telefono;
          if (!mounted) return;
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: const Text(
                '✅ REGISTRO EXITOSO',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xff3AF500)),
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
                      border:
                          Border.all(color: const Color(0xff3AF500), width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TUS DATOS DE ACCESO',
                            style: TextStyle(
                                color: Color(0xff3AF500),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2)),
                        const SizedBox(height: 10),
                        Row(children: [
                          const Text('USUARIO: ',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          Text(usuarioMostrar,
                              style: const TextStyle(
                                  color: Color(0xff3AF500),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Text('CLAVE:   ',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          Text(telefonoPwd,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '💡 Para ingresar usa tu número de teléfono o tu usuario. No uses el correo.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.black),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/', (route) => false);
                  },
                  child: const Text(
                    'ENTENDIDO',
                    style: TextStyle(
                        color: Color(0xff3AF500), fontWeight: FontWeight.bold),
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
    final titulos = _rolSeleccionado != 'movil'
        ? ['Tu rol', 'Tus datos', 'Tu cuenta', 'Confirmar']
        : _esPrePost
            ? ['Tu rol', 'Plan de trabajo', 'Tus datos', 'Documentación', 'Tu cuenta', 'Confirmar']
            : _tipoMovil == 'suscripcion'
                ? ['Tu rol', 'Plan de trabajo', 'Tus datos', 'Verificación', 'Tu cuenta', 'Confirmar']
                : ['Tu rol', 'Plan de trabajo', 'Tus datos', 'Tu cuenta', 'Confirmar'];
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            OutlinedButton(
              onPressed: _procesando ? null : _retrocederPaso,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                side: const BorderSide(color: Colors.black26),
              ),
              child: Text(
                _pasoActual == 0 ? 'CANCELAR' : 'ATRÁS',
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _procesando ? null : _avanzarPaso,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
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
                        _pasoActual == _totalPasos - 1
                            ? 'CREAR CUENTA'
                            : 'SIGUIENTE',
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
    if (_rolSeleccionado == 'movil') {
      if (_esPrePost) {
        // 0=Rol, 1=Plan, 2=Datos, 3=Docs, 4=Cuenta, 5=Confirmar
        switch (_pasoActual) {
          case 0: return _pasoRol();
          case 1: return _pasoTipoMovil();
          case 2: return _pasoDatos();
          case 3: return _pasoDocumentacion();
          case 4: return _pasoCuenta();
          case 5: return _pasoTerminos();
          default: return const SizedBox.shrink();
        }
      } else {
        // Suscripción: 0=Rol, 1=Plan, 2=Datos, 3=Selfie, 4=Cuenta, 5=Confirmar
        switch (_pasoActual) {
          case 0: return _pasoRol();
          case 1: return _pasoTipoMovil();
          case 2: return _pasoDatos();
          case 3: return _pasoSelfie();
          case 4: return _pasoCuenta();
          case 5: return _pasoTerminos();
          default: return const SizedBox.shrink();
        }
      }
    }
    switch (_pasoActual) {
      case 0: return _pasoRol();
      case 1: return _pasoDatos();
      case 2: return _pasoCuenta();
      case 3: return _pasoTerminos();
      default: return const SizedBox.shrink();
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
          'Requiere validación de Central para enviar servicios.',
          'local',
          Icons.storefront,
        ),
      ],
    );
  }

  Widget _opcionRol(
      String titulo, String subtitulo, String valorRol, IconData icono) {
    final bool seleccionado = _rolSeleccionado == valorRol;
    return GestureDetector(
      onTap: () => setState(() {
        _rolSeleccionado = valorRol;
        _tipoMovil = null;
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
          boxShadow: seleccionado
              ? []
              : const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            Icon(icono,
                color: seleccionado ? const Color(0xff3AF500) : Colors.black54,
                size: 28),
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
                    style: TextStyle(
                        fontSize: 11,
                        color: seleccionado ? Colors.white70 : Colors.black54),
                  ),
                ],
              ),
            ),
            if (seleccionado)
              const Icon(Icons.check_circle, color: Color(0xff3AF500)),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PASO 1 — PLAN DE TRABAJO (solo para rol 'movil')
  // =========================================================================
  Widget _pasoTipoMovil() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Selecciona tu plan de trabajo',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        _opcionTipoMovil(
          'SUSCRIPCIÓN SEMANAL',
          'Trabajas con el uniforme de la empresa. Pagas una suscripción fija cada semana. '
              'Elige tu número entre el 01 y el 100.',
          'suscripcion',
          Icons.card_membership_outlined,
        ),
        _opcionTipoMovil(
          'PREDIARIO',
          'Trabajo independiente. Pagas antes de iniciar tu turno del día. '
              'Tu número se asigna automáticamente (rango 200-299).',
          'prediario',
          Icons.wb_sunny_outlined,
        ),
        _opcionTipoMovil(
          'POSTDIA',
          'Trabajo independiente. Pagas al finalizar el día según los servicios realizados. '
              'Tu número se asigna automáticamente (rango 200-299).',
          'postdia',
          Icons.nights_stay_outlined,
        ),
      ],
    );
  }

  Widget _opcionTipoMovil(
      String titulo, String descripcion, String tipo, IconData icono) {
    final bool sel = _tipoMovil == tipo;
    return GestureDetector(
      onTap: () => setState(() => _tipoMovil = tipo),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? const Color(0xff3AF500) : Colors.black12,
            width: 2,
          ),
          boxShadow: sel
              ? []
              : const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono,
                color: sel ? const Color(0xff3AF500) : Colors.black54,
                size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: sel ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    descripcion,
                    style: TextStyle(
                      fontSize: 11,
                      color: sel ? Colors.white70 : Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (sel)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.check_circle,
                    color: Color(0xff3AF500), size: 20),
              ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PASO 3 — SELFIE (solo suscripcion) — verificación de identidad
  // =========================================================================
  Widget _pasoSelfie() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verificación de identidad',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tómate una selfie clara con buena iluminación. '
          'La Central la usará para verificar tu identidad antes de activar tu cuenta.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () async {
              final f = await _picker.pickImage(
                  source: ImageSource.camera, imageQuality: 80);
              if (f != null) setState(() => _fotoPerfil = f);
            },
            child: _fotoPerfil == null
                ? Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26, width: 2),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 48, color: Colors.black38),
                        SizedBox(height: 8),
                        Text('Tomar selfie',
                            style: TextStyle(
                                color: Colors.black45, fontSize: 13)),
                      ],
                    ),
                  )
                : ClipOval(
                    child: Image.file(
                      File(_fotoPerfil!.path),
                      width: 180,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        if (_fotoPerfil != null)
          Center(
            child: Column(
              children: [
                const Text('✅ Selfie tomada',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final f = await _picker.pickImage(
                        source: ImageSource.camera, imageQuality: 80);
                    if (f != null) setState(() => _fotoPerfil = f);
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Volver a tomar'),
                ),
              ],
            ),
          )
        else
          Center(
            child: OutlinedButton.icon(
              onPressed: () async {
                final f = await _picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 80);
                if (f != null) setState(() => _fotoPerfil = f);
              },
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('Usar foto de galería'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.black26),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  // =========================================================================
  // PASO 3 — DOCUMENTACIÓN (solo prediario/postdia)
  // =========================================================================
  Widget _pasoDocumentacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sube tus documentos para verificar tu identidad.',
          style: TextStyle(fontSize: 14, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        const Text(
          'Selfie y cédula son obligatorias. Los demás documentos son opcionales pero agilizarán tu activación.',
          style: TextStyle(fontSize: 12, color: Colors.orange),
        ),
        const SizedBox(height: 20),
        _itemDocumento(
          titulo: 'Selfie de Verificación *',
          subtitulo: 'Foto tuya con buena iluminación para verificar tu identidad.',
          icono: Icons.face,
          archivo: _fotoPerfil,
          obligatorio: true,
          onSeleccionar: () async {
            final f = await _picker.pickImage(
                source: ImageSource.gallery, imageQuality: 75);
            if (f != null) setState(() => _fotoPerfil = f);
          },
          onBorrar: () => setState(() => _fotoPerfil = null),
        ),
        const SizedBox(height: 12),
        _itemDocumento(
          titulo: 'Cédula de Ciudadanía *',
          subtitulo: 'Foto legible de tu cédula (ambos lados si puedes).',
          icono: Icons.credit_card,
          archivo: _fotoCedula,
          obligatorio: true,
          onSeleccionar: () async {
            final f = await _picker.pickImage(
                source: ImageSource.gallery, imageQuality: 80);
            if (f != null) setState(() => _fotoCedula = f);
          },
          onBorrar: () => setState(() => _fotoCedula = null),
        ),
        const SizedBox(height: 12),
        _itemDocumento(
          titulo: 'Licencia de Conducción',
          subtitulo: 'Opcional pero recomendada.',
          icono: Icons.drive_eta,
          archivo: _fotoLicencia,
          obligatorio: false,
          onSeleccionar: () async {
            final f = await _picker.pickImage(
                source: ImageSource.gallery, imageQuality: 80);
            if (f != null) setState(() => _fotoLicencia = f);
          },
          onBorrar: () => setState(() => _fotoLicencia = null),
        ),
        const SizedBox(height: 12),
        _itemDocumento(
          titulo: 'SOAT',
          subtitulo: 'Foto o captura del SOAT vigente.',
          icono: Icons.shield_outlined,
          archivo: _fotoSoat,
          obligatorio: false,
          onSeleccionar: () async {
            final f = await _picker.pickImage(
                source: ImageSource.gallery, imageQuality: 80);
            if (f != null) setState(() => _fotoSoat = f);
          },
          onBorrar: () => setState(() => _fotoSoat = null),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _itemDocumento({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required XFile? archivo,
    required bool obligatorio,
    required VoidCallback onSeleccionar,
    required VoidCallback onBorrar,
  }) {
    final tieneFoto = archivo != null;
    return Container(
      decoration: BoxDecoration(
        color: tieneFoto ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tieneFoto
              ? Colors.green
              : (obligatorio ? Colors.black38 : Colors.black12),
          width: tieneFoto ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(
              tieneFoto ? Icons.check_circle : icono,
              color: tieneFoto ? Colors.green : Colors.black45,
            ),
            title: Text(titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(
              tieneFoto ? '✅ Foto cargada' : subtitulo,
              style: TextStyle(
                fontSize: 11,
                color: tieneFoto ? Colors.green.shade700 : Colors.black45,
              ),
            ),
            trailing: tieneFoto
                ? IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: onBorrar,
                    tooltip: 'Quitar foto',
                  )
                : null,
          ),
          if (tieneFoto)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(archivo.path),
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          if (!tieneFoto)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSeleccionar,
                      icon: const Icon(Icons.photo_library_outlined, size: 16),
                      label: const Text('Galería', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black26),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final f = await _picker.pickImage(
                            source: ImageSource.camera, imageQuality: 80);
                        if (f != null) {
                          setState(() {
                            if (titulo.contains('Selfie') || titulo.contains('Perfil')) _fotoPerfil = f;
                            else if (titulo.contains('Cédula')) _fotoCedula = f;
                            else if (titulo.contains('Licencia')) _fotoLicencia = f;
                            else if (titulo.contains('SOAT')) _fotoSoat = f;
                          });
                        }
                      },
                      icon: const Icon(Icons.camera_alt_outlined, size: 16),
                      label: const Text('Cámara', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black26),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // PASO 2 — DATOS
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
              helper: _rolSeleccionado == 'movil'
                  ? 'Debes ser mayor de 18 años'
                  : null,
            ),
            child: Text(
              _fechaNacimiento == null
                  ? 'Toca para seleccionar'
                  : '${_fechaNacimiento!.day.toString().padLeft(2, '0')}/'
                      '${_fechaNacimiento!.month.toString().padLeft(2, '0')}/'
                      '${_fechaNacimiento!.year}',
              style: TextStyle(
                color:
                    _fechaNacimiento == null ? Colors.black38 : Colors.black87,
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
          decoration: _decoracion(
              'Nombre de quien responde por la cuenta', Icons.badge),
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
            DropdownMenuItem(
                value: 'Supermercado', child: Text('Supermercado')),
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
          decoration:
              _decoracion('Dirección del local', Icons.location_on_outlined),
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
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.my_location, size: 16),
                label: Text(
                  _localLat != null
                      ? '📍 Ubicación fijada'
                      : 'Usar mi ubicación',
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
                label:
                    const Text('Fijar en mapa', style: TextStyle(fontSize: 12)),
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

    LatLng? puntoPinchado =
        _localLat != null ? LatLng(_localLat!, _localLng!) : null;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
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
  // PASO 3 — CUENTA
  // =========================================================================
  Widget _pasoCuenta() {
    final esAutoNum = _tipoMovil == 'prediario' || _tipoMovil == 'postdia';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_rolSeleccionado == 'movil' && _tipoMovil == 'suscripcion')
          // Suscripción: elige número manual 01-100
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: const Text(
                  'movil',
                  style: TextStyle(
                      color: Color(0xff3AF500),
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _numeroMovilCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _decoracion(
                    'Tu número (01-100)',
                    Icons.tag,
                    helper: 'Elige el número disponible que quieres usar',
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          )
        else if (_rolSeleccionado == 'movil' && esAutoNum)
          // Prediario / Postdia: número automático
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              border: Border.all(color: Colors.orange[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.orange[700], size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Número asignado automáticamente',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.orange[800]),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Recibirás un número en el rango 200-299. Tu cuenta se activa de inmediato.',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[700],
                            height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else if (_rolSeleccionado != 'movil')
          TextField(
            controller: _usuarioCtrl,
            decoration: _decoracion(
              _rolSeleccionado == 'local'
                  ? 'Usuario del local (Ej: localcentro)'
                  : 'Usuario (para iniciar sesión)',
              Icons.account_circle,
              helper: 'Solo letras sin tilde, números y guión bajo',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'))
            ],
          ),
        const SizedBox(height: 15),
        TextField(
          controller: _passwordCtrl,
          obscureText: !_verPassword,
          decoration: _decoracion(
                  'Contraseña (mínimo 4 caracteres)', Icons.lock_outline)
              .copyWith(
            suffixIcon: IconButton(
              icon: Icon(_verPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.black38),
              onPressed: () => setState(() => _verPassword = !_verPassword),
            ),
          ),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: _confirmarPasswordCtrl,
          obscureText: !_verConfirmarPassword,
          decoration:
              _decoracion('Confirmar contraseña', Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                  _verConfirmarPassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: Colors.black38),
              onPressed: () => setState(
                  () => _verConfirmarPassword = !_verConfirmarPassword),
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
              const Text('Revisa tus datos',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              _filaResumen(
                  'Rol',
                  _rolSeleccionado == 'movil'
                      ? 'Móvil'
                      : _rolSeleccionado == 'local'
                          ? 'Local'
                          : 'Cliente'),
              if (_rolSeleccionado == 'movil')
                _filaResumen(
                    'Tipo',
                    _tipoMovil == 'suscripcion'
                        ? 'Suscripción semanal'
                        : _tipoMovil == 'prediario'
                            ? 'Prediario'
                            : 'Postdia'),
              _filaResumen('Nombre', _nombreCtrl.text.trim()),
              if (_rolSeleccionado != 'local')
                _filaResumen(
                  'Usuario',
                  _rolSeleccionado == 'movil'
                      ? (_tipoMovil == 'suscripcion'
                          ? 'movil${_numeroMovilCtrl.text.trim().padLeft(2, '0')}'
                          : 'Se asignará automáticamente')
                      : _usuarioCtrl.text.trim(),
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
              onChanged: (val) =>
                  setState(() => _terminosAceptados = val ?? false),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 12.5, color: Colors.black87, height: 1.4),
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
            child: Text(etiqueta,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                width: 90,
                height: 90,
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
                style: TextStyle(
                    color: Colors.grey[400], fontSize: 13, height: 1.5),
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
                  _estadoFila(Icons.check_circle_outline,
                      '¡Registro completado!', Colors.green[400]!),
                  const SizedBox(height: 10),
                  _estadoFila(Icons.pending_outlined,
                      'Verificación por Central', Colors.amber[400]!),
                  const SizedBox(height: 10),
                  _estadoFila(Icons.rocket_launch_outlined,
                      'Activación de cuenta', Colors.grey[600]!),
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
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, '/', (r) => false),
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
      Text(texto,
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w500)),
    ]);
  }
}
