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
      final rows = await _db
          .from('usuarios')
          .select('id, nombre, usuario, rango_movil, puntuacion, activo, tipo_plan_movil, numero_movil, saldo_wallet, comision_pct, wallet_bloqueado, tiene_fn, tiene_se')
          .eq('rol', 'movil')
          .order('usuario', ascending: true);
      if (mounted) setState(() { _moviles = List<Map<String, dynamic>>.from(rows); _cargando = false; });
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
    final esSemanal = s['tipo_solicitud']?.toString() == 'pago_semanal';
    final fecha = s['created_at'] != null
        ? DateTime.tryParse(s['created_at'].toString())?.toLocal()
        : null;
    final fechaStr = fecha != null
        ? '${fecha.day.toString().padLeft(2,'0')}/${fecha.month.toString().padLeft(2,'0')} ${fecha.hour.toString().padLeft(2,'0')}:${fecha.minute.toString().padLeft(2,'0')}'
        : '';

    final borderColor = esSemanal
        ? Colors.orange[700]!.withValues(alpha: 0.5)
        : Colors.amber[700]!.withValues(alpha: 0.4);
    final bgColor = esSemanal
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
          Row(children: [
            Icon(
              esSemanal ? Icons.lock_clock : Icons.pending_actions_rounded,
              color: esSemanal ? Colors.orange : Colors.amber,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(
              '$nombre — \$${monto.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            )),
            if (esSemanal)
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
                  await _db.from('solicitudes_recarga_wallet').update({
                    'estado': 'rechazada', 'revisado_por': 'central',
                    'revisado_at': DateTime.now().toUtc().toIso8601String(),
                  }).eq('id', s['id']);
                  MotorNotificaciones.dispararMisil(
                    idDestino: s['movil_id'].toString(),
                    titulo: '❌ Solicitud rechazada',
                    mensaje: esSemanal
                        ? 'Tu comprobante de pago semanal fue rechazado. Comunícate con la Central.'
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
                  backgroundColor: esSemanal ? Colors.orange : const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  try {
                    final comprUrlAp = s['comprobante_url']?.toString();
                    if (esSemanal) {
                      await _db.from('usuarios').update({
                        'wallet_bloqueado': false,
                      }).eq('id', s['movil_id']);
                      await _db.from('wallet_movimientos').insert({
                        'movil_id': s['movil_id'],
                        'tipo': 'pago_semanal',
                        'monto': monto,
                        'concepto': 'Pago semanal aprobado — billetera desbloqueada',
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
                      titulo: esSemanal ? '🔓 Billetera desbloqueada' : '✅ Recarga aprobada',
                      mensaje: esSemanal
                          ? 'Tu pago semanal fue aprobado. Ya puedes usar tu billetera con normalidad.'
                          : 'Se acreditaron \$${monto.toStringAsFixed(0)} en tu billetera.',
                      urgente: false,
                    );
                    _cargar();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(esSemanal
                          ? '🔓 Pago semanal aprobado — $nombre desbloqueado'
                          : '✅ Recarga de \$${monto.toStringAsFixed(0)} aprobada para $nombre'),
                      backgroundColor: esSemanal ? Colors.orange : const Color(0xFF22C55E),
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
                  esSemanal ? 'APROBAR Y DESBLOQUEAR' : 'APROBAR',
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
    final esSemanal = plan == 'semanal';

    final positivo = esSemanal ? !bloqueado : (plan == 'postdia' ? saldo >= 0 : saldo > 0);
    final colorSaldo = positivo ? const Color(0xFF22C55E) : Colors.redAccent;

    final planChip = esSemanal ? 'SEMANAL'
        : plan == 'prediario' ? 'PREDIA' : 'POSTDIA';
    final planColor = esSemanal ? Colors.purple[400]!
        : plan == 'prediario' ? Colors.orange[700]! : Colors.blue[600]!;

    final borderColor = bloqueado
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
          // Banner de bloqueo semanal
          if (bloqueado && esSemanal) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.lock_rounded, color: Colors.orange, size: 14),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('BILLETERA BLOQUEADA — pendiente pago semanal',
                      style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1A1A),
                        title: const Text('🔓 Desbloquear billetera',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        content: Text('¿Desbloquear manualmente la billetera de $nombre sin comprobante?',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('CANCELAR', style: TextStyle(color: Colors.grey))),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange, foregroundColor: Colors.black),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('DESBLOQUEAR', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _db.from('usuarios')
                          .update({'wallet_bloqueado': false}).eq('id', u['id']);
                      await _db.from('wallet_movimientos').insert({
                        'movil_id': u['id'],
                        'tipo': 'desbloqueo_manual',
                        'monto': 0,
                        'concepto': 'Desbloqueo manual por central',
                        'registrado_por': 'central',
                      });
                      _cargar();
                    }
                  },
                  child: const Text('DESBLOQUEAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ),
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

  // ── Build principal ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0A),
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
          ),
        ],
        body: _cargando
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)))
            : Column(children: [
                // ── Barra de búsqueda ──────────────────────────────────────
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
                // ── Contenido ──────────────────────────────────────────────
                Expanded(
                  child: FutureBuilder<List<dynamic>>(
                    future: Future.wait([
                      _db
                          .from('solicitudes_recarga_wallet')
                          .select('id, movil_id, monto_solicitado, nota, comprobante_url, estado, tipo_solicitud, created_at, usuarios(nombre, usuario, numero_movil, tipo_plan_movil)')
                          .eq('estado', 'pendiente')
                          .order('created_at', ascending: false),
                      _db.from('config_sistema').select('info_recarga_wallet').eq('id', 1).maybeSingle(),
                      _db
                          .from('wallet_movimientos')
                          .select('id, movil_id, tipo, monto, concepto, created_at, usuarios(nombre, numero_movil)')
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

                          // ── RESUMEN ─────────────────────────────────────
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

                          // ── FILTROS ─────────────────────────────────────
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
                                            color: _planFiltroWallet == entry.$1
                                                ? Colors.black
                                                : Colors.white70)),
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

                          // ── DATOS DE TRANSFERENCIA ──────────────────────
                          _encabezadoSeccion('DATOS DE TRANSFERENCIA', Colors.white54),
                          _cardInfoRecarga(infoRecarga),
                          const SizedBox(height: 8),

                          // ── SOLICITUDES PENDIENTES ──────────────────────
                          () {
                            final semanales = solicitudes
                                .where((s) => (s as Map)['tipo_solicitud'] == 'pago_semanal')
                                .toList();
                            final recargas = solicitudes
                                .where((s) => (s as Map)['tipo_solicitud'] != 'pago_semanal')
                                .toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (semanales.isNotEmpty) ...[
                                  _encabezadoSeccion(
                                      '🔒 SOPORTES DE PAGO (${semanales.length})',
                                      Colors.orange[400]!),
                                  ...semanales.map((s) =>
                                      _cardSolicitudRecarga(s as Map<String, dynamic>)),
                                  const SizedBox(height: 8),
                                ],
                                if (recargas.isNotEmpty) ...[
                                  _encabezadoSeccion(
                                      '💳 RECARGAS PENDIENTES (${recargas.length})',
                                      Colors.amber[600]!),
                                  ...recargas.map((s) =>
                                      _cardSolicitudRecarga(s as Map<String, dynamic>)),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            );
                          }(),

                          // ── MOVIMIENTOS RECIENTES ───────────────────────
                          if (movimientos.isNotEmpty) ...[
                            _encabezadoSeccion('MOVIMIENTOS RECIENTES', Colors.white38),
                            ...movimientos.map((mv) {
                              final m      = mv as Map<String, dynamic>;
                              final monto  = (m['monto'] as num?)?.toDouble() ?? 0.0;
                              final tipo   = m['tipo']?.toString() ?? '';
                              final nombre = (m['usuarios'] as Map?)?['nombre']?.toString() ?? '—';
                              final numMov = (m['usuarios'] as Map?)?['numero_movil'];
                              final label  = numMov != null
                                  ? 'Movil${numMov.toString().padLeft(2, '0')}'
                                  : nombre;
                              final esDescuento = monto < 0;
                              final color  = esDescuento ? Colors.redAccent : const Color(0xFF22C55E);
                              final icon   = switch (tipo) {
                                'descuento_servicio' => Icons.remove_circle_outline_rounded,
                                'pago_semanal'       => Icons.lock_open_rounded,
                                'bloqueo_semanal'    => Icons.lock_rounded,
                                'recarga'            => Icons.add_circle_outline_rounded,
                                'desbloqueo_manual'  => Icons.admin_panel_settings_rounded,
                                _                    => Icons.swap_horiz_rounded,
                              };
                              final fecha = m['created_at'] != null
                                  ? DateTime.parse(m['created_at'].toString()).toLocal()
                                  : null;
                              final fechaStr = fecha != null
                                  ? '${fecha.day}/${fecha.month} ${fecha.hour.toString().padLeft(2,'0')}:${fecha.minute.toString().padLeft(2,'0')}'
                                  : '';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141414),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(children: [
                                  Icon(icon, color: color, size: 16),
                                  const SizedBox(width: 10),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(label,
                                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                      Text(m['concepto']?.toString() ?? tipo,
                                          style: const TextStyle(color: Colors.white54, fontSize: 10),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  )),
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
                              );
                            }),
                            const SizedBox(height: 8),
                          ],

                          // ── PLANES DE PAGO ──────────────────────────────
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
              ]),
      ),
    );
  }
}
