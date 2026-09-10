// Importación condicional: en web usa dart:html, en otras plataformas usa el stub.
export 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_web.dart';
