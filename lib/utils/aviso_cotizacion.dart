// ═══════════════════════════════════════════════════════════════════════════
// AVISO "LA CENTRAL TE RESPONDIÓ" (cliente e invitado)
//
// Cuando un pedido pasa de 'cotizacion' a 'cotizada' (la Central puso el
// precio) y la pantalla del cliente/invitado está abierta:
//   • suena su sonido propio (fn_cotizacion — no es la alerta ni la alarma),
//   • vibra el celular,
//   • el título de la pestaña cambia a "(1) 💬 Precio listo",
//   • si la pestaña está oculta, notificación del navegador,
//   • ventana grande con el precio y APROBAR Y PEDIR / RECHAZAR.
// Con la app cerrada (cliente registrado en la app) avisa el push del
// servidor (trg_aviso_cotizacion_cliente).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'sonido_manager.dart';
import 'web_notif.dart';
import 'tema_serviexpress.dart';

/// Llamar al ENVIAR un pedido (viene de un toque): pide permiso de
/// notificaciones del navegador para poder avisar cuando responda la Central.
void prepararAvisoRespuesta() {
  if (!kIsWeb) return;
  // Permiso vía OneSignal: crea la suscripción web para avisar aunque la
  // página esté cerrada. (Si OneSignal no carga, el permiso del navegador
  // igual sirve para el aviso con la pestaña en segundo plano.)
  WebAlertaManager.pushPermiso();
  WebAlertaManager.pedirPermisoConToque();
}

/// Invitado (sin cuenta): marca su navegador con el número de pedido para
/// que el servidor le envíe "La Central te respondió" a él.
void registrarPedidoInvitadoParaAviso(int pedidoId) {
  if (kIsWeb) WebAlertaManager.pushTag('pedido_invitado', '$pedidoId');
}

/// Cliente registrado en el navegador: lo identifica en OneSignal con el
/// mismo id que usa la app, así el aviso del servidor le llega también aquí.
void registrarClienteParaAviso(String usuarioId) {
  if (kIsWeb) WebAlertaManager.pushLogin(usuarioId);
}

/// Vigila los pedidos y avisa una sola vez por pedido cuando llega el precio.
class VigiaCotizacion {
  final Map<int, String> _estados = {};
  final Set<int> _avisados = {};
  bool _dialogoAbierto = false;

  /// [servicios]: pedidos que la pantalla está mostrando ahora.
  /// [onResponder]: aprobar (true) o rechazar (false) — la misma acción de
  /// los botones de la tarjeta.
  void revisar(
    BuildContext context,
    List<Map<String, dynamic>> servicios, {
    required Future<void> Function(Map<String, dynamic> servicio, bool aprobar) onResponder,
  }) {
    Map<String, dynamic>? nuevo;
    for (final s in servicios) {
      final id = (s['id'] as num?)?.toInt();
      if (id == null) continue;
      final estado = s['estado']?.toString() ?? '';
      final antes = _estados[id];
      _estados[id] = estado;
      if (estado != 'cotizada' || _avisados.contains(id)) continue;
      // Avisa si pasó de cotización → cotizada mientras miraba, o si al
      // abrir la pantalla ya había un precio esperando respuesta.
      if (antes == 'cotizacion' || antes == null) {
        _avisados.add(id);
        nuevo ??= s;
      }
    }
    if (nuevo == null || _dialogoAbierto) return;
    final servicio = nuevo;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _avisar(context, servicio, onResponder);
    });
  }

  Future<void> _avisar(
    BuildContext context,
    Map<String, dynamic> s,
    Future<void> Function(Map<String, dynamic>, bool) onResponder,
  ) async {
    final tarifa = (s['tarifa'] as num?)?.toDouble() ?? 0;
    final precio = PrecioServicioSE.formatoPeso(tarifa);
    final estilo = EstiloServicio.deTipo(s['tipo_servicio']?.toString());

    // Sonido propio + vibración
    SonidoManager().reproducirSuave(Sonidos.fnCotizacion);
    HapticFeedback.heavyImpact();
    if (kIsWeb) {
      WebAlertaManager.vibrar([300, 150, 300]);
      WebAlertaManager.ponerTitulo('(1) 💬 Precio listo — ServiExpress');
      if (WebAlertaManager.pestanaOculta()) {
        WebAlertaManager.mostrar(
          titulo: '💬 La Central te respondió',
          cuerpo: 'Precio de tu ${estilo.nombreCorto.toLowerCase()}: $precio. Entra para aprobarlo.',
          segundos: 30,
        );
      }
    }

    _dialogoAbierto = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool enviando = false;
        return StatefulBuilder(builder: (ctx, setSt) {
          Future<void> responder(bool aprobar) async {
            setSt(() => enviando = true);
            try {
              await onResponder(s, aprobar);
            } finally {
              if (ctx.mounted) Navigator.pop(ctx);
            }
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadioTarjetaSE)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: estilo.color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(child: Text('💬', style: TextStyle(fontSize: 38))),
                  ),
                  const SizedBox(height: 14),
                  const Text('¡La Central te respondió!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black87)),
                  const SizedBox(height: 6),
                  Text('Precio de tu ${estilo.nombreCorto.toLowerCase()}:',
                      style: const TextStyle(fontSize: 15, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(precio,
                      style: TextStyle(
                          fontSize: 34, fontWeight: FontWeight.w900, color: estilo.colorIcono)),
                  if ((s['destino'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${s['origen'] ?? ''} → ${s['destino'] ?? ''}',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                  const SizedBox(height: 18),
                  BotonPrincipalSE(
                    texto: 'APROBAR Y PEDIR',
                    color: kVerdeSE,
                    icono: Icons.check_rounded,
                    cargando: enviando,
                    textoCargando: 'ENVIANDO…',
                    onPressed: () => responder(true),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        side: BorderSide(color: Colors.red[300]!),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: enviando ? null : () => responder(false),
                      child: const Text('RECHAZAR',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  TextButton(
                    onPressed: enviando ? null : () => Navigator.pop(ctx),
                    child: const Text('Decidir después',
                        style: TextStyle(color: Colors.black45, fontSize: 13)),
                  ),
                ]),
              ),
            ),
          );
        });
      },
    );
    _dialogoAbierto = false;
    if (kIsWeb) WebAlertaManager.restaurarTitulo();
  }
}
