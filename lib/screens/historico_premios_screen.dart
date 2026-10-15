// Histórico de la competencia semanal: una tarjeta por semana con el podio
// (👑 🥈 🥉), quién ganó premio (≥80 pts) y el top 10. Lo ven la central y
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
      if (!mounted) return;
      setState(() {
        _semanas = porSemana.entries.toList();
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
              : _semanas.isEmpty
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
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _semanas.length,
                        itemBuilder: (_, i) => _tarjetaSemana(_semanas[i].key, _semanas[i].value),
                      ),
                    ),
    );
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
