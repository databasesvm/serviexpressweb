// lib/screens/login_screen.dart
//
// CAMBIOS VS VERSIÓN ANTERIOR
// ============================
// [FIX #1 - SEGURIDAD] Las contraseñas nunca se guardan en texto plano.
//   - Login: hashea antes de comparar contra la BD.
//   - SharedPreferences: guarda el hash (clave 'saved_hash'), no el texto.
//   - Migración silenciosa: si el usuario existente tiene contraseña en texto
//     plano, la actualiza a hash la primera vez que inicia sesión correctamente.
//
// [FIX #2 - BUG CRÍTICO] CentralScreen ahora recibe el objeto `usuario`.
//   - La llamada anterior era `const CentralScreen()` → widget.usuario == null.
//   - Ahora es `CentralScreen(usuario: usuario)`.
//
// [REFACTOR] La lógica de enrutamiento y filtro de usuario se extrajo a
//   _navegarSegunRol() y _filtrarUsuarioValido() para eliminar duplicación
//   entre el login manual y el auto-login.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serviexpress_app/utils/auth_helper.dart'; // <-- SEGURIDAD: hash de contraseñas
import 'package:flutter/services.dart';
import 'central_screen.dart';
import 'movil_screen.dart';
import 'package:serviexpress_app/screens/local_screen.dart';
import 'package:serviexpress_app/screens/cliente_screen.dart';
import 'package:serviexpress_app/screens/registro_screen.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:serviexpress_app/screens/guest_home_screen.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';
import 'package:serviexpress_app/services/ota_updater.dart';
import 'package:serviexpress_app/utils/deeplink_service.dart';
import 'package:serviexpress_app/screens/pedidos_cliente_screen.dart';
import 'package:serviexpress_app/screens/sede_fn_screen.dart';
import 'package:serviexpress_app/screens/supervisor_fn_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _telefonoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _cargando = false;
  bool _guardarCredenciales = false;
  bool _verPassword = false;
  String? _mensajeError;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    _verificarSesionGuardada();
  }

  @override
  void dispose() {
    _telefonoController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // SESIÓN REAL — igual que Instagram/Facebook/TikTok
  // =========================================================================
  // ANTES: cada arranque guardaba usuario+contraseña y volvía a
  // autenticarse contra la BD cada vez — dependía de la red en cada
  // apertura, y si la conexión se quedaba a medias (sin fallar, sin
  // responder), la pantalla se congelaba esperando para siempre.
  //
  // AHORA: al iniciar sesión se guarda el USUARIO COMPLETO localmente.
  // Al abrir la app, si existe esa sesión, se entra DE INMEDIATO sin
  // tocar la red — minimizar, cerrar a la fuerza, o reiniciar el
  // teléfono nunca vuelven a pedir inicio de sesión. Las pantallas ya
  // tienen sus propios streams en vivo que corrigen solos cualquier
  // cosa que haya cambiado mientras tanto (suspensión, etc.).
  Future<void> _verificarSesionGuardada() async {
    final prefs = await SharedPreferences.getInstance();
    // Sin gate — si hay sesion guardada siempre se intenta el auto-login.
    // El flag 'auto_login' SOLO controla si la sesion sobrevive el cierre
    // completo de la app (lo gestiona main.dart con AppLifecycleState.detached).
    final sesionJson = prefs.getString('sesion_usuario_json');

    // CAMINO RÁPIDO — sesión real guardada. Cero red, entra al instante.
    if (sesionJson != null) {
      try {
        final Map<String, dynamic> usuario = jsonDecode(sesionJson);
        if (mounted) _navegarSegunRol(usuario);
        return;
      } catch (_) {
        await prefs.remove('sesion_usuario_json');
        // Si el JSON está corrupto, seguimos al camino legacy de abajo.
      }
    }

    // CAMINO LEGACY — migración única para sesiones guardadas ANTES de
    // este cambio (solo tenían usuario+hash, no el usuario completo).
    // Si funciona, se guarda ya en el formato nuevo para que la
    // próxima vez entre por el camino rápido sin tocar la red.
    final idGuardado = prefs.getString('saved_phone');
    final hashGuardado = prefs.getString('saved_hash');
    if (idGuardado != null && hashGuardado != null) {
      setState(() {
        _telefonoController.text = idGuardado;
        _guardarCredenciales = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoLoginSilenciosoLegacy(idGuardado, hashGuardado);
      });
    }
  }

  // =========================================================================
  // AUTO-LOGIN LEGACY — solo corre una vez por dispositivo, para migrar
  // sesiones viejas al modelo nuevo. Con timeout: si la red se cuelga,
  // no deja la pantalla esperando para siempre (el bug original).
  // =========================================================================
  Future<void> _autoLoginSilenciosoLegacy(
    String identificador,
    String hash,
  ) async {
    setState(() => _cargando = true);
    try {
      final respuesta = await Supabase.instance.client
          .from('usuarios')
          .select()
          .or('telefono.eq."$identificador",usuario.ilike."$identificador"')
          .eq('contrasena', hash)
          .timeout(const Duration(seconds: 8));

      if (respuesta.isEmpty) {
        // El hash no coincide (clave cambiada desde otro dispositivo).
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_login', false);
        return;
      }

      final usuario = _filtrarUsuarioValido(respuesta, identificador);
      if (usuario == null || usuario['activo'] == false) return;

      // Migramos al formato nuevo — la próxima apertura ya es instantánea.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sesion_usuario_json', jsonEncode(usuario));

      if (mounted) _navegarSegunRol(usuario);
    } catch (_) {
      // Fallo de red o timeout: el usuario verá la pantalla de login normal.
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // =========================================================================
  // LOGIN MANUAL — Hashea, compara, migra y enruta
  // =========================================================================
  Future<void> _iniciarSesion() async {
    setState(() {
      _cargando = true;
      _mensajeError = null;
    });

    try {
      final identificador = _telefonoController.text.trim();
      final claveTexto = _passwordController.text.trim();

      if (identificador.isEmpty || claveTexto.isEmpty) {
        setState(() => _mensajeError = 'Completa todos los campos.');
        return;
      }

      final claveHash = hashContrasena(claveTexto);

      // --- PASO 1: Intentamos con hash (flujo normal para cuentas nuevas/migradas) ---
      var respuesta = await Supabase.instance.client
          .from('usuarios')
          .select()
          .or('telefono.eq."$identificador",usuario.ilike."$identificador"')
          .eq('contrasena', claveHash)
          .timeout(const Duration(seconds: 8));

      // --- PASO 2: MIGRACIÓN SILENCIOSA para cuentas con contraseña en texto plano ---
      bool esMigracion = false;
      if (respuesta.isEmpty) {
        final respuestaLegacy = await Supabase.instance.client
            .from('usuarios')
            .select()
            .or('telefono.eq."$identificador",usuario.ilike."$identificador"')
            .eq('contrasena', claveTexto) // Comparación legacy con texto plano
            .timeout(const Duration(seconds: 8));

        if (respuestaLegacy.isNotEmpty) {
          respuesta = respuestaLegacy;
          esMigracion = true; // Marcamos para actualizar la BD al final
        }
      }

      if (respuesta.isEmpty) {
        setState(() => _mensajeError = 'Usuario o contraseña incorrectos.');
        return;
      }

      // --- PASO 3: Filtro de roles ---
      final usuario = _filtrarUsuarioValido(respuesta, identificador);

      if (usuario == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ACCESO RESTRINGIDO: El personal (Móviles/Locales) '
                'debe iniciar sesión con su USUARIO, no con su teléfono.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      if (usuario['activo'] == false) {
        setState(
          () => _mensajeError =
              'Cuenta inactiva. Central debe validar tu registro.',
        );
        return;
      }

      // --- PASO 4: Si es migración, actualizamos la BD al hash ---
      if (esMigracion) {
        try {
          await Supabase.instance.client
              .from('usuarios')
              .update({'contrasena': claveHash})
              .eq('id', usuario['id']);
        } catch (_) {
          // Si falla la migración, no bloqueamos el acceso. Se intentará en el próximo login.
        }
      }

      // --- PASO 5: Persistir SESIÓN ---
      // Siempre guardamos sesion_usuario_json para que el auto-login funcione
      // aunque se minimice la app y el SO la mate por presión de memoria.
      // 'auto_login' solo controla si la sesión SOBREVIVE el cierre total
      // de la app (cuando detached se dispara en main.dart):
      //   true  → "mantener sesión" — nunca se borra, indestructible.
      //   false → se borra al cerrar la app completa, pero no al minimizar.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sesion_usuario_json', jsonEncode(usuario));
      await prefs.setBool('auto_login', _guardarCredenciales);
      // Llaves del modelo viejo — ya no se usan, las limpiamos.
      await prefs.remove('saved_phone');
      await prefs.remove('saved_hash');
      await prefs.remove('saved_password');

      if (mounted) _navegarSegunRol(usuario);
    } catch (e) {
      final bool esTimeout = e.toString().contains('TimeoutException');
      setState(
        () => _mensajeError = esTimeout
            ? 'Conexión lenta. Verifica tu señal e intenta de nuevo.'
            : 'Error de conexión. Intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // =========================================================================
  // HELPERS — Filtro de rol y enrutador central
  // =========================================================================

  /// Devuelve el primer usuario válido según las reglas de acceso por rol:
  /// - Clientes: pueden entrar con teléfono o usuario.
  /// - Personal (movil, local, central, master): SOLO con su campo 'usuario'.
  Map<String, dynamic>? _filtrarUsuarioValido(
    List<dynamic> lista,
    String identificador,
  ) {
    for (var u in lista) {
      final rol = u['rol'];
      final loginUsuario = u['usuario']?.toString().toLowerCase() ?? '';

      if (rol == 'cliente') return u; // Clientes: cualquier identificador
      if (loginUsuario == identificador.toLowerCase()) {
        return u; // Personal: solo usuario exacto
      }
    }
    return null;
  }

  /// Enrutador central: decide a qué pantalla va cada rol.
  /// [FIX #2] CentralScreen ahora recibe usuario correctamente.
  Future<void> _navegarSegunRol(Map<String, dynamic> usuario) async {
    final rol = usuario['rol'];

    if (!mounted) return;

    // VINCULAR EXTERNAL USER ID EN ONESIGNAL ─────────────────────────────────
    // Sin OneSignal.login(id), el dispositivo queda registrado de forma
    // anónima y include_external_user_ids no puede encontrarlo → 0 pushes.
    // Se hace aquí para cubrir tanto el login manual como el auto-login.
    if (!kIsWeb) {
      try {
        await OneSignal.login(usuario['id'].toString());
      } catch (_) {}
    }

    // OTA: verificar si hay nueva versión disponible antes de navegar.
    // Si hay update, muestra el diálogo; el usuario puede instalar o posponer.
    await OtaUpdater.verificar(context);

    if (!mounted) return;

    if (rol == 'master' || rol == 'central') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          // ✅ FIX: antes era `const CentralScreen()` → widget.usuario llegaba null
          builder: (context) => CentralScreen(usuario: usuario),
        ),
      );
    } else if (rol == 'movil') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MovilScreen(usuario: usuario)),
      );
    } else if (rol == 'local' || rol == 'aliado') {
      // Verificar estado de aprobación del local
      final estadoLocal = usuario['estado_local']?.toString() ?? 'aprobado';
      if (estadoLocal == 'pendiente') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => _LocalPendienteLoginScreen(
              nombreLocal: usuario['nombre']?.toString() ?? '',
            ),
          ),
        );
      } else if (estadoLocal == 'rechazado') {
        final motivo = usuario['motivo_rechazo']?.toString() ?? '';
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => _LocalRechazadoScreen(
              nombreLocal: usuario['nombre']?.toString() ?? '',
              motivo: motivo,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LocalScreen(usuario: usuario),
          ),
        );
      }
    } else if (rol == 'cliente') {
      // Si hay un deep link pendiente (ej. serviexpress://pedido?local=42),
      // navegamos directo al menú del local en lugar de ClienteScreen.
      final pendingLink = DeeplinkService.consumePending();
      if (pendingLink != null) {
        final localId = pendingLink['local_id'] as int?;
        if (localId != null) {
          // Primero navegar a ClienteScreen, luego abrir el local
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ClienteScreen(usuario: usuario),
            ),
          );
          // Pequeño delay para que el widget esté montado
          Future.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            _abrirLocalDesdeDeeplink(
              context,
              usuario,
              localId,
              items:
                  (pendingLink['items'] as List?)
                      ?.cast<Map<String, dynamic>>() ??
                  [],
            );
          });
          return;
        }
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ClienteScreen(usuario: usuario),
        ),
      );
    } else if (rol == 'sede_fn') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SedeFnScreen(usuario: usuario),
        ),
      );
    } else if (rol == 'supervisor_fn') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => SupervisorFnScreen(usuario: usuario),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alerta: El rol "$rol" no tiene panel asignado.'),
        ),
      );
    }
  }

  // =========================================================================
  /// Abre MenuLocalScreen para el local con [localId], buscando primero
  /// sus datos en Supabase. Si el link incluye items, los pre-llena en el carrito.
  Future<void> _abrirLocalDesdeDeeplink(
    BuildContext ctx,
    Map<String, dynamic> usuario,
    int localId, {
    List<Map<String, dynamic>> items = const [],
  }) async {
    try {
      final db = Supabase.instance.client;
      final localData = await db
          .from('usuarios')
          .select(
            'id, nombre, direccion, foto_perfil, tiempo_entrega, categoria_local, horario_apertura, horario_cierre, dias_semana, pedido_minimo',
          )
          .eq('id', localId)
          .single();

      // Intentar pre-cargar items si el link los incluye
      List<CartItem> carritoInicial = [];
      if (items.isNotEmpty) {
        final nombresProductos = items
            .map((i) => i['nombre'].toString())
            .toList();
        final prods = await db
            .from('productos')
            .select()
            .eq('local_id', localId)
            .eq('disponible', true)
            .inFilter('nombre', nombresProductos);

        for (final item in items) {
          final prod = (prods as List).cast<Map<String, dynamic>>().firstWhere(
            (p) => p['nombre'].toString() == item['nombre'].toString(),
            orElse: () => <String, dynamic>{},
          );
          if (prod.isNotEmpty) {
            carritoInicial.add(
              CartItem(
                producto: prod,
                cantidad: (item['cantidad'] as num?)?.toInt() ?? 1,
              ),
            );
          }
        }
      }

      if (!ctx.mounted) return;
      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => MenuLocalScreen(
            local: Map<String, dynamic>.from(localData),
            usuario: usuario,
            carritoInicial: carritoInicial,
          ),
        ),
      );
    } catch (_) {
      // Si falla, simplemente no navega al local — el usuario está en ClienteScreen
    }
  }

  // UI — Rediseño visual: cabecera negra con el logo real (mismo
  // lenguaje visual que el perfil de Móvil, para que la marca se vea
  // consistente en toda la app), contraseña con mostrar/ocultar, y
  // separación clara entre "ya tengo cuenta" y "pedir como invitado".
  // =========================================================================

  // =========================================================================
  // GOOGLE SIGN-IN
  // =========================================================================
  Future<void> _loginConGoogle() async {
    setState(() => _cargando = true);
    try {
      final googleSignIn = GoogleSignIn(
        serverClientId:
            '1055128360248-q4epf6f91h4q655klc9spe1slmiamno2.apps.googleusercontent.com',
        scopes: ['email', 'profile'],
      );
      final cuenta = await googleSignIn.signIn();
      if (cuenta == null) return; // usuario canceló

      final correo = cuenta.email.toLowerCase().trim();
      final nombre = cuenta.displayName ?? correo.split('@').first;
      final foto = cuenta.photoUrl ?? '';

      final db = Supabase.instance.client;

      // Buscar usuario existente por correo
      final res = await db
          .from('usuarios')
          .select()
          .eq('correo', correo)
          .maybeSingle();

      Map<String, dynamic> usuario;

      if (res != null) {
        // Ya existe → login directo
        usuario = Map<String, dynamic>.from(res);
      } else {
        // No existe → crear cuenta cliente automáticamente
        final usuarioGen =
            nombre.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') +
            DateTime.now().millisecondsSinceEpoch.toString().substring(8);
        final filaInsert = await db
            .from('usuarios')
            .insert({
              'nombre': nombre,
              'correo': correo,
              'usuario': usuarioGen,
              'rol': 'cliente',
              'telefono': '',
              'contrasena': hashContrasena(
                'google_\$correo',
              ), // no se usa para login
              'activo': true,
              'foto_perfil': foto,
              'google_auth': true,
            })
            .select()
            .single();
        usuario = Map<String, dynamic>.from(filaInsert);
      }

      if (usuario['activo'] == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tu cuenta está desactivada. Contacta a soporte.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Guardar sesión
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sesion_usuario_json', jsonEncode(usuario));
      await prefs.setBool('auto_login', true);

      if (mounted) _navegarSegunRol(usuario);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar con Google: \$e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // =========================================================================
  // RECUPERAR CONTRASEÑA
  // =========================================================================
  Future<void> _mostrarRecuperarContrasena() async {
    // ── Próximamente ─────────────────────────────────────────────────────────
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('🔒 Recuperar contraseña',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_rounded, color: Color(0xFFF59E0B), size: 48),
            SizedBox(height: 14),
            Text(
              'Esta función estará disponible próximamente.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 10),
            Text(
              'Por ahora, contacta a la Central Operativa para restablecer tu acceso.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(ctx).pop,
            child: const Text('ENTENDIDO', style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return;
    // ignore: dead_code
    final correoCtrl = TextEditingController();
    final codigoCtrl = TextEditingController();
    final nuevaClaveCtrl = TextEditingController();
    bool paso2 = false; // false=pide correo, true=pide código+nueva clave
    bool enviando = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              paso2 ? 'Código enviado' : 'Recuperar contraseña',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: paso2
                ? _contenidoPaso2(codigoCtrl, nuevaClaveCtrl)
                : _contenidoPaso1(correoCtrl),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff3AF500),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: enviando
                    ? null
                    : () async {
                        if (!paso2) {
                          // PASO 1: enviar código
                          final correo = correoCtrl.text.trim();
                          if (correo.isEmpty || !correo.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Escribe un correo válido'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          setDlg(() => enviando = true);
                          try {
                            await Supabase.instance.client.functions.invoke(
                              'recuperar-contrasena',
                              body: {'correo': correo},
                            );
                          } catch (_) {}
                          setDlg(() {
                            enviando = false;
                            paso2 = true;
                          });
                        } else {
                          // PASO 2: verificar código y cambiar clave
                          final codigo = codigoCtrl.text.trim();
                          final nuevaClave = nuevaClaveCtrl.text.trim();
                          if (codigo.length != 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('El código debe tener 6 dígitos'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          if (nuevaClave.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'La contraseña debe tener al menos 6 caracteres',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          setDlg(() => enviando = true);
                          final ok = await _verificarYCambiarClave(
                            correo: correoCtrl.text.trim(),
                            codigo: codigo,
                            nuevaClave: nuevaClave,
                          );
                          setDlg(() => enviando = false);
                          if (ok && ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '¡Contraseña actualizada! Ya puedes iniciar sesión.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      },
                child: enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        paso2 ? 'Cambiar contraseña' : 'Enviar código',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _contenidoPaso1(TextEditingController correoCtrl) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Escribe el correo asociado a tu cuenta. Te enviaremos un código de 6 dígitos.',
          style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: correoCtrl,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'tu@correo.com',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(
              Icons.email_outlined,
              color: Colors.white38,
              size: 18,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _contenidoPaso2(
    TextEditingController codigoCtrl,
    TextEditingController nuevaClaveCtrl,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green[900]!.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: Colors.green[400],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Código enviado a tu correo. Válido por 15 minutos.',
                  style: TextStyle(color: Colors.green[300], fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: codigoCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 6,
          ),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: const TextStyle(color: Colors.white24),
            counterText: '',
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: nuevaClaveCtrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Nueva contraseña',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: Colors.white38,
              size: 18,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.07),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Future<bool> _verificarYCambiarClave({
    required String correo,
    required String codigo,
    required String nuevaClave,
  }) async {
    try {
      final db = Supabase.instance.client;

      // Verificar código vigente
      final res = await db
          .from('usuarios')
          .select('id, reset_token, reset_token_exp')
          .eq('correo', correo.toLowerCase())
          .eq('reset_token', codigo)
          .maybeSingle();

      if (res == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Código incorrecto'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final exp = res['reset_token_exp']?.toString();
      if (exp != null && DateTime.parse(exp).isBefore(DateTime.now().toUtc())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El código ha expirado. Solicita uno nuevo.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }

      // Cambiar contraseña y limpiar token
      final nuevoHash = hashContrasena(nuevaClave);
      await db
          .from('usuarios')
          .update({
            'contrasena': nuevoHash,
            'reset_token': null,
            'reset_token_exp': null,
          })
          .eq('id', res['id']);

      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cambiar la contraseña. Intenta de nuevo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // --- CABECERA NEGRA CON LOGO ---
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(24, topPad + 20, 24, 24),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            'assets/logo.png',
                            height: 36,
                            width: 36,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  height: 36,
                                  width: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xff3AF500),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.motorcycle,
                                    color: Colors.black,
                                    size: 20,
                                  ),
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'ServiExpress',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Seguridad, rapidez y confianza en un solo servicio',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // --- CONTENIDO ---
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                    child: Column(
                      children: [
                        // --- TARJETA DE LOGIN ---
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Iniciar sesión',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _telefonoController,
                                decoration: InputDecoration(
                                  labelText: 'Usuario',
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF3AF500),
                                      width: 1.5,
                                    ),
                                  ),
                                  prefixIcon: const Icon(Icons.person_outline),
                                ),
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) => FocusScope.of(
                                  context,
                                ).requestFocus(_passwordFocus),
                                inputFormatters: [
                                  // Rechaza espacios y caracteres con acento/diacrítico
                                  FilteringTextInputFormatter.deny(
                                    RegExp(r'[^\x00-\x7F]'),
                                  ),
                                  FilteringTextInputFormatter.deny(
                                    RegExp(r'\s'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passwordController,
                                focusNode: _passwordFocus,
                                decoration: InputDecoration(
                                  labelText: 'Contraseña',
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF3AF500),
                                      width: 1.5,
                                    ),
                                  ),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _verPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: Colors.black38,
                                    ),
                                    onPressed: () => setState(
                                      () => _verPassword = !_verPassword,
                                    ),
                                  ),
                                ),
                                obscureText: !_verPassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_cargando) _iniciarSesion();
                                },
                              ),
                              const SizedBox(height: 10),
                              GestureDetector(
                                onTap: () => setState(
                                  () => _guardarCredenciales =
                                      !_guardarCredenciales,
                                ),
                                child: Row(
                                  children: [
                                    Theme(
                                      data: Theme.of(context).copyWith(
                                        unselectedWidgetColor: Colors.black38,
                                      ),
                                      child: Checkbox(
                                        value: _guardarCredenciales,
                                        activeColor: Colors.black,
                                        checkColor: const Color(0xff3AF500),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: (valor) => setState(
                                          () => _guardarCredenciales =
                                              valor ?? false,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Mantener mi sesión iniciada',
                                      style: TextStyle(
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_mensajeError != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.redAccent,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _mensajeError!,
                                        style: const TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: _cargando ? null : _iniciarSesion,
                                  child: _cargando
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Color(0xff3AF500),
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'INICIAR SESIÓN',
                                          style: TextStyle(
                                            color: Color(0xff3AF500),
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Center(
                                child: TextButton(
                                  onPressed: _mostrarRecuperarContrasena,
                                  child: const Text(
                                    '¿Olvidaste tu contraseña?',
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const RegistroScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    '¿Nuevo aquí? Crea tu cuenta gratis',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const _GoogleIcon(),
                                  label: const Text('Continuar con Google'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black87,
                                    side: const BorderSide(
                                      color: Colors.black38,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: _cargando ? null : _loginConGoogle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Expanded(child: Divider(thickness: 1)),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      'o',
                                      style: TextStyle(
                                        color: Colors.black45,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider(thickness: 1)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.directions_bike_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Pedir como invitado'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black87,
                                    side: const BorderSide(
                                      color: Colors.black38,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const GuestHomeScreen(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(
                                    Icons.location_on_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Rastrear mi pedido'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.black87,
                                    side: const BorderSide(
                                      color: Colors.black38,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const GuestTrackingScreen(),
                                    ),
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
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PANTALLA DE ESPERA — LOCAL PENDIENTE (acceso desde Login)
// ============================================================
class _LocalPendienteLoginScreen extends StatelessWidget {
  final String nombreLocal;
  const _LocalPendienteLoginScreen({required this.nombreLocal});

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
                child: Icon(
                  Icons.hourglass_top_rounded,
                  size: 44,
                  color: Colors.amber[400],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                nombreLocal.isNotEmpty ? nombreLocal : 'Tu local',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cuenta en revisión',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xff3AF500),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Tu solicitud aún está siendo evaluada por el equipo de Serviexpress. '
                'Recibirás una notificación cuando tu cuenta sea activada.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('sesion_usuario_json');
                    await prefs.setBool('auto_login', false);
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/',
                        (r) => false,
                      );
                    }
                  },
                  child: const Text('Cerrar sesión'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// PANTALLA DE RECHAZO — LOCAL RECHAZADO (acceso desde Login)
// ============================================================
class _LocalRechazadoScreen extends StatelessWidget {
  final String nombreLocal;
  final String motivo;
  const _LocalRechazadoScreen({
    required this.nombreLocal,
    required this.motivo,
  });

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
                  color: Colors.red[900]!.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red[600]!, width: 2),
                ),
                child: Icon(
                  Icons.cancel_outlined,
                  size: 44,
                  color: Colors.red[400],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                nombreLocal.isNotEmpty ? nombreLocal : 'Tu local',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Solicitud no aprobada',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red[400],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (motivo.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red[900]!.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.red[900]!.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.red[300],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          motivo,
                          style: TextStyle(
                            color: Colors.red[200],
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                'Para más información contacta al equipo de Serviexpress.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('sesion_usuario_json');
                    await prefs.setBool('auto_login', false);
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/',
                        (r) => false,
                      );
                    }
                  },
                  child: const Text('Volver al inicio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: const Text(
        'G',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF4285F4),
        ),
      ),
    );
  }
}
