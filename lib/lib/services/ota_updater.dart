/// Exportación condicional — en Android usa la implementación real (dart:io),
/// en Web/iOS usa el stub vacío que no hace nada.
library;
export 'ota_updater_stub.dart'
    if (dart.library.io) 'ota_updater_io.dart';
