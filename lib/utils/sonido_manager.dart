// lib/utils/sonido_manager.dart
//
// MOTOR DE AUDIO IN-APP
// ======================
// Maneja la reproducción de sonidos cuando la app está en PRIMER PLANO.
// Para segundo plano en móvil (pantalla apagada / app minimizada), los sonidos
// viajan por OneSignal como parámetro de notificación push.
//
// EN WEB (Flutter web — navegador de escritorio o teléfono):
//   • Los sonidos se reproducen via HTML Audio API (audioplayers lo maneja).
//   • Las notificaciones emergentes (toast Windows/Android) van por la
//     Web Notifications API → WebAlertaManager (web_notif.dart).
//   • Se pide permiso de notificaciones al crear el singleton (una sola vez).
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
// │ Sonidos.fnCotizacion        │                              │
// └─────────────────────────────┴──────────────────────────────┘

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'web_notif.dart';

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
  static const String master = 'master';                   // Push suave para rango MASTER
  static const String movilInactividad = 'movil_inactividad'; // Aviso 5h45min sin servicios
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

  // FARMANORTE (sede FN ↔ central)
  /// Suena en la central cuando llega solicitud de cotización desde una sede FN.
  /// Suena en la sede FN cuando la central responde la cotización.
  static const String fnCotizacion = 'fn_cotizacion';

  // COMPARTIDO
  static const String panico = 'panico';
}

class SonidoManager {
  // =========================================================================
  // TEXTOS PARA NOTIFICACIONES WEB — titulo y cuerpo del toast del SO
  // Solo aplica en reproducir() cuando kIsWeb == true.
  // reproducirSuave() no genera toast (son sonidos de UI en segundo plano).
  // =========================================================================
  static const Map<String, List<String>> _alertasWeb = {
    Sonidos.centralCotizacion: ['📋 Nueva cotización', 'Cotización pendiente de asignar'],
    Sonidos.centralRadar:      ['🚨 Servicio en radar', 'Nuevo servicio disponible'],
    Sonidos.centralDemora:     ['⏰ Demora', 'Un móvil reporta demora'],
    Sonidos.centralProblema:   ['⚠ Problema', 'Un móvil reportó un problema'],
    Sonidos.centralCaducado:   ['⏱ Caducado', 'Un servicio ha caducado'],
    Sonidos.centralCancelado:  ['❌ Cancelado', 'Un servicio fue cancelado'],
    Sonidos.fnCotizacion:      ['💊 Cotización FN', 'Nueva solicitud de Farmanorte'],
    Sonidos.localRespuesta:    ['✅ Respuesta Central', 'La central respondió tu solicitud'],
    Sonidos.localEstado:       ['📦 Estado actualizado', 'El estado de tu pedido cambió'],
    Sonidos.panico:            ['🚨 PÁNICO', '¡Alerta de emergencia activada!'],
    Sonidos.alerta:            ['🔔 Alerta', 'Nuevo evento en ServiMoto'],
  };

  // =========================================================================
  // SINGLETON — Una sola instancia en toda la app
  // =========================================================================
  static final SonidoManager _instancia = SonidoManager._interno();
  factory SonidoManager() => _instancia;

  SonidoManager._interno() {
    // AudioContext solo aplica en Android/iOS — en web la API de audio
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
    } else {
      // En web: pedir permiso de notificaciones al navegador (una sola vez).
      // El navegador recuerda la respuesta entre sesiones.
      WebAlertaManager.pedirPermiso();
    }
    _playerPrincipal.setReleaseMode(ReleaseMode.stop);
    _playerSecundario.setReleaseMode(ReleaseMode.stop);
    _playerPanico.setReleaseMode(ReleaseMode.loop);
  }

  final AudioPlayer _playerPrincipal = AudioPlayer();
  final AudioPlayer _playerSecundario = AudioPlayer();
  final AudioPlayer _playerPanico = AudioPlayer(); // Dedicado: loop hasta cerrar

  // =========================================================================
  // REPRODUCCIÓN PRINCIPAL — Interrumpe lo que esté sonando
  // Para: alertas, notificaciones importantes, cotizaciones, pánico
  // En web: además lanza notificación emergente del SO (toast Windows/Android).
  // =========================================================================
  Future<void> reproducir(String nombreArchivo) async {
    try {
      await _playerPrincipal.stop();
      await _playerPrincipal.play(AssetSource('sounds/$nombreArchivo.mp3'));
    } catch (e) {
      debugPrint('SonidoManager › reproducir "$nombreArchivo" → $e');
    }
    // Toast del navegador (solo en web)
    if (kIsWeb) {
      final alerta = _alertasWeb[nombreArchivo];
      if (alerta != null) {
        WebAlertaManager.mostrar(titulo: alerta[0], cuerpo: alerta[1]);
      }
    }
  }

  // =========================================================================
  // REPRODUCCIÓN SUAVE — No interrumpe el player principal
  // Para: confirmaciones, chat, botones UI
  // En web: reproduce sonido pero NO muestra toast (son eventos de fondo).
  // =========================================================================
  Future<void> reproducirSuave(String nombreArchivo) async {
    try {
      await _playerSecundario.stop();
      await _playerSecundario.play(AssetSource('sounds/$nombreArchivo.mp3'));
    } catch (e) {
      debugPrint('SonidoManager › reproducirSuave "$nombreArchivo" → $e');
    }
  }

  // =========================================================================
  // PÁNICO — Loop hasta detenerPanico()
  // =========================================================================
  Future<void> reproducirPanico() async {
    try {
      await _playerPanico.stop();
      await _playerPanico.play(AssetSource('sounds/${Sonidos.panico}.mp3'));
    } catch (e) {
      debugPrint('SonidoManager › reproducirPanico → $e');
    }
    if (kIsWeb) {
      WebAlertaManager.mostrar(
        titulo: '🚨 PÁNICO',
        cuerpo: '¡Alerta de emergencia activada!',
      );
    }
  }

  Future<void> detenerPanico() async {
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
