part of 'movil_screen.dart';
// Widgets auxiliares de MovilScreen

class _CircularOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.38;
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ===========================================================================
// WIDGET: BotonPresionSostenida (hold-to-confirm button)
// ===========================================================================
class BotonPresionSostenida extends StatefulWidget {
  final String texto;
  final Color colorBase;
  final Color colorTexto;
  final VoidCallback onCompletado;

  const BotonPresionSostenida({
    super.key,
    required this.texto,
    required this.colorBase,
    required this.colorTexto,
    required this.onCompletado,
  });

  @override
  State<BotonPresionSostenida> createState() => _BotonPresionSostenidaState();
}

class _BotonPresionSostenidaState extends State<BotonPresionSostenida>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _presionado = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _presionado) {
          widget.onCompletado();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) {
        setState(() => _presionado = true);
        _ctrl.forward(from: 0);
      },
      onLongPressEnd: (_) {
        setState(() => _presionado = false);
        if (!_ctrl.isCompleted) _ctrl.reverse();
      },
      onLongPressCancel: () {
        setState(() => _presionado = false);
        _ctrl.reverse();
      },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: widget.colorBase,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: _ctrl.value,
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                Center(
                  child: Text(
                    _presionado
                        ? 'Mantén presionado...'
                        : widget.texto,
                    style: TextStyle(
                      color: widget.colorTexto,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =========================================// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN TÁCTICO DE ACCIÓN — usado en la fila de acciones del servicio activo
// (WhatsApp, Chat, Central). Muestra icono + texto con color de marca,
// fondo suave y badge de alarma opcional.
// ─────────────────────────────────────────────────────────────────────────────
class BotonTacticoAccion extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color colorBase;
  final Color colorFondo;
  final bool tieneAlarma;
  final VoidCallback onTap;

  const BotonTacticoAccion({
    super.key,
    required this.icono,
    required this.texto,
    required this.colorBase,
    required this.colorFondo,
    required this.onTap,
    this.tieneAlarma = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colorFondo,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icono, color: colorBase, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      texto,
                      style: TextStyle(
                        color: colorBase,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (tieneAlarma)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
