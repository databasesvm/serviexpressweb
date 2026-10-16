// Histórico de la competencia semanal: una tarjeta por semana con el podio
// (🥇 🥈 🥉), quién ganó premio (≥80 pts) y el top 10. Lo ven la central y
// los móviles. Los datos los guarda el servidor cada lunes al cerrar la
// semana (fn_calcular_premios_semanales → tabla premios_semanales).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/competencia_semanal.dart';

class HistoricoPremiosScreen extends StatefulWidget {
  /// Si lo abre un móvil, sus semanas ganadas se resaltan.
  final int? miMovilId;
  const HistoricoPremiosScreen({super.key, this.miMovilId});

  @override
  State<HistoricoPremiosScreen> createState() => _HistoricoPremiosScreenState();
}

class _HistoricoPremiosScreenState extends State<HistoricoPremiosScreen> {
  bool _cargando = true;
  String? _error;
  // semana_inicio → filas ordenadas por posición
  List<MapEntry<String, List<Map<String, dynamic>>>> _semanas = [];
  final Set<String> _expandidas = {};
  // Empates del premio que la Central debe decidir
  List<Map<String, dynamic>> _empates = [];
  // empate_id → (movil_id → puesto elegido: 0 = sin premio)
  final Map<int, Map<int, int>> _eleccion = {};
  bool _guardandoEmpate = false;

  /// La abre la Central (sin miMovilId) → puede decidir. El servidor igual
  /// verifica que sea la Central (fn_es_central).
  bool get _esCentral => widget.miMovilId == null;

  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final rows = await Supabase.instance.client
          .from('premios_semanales')
          .select('semana_inicio, semana_fin, movil_id, numero_movil, nombre, '
              'puntos, posicion, premio_puesto, premio_pct')
          .order('semana_inicio', ascending: false)
          .order('posicion', ascending: true)
          .limit(600);
      final Map<String, List<Map<String, dynamic>>> porSemana = {};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        porSemana.putIfAbsent(r['semana_inicio'].toString(), () => []).add(r);
      }
      List<Map<String, dynamic>> empates = [];
      try {
        empates = List<Map<String, dynamic>>.from(await Supabase.instance.client
            .from('premios_empates')
            .select('id, semana_inicio, semana_fin, puestos, candidatos, estado')
            .eq('estado', 'pendiente')
            .order('id', ascending: false));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _semanas = porSemana.entries.toList();
        _empates = empates;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  String _rango(Map<String, dynamic> r) {
    final ini = DateTime.tryParse(r['semana_inicio'].toString());
    final fin = DateTime.tryParse(r['semana_fin'].toString());
    if (ini == null || fin == null) return r['semana_inicio'].toString();
    final mesIni = _meses[ini.month - 1];
    final mesFin = _meses[fin.month - 1];
    return ini.month == fin.month
        ? 'Semana ${ini.day} – ${fin.day} $mesFin ${fin.year}'
        : 'Semana ${ini.day} $mesIni – ${fin.day} $mesFin ${fin.year}';
  }

  String _movil(Map<String, dynamic> r) {
    final n = (r['numero_movil'] as num?)?.toInt();
    return n != null ? 'Móvil ${n.toString().padLeft(2, '0')}' : (r['nombre']?.toString() ?? 'Móvil');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('🏆 Histórico de premios',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFFD54F)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar el histórico.\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54)),
                  ),
                )
              : (_semanas.isEmpty && _empates.isEmpty)
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aún no hay semanas cerradas.\n'
                          'El primer registro se guarda el lunes al cerrar la semana.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          ..._empates.map(_tarjetaEmpate),
                          ..._semanas.map((s) => _tarjetaSemana(s.key, s.value)),
                        ],
                      ),
                    ),
    );
  }

  // ── EMPATE: la Central decide quién gana (o si varios ganan el mismo) ──
  Widget _tarjetaEmpate(Map<String, dynamic> e) {
    final id = (e['id'] as num).toInt();
    final puestos = List<int>.from((e['puestos'] as List? ?? []).map((x) => (x as num).toInt()));
    final cands = List<Map<String, dynamic>>.from(
        (e['candidatos'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)));
    final eleccion = _eleccion.putIfAbsent(id, () => {});
    final puestosTxt = puestos.map((p) => '$p°').join(' y ');

    Widget chip(int movilId, int puesto, String texto) {
      final sel = (eleccion[movilId] ?? 0) == puesto;
      return Padding(
        padding: const EdgeInsets.only(right: 6, bottom: 6),
        child: ChoiceChip(
          label: Text(texto, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              color: sel ? Colors.black : Colors.white70)),
          selected: sel,
          selectedColor: const Color(0xFFFFD54F),
          backgroundColor: const Color(0xFF2A2A2A),
          side: BorderSide(color: sel ? const Color(0xFFFFD54F) : Colors.white24),
          onSelected: _esCentral && !_guardandoEmpate
              ? (_) => setState(() => eleccion[movilId] = puesto)
              : null,
        ),
      );
    }

    return Card(
      color: const Color(0xFF241C00),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFD54F), width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚖️ Empate en el premio — ${_rango(e)}',
              style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            _esCentral
                ? 'Falta decidir el $puestosTxt puesto. Elige el puesto de cada Móvil '
                    '(puedes dar el mismo puesto a varios).'
                : 'La Central está decidiendo el $puestosTxt puesto.',
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
          ),
          const SizedBox(height: 12),
          for (final c in cands) ...[
            Builder(builder: (_) {
              final mid = (c['movil_id'] as num).toInt();
              final num_ = (c['numero_movil'] as num?)?.toInt();
              final punt = (c['puntuacion'] as num?)?.toDouble();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${num_ != null ? 'Móvil $num_' : (c['nombre'] ?? 'Móvil')}  ·  ${c['puntos']} pts'
                    '${punt != null ? '  ·  ⭐ ${punt.toStringAsFixed(2)}' : ''}'
                    '  ·  ${c['servicios'] ?? 0} servicios',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(children: [
                    for (final p in puestos) chip(mid, p, '${emojiPodio(p)} $p°'),
                    chip(mid, 0, 'Sin premio'),
                  ]),
                ]),
              );
            }),
          ],
          if (_esCentral)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD54F),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _guardandoEmpate ? null : () => _guardarEmpate(id, cands),
                icon: _guardandoEmpate
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.gavel_rounded),
                label: const Text('GUARDAR DECISIÓN',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
            ),
        ]),
      ),
    );
  }

  Future<void> _guardarEmpate(int empateId, List<Map<String, dynamic>> cands) async {
    final eleccion = _eleccion[empateId] ?? {};
    final asignaciones = [
      for (final c in cands)
        if ((eleccion[(c['movil_id'] as num).toInt()] ?? 0) > 0)
          {'movil_id': (c['movil_id'] as num).toInt(), 'puesto': eleccion[(c['movil_id'] as num).toInt()]},
    ];
    final resumen = cands.map((c) {
      final p = eleccion[(c['movil_id'] as num).toInt()] ?? 0;
      final n = (c['numero_movil'] as num?)?.toInt();
      return '• Móvil ${n ?? '?'}: ${p == 0 ? 'sin premio' : '${emojiPodio(p)} $p° puesto'}';
    }).join('\n');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('¿Confirmas la decisión?', style: TextStyle(color: Colors.white)),
        content: Text('$resumen\n\nA los ganadores les llega el aviso y su descuento. '
            'No se puede cambiar después.',
            style: const TextStyle(color: Colors.white70, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('REVISAR', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD54F), foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _guardandoEmpate = true);
    try {
      final r = await Supabase.instance.client.rpc('fn_resolver_empate_premio',
          params: {'p_empate_id': empateId, 'p_asignaciones': asignaciones});
      final res = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      if (!mounted) return;
      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Decisión guardada. Se avisó a los ganadores.'),
          backgroundColor: Colors.green,
        ));
        await _cargar();
      } else {
        final err = res['error']?.toString() ?? '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err == 'no_autorizado'
              ? 'Solo la Central puede decidir el empate.'
              : err == 'ya_resuelto'
                  ? 'Este empate ya fue decidido.'
                  : 'No se pudo guardar. Intenta de nuevo.'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo guardar. Revisa tu conexión e intenta de nuevo.'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _guardandoEmpate = false);
    }
  }

  Widget _tarjetaSemana(String clave, List<Map<String, dynamic>> filas) {
    final ganadores = filas.where((r) => r['premio_puesto'] != null).toList()
      ..sort((a, b) => (a['premio_puesto'] as int).compareTo(b['premio_puesto'] as int));
    final top3 = filas.take(3).toList();
    final bool yoGane = widget.miMovilId != null &&
        ganadores.any((r) => (r['movil_id'] as num?)?.toInt() == widget.miMovilId);
    final bool abierta = _expandidas.contains(clave);

    return Card(
      color: yoGane ? const Color(0xFF2E2300) : const Color(0xFF1A1A1A),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: yoGane ? const Color(0xFFFFD54F) : Colors.white12, width: yoGane ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(_rango(filas.first),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              if (yoGane)
                const Text('⭐ ¡Ganaste!',
                    style: TextStyle(
                        color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            if (ganadores.isNotEmpty)
              ...ganadores.map((r) => _filaPodio(r, premio: true))
            else ...[
              const Text('Nadie llegó a $kPuntosPremioSemana pts esta semana',
                  style: TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(height: 4),
              ...top3.map((r) => _filaPodio(r, premio: false)),
            ],
            if (filas.length > 3) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => setState(() =>
                      abierta ? _expandidas.remove(clave) : _expandidas.add(clave)),
                  child: Text(abierta ? 'Ocultar top 10 ▲' : 'Ver top 10 ▼',
                      style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12)),
                ),
              ),
              if (abierta)
                ...filas.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        SizedBox(
                          width: 28,
                          child: Text('#${r['posicion']}',
                              style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ),
                        Expanded(
                          child: Text(_movil(r),
                              style: TextStyle(
                                color: (r['movil_id'] as num?)?.toInt() == widget.miMovilId
                                    ? const Color(0xFFFFD54F)
                                    : Colors.white70,
                                fontSize: 12,
                                fontWeight: (r['movil_id'] as num?)?.toInt() == widget.miMovilId
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              )),
                        ),
                        Text('${r['puntos']} pts',
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ]),
                    )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaPodio(Map<String, dynamic> r, {required bool premio}) {
    final int puesto = premio
        ? (r['premio_puesto'] as int)
        : ((r['posicion'] as num?)?.toInt() ?? 0);
    final pct = (r['premio_pct'] as num?)?.toInt();
    final bool esYo = (r['movil_id'] as num?)?.toInt() == widget.miMovilId;
    final String textoPremio = !premio
        ? ''
        : pct == 100
            ? 'No pagó semana'
            : pct != null
                ? '$pct% desc.'
                : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(emojiPodio(puesto).isEmpty ? '•' : emojiPodio(puesto),
            style: TextStyle(fontSize: puesto == 1 ? 20 : 17)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_movil(r)}${esYo ? '  (tú)' : ''}',
            style: TextStyle(
              color: esYo ? const Color(0xFFFFD54F) : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        Text('${r['puntos']} pts',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
        if (textoPremio.isNotEmpty) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(40),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.greenAccent.withAlpha(120)),
            ),
            child: Text(textoPremio,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ]),
    );
  }
}
