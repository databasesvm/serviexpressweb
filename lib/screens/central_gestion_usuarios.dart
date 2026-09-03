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
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this, initialIndex: widget.tabInicial);
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
      final hace30 = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      final results = await Future.wait([
        _db.from('usuarios')
            .select('id, nombre, usuario, correo, telefono, direccion_local, tipo_negocio, zona_cobertura, created_at')
            .eq('rol', 'local').eq('estado_local', 'pendiente').order('created_at'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, telefono, correo, activo, suspendido, created_at, numero_movil, tipo_plan_movil, doc_perfil_url, doc_cedula_url, doc_licencia_url, doc_soat_url')
            .eq('activo', false)
            .or('suspendido.is.null,suspendido.eq.false')
            .or('eliminado.is.null,eliminado.eq.false')
            .order('created_at'),
        _db.from('usuarios')
            .select('id, nombre, usuario, rango_movil, puntuacion, activo, tipo_plan_movil, numero_movil')
            .eq('rol', 'movil').order('usuario', ascending: true),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, estado_local, activo, suspendido, created_at')
            .gte('created_at', hace30).order('created_at', ascending: false),
        _db.from('solicitudes_descanso')
            .select('id, movil_id, fecha_inicio, fecha_fin, dias_solicitados, razon, estado, aprobado_por, rechazado_motivo, created_at, usuarios(nombre, usuario)')
            .order('created_at', ascending: false)
            .limit(50),
        _db.from('usuarios')
            .select('id, nombre, usuario, rol, correo, telefono, tipo_plan_movil, rango_movil, numero_movil, eliminado_at, eliminado_por, created_at')
            .eq('eliminado', true)
            .order('eliminado_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _solicitudes              = List<Map<String, dynamic>>.from(results[0]);
        _activaciones             = List<Map<String, dynamic>>.from(results[1]);
        _moviles                  = List<Map<String, dynamic>>.from(results[2]);
        _registros                = List<Map<String, dynamic>>.from(results[3]);
        _solicitudesDescansoList  = List<Map<String, dynamic>>.from(results[4]);
        _eliminados               = List<Map<String, dynamic>>.from(results[5]);
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

    // ── Activar ──────────────────────────────────────────────────────────
    await _db.from('usuarios').update({'activo': true}).eq('id', u['id']);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ $identificador activado'), backgroundColor: Colors.green[700]),
    );
    _cargar();
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

  // ── Dialog: Ver registro completo del usuario ────────────────────────────
  void _verRegistroDialog(Map<String, dynamic> u) {
    final plan = u['tipo_plan_movil']?.toString() ?? '';
    final numMovil = u['numero_movil']?.toString() ?? '';
    Widget _docImg(String? url, String label) {
      if (url == null || url.isEmpty) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            const Icon(Icons.image_not_supported_rounded, color: Colors.white24, size: 16),
            const SizedBox(width: 6),
            Text('$label: no subido', style: const TextStyle(color: Colors.white30, fontSize: 12)),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(url, height: 160, width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 60, color: Colors.white10,
                child: const Center(child: Text('No se pudo cargar', style: TextStyle(color: Colors.white30, fontSize: 11))),
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
            Row(children: [
              const Icon(Icons.person_search_rounded, color: Colors.lightBlueAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Registro de ${u['nombre'] ?? '—'}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                  onPressed: () => Navigator.pop(ctx), padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
            ]),
            const Divider(color: Colors.white12, height: 20),
            // ── Datos básicos ──
            _infoRow(Icons.badge_rounded, 'Usuario', '@${u['usuario'] ?? '—'}'),
            _infoRow(Icons.phone_rounded, 'Teléfono', u['telefono']?.toString() ?? '—'),
            _infoRow(Icons.email_rounded, 'Correo', u['correo']?.toString() ?? '—'),
            if (numMovil.isNotEmpty)
              _infoRow(Icons.tag_rounded, 'Número solicitado', '#$numMovil'),
            if (plan.isNotEmpty)
              _infoRow(Icons.work_rounded, 'Plan', plan.toUpperCase()),
            _infoRow(Icons.people_rounded, 'Rol', u['rol']?.toString().toUpperCase() ?? '—'),
            const SizedBox(height: 12),
            // ── Documentos ──
            const Text('Documentación', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _docImg(u['doc_perfil_url']?.toString(), '📸 Selfie de verificación'),
            _docImg(u['doc_cedula_url']?.toString(), '🪪 Cédula'),
            _docImg(u['doc_licencia_url']?.toString(), '🚗 Licencia de conducción'),
            _docImg(u['doc_soat_url']?.toString(), '🛡️ SOAT'),
            const SizedBox(height: 4),
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
        final numMovilStr = numMovilInt?.toString() ?? '';
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
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: numMovilStr.isNotEmpty ? color : color.withValues(alpha: 0.15),
              child: numMovilStr.isNotEmpty
                  ? Text(numMovilStr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10))
                  : Text(_iniciales(u['nombre']), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            title: Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((u['usuario'] ?? '').toString().isNotEmpty)
                Text('@${u['usuario']}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              if (numMovilStr.isNotEmpty)
                Text('Número solicitado: #$numMovilStr${planLabel != null ? ' · $planLabel' : ''}',
                    style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 11, fontWeight: FontWeight.w600)),
              _chip(rol.toUpperCase(), color),
            ]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Ver registro',
                icon: const Icon(Icons.person_search_rounded, color: Colors.lightBlueAccent, size: 20),
                onPressed: () => _verRegistroDialog(u),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: 'Cambiar contraseña',
                icon: const Icon(Icons.lock_reset_rounded, color: Colors.amber, size: 18),
                onPressed: () => _cambiarContrasenaDialog(u),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _activarUsuario(u),
                child: const Text('ACTIVAR'),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── Tab 2: Ascensos / gestión de rangos de móviles ───────────────────────
  Widget _tabAscensos() {
    final lista = _filtrar(_moviles);
    if (lista.isEmpty) return _empty(Icons.military_tech_rounded, 'Sin móviles registrados');
    const rangos = ['NOVATO', 'PRO', 'ÉLITE', 'LEYENDA', 'MASTER'];
    return ListView.builder(
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
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
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
                  Text(u['nombre'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Row(children: [
                    Text('@${u['usuario'] ?? ''}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    if (u['tipo_plan'] != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: u['tipo_plan'] == 'prediario' ? Colors.orange[700] : Colors.green[700],
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          u['tipo_plan'] == 'prediario' ? 'PREDIA' : 'SUSCR',
                          style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ]),
                ])),
                IconButton(
                  tooltip: 'Cambiar contraseña',
                  icon: const Icon(Icons.lock_reset_rounded, color: Colors.amber, size: 16),
                  onPressed: () => _cambiarContrasenaDialog(u),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  tooltip: 'Eliminar cuenta',
                  icon: Icon(Icons.delete_forever_rounded, color: Colors.red[300], size: 16),
                  onPressed: () => _eliminarCuentaMovil(u),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                if (rangoActual != null && rangoActual.isNotEmpty)
                  _chip(rangoActual, rc),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: rangos.map((r) {
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
              }).toList()),
            ]),
          ),
        );
      },
    );
  }

  // ── Tab 3: Registros recientes (últimos 30 días) ──────────────────────────
  Widget _tabRecientes() {
    final lista = _filtrar(_registros);
    if (lista.isEmpty) return _empty(Icons.person_add_rounded, 'Sin registros en los últimos 30 días');
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
