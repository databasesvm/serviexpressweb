// lib/utils/sonido_manager.dart
//
// MOTOR DE AUDIO IN-APP
// ======================
// Maneja la reproducción de sonidos cuando la app está en PRIMER PLANO.
// Para segundo plano (pantalla apagada / app minimizada), los sonidos
// viajan por OneSignal como parámetro de notificación push.
//
// DOS PLAYERS — sin conflictos de prioridad:
//
//   _playerPrincipal → alertas, notificaciones, cotizaciones, pánico.
//     Interrumpe cualquier sonido que esté sonando.
//     Método: reproducir()
//
//   _playerSecundario → botones UI, confirmaciones, chat suave.
//     No interrumpe al player principal.
//     Método: reproducirSuave()
//
// GUÍA DE USO POR SONIDO:
// ┌─────────────────────────────┬──────────────────────────────┐
// │ reproducir()                │ reproducirSuave()            │
// ├─────────────────────────────┼──────────────────────────────┤
// │ Sonidos.centralCotizacion   │ Sonidos.centralChat          │
// │ Sonidos.centralRadar        │ Sonidos.centralCancelado     │
// │ Sonidos.centralDemora       │ Sonidos.localAccion          │
// │ Sonidos.centralProblema     │ Sonidos.localCotizacion      │
// │ Sonidos.centralCaducado     │ Sonidos.localChat            │
// │ Sonidos.localRespuesta      │ Sonidos.movilConfirmar        │
// │ Sonidos.movilChatCentral    │ Sonidos.movilChatCliente     │
// │ Sonidos.alerta              │ Sonidos.movilParadero        │
// │ Sonidos.panico              │ Sonidos.movilCarga           │
// └─────────────────────────────┴──────────────────────────────┘

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

// =========================================================================
// CATÁLOGO DE SONIDOS — Referencia única para toda la app
// Importar este archivo da acceso tanto a SonidoManager como a Sonidos.
// =========================================================================
class Sonidos {
  Sonidos._(); // No instanciable

  // CENTRAL
  static const String centralChat = 'central_chat';
  static const String centralCotizacion = 'central_cotizacion';
  static const String centralRadar = 'central_radar';
  static const String centralDemora = 'central_demora';
  static const String centralProblema = 'central_problema';
  static const String centralCaducado = 'central_caducado';
  static const String centralCancelado = 'central_cancelado';

  // MÓVIL
  static const String alerta = 'alerta';
  static const String movilChatCliente = 'movil_chat_cliente';
  static const String movilChatCentral = 'movil_chat_central';
  static const String movilConfirmar = 'movil_confirmar';
  static const String movilCarga = 'movil_cargar';
  static const String movilParadero = 'movil_paradero';
  static const String movilConectado = 'movil_conectado';  // Al activar turno
  static const String movilFinalizar = 'movil_finalizar';  // Al completar servicio (hold)

  // LOCAL
  static const String localAccion = 'local_accion';
  static const String localEstado = 'local_estado';
  static const String localCotizacion = 'local_cotizacion';
  static const String localRespuesta = 'local_respuesta';
  static const String localChat = 'local_chat';

  // COMPARTIDO
  static const String panico = 'panico';
}

class SonidoManager {
  // =========================================================================
  // SINGLETON — Una sola instancia en toda la app
  // =========================================================================
  static final SonidoManager _instancia = SonidoManager._interno();
  factory SonidoManager() => _instancia;

  SonidoManager._interno() {
    // setAudioContext solo aplica en Android/iOS — en web la API de audio
    // es completamente diferente y este bloque causaría un crash en runtime.
    if (!kIsWeb) {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            audioFocus: AndroidAudioFocus.gain,
            usageType: AndroidUsageType.notificationRingtone,
            contentType: AndroidContentType.sonification,
            stayAwake: true,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    }
    _playerPrincipal.setReleaseMode(ReleaseMode.stop);
    _playerSecundario.setReleaseMode(ReleaseMode.stop);
    _playerPanico.setReleaseMode(ReleaseMode.loop);
  }

  final AudioPlayer _playerPrincipal = AudioPlayer();
  final AudioPlayer _playerSecundario = AudioPlayer();
  final AudioPlayer _playerPanico =
      AudioPlayer(); // Dedicado: loop hasta cerrar

  // =========================================================================
  // REPRODUCCIÓN PRINCIPAL — Interrumpe lo que esté sonando
  // Para: alertas, notificaciones importantes, cotizaciones, pánico
  // =========================================================================
  Future<void> reproducir(String nombreArchivo) async {
    if (kIsWeb) return; // Web no usa AssetSource de sounds/
    try {
      await _playerPrincipal.stop();
      await _playerPrincipal.play(AssetSource('sounds/$nombreArchivo.mp3'));
    } catch (e) {
      debugPrint('SonidoManager › reproducir "$nombreArchivo" → $e');
    }
  }

  Future<void> reproducirSuave(String nombreArchivo) async {
    if (kIsWeb) return;
    try {
      await _playerSecundario.stop();
      await _playerSecundario.play(AssetSource('sounds/$nombreArchivo.mp3'));
    } catch (e) {
      debugPrint('SonidoManager › reproducirSuave "$nombreArchivo" → $e');
    }
  }

  Future<void> reproducirPanico() async {
    if (kIsWeb) return;
    try {
      await _playerPanico.stop();
      await _playerPanico.play(AssetSource('sounds/${Sonidos.panico}.mp3'));
    } catch (e) {
      debugPrint('SonidoManager › reproducirPanico → $e');
    }
  }

  Future<void> detenerPanico() async {
    if (kIsWeb) return;
    try {
      await _playerPanico.stop();
    } catch (_) {}
  }

  // =========================================================================
  // SILENCIAR — Corta los tres players de inmediato
  // Usar al navegar fuera de la pantalla o en modo "No molestar"
  // =========================================================================
  Future<void> silenciar() async {
    try {
      await _playerPrincipal.stop();
      await _playerSecundario.stop();
      await _playerPanico.stop();
    } catch (_) {}
  }

  // =========================================================================
  // DISPOSE — Llamar en el dispose() del widget que lo inicializó
  // =========================================================================
  void dispose() {
    _playerPrincipal.dispose();
    _playerSecundario.dispose();
    _playerPanico.dispose();
  }
}
