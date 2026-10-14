// lib/utils/iconos.dart
//
// Íconos de marca que no vienen en los Material Icons de Flutter.
//
// Usamos SOLO la fuente del paquete font_awesome_flutter (v11+). Desde
// Flutter 3.3x `IconData` es una clase final y la v11 del paquete ya no
// permite usar sus íconos con el widget `Icon`, así que definimos aquí el
// IconData directamente sobre su fuente "FontAwesomeBrands". Al ser `const`,
// el tree-shaking de íconos del build release conserva el glifo.

import 'package:flutter/widgets.dart';

/// Logo real de WhatsApp (Font Awesome Brands, U+F232) — usar en todos los
/// botones que abren WhatsApp. Funciona con `Icon(...)` normal y es const.
const IconData iconoWhatsApp = IconData(
  0xf232,
  fontFamily: 'FontAwesomeBrands',
  fontPackage: 'font_awesome_flutter',
);

/// Verde oficial de WhatsApp.
const Color verdeWhatsApp = Color(0xFF25D366);
