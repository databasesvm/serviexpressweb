// Import condicional: en web usa dart:html, en mobile el stub vacío.
export 'web_downloader_stub.dart'
    if (dart.library.html) 'web_downloader_web.dart';
