// lib/utils/widgets_compartidos.dart
//
// WIDGETS Y FORMATEADORES COMPARTIDOS
// =====================================
// Antes: PulsingWidget y CurrencyInputFormatter estaban duplicados
// al final de central_screen.dart y local_screen.dart.
// Si se corregía un bug en uno, el otro quedaba desactualizado.
//
// Ahora: definición única aquí. Ambas pantallas importan este archivo.
// Cualquier mejora futura aplica automáticamente en toda la app.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =========================================================================
// FORMATEADOR DE MONEDA UNIVERSAL — $X.XXX (punto como separador de miles)
// =========================================================================
// Uso: fmtPeso(servicio['tarifa'])          → '$8.000'
//      fmtPeso(0, mostrarCero: true)   → '$0'
//      fmtPeso(null)                   → 'SIN TARIFA'
String fmtPeso(dynamic monto, {bool mostrarCero = false}) {
  if (monto == null || monto == 0 || monto == 0.0) {
    return mostrarCero ? '\$0' : 'SIN TARIFA';
  }
  String texto = (monto as num).toInt().toString();
  String resultado = '';
  int contador = 0;
  for (int i = texto.length - 1; i >= 0; i--) {
    resultado = texto[i] + resultado;
    contador++;
    if (contador == 3 && i > 0) {
      resultado = '.$resultado';
      contador = 0;
    }
  }
  return '\$$resultado';
}

// =========================================================================
// PULSING PANICO BUTTON — Latido de corazón + borde/glow animado
// Úsalo cuando un botón de pánico o convocatoria está ACTIVO.
// Parámetros: color = color del glow (rojo para pánico, naranja para convocatoria)
// =========================================================================
class PulsingPanicoButton extends StatefulWidget {
  final Widget child;
  final Color color;
  const PulsingPanicoButton({
    super.key,
    required this.child,
    required this.color,
  });

  @override
  State<PulsingPanicoButton> createState() => _PulsingPanicoButtonState();
}

class _PulsingPanicoButtonState extends State<PulsingPanicoButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    // Ciclo de 1100ms: dos pulsos rápidos + pausa
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    // Escala: pulso1 sube/baja, pulso2 sube/baja más suave, luego pausa
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.20)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.20, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.10)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.10, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0), // pausa
        weight: 56,
      ),
    ]).animate(_ctrl);

    // Glow: sigue el ritmo de los pulsos
    _glow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.1)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 12,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.1, end: 0.7)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.7, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 56,
      ),
    ]).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.scale(
        scale: _scale.value,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: widget.color.withValues(alpha: _glow.value),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: _glow.value * 0.65),
                blurRadius: 14 * _glow.value,
                spreadRadius: 3 * _glow.value,
              ),
            ],
          ),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// =========================================================================
// FADE SLIDE IN — Aparece con fade + deslizamiento desde abajo
// Úsalo con ValueKey(id) en items de lista para animar entradas/salidas.
// =========================================================================
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Offset beginOffset;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
    this.beginOffset = const Offset(0, 0.12),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: widget.beginOffset, end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// =========================================================================
// PULSING WIDGET — Animación de escala para alertas visuales
// =========================================================================
class PulsingWidget extends StatefulWidget {
  final Widget child;
  const PulsingWidget({super.key, required this.child});

  @override
  State<PulsingWidget> createState() => _PulsingWidgetState();
}

class _PulsingWidgetState extends State<PulsingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _animation, child: widget.child);
  }
}

// =========================================================================
// CURRENCY INPUT FORMATTER — Formatea números como moneda en tiempo real
// Ejemplo: 15000 → $15.000
// =========================================================================
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Extraemos dígitos de ambos valores
    final String oldDigits = oldValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String newDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Campo vacío
    if (newDigits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Si el usuario BORRÓ un carácter no-dígito (ej. el punto separador o el $),
    // forzamos la eliminación del último dígito significativo para que
    // cada backspace siempre quite exactamente un dígito de la cifra.
    String digitsToFormat = newDigits;
    if (newValue.text.length < oldValue.text.length && newDigits == oldDigits) {
      // Se borró un separador — quitamos el último dígito
      if (digitsToFormat.isNotEmpty) {
        digitsToFormat = digitsToFormat.substring(0, digitsToFormat.length - 1);
      }
      if (digitsToFormat.isEmpty) {
        return const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );
      }
    }

    // Formateamos con punto de miles
    String result = '';
    int count = 0;
    for (int i = digitsToFormat.length - 1; i >= 0; i--) {
      result = digitsToFormat[i] + result;
      count++;
      if (count == 3 && i > 0) {
        result = '.$result';
        count = 0;
      }
    }
    result = '\$$result';

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
