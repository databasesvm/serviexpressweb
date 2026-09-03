// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Dispara la descarga de [bytes] como un archivo en el navegador.
void descargarArchivosWeb(List<int> bytes, String nombre, String mime) {
  final blob = html.Blob([bytes], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', nombre)
    ..click();
  html.Url.revokeObjectUrl(url);
}
