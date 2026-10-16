// lib/screens/central_screen_reportes_paradero.dart
part of 'central_screen.dart';

// ── REPORTES DE AUSENCIA EN PARADERO ──────────────────────────────────────────
// Un móvil reporta a otro de la fila. El servidor fuerza el GPS del reportado y
// decide: si está fuera lo saca de la fila (retirado_auto); si está dentro o el
// GPS no respondió, queda para que la central verifique (pendiente_central).
// Todos aparecen aquí hasta que la central los marque como revisados.
extension CentralScreenReportesParadero on _CentralScreenState {
  static const String _selectReportes =
      'id, created_at, paradero, estado, gps_respondio, distancia_m, reportado_id, '
      'reportante:usuarios!reportes_paradero_reportante_id_fkey(numero_movil, usuario, nombre), '
      'reportado:usuarios!reportes_paradero_reportado_id_fkey(numero_movil, usuario, nombre, paradero_actual)';

  void _iniciarReportesParadero() {
    _canalReportesParadero?.unsubscribe();
    _canalReportesParadero = Supabase.instance.client
        .channel('reportes_paradero_central')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reportes_paradero',
          callback: (_) {
            _debounceReportesParadero?.cancel();
            _debounceReportesParadero =
                Timer(const Duration(milliseconds: 500), _cargarReportesParadero);
          },
        )
        .subscribe();
    _cargarReportesParadero();
  }

  Future<void> _cargarReportesParadero() async {
    try {
      final db = Supabase.instance.client;
      var rows = List<Map<String, dynamic>>.from(await db
          .from('reportes_paradero')
          .select(_selectReportes)
          .eq('revisado', false)
          .order('created_at', ascending: false)
          .limit(30));
      // Respaldo: si el móvil que reportó cerró la app antes de que se
      // resolviera, la central lo resuelve (después de 30 s).
      bool resolvio = false;
      for (final r in rows) {
        if (r['estado'] != 'verificando') continue;
        final t = DateTime.tryParse(r['created_at']?.toString() ?? '');
        if (t == null || DateTime.now().toUtc().difference(t.toUtc()).inSeconds < 30) {
          continue;
        }
        try {
          await db.rpc('fn_resolver_reporte_ausente', params: {'p_reporte': r['id']});
          resolvio = true;
        } catch (_) {}
      }
      if (resolvio) {
        rows = List<Map<String, dynamic>>.from(await db
            .from('reportes_paradero')
            .select(_selectReportes)
            .eq('revisado', false)
            .order('created_at', ascending: false)
            .limit(30));
      }
      // Los que siguen verificando (< 20 s) no se muestran todavía
      final visibles = rows.where((r) => r['estado'] != 'verificando').toList();
      if (mounted) _reportesParadero.value = visibles;
      // Si quedó alguno verificando, volver a mirar en 25 s (por si el
      // móvil que reportó cerró la app y nadie más lo resuelve).
      if (rows.any((r) => r['estado'] == 'verificando')) {
        _debounceReportesParadero?.cancel();
        _debounceReportesParadero =
            Timer(const Duration(seconds: 35), _cargarReportesParadero);
      }
    } catch (e) {
      debugPrint('reportes_paradero: $e');
    }
  }

  Future<void> _revisarReporteParadero(Map<String, dynamic> r, {required bool sacar}) async {
    try {
      await Supabase.instance.client.rpc('fn_revisar_reporte_paradero',
          params: {'p_reporte': r['id'], 'p_sacar': sacar});
      await _cargarReportesParadero();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _abrirReportesParadero() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: _reportesParadero,
            builder: (_, lista, __) {
              if (lista.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No hay reportes por revisar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54)),
                );
              }
              return ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(14),
                children: [
                  const Text('🚩 REPORTES DE PARADERO',
                      style: TextStyle(
                          color: Colors.deepOrangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  ...lista.map(_tarjetaReporteParadero),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _tarjetaReporteParadero(Map<String, dynamic> r) {
    final reportado = (r['reportado'] as Map?)?.cast<String, dynamic>() ?? {};
    final reportante = (r['reportante'] as Map?)?.cast<String, dynamic>() ?? {};
    final nomReportado = movilLabel(reportado, fallback: 'Móvil');
    final nomReportante = movilLabel(reportante, fallback: 'Móvil');
    final paradero = r['paradero']?.toString() ?? '';
    final estado = r['estado']?.toString() ?? '';
    final retirado = estado == 'retirado_auto';
    final gpsOk = r['gps_respondio'] == true;
    final dist = (r['distancia_m'] as num?)?.toInt();
    final sigueEnFila = reportado['paradero_actual']?.toString() == paradero;
    final t = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
    final hora = t != null
        ? hora12(t)
        : '';

    final String detalle = retirado
        ? 'Su GPS lo ubicó a ${dist ?? '?'} m del paradero → el sistema lo sacó de la fila.'
        : gpsOk
            ? 'Su GPS lo ubica DENTRO del paradero (${dist ?? '?'} m). Verifica si de verdad está.'
            : 'Su GPS NO respondió (app cerrada, sin señal o GPS apagado). Verifica si está.';
    final Color color = retirado ? Colors.green : (gpsOk ? Colors.orange : Colors.redAccent);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('$nomReportado — $paradero',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Text(hora, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ]),
        const SizedBox(height: 4),
        Text('Reportado por $nomReportante',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 6),
        Text(detalle, style: TextStyle(color: color, fontSize: 12, height: 1.35)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () => _revisarReporteParadero(r, sacar: false),
              child: const Text('REVISADO',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
          if (!retirado && sigueEnFila) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                onPressed: () => _revisarReporteParadero(r, sacar: true),
                child: const Text('SACAR DE LA FILA',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ]),
      ]),
    );
  }
}
