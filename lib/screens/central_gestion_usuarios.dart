part of 'central_screen.dart';
// // Gestión de usuarios (activaciones / rangos)

class _PanelGestionUsuarios extends StatefulWidget {
  final int tabInicial;
  const _PanelGestionUsuarios({this.tabInicial = 0});
  @override
  State<_PanelGestionUsuarios> createState() => _PanelGestionUsuariosState();
}

class _PanelGestionUsuariosState extends State<_PanelGestionUsuarios>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  late final TabController _tabCtrl;
  final _busqCtrl = TextEditingController();
  String _busq = '';

  List<Map<String, dynamic>> _solicitudes = [];
  List<Map<String, dynamic>> _activaciones = [];
  List<Map<String, dynamic>> _moviles = [];
  List<Map<String, dynamic>> _registros = [];
  List<Map<String, dynamic>> _solicitudesDescansoList = [];
  List<Map<String, dynamic>> _eliminados = [];
  List<Map<String, dynamic>> _locales = [];
  List<Map<String, dynamic>> _clientes = [];
  bool _cargando = true;
  String _planFiltroWallet = ''; // '' = todos, 'prediario', 'postdia', 'semanal'
  String _filtroFaccion = ''; // '' = todos, 'ninguna', 'se', 'fn', 'ambas'

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 9, vsync: this, initialIndex: widget.tabInicial);
    _cargar();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _busqCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      // Medianoche local de hoy → "Recientes" se reinicia cada día
      final hoy = DateTime.now();
      final hoyMedianoche = DateTime(hoy.year, hoy.month, hoy.day).toIso8601String();
      final results = await Future.wait([
        _db.from('usuarios')
            .select('id, nombre, usuario, correo, telefono, direccion_local, tipo_negocio, zona_cobertura, created_at')
            .eq('rol', 'local').eq('estado_local', 'pendiente').order('created_at'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, telefono, correo, activo, suspendido, created_at, numero_movil, tipo_plan_movil, doc_perfil_url, doc_cedula_url, doc_licencia_url, doc_soat_url')
            .eq('activo', false)
            .neq('rol', 'local')   // locales van en "Solicitudes", no aquí
            .or('suspendido.is.null,suspendido.eq.false')
            .or('eliminado.is.null,eliminado.eq.false')
            .order('created_at'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rango_movil, puntuacion, activo, tipo_plan_movil, numero_movil, saldo_wallet, comision_pct, wallet_bloqueado, tiene_fn, tiene_se')
            .eq('rol', 'movil').order('usuario', ascending: true),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, estado_local, activo, suspendido, created_at')
            .gte('created_at', hoyMedianoche).order('created_at', ascending: false),
        _db.from('solicitudes_descanso')
            .select('id, movil_id, fecha_inicio, fecha_fin, dias_solicitados, razon, estado, aprobado_por, rechazado_motivo, created_at, usuarios(nombre, usuario)')
            .order('created_at', ascending: false)
            .limit(50),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, correo, telefono, tipo_plan_movil, rango_movil, numero_movil, eliminado_at, eliminado_por, created_at')
            .eq('eliminado', true)
            .order('eliminado_at', ascending: false),
        _db.from('usuarios')
            .select('id, nombre, usuario, correo, telefono, direccion_local, tipo_negocio, zona_cobertura, activo, created_at')
            .eq('rol', 'local')
            .eq('estado_local', 'activo')
            .order('nombre', ascending: true),
        _db.from('usuarios')
            .select('id, nombre, usuario, correo, telefono, created_at')
            .eq('rol', 'cliente')
            .or('eliminado.is.null,eliminado.eq.false')
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _solicitudes              = List<Map<String, dynamic>>.from(results[0]);
        _activaciones             = List<Map<String, dynamic>>.from(results[1]);
        _moviles                  = List<Map<String, dynamic>>.from(results[2]);
        _registros                = List<Map<String, dynamic>>.from(results[3]);
        _solicitudesDescansoList  = List<Map<String, dynamic>>.from(results[4]);
        _eliminados               = List<Map<String, dynamic>>.from(results[5]);
        _locales                  = List<Map<String, dynamic>>.from(results[6]);
        _clientes                 = List<Map<String, dynamic>>.from(results[7]);
        _cargando = false;
      });
    } catch (e) {
      debugPrint('ERROR _cargar gestion usuarios: $e');
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _colorRol(String? rol) {
    switch (rol) {
      case 'local':   return const Color(0xFFF59E0B);
      case 'movil':   return const Color(0xFF3B82F6);
      case 'cliente': return const Color(0xFF22C55E);
      case 'central': return const Color(0xFFA855F7);
      default:        return Colors.grey;
    }
  }

  Color _colorRango(String? r) => switch (r) {
    'NOVATO'  => const Color(0xFF6B7280),
    'PRO'     => const Color(0xFF3B82F6),
    'ÉLITE'   => const Color(0xFFA855F7),
    'LEYENDA' => const Color(0xFFEF8C0E),
    'MASTER'  => const Color(0xFFEF4444),
    _         => Colors.grey,
  };

  String _numMovil(String? usuario) {
    if (usuario == null || usuario.isEmpty) return '';
    final m = RegExp(r'\d+').firstMatch(usuario);
    return m != null ? '#${m.group(0)}' : '';
  }

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

  // Botón de acción con etiqueta — para la fila 2 de la tarjeta de móvil
  Widget _botonAccion(IconData icono, Color color, String label, VoidCallback onTap) =>
    SizedBox(
      width: 80,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, color: color, size: 18),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );

  List<Map<String, dynamic>> _filtrar(List<Map<String, dynamic>> lista) {
    if (_busq.isEmpty) return lista;
    final q = _busq.toLowerCase();
    return lista.where((u) =>
      (u['nombre'] ?? '').toString().toLowerCase().contains(q) ||
      (u['usuario'] ?? '').toString().toLowerCase().contains(q) ||
      (u['rol'] ?? '').toString().toLowerCase().contains(q) ||
      (u['tipo_negocio'] ?? '').toString().toLowerCase().contains(q),
    ).toList();
  }


  // ── Acciones ──────────────────────────────────────────────────────────────
  Future<void> _aprobarLocal(Map<String, dynamic> l) async {
    await _db.from('usuarios').update({'estado_local': 'aprobado', 'motivo_rechazo': null}).eq('id', l['id']);
    _pushLocal(l['id'].toString(), l['nombre']?.toString() ?? '', '✅ ¡Cuenta aprobada!',
        'Tu local "${l['nombre']}" ya está activo en Serviexpress. ¡Bienvenido!', 'local_aprobado');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l['nombre']} aprobado'), backgroundColor: Colors.green[700]));
    _cargar();
  }

  Future<void> _rechazarLocal(Map<String, dynamic> l) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rechazar solicitud', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l['nombre'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Motivo del rechazo (opcional)',
              hintStyle: const TextStyle(color: Colors.white30),
              filled: true, fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final motivo = ctrl.text.trim().isEmpty ? 'Solicitud no aprobada por Central' : ctrl.text.trim();
    await _db.from('usuarios').update({'estado_local': 'rechazado', 'motivo_rechazo': motivo}).eq('id', l['id']);
    _pushLocal(l['id'].toString(), l['nombre']?.toString() ?? '', '❌ Solicitud no aprobada',
        'Tu solicitud para "${l['nombre']}" no fue aprobada. Contáctanos para más información.', 'local_rechazado');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l['nombre']} rechazado'), backgroundColor: Colors.red[700]));
    _cargar();
  }

  void _pushLocal(String id, String nombre, String titulo, String cuerpo, String tipo) {
    Supabase.instance.client.functions.invoke('enviar-push', body: {
      'filtros': {'external_id': id},
      'titulo': titulo, 'cuerpo': cuerpo, 'data': {'tipo': tipo},
    }).ignore();
  }

  Future<void> _activarUsuario(Map<String, dynamic> u) async {
    final esMovil = u['rol']?.toString() == 'movil';
    final numMovilRaw = u['numero_movil'];
    final identificador = esMovil && numMovilRaw != null
        ? 'MOVIL$numMovilRaw'
        : (u['usuario']?.toString().toUpperCase() ?? '—');

    // ── Verificar conflicto de número antes de activar ───────────────────
    if (esMovil && numMovilRaw != null) {
      final conflicto = await _db
          .from('usuarios')
          .select('id, nombre, usuario')
          .eq('numero_movil', numMovilRaw)
          .or('eliminado.is.null,eliminado.eq.false')
          .eq('activo', true)
          .neq('id', u['id'])
          .limit(1);

      if (!mounted) return;

      if (conflicto.isNotEmpty) {
        final otro = conflicto.first;
        final otroNombre = otro['nombre']?.toString() ?? '—';
        final otroUser   = otro['usuario']?.toString() ?? '—';
        final continuar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('Número duplicado', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ]),
            content: Text(
              'El número $numMovilRaw ya está en uso por:\n\n'
              '• $otroNombre  (@$otroUser)\n\n'
              'Desactiva ese móvil primero o pídele al solicitante que cambie su número.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ACTIVAR DE TODAS FORMAS', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        );
        if (continuar != true) return;
      }
    }

    // ── Seleccionar facción (solo móviles) ───────────────────────────────
    bool selSE = false;
    bool selFN = false;
    if (esMovil) {
      final faccion = await showDialog<(bool, bool)?>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.military_tech_rounded, color: Colors.amber, size: 18),
              SizedBox(width: 8),
              Text('Asignar facción', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Selecciona las facciones para $identificador.\nSin facción asignada, el móvil no podrá conectarse.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => setSt(() => selSE = !selSE),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selSE ? const Color(0xFF1B5E20) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selSE ? const Color(0xFF3AF500) : Colors.white24, width: 1.5),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.electric_bolt, color: selSE ? const Color(0xFF3AF500) : Colors.white38, size: 22),
                      const SizedBox(height: 4),
                      Text('SE', style: TextStyle(color: selSE ? const Color(0xFF3AF500) : Colors.white38,
                          fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2)),
                      Text('ServiExpress', style: TextStyle(color: selSE ? Colors.white70 : Colors.white24, fontSize: 9)),
                    ]),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: () => setSt(() => selFN = !selFN),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: selFN ? const Color(0xFF001A5E) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: selFN ? const Color(0xFF3949AB) : Colors.white24, width: 1.5),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.local_pharmacy, color: selFN ? const Color(0xFF7986CB) : Colors.white38, size: 22),
                      const SizedBox(height: 4),
                      Text('FN', style: TextStyle(color: selFN ? const Color(0xFF7986CB) : Colors.white38,
                          fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2)),
                      Text('Farmanorte', style: TextStyle(color: selFN ? Colors.white70 : Colors.white24, fontSize: 9)),
                    ]),
                  ),
                )),
              ]),
              if (!selSE && !selFN) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                  child: const Text('⚠️ Sin facción: el móvil no podrá conectarse hasta que le asignes una.',
                      style: TextStyle(color: Colors.orange, fontSize: 11)),
                ),
              ],
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, (selSE, selFN)),
                child: const Text('ACTIVAR', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
      if (faccion == null) return; // canceló
      selSE = faccion.$1;
      selFN = faccion.$2;
    }

    // ── Activar ──────────────────────────────────────────────────────────
    await _db.from('usuarios').update({
      'activo': true,
      if (esMovil) 'tiene_se': selSE,
      if (esMovil) 'tiene_fn': selFN,
    }).eq('id', u['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ $identificador activado'), backgroundColor: Colors.green[700]),
    );
    _cargar();
  }

  // ── Cambiar facción de un móvil ──────────────────────────────────────────
  Future<void> _cambiarFaccionDialog(Map<String, dynamic> u) async {
    bool selSE = u['tiene_se'] == true;
    bool selFN = u['tiene_fn'] == true;
    final nombre = u['nombre']?.toString() ?? '—';

    final faccion = await showDialog<(bool, bool)?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.military_tech_rounded, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Text('Cambiar facción', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(nombre, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => setSt(() => selSE = !selSE),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selSE ? const Color(0xFF1B5E20) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selSE ? const Color(0xFF3AF500) : Colors.white24, width: 1.5),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.electric_bolt, color: selSE ? const Color(0xFF3AF500) : Colors.white38, size: 22),
                    const SizedBox(height: 4),
                    Text('SE', style: TextStyle(color: selSE ? const Color(0xFF3AF500) : Colors.white38,
                        fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2)),
                    Text('ServiExpress', style: TextStyle(color: selSE ? Colors.white70 : Colors.white24, fontSize: 9)),
                  ]),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => setSt(() => selFN = !selFN),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: selFN ? const Color(0xFF001A5E) : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: selFN ? const Color(0xFF3949AB) : Colors.white24, width: 1.5),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_pharmacy, color: selFN ? const Color(0xFF7986CB) : Colors.white38, size: 22),
                    const SizedBox(height: 4),
                    Text('FN', style: TextStyle(color: selFN ? const Color(0xFF7986CB) : Colors.white38,
                        fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.2)),
                    Text('Farmanorte', style: TextStyle(color: selFN ? Colors.white70 : Colors.white24, fontSize: 9)),
                  ]),
                ),
              )),
            ]),
            if (!selSE && !selFN) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                child: const Text('⚠️ Sin facción: el móvil no podrá conectarse.',
                    style: TextStyle(color: Colors.orange, fontSize: 11)),
              ),
            ],
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, (selSE, selFN)),
              child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (faccion == null || !mounted) return;
    await _db.from('usuarios').update({'tiene_se': faccion.$1, 'tiene_fn': faccion.$2}).eq('id', u['id']);
    final idx = _moviles.indexWhere((m) => m['id'] == u['id']);
    if (idx != -1) setState(() => _moviles[idx] = {..._moviles[idx], 'tiene_se': faccion.$1, 'tiene_fn': faccion.$2});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: const Text('✅ Facción actualizada'), backgroundColor: Colors.green[700]),
    );
  }

  // ── Cambiar plan (tipo_plan_movil) ───────────────────────────────────────
  Future<void> _cambiarPlanDialog(Map<String, dynamic> u) async {
    String selPlan = u['tipo_plan_movil']?.toString() ?? 'prediario';
    final nombre = u['nombre']?.toString() ?? '—';

    const planes = [
      ('prediario', 'PRE-DIARIO', 'Paga antes de conectar', Icons.wb_sunny_rounded, Color(0xFFE65100)),
      ('postdia',   'POST-DÍA',   'Paga al finalizar el día', Icons.nightlight_round, Color(0xFF1565C0)),
      ('semanal',   'SEMANAL',    'Cobro automático lunes',   Icons.calendar_today_rounded, Color(0xFF6A1B9A)),
    ];

    final nuevoPlan = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.credit_card_rounded, color: Colors.lightBlueAccent, size: 18),
            SizedBox(width: 8),
            Text('Cambiar método de pago', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(nombre, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 14),
            ...planes.map((p) {
              final activo = selPlan == p.$1;
              return GestureDetector(
                onTap: () => setSt(() => selPlan = p.$1),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: activo ? p.$5.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: activo ? p.$5 : Colors.white24, width: 1.5),
                  ),
                  child: Row(children: [
                    Icon(p.$4, color: activo ? p.$5 : Colors.white38, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.$2, style: TextStyle(color: activo ? p.$5 : Colors.white70,
                          fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.8)),
                      Text(p.$3, style: TextStyle(color: activo ? Colors.white70 : Colors.white30, fontSize: 10)),
                    ])),
                    if (activo) Icon(Icons.check_circle_rounded, color: p.$5, size: 18),
                  ]),
                ),
              );
            }),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlue[700], foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, selPlan),
              child: const Text('GUARDAR', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (nuevoPlan == null || !mounted) return;
    try {
      await _db.from('usuarios').update({'tipo_plan_movil': nuevoPlan}).eq('id', u['id']);
      final idx = _moviles.indexWhere((m) => m['id'] == u['id']);
      if (idx != -1) setState(() => _moviles[idx] = {..._moviles[idx], 'tipo_plan_movil': nuevoPlan});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Plan actualizado a $nuevoPlan'), backgroundColor: Colors.lightBlue[700]),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error al guardar plan: $e'), backgroundColor: Colors.red[700]),
      );
    }
  }

  // ── Cambiar contraseña ────────────────────────────────────────────────────
  Future<void> _cambiarContrasenaDialog(Map<String, dynamic> usuario) async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool verPass = false;
    bool guardando = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.lock_reset_rounded, color: Colors.amber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Cambiar contraseña',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '${usuario['nombre'] ?? '—'}  •  @${usuario['usuario'] ?? ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: passCtrl,
              obscureText: !verPass,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Nueva contraseña',
                labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38, size: 16),
                suffixIcon: IconButton(
                  icon: Icon(verPass ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white30, size: 16),
                  onPressed: () => setSt(() => verPass = !verPass),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              obscureText: !verPass,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Confirmar contraseña',
                labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.white38, size: 16),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[800],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: guardando ? null : () async {
                final pass = passCtrl.text.trim();
                final confirm = confirmCtrl.text.trim();
                if (pass.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ingresa la nueva contraseña')));
                  return;
                }
                if (pass != confirm) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Las contraseñas no coinciden'), backgroundColor: Colors.red));
                  return;
                }
                setSt(() => guardando = true);
                try {
                  await _db.from('usuarios')
                      .update({'contrasena': hashContrasena(pass)})
                      .eq('id', usuario['id']);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('✓ Contraseña de ${movilLabel(usuario)} actualizada'),
                      backgroundColor: Colors.green[700],
                    ));
                  }
                } catch (e) {
                  setSt(() => guardando = false);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[800]));
                  }
                }
              },
              icon: guardando
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, size: 15),
              label: const Text('Guardar', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
    passCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _cambiarRango(Map<String, dynamic> u, String rango) async {
    try {
      await _db.from('usuarios').update({'rango_movil': rango}).eq('id', u['id']);
      final idx = _moviles.indexWhere((m) => m['id'] == u['id']);
      if (idx >= 0 && mounted) {
        setState(() => _moviles[idx] = {..._moviles[idx], 'rango_movil': rango});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${movilLabel(u)} ascendido a $rango'),
          backgroundColor: const Color(0xFF3B82F6),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[800]));
      }
    }
  }

  // ── Eliminar cuenta de móvil (soft delete) ───────────────────────────────
  Future<void> _eliminarCuentaMovil(Map<String, dynamic> u) async {
    final nombre = u['nombre']?.toString() ?? 'este móvil';

    // Paso 1: confirmación inicial
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red[300], size: 22),
          const SizedBox(width: 8),
          const Text('Eliminar cuenta', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Text(
          '¿Estás seguro de que quieres eliminar la cuenta de $nombre?\n\n'
          'El historial de servicios se conserva, pero el móvil no podrá volver a iniciar sesión.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CONTINUAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    // Paso 2: verificar si tiene servicio activo
    try {
      final activos = await _db.from('servicios')
          .select('id')
          .eq('movil_id', u['id'])
          .inFilter('estado', ['en_ruta_origen', 'en_origen', 'en_ruta_destino', 'problema'])
          .limit(1);
      if (activos.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('⚠️ No se puede eliminar: el móvil tiene un servicio activo en este momento.'),
            backgroundColor: Colors.orange,
          ));
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error verificando servicios: $e'), backgroundColor: Colors.red));
      }
      return;
    }

    // Paso 3: confirmación final
    final confirmadoFinal = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('⚠️ Confirmar eliminación', style: TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Esta acción no se puede deshacer.\n\n'
          'La cuenta de $nombre quedará deshabilitada permanentemente.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NO, VOLVER', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SÍ, ELIMINAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmadoFinal != true || !mounted) return;

    // Paso 4: soft delete
    try {
      await _db.from('usuarios').update({
        'activo': false,
        'en_linea': false,
        'suspendido': true,
        'paradero_actual': null,
        'ingreso_fila': null,
        'nombre': '[Eliminado]',
        'correo': null,
        'telefono': null,
      }).eq('id', u['id']);

      if (mounted) {
        setState(() => _moviles.removeWhere((m) => m['id'] == u['id']));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ Cuenta de $nombre eliminada correctamente.'),
          backgroundColor: Colors.green[800],
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0A0A0A),
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text('Gestión de Usuarios',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            centerTitle: false,
            actions: [IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white60), onPressed: _cargar)],
          ),
        ],
        body: _cargando
          ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
          : Column(children: [
              // ── Stat boxes (scroll horizontal para 5 tabs) ─────────────
              SizedBox(
                height: 56,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      _statBox('${_solicitudes.length}', 'Solicitudes', const Color(0xFFF59E0B), onTap: () => _tabCtrl.animateTo(0)),
                      const SizedBox(width: 8),
                      _statBox('${_activaciones.length}', 'Por activar', const Color(0xFF3B82F6), onTap: () => _tabCtrl.animateTo(1)),
                      const SizedBox(width: 8),
                      _statBox('${_moviles.length}', 'Móviles', const Color(0xff3AF500), onTap: () => _tabCtrl.animateTo(2)),
                      const SizedBox(width: 8),
                      _statBox('${_registros.length}', 'Recientes', const Color(0xFFA855F7), onTap: () => _tabCtrl.animateTo(3)),
                      const SizedBox(width: 8),
                      _statBox(
                        '${_solicitudesDescansoList.where((s) => s['estado'] == 'pendiente').length}',
                        'Descansos',
                        const Color(0xFF10B981),
                        onTap: () => _tabCtrl.animateTo(4),
                      ),
                      const SizedBox(width: 8),
                      _statBox('${_eliminados.length}', 'Eliminados', Colors.red[400]!, onTap: () => _tabCtrl.animateTo(5)),
                      const SizedBox(width: 8),
                      _statBox(
                        '${_moviles.where((m) => (m['tipo_plan_movil']?.toString() == 'prediario' || m['tipo_plan_movil']?.toString() == 'postdia' || m['tipo_plan_movil']?.toString() == 'semanal')).length}',
                        'Billetera',
                        const Color(0xFF818CF8),
                        onTap: () => _tabCtrl.animateTo(6),
                      ),
                      const SizedBox(width: 8),
                      _statBox('${_locales.length}', 'Locales', const Color(0xFFF59E0B), onTap: () => _tabCtrl.animateTo(7)),
                      const SizedBox(width: 8),
                      _statBox('${_clientes.length}', 'Clientes', const Color(0xFF22C55E), onTap: () => _tabCtrl.animateTo(8)),
                      const SizedBox(width: 8),
                      _statBox('🏪', 'Panel FN', Colors.indigo[400]!, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FnPanelScreen()))),
                    ],
                  ),
                ),
              ),
              // ── Búsqueda ───────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextField(
                  controller: _busqCtrl,
                  onChanged: (v) => setState(() => _busq = v),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, usuario o tipo...',
                    hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white30, size: 18),
                    suffixIcon: _busq.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white30, size: 16),
                          onPressed: () { _busqCtrl.clear(); setState(() => _busq = ''); })
                      : null,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: TabBarView(controller: _tabCtrl, children: [
                _tabSolicitudes(),
                _tabActivaciones(),
                _tabAscensos(),
                _tabRecientes(),
                _tabDescansos(),
                _tabEliminados(),
                _tabWallet(),
                _tabLocales(),
                _tabClientes(),
              ])),
            ]),
      ),
    );
  }

  Widget _statBox(String val, String label, Color color, {VoidCallback? onTap}) => SizedBox(
    width: 86,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(val, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 8), textAlign: TextAlign.center),
        ]),
      ),
    ),
  );

  // ── Tab 0: Solicitudes de locales ──────────────────────────────────────────
  Widget _tabSolicitudes() {
    final lista = _filtrar(_solicitudes);
    if (lista.isEmpty) return _empty(Icons.store_mall_directory_rounded, 'Sin solicitudes pendientes');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final l = lista[i];
        final fecha = DateTime.tryParse(l['created_at']?.toString() ?? '');
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [const Color(0xFFF59E0B).withValues(alpha: 0.12), Colors.transparent]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                  child: Text(_iniciales(l['nombre']), style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('@${l['usuario'] ?? ''}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ])),
                if (fecha != null) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${fecha.day}/${fecha.month}/${fecha.year}', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  Text('${fecha.hour}:${fecha.minute.toString().padLeft(2,'0')}', style: const TextStyle(color: Colors.white24, fontSize: 9)),
                ]),
              ]),
            ),
            // Info rows
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(children: [
                if ((l['tipo_negocio'] ?? '').toString().isNotEmpty) _infoR(Icons.category_outlined, l['tipo_negocio'].toString(), const Color(0xFFF59E0B)),
                if ((l['direccion_local'] ?? '').toString().isNotEmpty) _infoR(Icons.location_on_outlined, l['direccion_local'].toString(), Colors.white38),
                if ((l['zona_cobertura'] ?? '').toString().isNotEmpty) _infoR(Icons.map_outlined, 'Zona: ${l['zona_cobertura']}', Colors.white38),
                if ((l['telefono'] ?? '').toString().isNotEmpty) _infoR(Icons.phone_outlined, l['telefono'].toString(), Colors.white38),
                if ((l['correo'] ?? '').toString().isNotEmpty) _infoR(Icons.email_outlined, l['correo'].toString(), Colors.white38),
              ]),
            ),
            // Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[400], side: BorderSide(color: Colors.red[900]!),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 15),
                  label: const Text('Rechazar', style: TextStyle(fontSize: 12)),
                  onPressed: () => _rechazarLocal(l),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 15),
                  label: const Text('Aprobar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _aprobarLocal(l),
                )),
              ]),
            ),
          ],
        ),
        );
      },
    );
  }

  // ── Helper: fila de info con icono ───────────────────────────────────────
  Widget _infoR(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12), overflow: TextOverflow.ellipsis)),
    ]),
  );

  // ── Helper: pantalla vacía ────────────────────────────────────────────────
  Widget _empty(IconData icon, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: Colors.white12),
      const SizedBox(height: 10),
      Text(msg, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]),
  );

  // ── Genera URL firmada (1h) para fotos del bucket privado movil-docs ──────
  Future<String?> _getSignedUrl(String? pathOrUrl) async {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    String path = pathOrUrl;
    // Datos legacy: URL pública completa guardada — extraer solo el path
    if (pathOrUrl.startsWith('http')) {
      const marker = '/movil-docs/';
      final idx = pathOrUrl.indexOf(marker);
      if (idx == -1) return null;
      path = pathOrUrl.substring(idx + marker.length);
    }
    try {
      return await Supabase.instance.client.storage
          .from('movil-docs')
          .createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  // ── Dialog: Ver registro completo del usuario ────────────────────────────
  void _verRegistroDialog(Map<String, dynamic> u) async {
    // Pre-cargar URLs firmadas antes de abrir el dialog (bucket privado)
    final perfilUrl  = await _getSignedUrl(u['doc_perfil_url']?.toString());
    final cedulaUrl  = await _getSignedUrl(u['doc_cedula_url']?.toString());
    final licenciaUrl = await _getSignedUrl(u['doc_licencia_url']?.toString());
    final soatUrl    = await _getSignedUrl(u['doc_soat_url']?.toString());
    if (!mounted) return;

    final plan = u['tipo_plan_movil']?.toString() ?? '';
    final numMovil = u['numero_movil']?.toString() ?? '';

    // Abre imagen a pantalla completa al tocar
    void _verImagen(BuildContext ctx, String url) {
      showDialog(
        context: ctx,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.broken_image_rounded, color: Colors.white30, size: 48),
                    SizedBox(height: 12),
                    Text('No se pudo cargar la imagen', style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Selfie grande con tap para ampliar
    Widget _selfieWidget(String? url) {
      if (url == null || url.isEmpty) {
        return Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.no_photography_rounded, color: Colors.white24, size: 32),
              SizedBox(height: 6),
              Text('Selfie no subida', style: TextStyle(color: Colors.white30, fontSize: 12)),
            ]),
          ),
        );
      }
      return GestureDetector(
        onTap: () => _verImagen(context, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(url, height: 180, width: double.infinity, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 80, color: Colors.white10,
              child: const Center(child: Text('No se pudo cargar', style: TextStyle(color: Colors.white30, fontSize: 11))),
            ),
          ),
        ),
      );
    }

    // Doc pequeño en grid (tap para ampliar)
    Widget _docGrid(String? url, String label) {
      if (url == null || url.isEmpty) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 4),
          Container(
            height: 100,
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
            child: const Center(child: Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 20)),
          ),
        ]);
      }
      return GestureDetector(
        onTap: () => _verImagen(context, url),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, height: 100, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 100, color: Colors.white10,
                child: const Center(child: Text('Error', style: TextStyle(color: Colors.white30, fontSize: 10))),
              ),
            ),
          ),
        ]),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Header ──
            Row(children: [
              const Icon(Icons.person_search_rounded, color: Colors.lightBlueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Registro de ${u['nombre'] ?? '—'}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.pop(ctx), padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
            ]),
            const SizedBox(height: 14),

            // ── Selfie de verificación (destacada) ──
            const Text('📸 Selfie de verificación',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _selfieWidget(perfilUrl),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 14),

            // ── Datos básicos ──
            const Text('Datos del registro',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _infoRow(Icons.badge_rounded, 'Usuario', '@${u['usuario'] ?? '—'}'),
            _infoRow(Icons.phone_rounded, 'Teléfono', u['telefono']?.toString() ?? '—'),
            _infoRow(Icons.email_rounded, 'Correo', u['correo']?.toString() ?? '—'),
            if (numMovil.isNotEmpty)
              _infoRow(Icons.tag_rounded, 'Número solicitado', '#$numMovil'),
            if (plan.isNotEmpty)
              _infoRow(Icons.work_rounded, 'Plan', plan.toUpperCase()),
            _infoRow(Icons.people_rounded, 'Rol', u['rol']?.toString().toUpperCase() ?? '—'),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 14),

            // ── Documentos en grid 2 columnas ──
            const Text('Documentos de identidad',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _docGrid(cedulaUrl, '🪪 Cédula')),
              const SizedBox(width: 10),
              Expanded(child: _docGrid(licenciaUrl, '🚗 Licencia')),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _docGrid(soatUrl, '🛡️ SOAT')),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()), // espacio vacío si solo hay 3 docs
            ]),
            const SizedBox(height: 16),

            // ── Botones ──
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar', style: TextStyle(color: Colors.white54))),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('ACTIVAR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                onPressed: () { Navigator.pop(ctx); _activarUsuario(u); },
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String val) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, color: Colors.white38, size: 14),
      const SizedBox(width: 6),
      Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 12)),
      Expanded(child: Text(val, style: const TextStyle(color: Colors.white70, fontSize: 12))),
    ]),
  );

  // ── Tab 1: Activaciones pendientes (usuarios inactivos no suspendidos) ────
  Widget _tabActivaciones() {
    final lista = _filtrar(_activaciones);
    if (lista.isEmpty) return _empty(Icons.how_to_reg_rounded, 'Sin activaciones pendientes');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final u = lista[i];
        final rol = u['rol']?.toString() ?? '';
        final color = _colorRol(rol);
        final numMovilInt = u['numero_movil'] as int?;
        // numero_movil = 0 → "00" (cuenta dual Master)
        final numMovilStr = numMovilInt == null ? '' : (numMovilInt == 0 ? '00' : numMovilInt.toString());
        // Etiqueta de rango de plan según número
        String? planLabel;
        if (numMovilInt != null) {
          if (numMovilInt >= 1 && numMovilInt <= 100) {
            planLabel = 'SUSCRIPCIÓN';
          } else if (numMovilInt >= 200 && numMovilInt <= 299) {
            planLabel = 'PREDIARIO / POSTDIA';
          }
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Fila 1: avatar + info
              Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: numMovilStr.isNotEmpty ? color : color.withValues(alpha: 0.15),
                  child: numMovilStr.isNotEmpty
                      ? Text(numMovilStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                      : Text(_iniciales(u['nombre']), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  if ((u['usuario'] ?? '').toString().isNotEmpty)
                    Text('@${u['usuario']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  if (numMovilStr.isNotEmpty)
                    Text('Número solicitado: #$numMovilStr${planLabel != null ? ' · $planLabel' : ''}',
                        style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 11, fontWeight: FontWeight.w600)),
                  _chip(rol.toUpperCase(), color),
                ])),
              ]),
              const SizedBox(height: 8),
              // Fila 2: botones de acción
              Row(mainAxisSize: MainAxisSize.min, children: [
                _botonAccion(Icons.person_search_rounded, Colors.lightBlueAccent, 'Registro', () => _verRegistroDialog(u)),
                _botonAccion(Icons.lock_reset_rounded, Colors.amber, 'Contraseña', () => _cambiarContrasenaDialog(u)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: 100,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _activarUsuario(u),
                      child: const Text('ACTIVAR'),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  // ── Tab 2: Ascensos / gestión de rangos de móviles ───────────────────────
  Widget _tabAscensos() {
    // Filtro por facción
    var listaBase = _filtrar(_moviles);
    if (_filtroFaccion == 'ninguna') {
      listaBase = listaBase.where((u) => u['tiene_se'] != true && u['tiene_fn'] != true).toList();
    } else if (_filtroFaccion == 'se') {
      listaBase = listaBase.where((u) => u['tiene_se'] == true && u['tiene_fn'] != true).toList();
    } else if (_filtroFaccion == 'fn') {
      listaBase = listaBase.where((u) => u['tiene_fn'] == true && u['tiene_se'] != true).toList();
    } else if (_filtroFaccion == 'ambas') {
      listaBase = listaBase.where((u) => u['tiene_se'] == true && u['tiene_fn'] == true).toList();
    }
    final lista = listaBase;

    // Conteos para los chips
    final cntNinguna = _moviles.where((u) => u['tiene_se'] != true && u['tiene_fn'] != true).length;
    final cntSE = _moviles.where((u) => u['tiene_se'] == true && u['tiene_fn'] != true).length;
    final cntFN = _moviles.where((u) => u['tiene_fn'] == true && u['tiene_se'] != true).length;
    final cntAmbas = _moviles.where((u) => u['tiene_se'] == true && u['tiene_fn'] == true).length;

    const rangos = ['NOVATO', 'PRO', 'ÉLITE', 'LEYENDA', 'MASTER'];
    return Column(children: [
      // Chips de filtro por facción
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final entry in [
              ('', 'Todos', null),
              ('ninguna', 'Sin facción ($cntNinguna)', Colors.orange),
              ('se', 'SE ($cntSE)', const Color(0xFF3AF500)),
              ('fn', 'FN ($cntFN)', const Color(0xFF7986CB)),
              ('ambas', 'Ambas ($cntAmbas)', Colors.amber),
            ]) ...[
              GestureDetector(
                onTap: () => setState(() => _filtroFaccion = entry.$1),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _filtroFaccion == entry.$1
                        ? (entry.$3 ?? Colors.white).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _filtroFaccion == entry.$1
                          ? (entry.$3 ?? Colors.white)
                          : Colors.white24,
                      width: 1.5,
                    ),
                  ),
                  child: Text(entry.$2,
                      style: TextStyle(
                          color: _filtroFaccion == entry.$1
                              ? (entry.$3 ?? Colors.white)
                              : Colors.white54,
                          fontSize: 11,
                          fontWeight: _filtroFaccion == entry.$1
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ),
              ),
            ],
          ]),
        ),
      ),
      if (lista.isEmpty) Expanded(child: _empty(Icons.military_tech_rounded, 'Sin móviles en esta categoría')),
      if (lista.isNotEmpty) Expanded(child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final u = lista[i];
        final rangoActual = u['rango_movil']?.toString();
        final rc = _colorRango(rangoActual);
        final numMovil = _numMovil(u['usuario']?.toString());
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: rc.withValues(alpha: 0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(builder: (context, constraints) {
              final esPC = constraints.maxWidth > 520;

              // ── Info del móvil (avatar + nombre + plan) ──────────────────
              Widget filaInfo({bool conBadges = false}) => Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: numMovil.isNotEmpty ? rc : rc.withValues(alpha: 0.15),
                  child: numMovil.isNotEmpty
                      ? Text(numMovil, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                      : Text(_iniciales(u['nombre']),
                          style: TextStyle(color: rc, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u['nombre'] ?? '—',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Row(children: [
                    Flexible(
                      child: Text('@${u['usuario'] ?? ''}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (u['tipo_plan_movil'] != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: u['tipo_plan_movil'] == 'semanal'
                              ? Colors.purple[700]
                              : u['tipo_plan_movil'] == 'prediario'
                                  ? Colors.orange[700]
                                  : Colors.blue[700],
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          u['tipo_plan_movil'] == 'prediario'
                              ? 'PREDIA'
                              : u['tipo_plan_movil'] == 'semanal'
                                  ? 'SEM'
                                  : 'POSTDÍA',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ]),
                ])),
                // Badges en móvil (en PC van a la columna derecha)
                if (conBadges) ...[
                  if (u['tiene_se'] == true)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF1B5E20), borderRadius: BorderRadius.circular(6)),
                      child: const Text('SE', style: TextStyle(color: Color(0xFF3AF500), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                    ),
                  if (u['tiene_fn'] == true)
                    Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF002DA2), borderRadius: BorderRadius.circular(6)),
                      child: const Text('FN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                    ),
                  if (rangoActual != null && rangoActual.isNotEmpty)
                    _chip(rangoActual, rc),
                ],
              ]);

              // ── Badges + rango (columna derecha en PC) ───────────────────
              final badgesPC = Row(mainAxisSize: MainAxisSize.min, children: [
                if (u['tiene_se'] == true)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF1B5E20), borderRadius: BorderRadius.circular(6)),
                    child: const Text('SE', style: TextStyle(color: Color(0xFF3AF500), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ),
                if (u['tiene_fn'] == true)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF002DA2), borderRadius: BorderRadius.circular(6)),
                    child: const Text('FN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                  ),
                if (rangoActual != null && rangoActual.isNotEmpty)
                  _chip(rangoActual, rc),
              ]);

              // ── Botones de acción ─────────────────────────────────────────
              final botones = Row(mainAxisSize: MainAxisSize.min, children: [
                _botonAccion(Icons.military_tech_rounded, Colors.amber, 'Facción', () => _cambiarFaccionDialog(u)),
                _botonAccion(Icons.credit_card_rounded, Colors.lightBlueAccent, 'Plan', () => _cambiarPlanDialog(u)),
                _botonAccion(Icons.lock_reset_rounded, Colors.white54, 'Clave', () => _cambiarContrasenaDialog(u)),
                _botonAccion(Icons.delete_forever_rounded, Colors.red[300]!, 'Eliminar', () => _eliminarCuentaMovil(u)),
              ]);

              // ── Chips de rangos ───────────────────────────────────────────
              final wrapRangos = Wrap(spacing: 6, runSpacing: 6, children: rangos.map((r) {
                final activo = rangoActual == r;
                final rangoColor = _colorRango(r);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _cambiarRango(u, r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: activo ? rangoColor : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: activo ? rangoColor : rangoColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(r,
                        style: TextStyle(
                          color: activo ? Colors.white : rangoColor.withValues(alpha: 0.85),
                          fontSize: 11, fontWeight: activo ? FontWeight.bold : FontWeight.normal)),
                  ),
                );
              }).toList());

              // ── Layout PC: info+rangos izquierda | badges+botones derecha ─
              if (esPC) {
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    filaInfo(conBadges: false),
                    const SizedBox(height: 10),
                    wrapRangos,
                  ])),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    badgesPC,
                    const SizedBox(height: 8),
                    botones,
                  ]),
                ]);
              }

              // ── Layout móvil: apilado ─────────────────────────────────────
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                filaInfo(conBadges: true),
                const SizedBox(height: 6),
                botones,
                const SizedBox(height: 10),
                wrapRangos,
              ]);
            }),
          ),
        );
      },
    )),
    ]);
  }

  // ── Tab 3: Registros de hoy (se reinicia a medianoche) ───────────────────
  Widget _tabRecientes() {
    final lista = _filtrar(_registros);
    if (lista.isEmpty) return _empty(Icons.person_add_rounded, 'Sin registros nuevos hoy');
    return Column(children: [
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Usuarios que se registraron en los últimos 30 días. '
          '"Activo" significa que ya pueden iniciar sesión.',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
          itemCount: lista.length,
          itemBuilder: (_, i) {
            final u = lista[i];
            final rol = u['rol']?.toString() ?? '';
            final color = _colorRol(rol);
            final activo = u['activo'] as bool? ?? false;
            final suspendido = u['suspendido'] as bool? ?? false;
            final numMovil = rol == 'movil' ? _numMovil(u['usuario']?.toString()) : '';
            final String estado;
            if (suspendido) {
              estado = 'SUSPENDIDO';
            } else if (activo) {
              estado = 'ACTIVO';
            } else {
              estado = 'PENDIENTE';
            }
            final estadoColor = suspendido
                ? Colors.red[400]!
                : activo
                    ? Colors.green[400]!
                    : Colors.orange[400]!;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: numMovil.isNotEmpty ? color : color.withValues(alpha: 0.15),
                  child: numMovil.isNotEmpty
                      ? Text(numMovil, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                      : Text(_iniciales(u['nombre']), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                title: Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((u['usuario'] ?? '').toString().isNotEmpty)
                    Text('@${u['usuario']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Row(children: [
                    _chip(rol.toUpperCase(), color),
                    const SizedBox(width: 6),
                    _chip(estado, estadoColor),
                  ]),
                ]),
                trailing: IconButton(
                  tooltip: 'Cambiar contraseña',
                  icon: const Icon(Icons.lock_reset_rounded, color: Colors.amber, size: 18),
                  onPressed: () => _cambiarContrasenaDialog(u),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── Tab 4: Solicitudes de descanso ────────────────────────────────────────
  Widget _tabDescansos() {
    final pendientes = _solicitudesDescansoList.where((s) => s['estado'] == 'pendiente').toList();
    final historial  = _solicitudesDescansoList.where((s) => s['estado'] != 'pendiente').toList();

    if (_solicitudesDescansoList.isEmpty) {
      return _empty(Icons.beach_access_rounded, 'Sin solicitudes de descanso');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        if (pendientes.isNotEmpty) ...[
          _encabezadoSeccion('⏳ PENDIENTES (${pendientes.length})', const Color(0xFFF59E0B)),
          ...pendientes.map((s) => _cardDescanso(s, esPendiente: true)),
        ],
        if (historial.isNotEmpty) ...[
          _encabezadoSeccion('📋 HISTORIAL', Colors.white24),
          ...historial.map((s) => _cardDescanso(s, esPendiente: false)),
        ],
      ],
    );
  }

  Widget _encabezadoSeccion(String texto, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
    child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
  );

  Widget _cardDescanso(Map<String, dynamic> s, {required bool esPendiente}) {
    final usuario = s['usuarios'] as Map<String, dynamic>?;
    final user    = usuario?['usuario']?.toString() ?? '—';
    final numStr  = RegExp(r'\d+').firstMatch(user)?.group(0);
    final nombre  = numStr != null ? 'Móvil $numStr' : (usuario?['nombre']?.toString() ?? '—');
    final estado  = s['estado']?.toString() ?? '';
    final Color estadoColor = estado == 'aprobado'
        ? const Color(0xFF10B981)
        : estado == 'rechazado'
            ? Colors.red[400]!
            : const Color(0xFFF59E0B);
    final String estadoEmoji = estado == 'aprobado' ? '✅' : estado == 'rechazado' ? '❌' : '⏳';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: estadoColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.2),
              child: Text(_iniciales(nombre), style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('@$user', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: estadoColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text('$estadoEmoji ${estado.toUpperCase()}', style: TextStyle(color: estadoColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.calendar_month, size: 13, color: Colors.white38),
            const SizedBox(width: 4),
            Text('${s['fecha_inicio']} → ${s['fecha_fin']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(width: 8),
            Text('(${s['dias_solicitados']} día(s))', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
          if (s['razon'] != null) ...[
            const SizedBox(height: 4),
            Text(s['razon'].toString(), style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
          ],
          if (estado == 'rechazado' && s['rechazado_motivo'] != null) ...[
            const SizedBox(height: 4),
            Text('Motivo rechazo: ${s['rechazado_motivo']}', style: TextStyle(color: Colors.red[300], fontSize: 11)),
          ],
          if (esPendiente) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[300],
                    side: BorderSide(color: Colors.red[800]!),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _rechazarDescanso(s),
                  child: const Text('RECHAZAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _aprobarDescanso(s),
                  child: const Text('APROBAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  // ── Tab 5: Cuentas eliminadas ──────────────────────────────────────────────
  Widget _tabEliminados() {
    final lista = _filtrar(_eliminados);
    if (_eliminados.isEmpty) {
      return _empty(Icons.delete_sweep_rounded, 'No hay cuentas eliminadas');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) => _cardEliminado(lista[i]),
    );
  }

  Widget _cardEliminado(Map<String, dynamic> u) {
    final nombre       = movilLabel(u);
    final usuario      = u['usuario']?.toString() ?? '—';
    final rol          = u['rol']?.toString() ?? '—';
    final tipoPlan     = u['tipo_plan']?.toString();
    final eliminadoPor = u['eliminado_por']?.toString() ?? 'Desconocido';
    final eliminadoAt  = u['eliminado_at'] != null
        ? DateTime.tryParse(u['eliminado_at'].toString())?.toLocal()
        : null;
    final registradoAt = u['created_at'] != null
        ? DateTime.tryParse(u['created_at'].toString())?.toLocal()
        : null;

    String _fmt(DateTime? dt) {
      if (dt == null) return '—';
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.red.withValues(alpha: 0.15),
              child: Text(_iniciales(nombre),
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombre, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              Text('@$usuario', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _chip(rol.toUpperCase(), _colorRol(rol)),
              if (tipoPlan != null) ...[
                const SizedBox(height: 4),
                _chip(tipoPlan == 'prediario' ? 'PREDIA' : 'SUSCR',
                    tipoPlan == 'prediario' ? Colors.orange[700]! : Colors.green[700]!),
              ],
            ]),
          ]),
          const SizedBox(height: 10),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),
          _filaInfo(Icons.person_off_rounded, 'Eliminado por', eliminadoPor, Colors.redAccent),
          const SizedBox(height: 4),
          _filaInfo(Icons.calendar_today_rounded, 'Fecha eliminación', _fmt(eliminadoAt), Colors.red[300]!),
          const SizedBox(height: 4),
          _filaInfo(Icons.app_registration_rounded, 'Registrado el', _fmt(registradoAt), Colors.white38),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.history_rounded, size: 15),
              label: const Text('VER HISTORIAL DE SERVICIOS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _verHistorialEliminado(u),
            ),
          ),
        ]),
      ),
    );
  }

  // ── TAB WALLET ─────────────────────────────────────────────────────────────
  Widget _tabWallet() {
    final externos = _moviles
        .where((m) =>
            m['tipo_plan_movil']?.toString() == 'prediario' ||
            m['tipo_plan_movil']?.toString() == 'postdia'  ||
            m['tipo_plan_movil']?.toString() == 'semanal')
        .toList();

    // Stats derivadas de la lista local (sin query extra)
    final bloqueados  = externos.where((m) => m['wallet_bloqueado'] == true).toList();
    final conDeuda    = externos.where((m) {
      final plan  = m['tipo_plan_movil']?.toString();
      final saldo = (m['saldo_wallet'] as num?)?.toDouble() ?? 0.0;
      if (plan == 'prediario') return saldo <= 0;
      if (plan == 'postdia')   return saldo < 0;
      return false;
    }).toList();
    final cntPre  = externos.where((m) => m['tipo_plan_movil'] == 'prediario').length;
    final cntPost = externos.where((m) => m['tipo_plan_movil'] == 'postdia').length;
    final cntSem  = externos.where((m) => m['tipo_plan_movil'] == 'semanal').length;

    // Filtro por plan + búsqueda
    var filtrados = _planFiltroWallet.isEmpty
        ? externos
        : externos.where((m) => m['tipo_plan_movil'] == _planFiltroWallet).toList();
    if (_busq.isNotEmpty) {
      final q = _busq.toLowerCase();
      filtrados = filtrados.where((m) =>
          (m['nombre']?.toString().toLowerCase().contains(q) ?? false) ||
          (m['usuario']?.toString().toLowerCase().contains(q) ?? false)).toList();
    }

    return FutureBuilder<List<dynamic>>(
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
        final solicitudes  = snap.hasData ? (snap.data![0] as List? ?? []) : [];
        final cfgMap       = snap.hasData ? snap.data![1] as Map<String, dynamic>? : null;
        final infoRecarga  = cfgMap?['info_recarga_wallet']?.toString() ?? '';
        final movimientos  = snap.hasData ? (snap.data![2] as List? ?? []) : [];

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [

            // ── RESUMEN ────────────────────────────────────────────────────
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
                  // Fila 1: bloqueados + en deuda
                  Row(children: [
                    Expanded(child: _statChip(
                      Icons.lock_rounded,
                      '${bloqueados.length}',
                      'Bloqueados',
                      bloqueados.isEmpty ? Colors.white24 : Colors.redAccent,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _statChip(
                      Icons.trending_down_rounded,
                      '${conDeuda.length}',
                      'Con deuda/sin saldo',
                      conDeuda.isEmpty ? Colors.white24 : Colors.orange,
                    )),
                  ]),
                  const SizedBox(height: 8),
                  // Fila 2: conteo por plan
                  Row(children: [
                    Expanded(child: _statChip(Icons.today_rounded,     '$cntPre',  'Prediario', const Color(0xFF818CF8))),
                    const SizedBox(width: 6),
                    Expanded(child: _statChip(Icons.event_rounded,     '$cntPost', 'Postdia',   Colors.teal)),
                    const SizedBox(width: 6),
                    Expanded(child: _statChip(Icons.date_range_rounded, '$cntSem',  'Semanal',   Colors.orange)),
                  ]),
                ]),
              ),
            ),

            // ── FILTROS POR PLAN ───────────────────────────────────────────
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
                      onSelected: (_) =>
                          setState(() => _planFiltroWallet = entry.$1),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),

            // ── Configurar datos de transferencia ──────────────────────────
            _encabezadoSeccion('DATOS DE TRANSFERENCIA', Colors.white54),
            _cardInfoRecarga(infoRecarga),
            const SizedBox(height: 8),

            // ── Solicitudes pendientes — separadas por tipo ────────────────
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

            // ── Movimientos recientes ──────────────────────────────────────
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
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12,
                                fontWeight: FontWeight.bold)),
                        Text(m['concepto']?.toString() ?? tipo,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    )),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(
                        monto == 0 ? '—' : '${monto >= 0 ? '+' : ''}\$${monto.abs().toStringAsFixed(0)}',
                        style: TextStyle(
                            color: monto == 0 ? Colors.white38 : color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(fechaStr,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 9)),
                    ]),
                  ]),
                );
              }),
              const SizedBox(height: 8),
            ],

            // ── Saldos de móviles externos ─────────────────────────────────
            _encabezadoSeccion('MÓVILES EXTERNOS', const Color(0xFF818CF8)),
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
    );
  }

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
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Text(etiqueta,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 9),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          )),
        ]),
      );

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
                    if (esSemanal) {
                      // Pago semanal: desbloquear + registrar movimiento
                      await _db.from('usuarios').update({
                        'wallet_bloqueado': false,
                      }).eq('id', s['movil_id']);
                      await _db.from('wallet_movimientos').insert({
                        'movil_id': s['movil_id'],
                        'tipo': 'pago_semanal',
                        'monto': monto,
                        'concepto': 'Pago semanal aprobado — billetera desbloqueada',
                        'registrado_por': 'central',
                      });
                    } else {
                      // Recarga normal: acreditar saldo
                      await _db.from('wallet_movimientos').insert({
                        'movil_id': s['movil_id'],
                        'tipo': 'recarga',
                        'monto': monto,
                        'concepto': 'Recarga aprobada',
                        'registrado_por': 'central',
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
                      .select('tipo, monto, concepto, created_at, registrado_por')
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
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Icon(
                              tipo == 'recarga' ? Icons.add_circle_outline
                                  : tipo == 'comision' ? Icons.remove_circle_outline
                                  : tipo == 'pago_postdia' ? Icons.check_circle_outline
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
                        );
                      },
                    );
                  },
                ),
              ),
              if (!soloLectura) ...[
                const Divider(color: Colors.white12, height: 20),
                // ── Nuevo movimiento ──────────────────────────────────
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
                  // Positivo para recarga/pago, negativo para ajuste manual de descuento
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
  // ───────────────────────────────────────────────────────────────────────────

  Widget _filaInfo(IconData icon, String label, String valor, Color color) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      Expanded(child: Text(valor, style: const TextStyle(color: Colors.white70, fontSize: 11))),
    ],
  );

  Future<void> _verHistorialEliminado(Map<String, dynamic> u) async {
    final uid    = u['id'];
    final nombre = u['nombre']?.toString() ?? '—';
    final rol    = u['rol']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (_) => _DialogHistorialEliminado(uid: uid, nombre: nombre, rol: rol, db: _db),
    );
  }

  Future<void> _aprobarDescanso(Map<String, dynamic> s) async {
    try {
      await _db.from('solicitudes_descanso').update({
        'estado':      'aprobado',
        'aprobado_por': 'central',
        'aprobado_at':  DateTime.now().toUtc().toIso8601String(),
      }).eq('id', s['id']);

      // Notificar al móvil
      await _db.from('notificaciones_push_pendientes').insert({
        'destinatario_id': s['movil_id'],
        'titulo': '✅ Descanso aprobado',
        'cuerpo': 'Tu solicitud de descanso del ${s['fecha_inicio']} al ${s['fecha_fin']} fue aprobada.',
        'tipo': 'descanso_aprobado',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Descanso aprobado'), backgroundColor: Colors.green),
        );
        _cargar();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _rechazarDescanso(Map<String, dynamic> s) async {
    final motivoCtrl = TextEditingController();

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rechazar solicitud', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: motivoCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Motivo del rechazo (opcional)',
            labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('RECHAZAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    try {
      await _db.from('solicitudes_descanso').update({
        'estado':            'rechazado',
        'rechazado_motivo':  motivoCtrl.text.trim().isEmpty ? null : motivoCtrl.text.trim(),
      }).eq('id', s['id']);

      // Notificar al móvil
      await _db.from('notificaciones_push_pendientes').insert({
        'destinatario_id': s['movil_id'],
        'titulo': '❌ Descanso rechazado',
        'cuerpo': 'Tu solicitud del ${s['fecha_inicio']} al ${s['fecha_fin']} fue rechazada.${motivoCtrl.text.trim().isNotEmpty ? ' Motivo: ${motivoCtrl.text.trim()}' : ''}',
        'tipo': 'descanso_rechazado',
      });

      motivoCtrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Solicitud rechazada'), backgroundColor: Colors.red),
        );
        _cargar();
      }
    } catch (e) {
      motivoCtrl.dispose();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Tab 7: Locales activos + toggle activar/desactivar ────────────────────
  Widget _tabLocales() {
    final lista = _filtrar(_locales);
    if (lista.isEmpty) return _empty(Icons.store_rounded, 'Sin locales activos');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final l = lista[i];
        final activo = l['activo'] as bool? ?? true;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: activo
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                  : Colors.white12,
            ),
          ),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  (activo ? const Color(0xFFF59E0B) : Colors.grey).withValues(alpha: 0.1),
                  Colors.transparent,
                ]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: (activo ? const Color(0xFFF59E0B) : Colors.grey).withValues(alpha: 0.2),
                  child: Text(
                    _iniciales(l['nombre']),
                    style: TextStyle(
                      color: activo ? const Color(0xFFF59E0B) : Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    l['nombre'] ?? '—',
                    style: TextStyle(
                      color: activo ? Colors.white : Colors.white38,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((l['tipo_negocio'] ?? '').toString().isNotEmpty)
                    Text(
                      l['tipo_negocio'].toString(),
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ])),
                // Toggle activar/desactivar
                Column(children: [
                  Switch(
                    value: activo,
                    activeColor: const Color(0xFFF59E0B),
                    inactiveThumbColor: Colors.grey,
                    onChanged: (val) async {
                      final confirmar = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A1A),
                          title: Text(
                            val ? '¿Activar local?' : '¿Desactivar local?',
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                          content: Text(
                            val
                                ? '${l['nombre']} podrá operar nuevamente.'
                                : '${l['nombre']} no podrá acceder hasta reactivarlo.',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('Cancelar', style: TextStyle(color: Colors.white38)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: val ? Colors.green[700] : Colors.red[800],
                              ),
                              onPressed: () => Navigator.pop(d, true),
                              child: Text(
                                val ? 'Activar' : 'Desactivar',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmar != true || !mounted) return;
                      try {
                        await _db.from('usuarios').update({'activo': val}).eq('id', l['id']);
                        setState(() => l['activo'] = val);
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                        );
                      }
                    },
                  ),
                  Text(
                    activo ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                      color: activo ? const Color(0xFFF59E0B) : Colors.white38,
                      fontSize: 9,
                    ),
                  ),
                ]),
              ]),
            ),
            // Info rows
            if ((l['telefono'] ?? '').toString().isNotEmpty ||
                (l['direccion_local'] ?? '').toString().isNotEmpty ||
                (l['zona_cobertura'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                child: Column(children: [
                  if ((l['telefono'] ?? '').toString().isNotEmpty)
                    _infoR(Icons.phone_outlined, l['telefono'].toString(), Colors.white38),
                  if ((l['direccion_local'] ?? '').toString().isNotEmpty)
                    _infoR(Icons.location_on_outlined, l['direccion_local'].toString(), Colors.white38),
                  if ((l['zona_cobertura'] ?? '').toString().isNotEmpty)
                    _infoR(Icons.map_outlined, 'Zona: ${l['zona_cobertura']}', Colors.white38),
                  if ((l['correo'] ?? '').toString().isNotEmpty)
                    _infoR(Icons.email_outlined, l['correo'].toString(), Colors.white38),
                ]),
              ),
          ]),
        );
      },
    );
  }

  // ── Tab 8: Clientes ────────────────────────────────────────────────────────
  Widget _tabClientes() {
    final lista = _filtrar(_clientes);
    if (lista.isEmpty) return _empty(Icons.people_alt_rounded, 'Sin clientes registrados');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final c = lista[i];
        final fecha = c['created_at'] != null
            ? DateTime.tryParse(c['created_at'].toString())?.toLocal()
            : null;
        final fechaStr = fecha != null
            ? '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}'
            : '—';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.2)),
          ),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  const Color(0xFF22C55E).withValues(alpha: 0.08),
                  Colors.transparent,
                ]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: const Color(0xFF22C55E).withValues(alpha: 0.18),
                  child: Text(
                    _iniciales(c['nombre']),
                    style: const TextStyle(color: Color(0xFF22C55E), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    c['nombre'] ?? '—',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${c['usuario'] ?? '—'}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ])),
                Text(
                  fechaStr,
                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ]),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
              child: Column(children: [
                if ((c['telefono'] ?? '').toString().isNotEmpty)
                  _infoR(Icons.phone_outlined, c['telefono'].toString(), Colors.white38),
                if ((c['correo'] ?? '').toString().isNotEmpty)
                  _infoR(Icons.email_outlined, c['correo'].toString(), Colors.white38),
              ]),
            ),
          ]),
        );
      },
    );
  }

}


// ── Diálogo: historial de servicios de cuenta eliminada ─────────────────────
class _DialogHistorialEliminado extends StatefulWidget {
  final dynamic uid;
  final String nombre;
  final String rol;
  final dynamic db;
  const _DialogHistorialEliminado({required this.uid, required this.nombre, required this.rol, required this.db});
  @override
  State<_DialogHistorialEliminado> createState() => _DialogHistorialEliminadoState();
}

class _DialogHistorialEliminadoState extends State<_DialogHistorialEliminado> {
  List<Map<String, dynamic>> _servicios = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    try {
      // Para móviles: servicios donde fue el conductor
      // Para clientes: servicios donde fue el solicitante
      // Para locales: servicios donde fue la sede
      final db = Supabase.instance.client;
      List<dynamic> resp = [];

      if (widget.rol == 'movil') {
        resp = await db.from('servicios')
            .select('id, estado, origen, destino, tarifa, created_at, tipo_servicio')
            .eq('movil_id', widget.uid)
            .order('created_at', ascending: false)
            .limit(100);
      } else if (widget.rol == 'cliente') {
        resp = await db.from('servicios')
            .select('id, estado, origen, destino, tarifa, created_at, tipo_servicio')
            .eq('cliente_id', widget.uid)
            .order('created_at', ascending: false)
            .limit(100);
      } else {
        resp = await db.from('servicios')
            .select('id, estado, origen, destino, tarifa, created_at, tipo_servicio')
            .eq('local_id', widget.uid)
            .order('created_at', ascending: false)
            .limit(100);
      }

      if (mounted) setState(() { _servicios = List<Map<String, dynamic>>.from(resp); _cargando = false; });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _servicios.fold<double>(0, (s, e) => s + ((e['tarifa'] as num?)?.toDouble() ?? 0));
    final completados = _servicios.where((s) => s['estado'] == 'completado').length;

    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('📋 ${widget.nombre}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        Text('Historial de servicios', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]),
      content: SizedBox(
        width: 360,
        height: 420,
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: Color(0xff3AF500)))
            : _servicios.isEmpty
                ? const Center(child: Text('Sin servicios registrados', style: TextStyle(color: Colors.white38)))
                : Column(children: [
                    // Resumen
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        _resumenItem('${_servicios.length}', 'Total'),
                        _resumenItem('$completados', 'Completados'),
                        _resumenItem('\$${total.toStringAsFixed(0)}', 'Facturado'),
                      ]),
                    ),
                    // Lista
                    Expanded(child: ListView.builder(
                      itemCount: _servicios.length,
                      itemBuilder: (_, i) {
                        final s = _servicios[i];
                        final estado = s['estado']?.toString() ?? '';
                        final Color ec = estado == 'completado'
                            ? Colors.green
                            : estado == 'cancelado'
                                ? Colors.red
                                : Colors.orange;
                        final fecha = s['created_at'] != null
                            ? DateTime.tryParse(s['created_at'].toString())?.toLocal()
                            : null;
                        final fechaStr = fecha != null
                            ? '${fecha.day.toString().padLeft(2,'0')}/${fecha.month.toString().padLeft(2,'0')}/${fecha.year}'
                            : '—';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ec.withValues(alpha: 0.2)),
                          ),
                          child: Row(children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s['origen']?.toString() ?? '—', style: const TextStyle(color: Colors.white70, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text('→ ${s['destino']?.toString() ?? '—'}', style: const TextStyle(color: Colors.white38, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(fechaStr, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                            ])),
                            const SizedBox(width: 8),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: ec.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                child: Text(estado.toUpperCase(), style: TextStyle(color: ec, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 3),
                              Text('\$${(s['tarifa'] as num?)?.toStringAsFixed(0) ?? '0'}', style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                            ]),
                          ]),
                        );
                      },
                    )),
                  ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CERRAR', style: TextStyle(color: Color(0xff3AF500), fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _resumenItem(String val, String label) => Column(children: [
    Text(val, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
    Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
  ]);
}
