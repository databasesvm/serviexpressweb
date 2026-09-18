import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/guest_home_screen.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/deeplink_service.dart';
import 'services/background_service.dart';

/// Clave global del Navigator — permite navegar desde DeeplinkService
/// sin necesitar un BuildContext explícito.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Captura errores Flutter (widgets, rendering)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  // Captura errores Dart fuera del árbol de widgets — evita pantalla negra
  // silenciosa en web release (el error se loguea pero runApp() igual corre)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true;
  };

  try {
    // OneSignal solo en Android/iOS — no tiene soporte web
    if (!kIsWeb) {
      OneSignal.Debug.setLogLevel(
        kDebugMode ? OSLogLevel.verbose : OSLogLevel.none,
      );
      OneSignal.initialize("207d1d0a-0218-46e0-9f35-7d8d88f6765a");
      OneSignal.Notifications.requestPermission(true);
    }

    await Supabase.initialize(
      url: 'https://oukiofdtargjrclualgm.supabase.co',
      // Se usa la clave anon JWT (legacy) en lugar de publishableKey porque
      // publishableKey requiere "Anonymous sign-ins" habilitado en Supabase para
      // funcionar correctamente con PostgREST HTTP. Sin eso, el SDK no puede
      // obtener un JWT válido y todos los INSERTs/UPDATEs retornan 401.
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im91a2lvZmR0YXJnanJjbHVhbGdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk0OTY0NzcsImV4cCI6MjA5NTA3MjQ3N30.LpX4HqQjlm1wfOGq0hdP4tFuVO6MzUV0bQVfGftf5Hk',
    );

    // Deep links + share intent solo en Android/iOS
    if (!kIsWeb) await DeeplinkService.init();

    // Opción B: inicializar foreground service sin await — no bloquea el hilo
    // principal al instalar/actualizar la app (previene ANR en arranque frío).
    // ignore: discarded_futures
    if (!kIsWeb) initBackgroundService();
  } catch (e, st) {
    debugPrint('ERROR en main() antes de runApp: $e\n$st');
  }

  runApp(const ServiexpressExpressApp());
}

/// Habilita drag con mouse + trackpad en todas las plataformas,
/// mantiene la física nativa de cada SO (bounce en iOS, clamp en Android).
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class ServiexpressExpressApp extends StatefulWidget {
  const ServiexpressExpressApp({super.key});

  @override
  State<ServiexpressExpressApp> createState() => _ServiexpressExpressAppState();
}

class _ServiexpressExpressAppState extends State<ServiexpressExpressApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      SharedPreferences.getInstance().then((prefs) {
        final mantenerSesion = prefs.getBool('auto_login') ?? false;
        if (!mantenerSesion) {
          prefs.remove('sesion_usuario_json');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Serviexpress Express',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      locale: const Locale('es', 'CO'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'CO'), Locale('en', 'US')],
      theme: ThemeData(primaryColor: Colors.black),
      scrollBehavior: const _AppScrollBehavior(),
      // Web: si la URL contiene '/form' → GuestHomeScreen (invitados)
      //      cualquier otra ruta      → LoginScreen (operadores)
      // Móvil: siempre LoginScreen.
      home: (kIsWeb && Uri.base.path.contains('/form'))
          ? const GuestHomeScreen()
          : const LoginScreen(),
    );
  }
}
