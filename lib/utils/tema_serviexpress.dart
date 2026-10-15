// ═══════════════════════════════════════════════════════════════════════════
// KIT DE DISEÑO SERVIEXPRESS (todo menos FN)
// Fondo negro + tarjetas claras redondeadas + un color por tipo de servicio.
// Cambiar aquí un color, radio o tamaño cambia toda la app.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'alta_demanda.dart';

// ── Colores base ────────────────────────────────────────────────────────────
const Color kFondoSE = Color(0xFF0D0D0D);
const Color kVerdeSE = Color(0xFF3AF500); // verde de la marca
const Color kVerdeOscuroSE = Color(0xFF1E8E00); // verde legible sobre blanco
const Color kCampoSE = Color(0xFFF3F4F6); // fondo de los campos
const Color kAvisoSE = Color(0xFFFFF7E6); // fondo de avisos suaves
const double kRadioTarjetaSE = 18;
const double kRadioCampoSE = 12;
const double kAnchoMaxSE = 560; // ancho máximo del contenido en PC

/// Texto legible encima de un color (negro sobre verde, blanco sobre azul…)
Color sobreColorSE(Color c) =>
    ThemeData.estimateBrightnessForColor(c) == Brightness.dark ? Colors.white : Colors.black;

/// ¿Pantalla angosta? (celulares pequeños) → márgenes compactos
bool angostoSE(BuildContext context) => MediaQuery.of(context).size.width < 380;
double margenSE(BuildContext context) => angostoSE(context) ? 10 : 16;

// ── Un color por tipo de servicio ───────────────────────────────────────────
class EstiloServicio {
  final Color color;
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final String textoBoton;
  final String nombreCorto; // para mosaicos y etiquetas
  const EstiloServicio({
    required this.color,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.textoBoton,
    required this.nombreCorto,
  });

  Color get sobreColor => sobreColorSE(color);

  /// Color del ícono sobre blanco (el verde de la marca es muy claro)
  Color get colorIcono => color == kVerdeSE ? kVerdeOscuroSE : color;

  static const mototaxi = EstiloServicio(
    color: kVerdeSE,
    icono: Icons.two_wheeler,
    titulo: 'Pedir Mototaxi',
    subtitulo: 'Te recogemos donde estés',
    textoBoton: 'PEDIR MOTOTAXI',
    nombreCorto: 'Mototaxi',
  );
  static const paqueteria = EstiloServicio(
    color: Color(0xFF2F80ED),
    icono: Icons.inventory_2,
    titulo: 'Enviar un paquete',
    subtitulo: 'Lo recogemos y lo entregamos',
    textoBoton: 'SOLICITAR ENVÍO',
    nombreCorto: 'Paquete',
  );
  static const comida = EstiloServicio(
    color: Color(0xFFFF8A00),
    icono: Icons.restaurant,
    titulo: 'Pedir comida',
    subtitulo: 'Te la traemos a la puerta',
    textoBoton: 'PEDIR COMIDA',
    nombreCorto: 'Comida',
  );
  static const compras = EstiloServicio(
    color: Color(0xFF9B51E0),
    icono: Icons.shopping_cart,
    titulo: 'Compras y mandados',
    subtitulo: 'Compramos por ti y te lo llevamos',
    textoBoton: 'SOLICITAR COMPRA',
    nombreCorto: 'Compras',
  );

  /// Estilo según el tipo_servicio guardado en la BD (para tarjetas y
  /// etiquetas en cliente, local, móvil y central).
  static EstiloServicio deTipo(String? tipo) {
    final t = (tipo ?? '').toUpperCase();
    if (t.contains('MOTO')) return mototaxi;
    if (t.contains('COMIDA') || t.contains('RECOGIDA')) return comida;
    if (t.contains('COMPRA')) return compras;
    return paqueteria; // PAQUETERÍA, DOMICILIO, PUNTO A PUNTO…
  }
}

// ── Tema de campos (gris claro sin borde, foco del color del servicio) ──────
ThemeData temaFormularioSE(BuildContext context, Color acento) {
  final base = Theme.of(context);
  OutlineInputBorder borde(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadioCampoSE),
        borderSide: w == 0 ? BorderSide.none : BorderSide(color: c, width: w),
      );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(primary: acento),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCampoSE,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: borde(Colors.transparent, 0),
      enabledBorder: borde(Colors.transparent, 0),
      focusedBorder: borde(acento == kVerdeSE ? kVerdeOscuroSE : acento, 2),
      errorBorder: borde(Colors.red, 1.2),
      focusedErrorBorder: borde(Colors.red, 2),
      labelStyle: const TextStyle(color: Colors.black54, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
      helperStyle: const TextStyle(color: Colors.black45, fontSize: 11),
      helperMaxLines: 2,
      errorMaxLines: 2,
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: acento == kVerdeSE ? kVerdeOscuroSE : acento),
  );
}

// ── Contenedor responsive: centra y limita el ancho en PC ───────────────────
class ContenidoSE extends StatelessWidget {
  final Widget child;
  final double anchoMax;
  const ContenidoSE({super.key, required this.child, this.anchoMax = kAnchoMaxSE});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: anchoMax),
          child: child,
        ),
      );
}

// ── Encabezado: ícono grande + título + frase ───────────────────────────────
class EncabezadoSE extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final Widget? accion; // opcional a la derecha
  const EncabezadoSE({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    this.subtitulo,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    final compacto = angostoSE(context);
    final double lado = compacto ? 52 : 60;
    return Row(children: [
      Container(
        width: lado,
        height: lado,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Icon(icono, color: color, size: lado * 0.5),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: compacto ? 21 : 24,
                  fontWeight: FontWeight.w800,
                  height: 1.1)),
          if (subtitulo != null) ...[
            const SizedBox(height: 4),
            Text(subtitulo!, style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ],
        ]),
      ),
      if (accion != null) accion!,
    ]);
  }
}

// ── Tarjeta clara (con o sin número de paso) ────────────────────────────────
class TarjetaSE extends StatelessWidget {
  final Widget child;
  final Color? acento; // sombra suave y franja opcional del color del servicio
  final bool franja; // franja vertical a la izquierda (tarjetas de servicio)
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;
  const TarjetaSE({
    super.key,
    required this.child,
    this.acento,
    this.franja = false,
    this.padding,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    final pad = padding ?? EdgeInsets.all(angostoSE(context) ? 14 : 18);
    final c = acento;
    Widget contenido = Padding(padding: pad, child: child);
    if (franja && c != null) {
      contenido = IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: c),
          Expanded(child: contenido),
        ]),
      );
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(kRadioTarjetaSE),
        boxShadow: [
          BoxShadow(
            color: (c ?? Colors.black).withValues(alpha: c != null ? 0.18 : 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: onTap == null ? contenido : InkWell(onTap: onTap, child: contenido),
      ),
    );
  }
}

/// Tarjeta con número de paso, título, ícono y línea de color.
class BloqueSE extends StatelessWidget {
  final int? paso;
  final String titulo;
  final IconData icono;
  final Color color;
  final List<Widget> hijos;
  const BloqueSE({
    super.key,
    this.paso,
    required this.titulo,
    required this.icono,
    required this.color,
    required this.hijos,
  });

  @override
  Widget build(BuildContext context) {
    final sobre = sobreColorSE(color);
    final colorIcono = color == kVerdeSE ? kVerdeOscuroSE : color;
    return TarjetaSE(
      acento: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (paso != null) ...[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text('$paso',
                  style: TextStyle(color: sobre, fontWeight: FontWeight.w800, fontSize: 14)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87)),
          ),
          Icon(icono, color: colorIcono, size: 22),
        ]),
        Container(
          height: 3,
          width: 40,
          margin: EdgeInsets.only(top: 10, bottom: 16, left: paso != null ? 38 : 0),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        ...hijos,
      ]),
    );
  }
}

// ── Etiqueta de color (tipo de servicio, estado…) ───────────────────────────
class EtiquetaSE extends StatelessWidget {
  final String texto;
  final Color color;
  const EtiquetaSE(this.texto, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    final fuerte = color == kVerdeSE ? kVerdeOscuroSE : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto,
          style: TextStyle(
              color: Color.lerp(fuerte, Colors.black, 0.35),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3)),
    );
  }
}

// ── Botón principal grande ──────────────────────────────────────────────────
class BotonPrincipalSE extends StatelessWidget {
  final String texto;
  final Color color;
  final VoidCallback? onPressed;
  final bool cargando;
  final IconData? icono;
  final String textoCargando;
  const BotonPrincipalSE({
    super.key,
    required this.texto,
    required this.onPressed,
    this.color = kVerdeSE,
    this.cargando = false,
    this.icono = Icons.send_rounded,
    this.textoCargando = 'ENVIANDO…',
  });

  @override
  Widget build(BuildContext context) {
    final sobre = sobreColorSE(color);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: sobre,
          disabledBackgroundColor: color.withValues(alpha: 0.5),
          disabledForegroundColor: sobre.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: cargando ? null : onPressed,
        icon: cargando
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: sobre),
              )
            : (icono != null ? Icon(icono, size: 20) : const SizedBox.shrink()),
        label: Text(
          cargando ? textoCargando : texto,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1),
        ),
      ),
    );
  }
}

// ── Mosaico de servicio (pantallas de inicio) ───────────────────────────────
class MosaicoServicioSE extends StatelessWidget {
  final EstiloServicio estilo;
  final VoidCallback onTap;
  final String? subtitulo;
  const MosaicoServicioSE({super.key, required this.estilo, required this.onTap, this.subtitulo});

  @override
  Widget build(BuildContext context) {
    return TarjetaSE(
      acento: estilo.color,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: estilo.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(estilo.icono, color: estilo.colorIcono, size: 24),
        ),
        const SizedBox(height: 10),
        Text(estilo.nombreCorto,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87)),
        const SizedBox(height: 2),
        Text(subtitulo ?? estilo.subtitulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.25)),
      ]),
    );
  }
}

/// Grilla responsive de mosaicos: 2 columnas en celular, 4 en pantallas anchas.
class GrillaServiciosSE extends StatelessWidget {
  final List<Widget> mosaicos;
  const GrillaServiciosSE({super.key, required this.mosaicos});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columnas = c.maxWidth >= 520 ? 4 : 2;
      const sep = 12.0;
      final ancho = (c.maxWidth - sep * (columnas - 1)) / columnas;
      return Wrap(
        spacing: sep,
        runSpacing: sep,
        children: [for (final m in mosaicos) SizedBox(width: ancho, child: m)],
      );
    });
  }
}

// ── Aviso suave de cotización ───────────────────────────────────────────────
class AvisoCotizacionSE extends StatelessWidget {
  const AvisoCotizacionSE({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: kAvisoSE, borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Text('💬', style: TextStyle(fontSize: 18)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'La Central te dice el precio antes de enviar el Móvil.',
              style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.3),
            ),
          ),
        ]),
      );
}

// ── Pantalla de formulario de servicio ──────────────────────────────────────
/// Fondo negro, encabezado del servicio, contenido centrado (máx. 560 px) y
/// botón fijo abajo que se esconde mientras el teclado está abierto.
class ScaffoldServicioSE extends StatelessWidget {
  final EstiloServicio estilo;
  final List<Widget> children;
  final bool procesando;
  final VoidCallback onEnviar;
  final String? tituloBarra;
  const ScaffoldServicioSE({
    super.key,
    required this.estilo,
    required this.children,
    required this.procesando,
    required this.onEnviar,
    this.tituloBarra,
  });

  @override
  Widget build(BuildContext context) {
    final margen = margenSE(context);
    final teclado = MediaQuery.of(context).viewInsets.bottom > 0;
    return Theme(
      data: temaFormularioSE(context, estilo.color),
      child: Scaffold(
        backgroundColor: kFondoSE,
        appBar: AppBar(
          backgroundColor: kFondoSE,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(tituloBarra ?? 'ServiExpress',
              style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          bottom: false,
          child: ContenidoSE(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(margen, 4, margen, 24),
              children: [
                EncabezadoSE(
                  icono: estilo.icono,
                  color: estilo.color,
                  titulo: estilo.titulo,
                  subtitulo: estilo.subtitulo,
                ),
                const SizedBox(height: 16),
                const BannerAltaDemanda(margin: EdgeInsets.only(bottom: 12)),
                ...children,
              ],
            ),
          ),
        ),
        bottomNavigationBar: teclado
            ? null
            : SafeArea(
                child: ContenidoSE(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(margen, 8, margen, 12),
                    child: BotonPrincipalSE(
                      texto: estilo.textoBoton,
                      color: estilo.color,
                      cargando: procesando,
                      onPressed: onEnviar,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
