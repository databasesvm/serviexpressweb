// ignore_for_file: use_build_context_synchronously, invalid_use_of_protected_member
part of 'central_screen.dart';

// Utilidades varias de la Central (limpieza de caducados, demoras, link de
// invitado, ranking y perfil). El botón de pánico / convocatoria fue
// eliminado por completo de la app y del servidor.
extension CentralScreenUtilidades on _CentralScreenState {

  Future<void> _ejecutarLimpiezaDeCaducados() async {
    // POLÍTICA: los servicios en estado 'pendiente' NUNCA se caducan
    // automáticamente por falta de móviles. Permanecen activos hasta que
    // la central decida cancelarlos manualmente.
    //
    // Solo se caduca automáticamente una cotización que el cliente no
    // respondió en 30 minutos.
    try {
      final corte30min = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 30))
          .toIso8601String();

      // Caducar SOLO cotizaciones sin respuesta del cliente en 30 min
      await Supabase.instance.client
          .from('servicios')
          .update({
            'estado': 'caducado',
            'observacion':
                'SISTEMA: Cotización expirada. El cliente no respondió en 30 minutos.',
          })
          .eq('estado', 'cotizada')
          .lt('created_at', corte30min);
    } catch (e) {
      debugPrint('Error en limpieza de caducados: $e');
    }
  }

  // Detecta servicios activos con +30 min y suena UNA sola vez por servicio.
  // Se llama desde el timer cada 5 minutos.
  // Usa _cacheSvcMonitor (mismo filtro archivado=false que el stream) para
  // garantizar que solo suenan servicios visibles para el operador y evitar
  // "alarmas fantasma" de servicios ocultos/colapsados o fuera del límite
  // de 500 del stream. El banner "DEMORAS ACTIVAS" en el monitor muestra
  // el detalle en tiempo real — aquí solo sonamos.
  Future<void> _detectarDemorasYSonar() async {
    try {
      final corte = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 30));

      bool sonoEnEsteCiclo = false;

      for (final s in _cacheSvcMonitor) {
        final estado = s['estado']?.toString() ?? '';
        if (!['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'problema']
            .contains(estado)) continue;

        final String? updStr = s['updated_at']?.toString();
        if (updStr == null) continue;
        final updatedAt = DateTime.parse(updStr).toUtc();
        if (updatedAt.isAfter(corte)) continue; // aún no lleva 30 min

        final int id = s['id'] as int;
        if (!_demorasAlertadas.contains(id)) {
          _demorasAlertadas.add(id);
          if (!sonoEnEsteCiclo) {
            // Una sola alarma por ciclo aunque haya varios demorados
            _sonidos.reproducir(Sonidos.centralDemora);
            sonoEnEsteCiclo = true;
          }
        }
      }
    } catch (e) {
      debugPrint('_detectarDemorasYSonar: $e');
    }
  }

  // ── LINK DE PEDIDO POR WHATSAPP ─────────────────────────────────────────
  /// Muestra un diálogo para capturar el número del cliente y abre WhatsApp
  /// con un mensaje que incluye el link de la app web para que el cliente
  /// haga su propio pedido como invitado.
  Future<void> _enviarLinkInvitado(BuildContext ctx) async {
    final telCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.share_rounded, color: Color(0xff25D366), size: 22),
            SizedBox(width: 10),
            Text(
              'Enviar link al cliente',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'El cliente recibirá un link por WhatsApp para hacer su pedido directamente como invitado.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: telCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Número WhatsApp del cliente',
                labelStyle: const TextStyle(color: Colors.white54),
                prefixText: '+57 ',
                prefixStyle: const TextStyle(color: Colors.white70),
                hintText: '3001234567',
                hintStyle: const TextStyle(color: Colors.white30),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xff25D366)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Abrir WhatsApp'),
            onPressed: () => Navigator.pop(dlgCtx, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    telCtrl.dispose();

    final tel = telCtrl.text.trim().replaceAll(RegExp(r'\D'), '');
    if (tel.isEmpty) return;

    // Número colombiano: prefijo 57 si no empieza con +
    final numero = tel.startsWith('57') ? tel : '57$tel';
    final mensaje = Uri.encodeComponent(
      '¡Hola! 👋 Puedes hacer tu pedido de Serviexpress directamente desde aquí:\n'
      '${_CentralScreenState._kUrlApp}\n\n'
      'Solo abre el link, elige el tipo de servicio y nosotros te atendemos. '
      '¡También puedes registrarte para guardar tus datos! 🛵',
    );
    final waUrl = Uri.parse('https://wa.me/$numero?text=$mensaje');

    if (await canLaunchUrl(waUrl)) {
      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
    }
  }

  // FIX #7: antes calculaba su propio ranking consultando el campo `puntuacion`
  // de la tabla `usuarios` — una fuente de verdad distinta a RankingScreen.
  // Ahora navega directamente a RankingScreen, que es la única fuente de verdad.
  // Beneficio: cualquier mejora a la lógica de ranking aplica automáticamente aquí.
  void _mostrarRankingSemanalDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RankingScreen()),
    );
  }

  void _mostrarPerfilHistorialCompleto(
    BuildContext context,
    String nombreMovil,
    List<Map<String, dynamic>> todoHistorial,
  ) {
    final completados = todoHistorial
        .where(
          (f) =>
              f['estado'] == 'finalizado' &&
              !(f['observacion'] ?? '').contains('[MARCA DE FALLA]'),
        )
        .length;
    final cancelados = todoHistorial
        .where((f) => f['estado'] == 'cancelado')
        .length;
    final demorados = todoHistorial
        .where((f) => f['estado'] == 'finalizado_por_demora')
        .length;
    final fallas = todoHistorial
        .where(
          (f) =>
              f['estado'] == 'finalizado_con_problema' ||
              (f['observacion'] ?? '').contains('[MARCA DE FALLA]'),
        )
        .length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'PERFIL DE OPERACIÓN | $nombreMovil',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _bloqueMetrico('Completados', completados, Colors.green),
                  _bloqueMetrico('Cancelados', cancelados, Colors.black54),
                  _bloqueMetrico('Demorados', demorados, Colors.deepPurple),
                  _bloqueMetrico('Fallas', fallas, Colors.red[700]!),
                ],
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ÚLTIMOS SERVICIOS ASIGNADOS:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              todoHistorial.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Historial vacío.',
                        style: TextStyle(color: Colors.black38),
                      ),
                    )
                  : SizedBox(
                      height: 300,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: todoHistorial.length,
                        itemBuilder: (context, index) {
                          final f = todoHistorial[index];
                          final est = f['estado'];
                          Color c = Colors.green;
                          String txt = 'FINALIZADO';
                          if (est == 'cancelado') {
                            c = Colors.black54;
                            txt = 'CANCELADO';
                          } else if (est == 'finalizado_por_demora') {
                            c = Colors.deepPurple;
                            txt = 'DEMORA';
                          } else if (est == 'finalizado_con_problema' ||
                              (f['observacion'] ?? '').contains(
                                '[MARCA DE FALLA]',
                              )) {
                            c = Colors.red[700]!;
                            txt = 'FALLA';
                          }

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0.5,
                            child: ListTile(
                              dense: true,
                              title: Text(
                                'Orden #${f['id']} | ${f['origen']} ➔ ${f['destino']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: Text(
                                f['observacion'] ??
                                    'Operación ordinaria sin notas.',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: c,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  txt,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 8,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CERRAR',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueMetrico(String t, int v, Color c) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            t,
            style: TextStyle(
              fontSize: 9,
              color: c,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$v',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: c,
            ),
          ),
        ],

      ),
    );
  }

}
