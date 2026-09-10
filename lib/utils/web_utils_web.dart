// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

// Abre (o reutiliza) una pestaña con el nombre dado.
void openWhatsAppTab(String url) => html.window.open(url, 'whatsapp');
