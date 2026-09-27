part of 'central_screen.dart';
// ── Pantalla independiente de Billetera ────────────────────────────────────────

class _PanelBilletera extends StatefulWidget {
  const _PanelBilletera();
  @override
  State<_PanelBilletera> createState() => _PanelBilleteraState();
}

class _PanelBilleteraState extends State<_PanelBilletera> {
  final _db = Supabase.instance.client;
  final _busqCtrl = TextEditingController();
  String _busq = '';
  String _planFiltroWallet = ''; // '' = todos, 'prediario', 'postdia', 'semanal'

  List<Map<String, dynamic>> _moviles = [];
  List<Map<String, dynamic>> _movimientosSemana = [];
  DateTime _weekStart = DateTime.now();
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      // Inicio de semana en Colombia (UTC-5, sin DST) = lunes 00:00 Colombia
      final nowCol = DateTime.now().toUtc().subtract(const Duration(hours: 5));
      final wd = nowCol.weekday; // 1 = lunes
      final wsCol = DateTime(nowCol.year, nowCol.month, nowCol.day - (wd - 1));
      final wsUtc = wsCol.add(const Duration(hours: 5)); // de vuelta a UTC

      final results = await Future.wait([
        _db
            .from('usuarios')
            .select('id, auth_id, nombre, usuario, rango_movil, puntuacion, activo, tipo_plan_movil, numero_movil, saldo_wallet, comision_pct, wallet_bloqueado, recargo_mora_activo, tiene_fn, tiene_se')
            .eq('rol', 'movil')
            .order('usuario', ascending: true),
        _db
            .from('wallet_movimientos')
            .select('movil_id, monto, tipo')
            .gte('created_at', wsUtc.toIso8601String()),
      ]);

      if (mounted) setState(() {
        _moviles = List<Map<String, dynamic>>.from(results[0] as List);
        _movimientosSemana = List<Map<String, dynamic>>.from(results[1] as List);
        _weekStart = wsCol;
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ── Helpers visuales ──────────────────────────────────────────────────────
  String _iniciales(String? n) {
    if (n == null || n.trim().isEmpty) return '?';
    final p = n.trim().split(' ');
    return p.length >= 2 ? '${p[0][0]}${p[1][0]}'.toUpperCase() : n[0].toUpperCase();
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _encabezadoSeccion(String texto, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
    child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
  );

  Widget _empty(IconData icon, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white12, size: 36),
      const SizedBox(height: 8),
      Text(msg, style: const TextStyle(color: Colors.white24, fontSize: 12)),
    ]),
  );

  Widget _statChip(IconData icon, String valor, String etiqueta, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor,
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(etiqueta,
                  style: const TextStyle(color: Colors.white54, fontSize: 9),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
        ]),
      );

  // ── Tarjeta de info de transferencia ─────────────────────────────────────
  Widget _cardInfoRecarga(String infoActual) {
    final ctrl = TextEditingController(text: infoActual);
    bool guardando = false;

    return StatefulBuilder(
      builder: (ctx, setLocal) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.account_balance_rounded, color: Color(0xFF818CF8), size: 14),
              SizedBox(width: 6),
              Text('Cuenta para recibir recargas',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Ej:\nNequi: 300 123 4567 - Juan Pérez\nDaviplata: 300 123 4567\nBancolombia: Cta 12345678-9',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                filled: true, fillColor: Colors.white.withValues(alpha: 0.04),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: guardando ? null : () async {
                  setLocal(() => guardando = true);
                  try {
                    await _db.from('config_sistema').update({
                      'info_recarga_wallet': ctrl.text.trim(),
                    }).eq('id', 1);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ Datos de pago actualizados'),
                      backgroundColor: Color(0xFF818CF8),
                      behavior: SnackBarBehavior.floating,
                    ));
                  } catch (_) {}
                  setLocal(() => guardando = false);
                },
                child: guardando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('GUARDAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Tarjeta de solicitud pendiente ────────────────────────────────────────
  Widget _cardSolicitudRecarga(Map<String, dynamic> s) {
    final movilData = s['usuarios'] as Map<String, dynamic>?;
    final nombre = movilData != null ? movilLabel(movilData) : 'Móvil';
    final monto = (s['monto_solicitado'] as num?)?.toDouble() ?? 0.0;
    final nota = s['nota']?.toString();
    final comprUrl = s['comprobante_url']?.toString();
    final tipoSolicitud = s['tipo_solicitud']?.toString() ?? '';
    final esSemanal = tipoSolicitud == 'pago_semanal';
    final esConRecargo = tipoSolicitud == 'pago_semanal_con_recargo';
    final esPagoSemanal = esSemanal || esConRecargo;
    // Descuento semanal (solo aplica a pago_semanal, no a pago_semanal_con_recargo)
    final int descuentoPct = esSemanal
        ? ((movilData?['descuento_semana_pct'] as int?) ?? 0)
        : 0;
    final int ptsSemana = (movilData?['puntos_semana'] as int?) ?? 0;
    // Monto esperado con descuento sobre base $60.000
    const double baseSemanal = 60000;
    final double montoEsperado = descuentoPct == 100
        ? 0
        : baseSemanal * (1 - descuentoPct / 100);
    final fecha = s['created_at'] != null
        ? DateTime.tryParse(s['created_at'].toString())?.toLocal()
        : null;
    final fechaStr = fecha != null
        ? '${fecha.day.toString().padLeft(2,'0')}/${fecha.month.toString().padLeft(2,'0')} ${fecha.hour.toString().padLeft(2,'0')}:${fecha.minute.toString().padLeft(2,'0')}'
        : '';

    final borderColor = esConRecargo
        ? Colors.red[700]!.withValues(alpha: 0.6)
        : esSemanal
            ? Colors.orange[700]!.withValues(alpha: 0.5)
            : Colors.amber[700]!.withValues(alpha: 0.4);
    final bgColor = esConRecargo
        ? Colors.red[900]!.withValues(alpha: 0.2)
        : esSemanal
            ? Colors.orange[900]!.withValues(alpha: 0.15)
            : Colors.amber[900]!.withValues(alpha: 0.15);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Cabecera ─────────────────────────────────────────────────────
          Row(children: [
            Icon(
              esConRecargo ? Icons.warning_amber_rounded
                  : esSemanal ? Icons.lock_clock
                  : Icons.pending_actions_rounded,
              color: esConRecargo ? Colors.red[400] : esSemanal ? Colors.orange : Colors.amber,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '$nombre — \$${monto.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            )),
            if (esConRecargo)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.6)),
                ),
                child: const Text('⚠️ MORA',
                    style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.bold)),
              )
            else if (esSemanal)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                child: const Text('SEMANAL',
                    style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            Text(fechaStr, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ]),
          // ── Aviso mora ───────────────────────────────────────────────────
          if (esConRecargo) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Pago con recargo por mora. Monto mínimo esperado: \$80.000 (\$60.000 semana + \$20.000 recargo).',
                style: TextStyle(color: Colors.red, fontSize: 10),
              ),
            ),
          ],
          // ── Aviso descuento semanal (premio puntos) ───────────────────────
          if (esSemanal && descuentoPct > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[900]!.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
              ),
              child: Row(children: [
                Text(
                  descuentoPct == 100 ? '🏆' : descuentoPct == 75 ? '🥈' : '🥉',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    descuentoPct == 100
                        ? '¡Premio #1! — $descuentoPct% de descuento ($ptsSemana pts). '
                          'No debe pagar nada esta semana.'
                        : 'Premio ($ptsSemana pts) — $descuentoPct% de descuento. '
                          'Monto esperado: \$${montoEsperado.toStringAsFixed(0)} '
                          '(\$${baseSemanal.toStringAsFixed(0)} × ${100 - descuentoPct}%).',
                    style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 10),
                  ),
                ),
              ]),
            ),
          ],
          if (nota != null && nota.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(nota, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
          if (comprUrl != null && comprUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.black,
                  child: Image.network(comprUrl, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(32),
                      child: Icon(Icons.broken_image_rounded, color: Colors.white30, size: 48),
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(comprUrl, height: 120, width: double.infinity, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // ── Botones ──────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red[400],
                  side: BorderSide(color: Colors.red[900]!),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  bool activarRecargo = false;
                  // Para pago_semanal normal: preguntar si activar recargo
                  if (esSemanal) {
                    final opcion = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1A1A),
                        title: const Text('Rechazar soporte',
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        content: const Text(
                            '¿Deseas activar recargo por mora para este móvil tras el rechazo?',
                            style: TextStyle(color: Colors.white70, fontSize: 13)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, 'cancelar'),
                            child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red[400],
                                side: BorderSide(color: Colors.red[800]!)),
                            onPressed: () => Navigator.pop(ctx, 'rechazar'),
                            child: const Text('SOLO RECHAZAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red[800], foregroundColor: Colors.white),
                            onPressed: () => Navigator.pop(ctx, 'rechazar_mora'),
                            child: const Text('RECHAZAR + MORA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (opcion == null || opcion == 'cancelar') return;
                    activarRecargo = opcion == 'rechazar_mora';
                  }
                  await _db.from('solicitudes_recarga_wallet').update({
                    'estado': 'rechazada', 'revisado_por': 'central',
                    'revisado_at': DateTime.now().toUtc().toIso8601String(),
                  }).eq('id', s['id']);
                  if (activarRecargo) {
                    await _db.from('usuarios')
                        .update({'recargo_mora_activo': true}).eq('id', s['movil_id']);
                  }
                  MotorNotificaciones.dispararMisil(
                    idDestino: s['movil_id'].toString(),
                    titulo: '❌ Soporte rechazado',
                    mensaje: esPagoSemanal
                        ? activarRecargo
                            ? 'Tu comprobante fue rechazado y se activó recargo por mora. Debes pagar \$80.000. Comunícate con la Central.'
                            : 'Tu comprobante de pago semanal fue rechazado. Comunícate con la Central.'
                        : 'Tu solicitud de recarga de \$${monto.toStringAsFixed(0)} fue rechazada. Comunícate con la Central.',
                    urgente: false,
                  );
                  _cargar();
                },
                child: const Text('RECHAZAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: esConRecargo
                      ? Colors.red[700]
                      : esSemanal ? Colors.orange : const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  try {
                    final comprUrlAp = s['comprobante_url']?.toString();
                    if (esPagoSemanal) {
                      await _db.from('usuarios').update({
                        'wallet_bloqueado': false,
                        if (esConRecargo) 'recargo_mora_activo': false,
                        // Limpiar descuento al aprobar — ya fue utilizado
                        if (esSemanal && descuentoPct > 0) 'descuento_semana_pct': 0,
                      }).eq('id', s['movil_id']);
                      await _db.from('wallet_movimientos').insert({
                        'movil_id': s['movil_id'],
                        'tipo': esConRecargo ? 'pago_semanal_con_recargo' : 'pago_semanal',
                        'monto': monto,
                        'concepto': esConRecargo
                            ? 'Pago semanal con recargo aprobado — billetera desbloqueada'
                            : 'Pago semanal aprobado — billetera desbloqueada',
                        'registrado_por': 'central',
                        if (comprUrlAp != null) 'comprobante_url': comprUrlAp,
                      });
                    } else {
                      await _db.from('wallet_movimientos').insert({
                        'movil_id': s['movil_id'],
                        'tipo': 'recarga',
                        'monto': monto,
                        'concepto': 'Recarga aprobada',
                        'registrado_por': 'central',
                        if (comprUrlAp != null) 'comprobante_url': comprUrlAp,
                      });
                      await _db.rpc('fn_wallet_ajuste_saldo', params: {
                        'p_movil_id': s['movil_id'],
                        'p_monto': monto,
                      });
                    }
                    await _db.from('solicitudes_recarga_wallet').update({
                      'estado': 'aprobada', 'revisado_por': 'central',
                      'revisado_at': DateTime.now().toUtc().toIso8601String(),
                    }).eq('id', s['id']);
                    MotorNotificaciones.dispararMisil(
                      idDestino: s['movil_id'].toString(),
                      titulo: esPagoSemanal ? '🔓 Billetera desbloqueada' : '✅ Recarga aprobada',
                      mensaje: esConRecargo
                          ? 'Tu pago semanal con recargo fue aprobado. Tu billetera está activa nuevamente.'
                          : esSemanal && descuentoPct == 100
                              ? '🏆 ¡Premio semanal! Tu semana fue GRATIS. Billetera desbloqueada.'
                              : esSemanal && descuentoPct > 0
                                  ? '🎉 Pago con $descuentoPct% de descuento aprobado. Billetera desbloqueada.'
                                  : esSemanal
                                      ? 'Tu pago semanal fue aprobado. Ya puedes usar tu billetera con normalidad.'
                                      : 'Se acreditaron \$${monto.toStringAsFixed(0)} en tu billetera.',
                      urgente: false,
                    );
                    _cargar();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(esConRecargo
                          ? '🔓 Pago con recargo aprobado — $nombre desbloqueado'
                          : esSemanal
                              ? '🔓 Pago semanal aprobado — $nombre desbloqueado'
                              : '✅ Recarga de \$${monto.toStringAsFixed(0)} aprobada para $nombre'),
                      backgroundColor: esConRecargo
                          ? Colors.red[700]
                          : esSemanal ? Colors.orange : const Color(0xFF22C55E),
                      behavior: SnackBarBehavior.floating,
                    ));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'), backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                child: Text(
                  esPagoSemanal ? 'APROBAR Y DESBLOQUEAR' : 'APROBAR',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Tarjeta individual de móvil ────────────────────────────────────────────
  Widget _cardWallet(Map<String, dynamic> u) {
    final nombre = movilLabel(u);
    final plan = u['tipo_plan_movil']?.toString() ?? '';
    final saldo = (u['saldo_wallet'] as num?)?.toDouble() ?? 0.0;
    final comPct = (u['comision_pct'] as num?)?.toDouble() ?? 10.0;
    final bloqueado = u['wallet_bloqueado'] == true;
    final recargo = u['recargo_mora_activo'] == true;
    final esSemanal = plan == 'semanal';

    final positivo = esSemanal ? !bloqueado : (plan == 'postdia' ? saldo >= 0 : saldo > 0);
    final colorSaldo = positivo ? const Color(0xFF22C55E) : Colors.redAccent;

    final planChip = esSemanal ? 'SEMANAL'
        : plan == 'prediario' ? 'PREDIA' : 'POSTDIA';
    final planColor = esSemanal ? Colors.purple[400]!
        : plan == 'prediario' ? Colors.orange[700]! : Colors.blue[600]!;

    final borderColor = (bloqueado && recargo)
        ? Colors.red.withValues(alpha: 0.6)
        : bloqueado
            ? Colors.orange.withValues(alpha: 0.5)
            : (positivo ? Colors.white12 : Colors.redAccent.withValues(alpha: 0.3));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Banner de bloqueo semanal (diferencia mora vs normal)
          if (bloqueado && esSemanal) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: recargo
                    ? Colors.red.withValues(alpha: 0.15)
                    : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: recargo
                    ? Colors.red.withValues(alpha: 0.5)
                    : Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(
                    recargo ? Icons.warning_amber_rounded : Icons.lock_rounded,
                    color: recargo ? Colors.red[400] : Colors.orange,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      recargo
                          ? '⚠️ MORA — debe pagar \$80.000'
                          : 'BILLETERA BLOQUEADA — pendiente pago semanal',
                      style: TextStyle(
                        color: recargo ? Colors.red[400] : Colors.orange,
                        fontSize: 10, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  if (recargo) ...[
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.orange,
                          backgroundColor: Colors.orange.withValues(alpha: 0.12),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A1A),
                              title: const Text('Exonerar recargo',
                                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                              content: Text(
                                  '¿Exonerar el recargo por mora de $nombre?\nPodrá pagar \$60.000 en lugar de \$80.000.',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange, foregroundColor: Colors.black),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('EXONERAR', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await _db.from('usuarios')
                                .update({'recargo_mora_activo': false}).eq('id', u['id']);
                            await _db.from('wallet_movimientos').insert({
                              'movil_id': u['id'],
                              'tipo': 'exoneracion_recargo',
                              'monto': 0,
                              'concepto': 'Recargo por mora exonerado por central',
                              'registrado_por': 'central',
                            });
                            MotorNotificaciones.dispararMisil(
                              idDestino: u['id'].toString(),
                              titulo: '✅ Recargo exonerado',
                              mensaje: 'Tu recargo por mora fue exonerado. Puedes pagar tu semana por \$60.000.',
                              urgente: false,
                            );
                            _cargar();
                          }
                        },
                        child: const Text('EXONERAR RECARGO',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white60,
                        backgroundColor: Colors.white.withValues(alpha: 0.07),
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: const Color(0xFF1A1A1A),
                            title: const Text('Activar semana',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            content: Text(
                                '¿Activar la semana de $nombre manualmente sin comprobante?\n\nUsar solo cuando haya razones externas conocidas por la central.',
                                style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange, foregroundColor: Colors.black),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('ACTIVAR SEMANA', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _db.from('usuarios').update({
                            'wallet_bloqueado': false,
                            'recargo_mora_activo': false,
                          }).eq('id', u['id']);
                          await _db.from('wallet_movimientos').insert({
                            'movil_id': u['id'],
                            'tipo': 'activacion_manual',
                            'monto': 0,
                            'concepto': 'Semana activada manualmente por central',
                            'registrado_por': 'central',
                          });
                          MotorNotificaciones.dispararMisil(
                            idDestino: u['id'].toString(),
                            titulo: '🔓 Semana activada',
                            mensaje: 'Tu semana fue activada por la central. Ya puedes conectarte.',
                            urgente: false,
                          );
                          _cargar();
                        }
                      },
                      child: const Text('ACTIVAR SEMANA',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              ]),
            ),
          ],
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: planColor.withValues(alpha: 0.15),
              child: Text(_iniciales(nombre), style: TextStyle(color: planColor, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text(
                esSemanal ? 'Pago semanal fijo' : 'Comisión ${comPct.toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _chip(planChip, planColor),
              const SizedBox(height: 4),
              if (!esSemanal)
                Text(
                  '\$${saldo.toStringAsFixed(0)}',
                  style: TextStyle(color: colorSaldo, fontWeight: FontWeight.bold, fontSize: 16),
                )
              else
                Icon(
                  bloqueado ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: bloqueado ? Colors.orange : const Color(0xFF22C55E),
                  size: 20,
                ),
            ]),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history_rounded, size: 14),
                label: const Text('Historial', style: TextStyle(fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: const BorderSide(color: Colors.white12),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _abrirDialogWallet(u, soloLectura: true),
              ),
            ),
            if (!esSemanal) ...[
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text('Movimiento', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF818CF8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _abrirDialogWallet(u, soloLectura: false),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  // ── Diálogo de historial / movimiento ────────────────────────────────────
  Future<void> _abrirDialogWallet(Map<String, dynamic> u, {required bool soloLectura}) async {
    final movilId = u['id'];
    final nombre = movilLabel(u);
    final plan = u['tipo_plan_movil']?.toString() ?? '';
    final montoCtrl = TextEditingController();
    final conceptoCtrl = TextEditingController();
    String tipoMov = plan == 'prediario' ? 'recarga'
        : plan == 'semanal' ? 'pago_semanal'
        : 'pago_postdia';
    bool procesando = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF818CF8), size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Billetera · $nombre',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Historial reciente ────────────────────────────────────
              SizedBox(
                height: 220,
                child: FutureBuilder<List<dynamic>>(
                  future: _db
                      .from('wallet_movimientos')
                      .select('tipo, monto, concepto, created_at, registrado_por, comprobante_url')
                      .eq('movil_id', movilId)
                      .order('created_at', ascending: false)
                      .limit(30),
                  builder: (ctx2, snap) {
                    if (snap.connectionState == ConnectionState.waiting)
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)));
                    if (!snap.hasData || snap.data!.isEmpty)
                      return const Center(child: Text('Sin movimientos', style: TextStyle(color: Colors.white38, fontSize: 12)));
                    final items = snap.data!;
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i] as Map<String, dynamic>;
                        final monto = (item['monto'] as num?)?.toDouble() ?? 0.0;
                        final positivo = monto > 0;
                        final tipo = item['tipo']?.toString() ?? '';
                        final concepto = item['concepto']?.toString() ?? tipo;
                        final fecha = item['created_at'] != null
                            ? DateTime.tryParse(item['created_at'].toString())?.toLocal()
                            : null;
                        final fechaStr = fecha != null
                            ? '${fecha.day.toString().padLeft(2,'0')}/${fecha.month.toString().padLeft(2,'0')} ${fecha.hour.toString().padLeft(2,'0')}:${fecha.minute.toString().padLeft(2,'0')}'
                            : '';
                        final comprUrl = item['comprobante_url']?.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(
                                tipo == 'recarga' ? Icons.add_circle_outline
                                    : tipo == 'comision' ? Icons.remove_circle_outline
                                    : tipo == 'pago_postdia' ? Icons.check_circle_outline
                                    : tipo == 'pago_semanal' ? Icons.lock_open_rounded
                                    : Icons.tune_rounded,
                                size: 14,
                                color: positivo ? const Color(0xFF22C55E) : Colors.redAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(concepto, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                if (fechaStr.isNotEmpty)
                                  Text(fechaStr, style: const TextStyle(color: Colors.white30, fontSize: 9)),
                              ])),
                              Text(
                                '${positivo ? '+' : ''}\$${monto.toStringAsFixed(0)}',
                                style: TextStyle(color: positivo ? const Color(0xFF22C55E) : Colors.redAccent,
                                    fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ]),
                            if (comprUrl != null && comprUrl.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    backgroundColor: Colors.black,
                                    child: Image.network(comprUrl, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Padding(
                                        padding: EdgeInsets.all(32),
                                        child: Icon(Icons.broken_image_rounded, color: Colors.white30, size: 48),
                                      ),
                                    ),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(comprUrl, height: 70, width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                                ),
                              ),
                            ],
                          ]),
                        );
                      },
                    );
                  },
                ),
              ),
              if (!soloLectura) ...[
                const Divider(color: Colors.white12, height: 20),
                DropdownButtonFormField<String>(
                  value: tipoMov,
                  dropdownColor: const Color(0xFF2A2A2A),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Tipo de movimiento',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                    filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  items: [
                    if (plan == 'prediario')
                      const DropdownMenuItem(value: 'recarga', child: Text('💚 Recarga')),
                    if (plan == 'postdia')
                      const DropdownMenuItem(value: 'pago_postdia', child: Text('✅ Pago postdia')),
                    const DropdownMenuItem(value: 'ajuste', child: Text('⚙️ Ajuste manual')),
                  ],
                  onChanged: (v) { if (v != null) setDs(() => tipoMov = v); },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: montoCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Monto (\$)',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(color: Colors.white54),
                    filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: conceptoCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Concepto (opcional)',
                    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                    filled: true, fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CERRAR', style: TextStyle(color: Colors.white38)),
            ),
            if (!soloLectura)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8), foregroundColor: Colors.white),
                onPressed: procesando ? null : () async {
                  final montoRaw = double.tryParse(montoCtrl.text.replaceAll(',', '.').trim());
                  if (montoRaw == null || montoRaw == 0) return;
                  final montoFinal = (tipoMov == 'ajuste' && montoRaw < 0) ? montoRaw : montoRaw.abs();
                  final montoConSigno = tipoMov == 'recarga' || tipoMov == 'pago_postdia'
                      ? montoFinal : -montoFinal;
                  final concepto = conceptoCtrl.text.trim().isNotEmpty
                      ? conceptoCtrl.text.trim()
                      : tipoMov == 'recarga' ? 'Recarga manual'
                          : tipoMov == 'pago_postdia' ? 'Pago postdia'
                          : 'Ajuste manual';
                  setDs(() => procesando = true);
                  try {
                    await _db.from('wallet_movimientos').insert({
                      'movil_id': movilId,
                      'tipo': tipoMov,
                      'monto': montoConSigno,
                      'concepto': concepto,
                      'registrado_por': 'central',
                    });
                    await _db.rpc('fn_wallet_ajuste_saldo', params: {
                      'p_movil_id': movilId,
                      'p_monto': montoConSigno,
                    });
                    if (mounted) {
                      Navigator.pop(ctx);
                      _cargar();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Movimiento registrado: $concepto'),
                        backgroundColor: const Color(0xFF818CF8),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  } catch (e) {
                    setDs(() => procesando = false);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ));
                  }
                },
                child: procesando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('REGISTRAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  // ── Tab Contabilidad ─────────────────────────────────────────────────────
  Widget _buildContabilidadTab() {
    String _numLabel(Map<String, dynamic> m) {
      final n = m['numero_movil'];
      if (n != null) return 'MOVIL${n.toString().padLeft(2, '0')}';
      return movilLabel(m);
    }

    int _sortNum(Map<String, dynamic> a, Map<String, dynamic> b) {
      final na = (a['numero_movil'] as num?)?.toInt() ?? 9999;
      final nb = (b['numero_movil'] as num?)?.toInt() ?? 9999;
      return na.compareTo(nb);
    }

    // Listas ordenadas por número de móvil
    final semanales = (_moviles.where((m) => m['tipo_plan_movil'] == 'semanal').toList()..sort(_sortNum));
    final prediarios = (_moviles.where((m) => m['tipo_plan_movil'] == 'prediario').toList()..sort(_sortNum));
    final postdias  = (_moviles.where((m) => m['tipo_plan_movil'] == 'postdia').toList()..sort(_sortNum));

    // Pagos de esta semana por movil_id (solo pagos semanal positivos)
    final Map<int, double> pagosPorMovil = {};
    for (final mv in _movimientosSemana) {
      final tipo  = mv['tipo']?.toString() ?? '';
      final monto = (mv['monto'] as num?)?.toDouble() ?? 0.0;
      final mid   = mv['movil_id'] as int?;
      if (mid == null) continue;
      if ((tipo == 'pago_semanal' || tipo == 'pago_semanal_con_recargo') && monto > 0) {
        pagosPorMovil[mid] = (pagosPorMovil[mid] ?? 0) + monto;
      }
    }

    // Recargas esta semana por movil_id (prediario)
    final Map<int, double> recargasPorMovil = {};
    for (final mv in _movimientosSemana) {
      final tipo  = mv['tipo']?.toString() ?? '';
      final monto = (mv['monto'] as num?)?.toDouble() ?? 0.0;
      final mid   = mv['movil_id'] as int?;
      if (mid == null) continue;
      if (tipo == 'recarga' && monto > 0) {
        recargasPorMovil[mid] = (recargasPorMovil[mid] ?? 0) + monto;
      }
    }

    // Cobros postdia esta semana
    final Map<int, double> cobrosPostdia = {};
    for (final mv in _movimientosSemana) {
      final tipo  = mv['tipo']?.toString() ?? '';
      final monto = (mv['monto'] as num?)?.toDouble() ?? 0.0;
      final mid   = mv['movil_id'] as int?;
      if (mid == null) continue;
      if (tipo == 'pago_postdia' && monto > 0) {
        cobrosPostdia[mid] = (cobrosPostdia[mid] ?? 0) + monto;
      }
    }

    // Totales semanal
    final totalRecSemanal = pagosPorMovil.values.fold<double>(0, (a, b) => a + b);
    final semanalesSinPagar = semanales.where((m) {
      final mid = m['id'] as int?;
      return mid == null || !pagosPorMovil.containsKey(mid);
    }).toList();
    final pendienteSemanal = semanalesSinPagar.fold<double>(0, (acc, m) {
      return acc + (m['recargo_mora_activo'] == true ? 80000.0 : 60000.0);
    });

    // Totales prediario
    final totalRecPrediario = recargasPorMovil.values.fold<double>(0, (a, b) => a + b);

    // Totales postdia
    final totalRecPostdia = cobrosPostdia.values.fold<double>(0, (a, b) => a + b);
    final deudaTotalPostdia = postdias.fold<double>(0, (acc, m) {
      final s = (m['saldo_wallet'] as num?)?.toDouble() ?? 0.0;
      return acc + (s < 0 ? s.abs() : 0);
    });

    // Etiqueta de semana
    final wsEnd = _weekStart.add(const Duration(days: 6));
    String _fmtD(DateTime d) => '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}';
    final semLabel = '${_fmtD(_weekStart)} — ${_fmtD(wsEnd)}';

    // Helper: fila de tabla compacta
    Widget _fila({
      required String label,
      required String estado,
      required Color estadoColor,
      required IconData estadoIcon,
      required String monto,
      required Color montoColor,
      required bool esPrimera,
      required bool esUltima,
      Color? leftBorderColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: (leftBorderColor ?? estadoColor).withValues(alpha: 0.5), width: 2),
            right: const BorderSide(color: Colors.white10),
            top: esPrimera ? BorderSide.none : const BorderSide(color: Colors.white10),
            bottom: esUltima ? const BorderSide(color: Colors.white12) : BorderSide.none,
          ),
        ),
        child: Row(children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Row(children: [
              Icon(estadoIcon, color: estadoColor, size: 11),
              const SizedBox(width: 4),
              Text(estado, style: TextStyle(color: estadoColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ]),
          ),
          Text(monto,
              style: TextStyle(color: montoColor, fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right),
        ]),
      );
    }

    // Helper: fila de total de sección
    Widget _filaTotalSeccion(String texto, double valor, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(children: [
        const SizedBox(width: 72),
        Expanded(child: Text(texto, style: const TextStyle(color: Colors.white38, fontSize: 10))),
        Text('+\$${valor.toStringAsFixed(0)}',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ]),
    );

    // Cabecera de tabla
    Widget _cabeceraTabla() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        border: const Border(
          left: BorderSide(color: Colors.white12),
          right: BorderSide(color: Colors.white12),
          top: BorderSide(color: Colors.white12),
        ),
      ),
      child: const Row(children: [
        SizedBox(width: 72, child: Text('MÓVIL', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold))),
        Expanded(child: Text('ESTADO', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold))),
        Text('MONTO', style: TextStyle(color: Colors.white30, fontSize: 9, fontWeight: FontWeight.bold)),
      ]),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
      children: [

        // ── Encabezado de semana ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF818CF8).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_month_rounded, color: Color(0xFF818CF8), size: 14),
            const SizedBox(width: 8),
            Text('Semana: $semLabel',
                style: const TextStyle(
                    color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'TOTAL: \$${(totalRecSemanal + totalRecPrediario + totalRecPostdia).toStringAsFixed(0)}',
                style: const TextStyle(color: Color(0xFF22C55E), fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ),

        // ══════════════════════════════════════════════════════════════════
        // SECCIÓN SEMANAL
        // ══════════════════════════════════════════════════════════════════
        if (semanales.isNotEmpty) ...[
          _encabezadoSeccion('📋 SEMANAL (${semanales.length} MÓVILES)', Colors.orange),
          // Banner de totales semanal
          Row(children: [
            Expanded(child: _statChip(
              Icons.check_circle_rounded,
              '${pagosPorMovil.length}/${semanales.length}',
              'Pagados esta semana',
              pagosPorMovil.length == semanales.length ? const Color(0xFF22C55E) : Colors.orange,
            )),
            const SizedBox(width: 6),
            Expanded(child: _statChip(
              Icons.attach_money_rounded,
              '\$${totalRecSemanal.toStringAsFixed(0)}',
              'Recaudado',
              const Color(0xFF22C55E),
            )),
            const SizedBox(width: 6),
            Expanded(child: _statChip(
              Icons.pending_actions_rounded,
              '\$${pendienteSemanal.toStringAsFixed(0)}',
              'Pendiente',
              pendienteSemanal > 0 ? Colors.orange : Colors.white24,
            )),
          ]),
          const SizedBox(height: 10),
          _cabeceraTabla(),
          ...semanales.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            final mid = m['id'] as int?;
            final pagado  = mid != null && pagosPorMovil.containsKey(mid);
            final montoPagado = mid != null ? (pagosPorMovil[mid] ?? 0.0) : 0.0;
            final bloqueado = m['wallet_bloqueado'] == true;
            final mora = m['recargo_mora_activo'] == true;

            final Color stColor;
            final String stTxt;
            final IconData stIcon;
            if (pagado) {
              stColor = const Color(0xFF22C55E); stTxt = 'PAGADO'; stIcon = Icons.check_circle_rounded;
            } else if (mora) {
              stColor = Colors.red[400]!; stTxt = 'MORA'; stIcon = Icons.warning_amber_rounded;
            } else if (bloqueado) {
              stColor = Colors.orange; stTxt = 'BLOQUEADO'; stIcon = Icons.lock_rounded;
            } else {
              stColor = Colors.white38; stTxt = 'SIN PAGAR'; stIcon = Icons.lock_open_rounded;
            }
            final montoStr = pagado
                ? '+\$${montoPagado.toStringAsFixed(0)}'
                : mora ? '—\$80.000' : '—\$60.000';
            final montoColor = pagado ? const Color(0xFF22C55E) : Colors.white24;

            return _fila(
              label: _numLabel(m),
              estado: stTxt,
              estadoColor: stColor,
              estadoIcon: stIcon,
              monto: montoStr,
              montoColor: montoColor,
              esPrimera: i == 0,
              esUltima: i == semanales.length - 1,
            );
          }),
          _filaTotalSeccion(
            '${pagosPorMovil.length} de ${semanales.length} pagaron · Pendiente: \$${pendienteSemanal.toStringAsFixed(0)}',
            totalRecSemanal,
            Colors.orange,
          ),
          const SizedBox(height: 20),
        ],

        // ══════════════════════════════════════════════════════════════════
        // SECCIÓN PREDIARIO
        // ══════════════════════════════════════════════════════════════════
        if (prediarios.isNotEmpty) ...[
          _encabezadoSeccion('📅 PREDIARIO (${prediarios.length} MÓVILES)', const Color(0xFF818CF8)),
          Row(children: [
            Expanded(child: _statChip(
              Icons.add_circle_rounded, '\$${totalRecPrediario.toStringAsFixed(0)}',
              'Recargas esta semana', const Color(0xFF22C55E),
            )),
            const SizedBox(width: 6),
            Expanded(child: _statChip(
              Icons.money_off_rounded,
              '${prediarios.where((m) => ((m['saldo_wallet'] as num?)?.toDouble() ?? 0.0) <= 0).length}',
              'Sin saldo / en negativo',
              prediarios.any((m) => ((m['saldo_wallet'] as num?)?.toDouble() ?? 0.0) <= 0) ? Colors.red[400]! : Colors.white24,
            )),
          ]),
          const SizedBox(height: 10),
          _cabeceraTabla(),
          ...prediarios.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            final saldo = (m['saldo_wallet'] as num?)?.toDouble() ?? 0.0;
            final sinSaldo = saldo <= 0;
            return _fila(
              label: _numLabel(m),
              estado: sinSaldo ? 'SIN SALDO' : 'CON SALDO',
              estadoColor: sinSaldo ? Colors.red[300]! : const Color(0xFF22C55E),
              estadoIcon: sinSaldo ? Icons.money_off_rounded : Icons.account_balance_wallet_rounded,
              monto: '\$${saldo.toStringAsFixed(0)}',
              montoColor: sinSaldo ? Colors.red[300]! : const Color(0xFF22C55E),
              esPrimera: i == 0,
              esUltima: i == prediarios.length - 1,
              leftBorderColor: const Color(0xFF818CF8),
            );
          }),
          _filaTotalSeccion('Recargas acumuladas esta semana', totalRecPrediario, const Color(0xFF818CF8)),
          const SizedBox(height: 20),
        ],

        // ══════════════════════════════════════════════════════════════════
        // SECCIÓN POSTDIA
        // ══════════════════════════════════════════════════════════════════
        if (postdias.isNotEmpty) ...[
          _encabezadoSeccion('📆 POSTDIA (${postdias.length} MÓVILES)', Colors.teal),
          Row(children: [
            Expanded(child: _statChip(
              Icons.payments_rounded, '\$${totalRecPostdia.toStringAsFixed(0)}',
              'Cobrado esta semana', Colors.teal,
            )),
            const SizedBox(width: 6),
            Expanded(child: _statChip(
              Icons.receipt_long_rounded,
              '\$${deudaTotalPostdia.toStringAsFixed(0)}',
              'Deuda total pendiente',
              deudaTotalPostdia > 0 ? Colors.red[300]! : Colors.white24,
            )),
          ]),
          const SizedBox(height: 10),
          _cabeceraTabla(),
          ...postdias.asMap().entries.map((e) {
            final i = e.key;
            final m = e.value;
            final saldo = (m['saldo_wallet'] as num?)?.toDouble() ?? 0.0;
            final enDeuda = saldo < 0;
            return _fila(
              label: _numLabel(m),
              estado: enDeuda ? 'EN DEUDA' : 'AL DÍA',
              estadoColor: enDeuda ? Colors.red[300]! : Colors.teal,
              estadoIcon: enDeuda ? Icons.trending_down_rounded : Icons.check_circle_outline_rounded,
              monto: '\$${saldo.toStringAsFixed(0)}',
              montoColor: enDeuda ? Colors.red[300]! : Colors.teal,
              esPrimera: i == 0,
              esUltima: i == postdias.length - 1,
              leftBorderColor: Colors.teal,
            );
          }),
          _filaTotalSeccion('Cobrado esta semana · Deuda pendiente: \$${deudaTotalPostdia.toStringAsFixed(0)}', totalRecPostdia, Colors.teal),
          const SizedBox(height: 20),
        ],

        if (semanales.isEmpty && prediarios.isEmpty && postdias.isEmpty)
          _empty(Icons.account_balance_wallet_rounded, 'Sin móviles con plan de pago registrados'),
      ],
    );
  }

  // ── Tab Solicitudes (contenido actual) ───────────────────────────────────
  Widget _buildSolicitudesTab() {
    final externos = _moviles
        .where((m) =>
            m['tipo_plan_movil']?.toString() == 'prediario' ||
            m['tipo_plan_movil']?.toString() == 'postdia'  ||
            m['tipo_plan_movil']?.toString() == 'semanal')
        .toList();

    final bloqueados = externos.where((m) => m['wallet_bloqueado'] == true).toList();
    final conDeuda   = externos.where((m) {
      final plan  = m['tipo_plan_movil']?.toString();
      final saldo = (m['saldo_wallet'] as num?)?.toDouble() ?? 0.0;
      if (plan == 'prediario') return saldo <= 0;
      if (plan == 'postdia')   return saldo < 0;
      return false;
    }).toList();
    final cntPre  = externos.where((m) => m['tipo_plan_movil'] == 'prediario').length;
    final cntPost = externos.where((m) => m['tipo_plan_movil'] == 'postdia').length;
    final cntSem  = externos.where((m) => m['tipo_plan_movil'] == 'semanal').length;

    var filtrados = _planFiltroWallet.isEmpty
        ? externos
        : externos.where((m) => m['tipo_plan_movil'] == _planFiltroWallet).toList();
    if (_busq.isNotEmpty) {
      final q = _busq.toLowerCase();
      filtrados = filtrados.where((m) =>
          (m['nombre']?.toString().toLowerCase().contains(q) ?? false) ||
          (m['usuario']?.toString().toLowerCase().contains(q) ?? false)).toList();
    }

    return Column(children: [
      // ── Barra de búsqueda ────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: TextField(
          controller: _busqCtrl,
          onChanged: (v) => setState(() => _busq = v),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Buscar móvil...',
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30, size: 18),
            suffixIcon: _busq.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 16),
                    onPressed: () { _busqCtrl.clear(); setState(() => _busq = ''); },
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: FutureBuilder<List<dynamic>>(
          future: Future.wait([
            _db
                .from('solicitudes_recarga_wallet')
                .select('id, movil_id, monto_solicitado, nota, comprobante_url, estado, tipo_solicitud, created_at, usuarios(nombre, usuario, numero_movil, tipo_plan_movil, descuento_semana_pct, puntos_semana)')
                .eq('estado', 'pendiente')
                .order('created_at', ascending: false),
            _db.from('config_sistema').select('info_recarga_wallet').eq('id', 1).maybeSingle(),
            _db
                .from('wallet_movimientos')
                .select('id, movil_id, tipo, monto, concepto, created_at, comprobante_url, usuarios(nombre, numero_movil)')
                .order('created_at', ascending: false)
                .limit(8),
          ]),
          builder: (ctx, snap) {
            final solicitudes = snap.hasData ? (snap.data![0] as List? ?? []) : [];
            final cfgMap      = snap.hasData ? snap.data![1] as Map<String, dynamic>? : null;
            final infoRecarga = cfgMap?['info_recarga_wallet']?.toString() ?? '';
            final movimientos = snap.hasData ? (snap.data![2] as List? ?? []) : [];

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
              children: [

                // ── RESUMEN ─────────────────────────────────────────────
                _encabezadoSeccion('RESUMEN', Colors.white54),
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: _statChip(
                          Icons.lock_rounded, '${bloqueados.length}', 'Bloqueados',
                          bloqueados.isEmpty ? Colors.white24 : Colors.redAccent,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _statChip(
                          Icons.trending_down_rounded, '${conDeuda.length}', 'Con deuda/sin saldo',
                          conDeuda.isEmpty ? Colors.white24 : Colors.orange,
                        )),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _statChip(Icons.today_rounded,      '$cntPre',  'Prediario', const Color(0xFF818CF8))),
                        const SizedBox(width: 6),
                        Expanded(child: _statChip(Icons.event_rounded,      '$cntPost', 'Postdia',   Colors.teal)),
                        const SizedBox(width: 6),
                        Expanded(child: _statChip(Icons.date_range_rounded, '$cntSem',  'Semanal',   Colors.orange)),
                      ]),
                    ]),
                  ),
                ),

                // ── FILTROS ──────────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final entry in [
                      ('', 'Todos'),
                      ('prediario', 'Prediario'),
                      ('postdia', 'Postdia'),
                      ('semanal', 'Semanal'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(entry.$2,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _planFiltroWallet == entry.$1 ? Colors.black : Colors.white70)),
                          selected: _planFiltroWallet == entry.$1,
                          selectedColor: const Color(0xFF818CF8),
                          backgroundColor: const Color(0xFF1E1E1E),
                          side: BorderSide(
                              color: _planFiltroWallet == entry.$1
                                  ? const Color(0xFF818CF8)
                                  : Colors.white24),
                          onSelected: (_) => setState(() => _planFiltroWallet = entry.$1),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 10),

                // ── DATOS DE TRANSFERENCIA ───────────────────────────────
                _encabezadoSeccion('DATOS DE TRANSFERENCIA', Colors.white54),
                _cardInfoRecarga(infoRecarga),
                const SizedBox(height: 8),

                // ── SOLICITUDES PENDIENTES ───────────────────────────────
                () {
                  final conMora = solicitudes
                      .where((s) => (s as Map)['tipo_solicitud'] == 'pago_semanal_con_recargo')
                      .toList();
                  final semsol = solicitudes
                      .where((s) => (s as Map)['tipo_solicitud'] == 'pago_semanal')
                      .toList();
                  final recargas = solicitudes.where((s) {
                    final tipo = (s as Map)['tipo_solicitud']?.toString() ?? '';
                    return tipo != 'pago_semanal' && tipo != 'pago_semanal_con_recargo';
                  }).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (conMora.isNotEmpty) ...[
                        _encabezadoSeccion('⚠️ PAGOS CON MORA (${conMora.length})', Colors.red[400]!),
                        ...conMora.map((s) => _cardSolicitudRecarga(s as Map<String, dynamic>)),
                        const SizedBox(height: 8),
                      ],
                      if (semsol.isNotEmpty) ...[
                        _encabezadoSeccion('🔒 SOPORTES DE PAGO (${semsol.length})', Colors.orange[400]!),
                        ...semsol.map((s) => _cardSolicitudRecarga(s as Map<String, dynamic>)),
                        const SizedBox(height: 8),
                      ],
                      if (recargas.isNotEmpty) ...[
                        _encabezadoSeccion('💳 RECARGAS PENDIENTES (${recargas.length})', Colors.amber[600]!),
                        ...recargas.map((s) => _cardSolicitudRecarga(s as Map<String, dynamic>)),
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                }(),

                // ── MOVIMIENTOS RECIENTES ────────────────────────────────
                if (movimientos.isNotEmpty) ...[
                  _encabezadoSeccion('MOVIMIENTOS RECIENTES', Colors.white38),
                  ...movimientos.map((mv) {
                    final m      = mv as Map<String, dynamic>;
                    final monto  = (m['monto'] as num?)?.toDouble() ?? 0.0;
                    final tipo   = m['tipo']?.toString() ?? '';
                    final numMov = (m['usuarios'] as Map?)?['numero_movil'];
                    final nombre = (m['usuarios'] as Map?)?['nombre']?.toString() ?? '—';
                    final label  = numMov != null
                        ? 'Movil${numMov.toString().padLeft(2, '0')}'
                        : nombre;
                    final esDescuento = monto < 0;
                    final color  = esDescuento ? Colors.redAccent : const Color(0xFF22C55E);
                    final icon   = switch (tipo) {
                      'descuento_servicio'       => Icons.remove_circle_outline_rounded,
                      'pago_semanal'             => Icons.lock_open_rounded,
                      'pago_semanal_con_recargo' => Icons.lock_open_rounded,
                      'bloqueo_semanal'          => Icons.lock_rounded,
                      'recarga'                  => Icons.add_circle_outline_rounded,
                      'desbloqueo_manual'        => Icons.admin_panel_settings_rounded,
                      'activacion_manual'        => Icons.check_circle_outline_rounded,
                      'exoneracion_recargo'      => Icons.remove_moderator_rounded,
                      _                          => Icons.swap_horiz_rounded,
                    };
                    final fecha = m['created_at'] != null
                        ? DateTime.parse(m['created_at'].toString()).toLocal()
                        : null;
                    final fechaStr = fecha != null
                        ? '${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2,'0')}:${fecha.minute.toString().padLeft(2,'0')}'
                        : '';
                    final comprUrlMv = m['comprobante_url']?.toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141414),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(icon, color: color, size: 16),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(label,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(m['concepto']?.toString() ?? tipo,
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(
                              monto == 0 ? '—' : '${monto >= 0 ? '+' : ''}\$${monto.abs().toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: monto == 0 ? Colors.white38 : color,
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            Text(fechaStr, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                          ]),
                        ]),
                        if (comprUrlMv != null && comprUrlMv.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.black,
                                child: Image.network(comprUrlMv, fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Icon(Icons.broken_image_rounded, color: Colors.white30, size: 48),
                                  ),
                                ),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(comprUrlMv,
                                  height: 60, width: double.infinity, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                            ),
                          ),
                        ],
                      ]),
                    );
                  }),
                  const SizedBox(height: 8),
                ],

                // ── PLANES DE PAGO ───────────────────────────────────────
                _encabezadoSeccion('PLANES DE PAGO', const Color(0xFF818CF8)),
                if (filtrados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: _empty(Icons.account_balance_wallet_rounded,
                        'Sin móviles con billetera registrados'),
                  )
                else
                  ...filtrados.map((u) => _cardWallet(u)),
              ],
            );
          },
        ),
      ),
    ]);
  }

  // ── Build principal ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A0A),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Row(children: [
            Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF818CF8), size: 18),
            SizedBox(width: 8),
            Text('Billetera', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ]),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
              onPressed: _cargar,
            ),
          ],
          bottom: const TabBar(
            labelColor: Color(0xFF818CF8),
            unselectedLabelColor: Colors.white38,
            indicatorColor: Color(0xFF818CF8),
            dividerColor: Colors.white12,
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'SOLICITUDES'),
              Tab(text: 'CONTABILIDAD'),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)))
            : TabBarView(
                children: [
                  _buildSolicitudesTab(),
                  _buildContabilidadTab(),
                ],
              ),
      ),
    );
  }
}
