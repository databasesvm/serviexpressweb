part of 'central_screen.dart';
// // Panel de precios por local

class _PanelPreciosLocal extends StatefulWidget {
  final String localId;
  final String localNombre;
  final VoidCallback onBack;

  const _PanelPreciosLocal({
    required this.localId,
    required this.localNombre,
    required this.onBack,
  });

  @override
  State<_PanelPreciosLocal> createState() => _PanelPreciosLocalState();
}

class _PanelPreciosLocalState extends State<_PanelPreciosLocal> {
  List<Map<String, dynamic>> _tarifas = [];
  List<Map<String, dynamic>> _sectores = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final tarifas = await Supabase.instance.client
          .from('tarifas_locales')
          .select('id, tarifa, sector_id, sectores(nombre, municipio)')
          .eq('local_id', widget.localId)
          .not('sector_id', 'is', null)
          .order('tarifa', ascending: true);

      final sectores = await Supabase.instance.client
          .from('sectores')
          .select('id, nombre, municipio')
          .eq('activo', true)
          .order('nombre');

      if (mounted) {
        setState(() {
          _tarifas = List<Map<String, dynamic>>.from(tarifas);
          _sectores = List<Map<String, dynamic>>.from(sectores);
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _agregarOEditar({Map<String, dynamic>? tarifaExistente}) async {
    int? sectorSelId = tarifaExistente?['sector_id'];
    final tarifaCtrl = TextEditingController(
      text: tarifaExistente != null ? '${tarifaExistente['tarifa']}' : '',
    );

    // Sectores ya configurados por este local (para excluir en nuevo)
    final configurados = _tarifas
        .where((t) => t['id'] != tarifaExistente?['id'])
        .map((t) => t['sector_id'] as int?)
        .toSet();

    final sectoresDisponibles = tarifaExistente != null
        ? _sectores
        : _sectores.where((s) => !configurados.contains(s['id'])).toList();

    if (sectoresDisponibles.isEmpty && tarifaExistente == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos los sectores ya tienen tarifa configurada.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(
            tarifaExistente != null ? 'Editar Tarifa' : 'Nueva Tarifa',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: sectorSelId,
                decoration: const InputDecoration(
                  labelText: 'Sector / Barrio',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: sectoresDisponibles
                    .map((s) => DropdownMenuItem<int>(
                          value: s['id'] as int,
                          child: Text('${s['nombre']} (${s['municipio']})'),
                        ))
                    .toList(),
                onChanged: (v) => setDlg(() => sectorSelId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tarifaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tarifa (\$)',
                  isDense: true,
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                if (sectorSelId == null) return;
                final tarifa = double.tryParse(tarifaCtrl.text.trim());
                if (tarifa == null || tarifa < 0) return;
                try {
                  await Supabase.instance.client
                      .from('tarifas_locales')
                      .upsert({
                    'local_id': widget.localId,
                    'local_nombre': widget.localNombre,
                    'sector_id': sectorSelId,
                    'tarifa': tarifa,
                  }, onConflict: 'local_id, sector_id');
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _cargar();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(
                tarifaExistente != null ? 'GUARDAR' : 'AGREGAR',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
    tarifaCtrl.dispose();
  }

  Future<void> _eliminar(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar tarifa?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCELAR')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ELIMINAR',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client
          .from('tarifas_locales')
          .delete()
          .eq('id', id);
      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
              Expanded(
                child: Text(
                  widget.localNombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: Color(0xff3AF500)),
                tooltip: 'Agregar tarifa',
                onPressed: () => _agregarOEditar(),
              ),
            ],
          ),
        ),
        // Lista
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.black))
              : _tarifas.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.price_change_outlined,
                              size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          Text(
                            'Sin tarifas configuradas',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black),
                            onPressed: () => _agregarOEditar(),
                            icon: const Icon(Icons.add, color: Colors.white),
                            label: const Text('Agregar primera tarifa',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _tarifas.length,
                      itemBuilder: (context, i) {
                        final t = _tarifas[i];
                        final sector = t['sectores'] as Map<String, dynamic>?;
                        final nombre = sector?['nombre'] ?? '—';
                        final municipio = sector?['municipio'] ?? '';
                        final tarifa = t['tarifa'];
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey[200]!),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '\$${tarifa?.toStringAsFixed(0) ?? '0'}',
                                style: TextStyle(
                                  color: Colors.green[800],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            title: Text(
                              nombre,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: municipio.isNotEmpty
                                ? Text(municipio,
                                    style: const TextStyle(fontSize: 12))
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blue, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () =>
                                      _agregarOEditar(tarifaExistente: t),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () => _eliminar(t['id']),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

