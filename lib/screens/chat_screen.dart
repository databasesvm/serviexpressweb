import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:serviexpress_app/utils/onesignal_api.dart';
import 'package:serviexpress_app/utils/sonido_manager.dart';

// ============================================================
// CHATBOT FAQ — Nivel 1 (botones) + Nivel 2 (palabras clave)
// ============================================================

/// Tipo de usuario que abre el chat — determina qué set de FAQs se muestra.
enum TipoFaqChat { cliente, movil, local, central }

class _FaqItem {
  final String pregunta;
  final String respuesta;
  final List<String> keywords;
  /// Si true: además de responder el bot, notifica a Central.
  /// Para Central (respuestas rápidas): este campo no aplica.
  final bool escalarACentral;
  const _FaqItem({
    required this.pregunta,
    required this.respuesta,
    this.keywords = const [],
    this.escalarACentral = false,
  });
}

class _FaqCategoria {
  final String nombre;
  final List<_FaqItem> items;
  const _FaqCategoria(this.nombre, this.items);
}

// ------------------------------------------------------------------
// FAQs CLIENTE (usuario registrado)
// ------------------------------------------------------------------
final _kFaqsCliente = <_FaqCategoria>[
  _FaqCategoria('💰 Tarifas y Precios', [
    _FaqItem(
      pregunta: '¿Cuánto cuesta el servicio?',
      respuesta:
          'Las tarifas dependen de la distancia y el horario.\n\n'
          '• Horario diurno: tarifa base según la ruta\n'
          '• Horario nocturno: aplica recargo adicional 🌙\n\n'
          'La Central te confirma el precio exacto antes de enviarte la moto. 😊',
      keywords: ['precio', 'cuesta', 'costo', 'valor', 'tarifa', 'cobra', 'cuanto', 'cuánto'],
    ),
    _FaqItem(
      pregunta: '¿Hay recargo nocturno?',
      respuesta:
          'Sí 🌙 A partir de cierta hora aplica tarifa mínima nocturna.\n'
          'La Central te informa el valor al confirmar el servicio.',
      keywords: ['nocturno', 'noche', 'recargo', 'madrugada', 'minima', 'mínima'],
    ),
  ]),
  _FaqCategoria('⏱️ Tiempos', [
    _FaqItem(
      pregunta: '¿Cuánto tarda en llegar la moto?',
      respuesta:
          'Normalmente entre 5 y 15 minutos ⏱️ según disponibilidad y ubicación.\n\n'
          'Puedes ver el estado en tiempo real desde la pantalla principal.',
      keywords: ['tarda', 'tiempo', 'llega', 'espera', 'demora', 'cuando', 'cuándo'],
    ),
  ]),
  _FaqCategoria('💳 Formas de Pago', [
    _FaqItem(
      pregunta: '¿Cómo puedo pagar?',
      respuesta:
          'Aceptamos:\n\n'
          '💵 Efectivo\n'
          '📱 Nequi\n'
          '📱 Daviplata\n'
          '🏦 Transferencias digitales\n\n'
          'El conductor te indica las opciones al llegar.',
      keywords: ['pago', 'pagar', 'efectivo', 'nequi', 'daviplata', 'transferencia', 'billetera'],
    ),
  ]),
  _FaqCategoria('📍 Cobertura', [
    _FaqItem(
      pregunta: '¿Cubren mi zona en Cúcuta?',
      respuesta:
          'Cubrimos gran parte de Cúcuta y sectores cercanos 📍.\n\n'
          'Cuéntanos tu barrio y te confirmamos disponibilidad.',
      keywords: ['zona', 'barrio', 'cobertura', 'llegan', 'cucuta', 'sector', 'ubicacion'],
    ),
  ]),
  _FaqCategoria('🕐 Horarios', [
    _FaqItem(
      pregunta: '¿Cuál es el horario de atención?',
      respuesta:
          'Atendemos todos los días 🕐\n\n'
          'Para el horario exacto en tu zona, escríbenos y la Central te orienta.',
      keywords: ['horario', 'horas', 'abierto', 'cierra', 'disponible', 'atienden', 'abren'],
    ),
  ]),
  _FaqCategoria('❌ Cancelaciones', [
    _FaqItem(
      pregunta: '¿Puedo cancelar mi pedido?',
      respuesta:
          'Sí, puedes cancelar mientras el servicio no haya iniciado ❌\n\n'
          'Escríbenos y la Central lo gestiona de inmediato.\n\n'
          '⚠️ Cancelaciones frecuentes pueden afectar tu historial.',
      keywords: ['cancelar', 'cancelacion', 'cancelación', 'anular', 'desistir'],
    ),
  ]),
  _FaqCategoria('📦 Servicios', [
    _FaqItem(
      pregunta: '¿Qué servicios ofrecen?',
      respuesta:
          'Ofrecemos:\n\n'
          '🏍️ Mototaxi — transporte personal\n'
          '📦 Domicilios y mensajería\n'
          '🛒 Mandados y compras\n'
          '🍔 Pedidos de comida\n\n'
          '¡Todo desde la app! 😊',
      keywords: ['servicio', 'servicios', 'ofrecen', 'domicilio', 'comida', 'mensajeria', 'mandado'],
    ),
  ]),
  _FaqCategoria('📱 Cómo Usar la App', [
    _FaqItem(
      pregunta: '¿Cómo solicito un servicio?',
      respuesta:
          'Muy sencillo 😊\n\n'
          '1️⃣ Elige el tipo de servicio\n'
          '2️⃣ Ingresa origen y destino\n'
          '3️⃣ Confirma el pedido\n'
          '4️⃣ La Central asigna un mototaxista\n'
          '5️⃣ Sigue el estado en tiempo real',
      keywords: ['como solicito', 'como pido', 'como funciona', 'usar', 'empezar', 'comenzar'],
    ),
  ]),
  _FaqCategoria('🆘 Soporte', [
    _FaqItem(
      pregunta: 'Necesito hablar con un agente',
      respuesta:
          '¡Entendido! 📞 Le avisamos a la Central que tienes una consulta.\n\n'
          'Escribe tu pregunta y te atendemos en breve.',
      keywords: ['hablar', 'persona', 'asesor', 'agente', 'ayuda', 'problema', 'queja'],
      escalarACentral: true,
    ),
  ]),
];

// ------------------------------------------------------------------
// FAQs MÓVIL (conductor)
// ------------------------------------------------------------------
final _kFaqsMovil = <_FaqCategoria>[
  _FaqCategoria('💼 Mi Trabajo', [
    _FaqItem(
      pregunta: '¿Cómo acepto un servicio?',
      respuesta:
          'En la pestaña Radar aparecen los servicios disponibles en tu zona.\n\n'
          'Toca uno para ver los detalles y pulsa Aceptar. '
          'Los Masters tienen prioridad en servicios de alta demanda. 🏍️',
      keywords: ['acepto', 'aceptar', 'recibir servicio', 'como acepto', 'tomar servicio'],
    ),
    _FaqItem(
      pregunta: '¿Por qué no me llegan servicios?',
      respuesta:
          'Verifica que:\n\n'
          '✅ El switch de Conectado esté en verde\n'
          '✅ Tu paradero asignado sea correcto\n'
          '✅ No estés suspendido\n\n'
          'En horas de poca demanda puede haber menos servicios. 📡',
      keywords: ['no llegan', 'no me llegan', 'sin servicios', 'no aparecen', 'demanda'],
    ),
  ]),
  _FaqCategoria('⭐ Rangos y Puntuación', [
    _FaqItem(
      pregunta: '¿Cómo funciona el sistema de rangos?',
      respuesta:
          'Acumulas puntos completando servicios y manteniendo buenas calificaciones.\n\n'
          'Rangos: 🥉 Bronce → 🥈 Plata → 🥇 Oro → 🏆 Leyenda → ⭐ Master\n\n'
          'Cada rango tiene beneficios distintos. Revisa tu perfil para más detalles.',
      keywords: ['rango', 'rangos', 'puntos', 'puntaje', 'bronce', 'plata', 'oro', 'leyenda', 'master', 'beneficios'],
    ),
    _FaqItem(
      pregunta: '¿Cómo subo de rango?',
      respuesta:
          'Completa servicios, mantén buenas calificaciones y acumula puntos. 🏆\n\n'
          'El sistema actualiza tu rango automáticamente al alcanzar el puntaje requerido.',
      keywords: ['subir rango', 'como subo', 'ascender', 'mejorar rango', 'subir'],
    ),
  ]),
  _FaqCategoria('🌙 Tarifas', [
    _FaqItem(
      pregunta: '¿Qué es el recargo nocturno?',
      respuesta:
          'Es un ajuste de tarifa que aplica a partir de cierta hora de la noche 🌙\n\n'
          'Cuando hay recargo nocturno activo, verás la indicación en el panel de tarifas. '
          'Asegúrate de no cobrar por debajo de la tarifa mínima nocturna.',
      keywords: ['recargo', 'nocturno', 'noche', 'tarifa nocturna', 'minima nocturna', 'mínima nocturna'],
    ),
  ]),
  _FaqCategoria('📋 Documentos y Perfil', [
    _FaqItem(
      pregunta: '¿Cómo actualizo mis documentos?',
      respuesta:
          'En tu perfil (ícono de usuario) → sección Documentos 📋\n\n'
          'Puedes subir o actualizar SOAT, licencia y cédula. '
          'Los documentos son revisados por la Central antes de activarse.',
      keywords: ['documento', 'documentos', 'soat', 'licencia', 'cedula', 'cédula', 'foto', 'actualizar'],
    ),
    _FaqItem(
      pregunta: '¿Cómo cambio mi contraseña o datos?',
      respuesta:
          'En tu perfil → sección Datos Personales 🔒\n\n'
          'Puedes actualizar contraseña, correo y teléfono desde ahí.',
      keywords: ['contraseña', 'password', 'clave', 'correo', 'telefono', 'datos', 'actualizar datos'],
    ),
  ]),
  _FaqCategoria('🆘 Emergencias', [
    _FaqItem(
      pregunta: '¿Cómo activo el botón de pánico?',
      respuesta:
          'El botón de pánico aparece cuando tienes un servicio activo 🆘\n\n'
          'Al activarlo se alerta a toda la Central y a los mototaxistas cercanos. '
          'Úsalo solo en situaciones de peligro real.',
      keywords: ['panico', 'pánico', 'emergencia', 'peligro', 'boton panico'],
    ),
    _FaqItem(
      pregunta: 'Necesito ayuda de la Central',
      respuesta:
          'Le avisamos a la Central que necesitas asistencia 📞\n\n'
          'Cuéntanos tu situación y te ayudamos de inmediato.',
      keywords: ['ayuda', 'problema', 'ayudar', 'hablar', 'central', 'soporte', 'asistencia'],
      escalarACentral: true,
    ),
  ]),
];

// ------------------------------------------------------------------
// FAQs LOCAL (negocio)
// ------------------------------------------------------------------
final _kFaqsLocal = <_FaqCategoria>[
  _FaqCategoria('📦 Pedidos', [
    _FaqItem(
      pregunta: '¿Cómo solicito un domicilio?',
      respuesta:
          'En la pantalla principal toca Solicitar servicio 📦\n\n'
          'Elige el tipo (domicilio, mandado, etc.), ingresa origen y destino, y confirma. '
          'La Central asigna la moto disponible.',
      keywords: ['solicito', 'pedir', 'solicitar', 'domicilio', 'mandado', 'pedido', 'como pido'],
    ),
    _FaqItem(
      pregunta: '¿Cómo hago una cotización?',
      respuesta:
          'Desde la pantalla principal usa la opción Cotizar 💰\n\n'
          'Ingresa los datos del servicio y la Central calcula la tarifa. '
          'Una vez aprobada, se despacha automáticamente.',
      keywords: ['cotizacion', 'cotización', 'cotizar', 'precio', 'cuánto cuesta', 'cuanto cuesta', 'presupuesto'],
    ),
  ]),
  _FaqCategoria('📍 Direcciones y GPS', [
    _FaqItem(
      pregunta: '¿Cómo agrego mis direcciones frecuentes?',
      respuesta:
          'La Central puede registrar tus direcciones habituales en el sistema 📍\n\n'
          'Escríbenos aquí el nombre y la dirección exacta que quieres agregar.',
      keywords: ['dirección', 'direccion', 'frecuente', 'ruta', 'agregar dirección', 'mis direcciones'],
    ),
    _FaqItem(
      pregunta: '¿Puedo pedir la ubicación GPS del destinatario?',
      respuesta:
          'Sí 📡 En el panel del servicio activo hay un botón para solicitar ubicación GPS.\n\n'
          'El sistema genera un enlace; cuando el destinatario lo abre, '
          'la ubicación llega automáticamente.',
      keywords: ['gps', 'ubicacion', 'ubicación', 'localizar', 'destino', 'donde esta'],
    ),
  ]),
  _FaqCategoria('📊 Historial y Estados', [
    _FaqItem(
      pregunta: '¿Cómo veo mis servicios anteriores?',
      respuesta:
          'En la pantalla principal → botón Historial 📊\n\n'
          'Ahí puedes ver todos tus servicios con detalles y calificaciones.',
      keywords: ['historial', 'anterior', 'anteriores', 'servicios anteriores', 'registro', 'ver servicios'],
    ),
    _FaqItem(
      pregunta: '¿Qué significan los estados del servicio?',
      respuesta:
          '• ⏳ Pendiente — esperando moto disponible\n'
          '• 🏍️ En camino — moto asignada y en ruta\n'
          '• ▶️ En curso — servicio iniciado\n'
          '• ✅ Finalizado — completado\n'
          '• ❌ Cancelado — no se realizó',
      keywords: ['estado', 'estados', 'pendiente', 'en camino', 'en curso', 'finalizado', 'que significa'],
    ),
  ]),
  _FaqCategoria('💰 Precios', [
    _FaqItem(
      pregunta: '¿Cómo funciona el precio para mi negocio?',
      respuesta:
          'Tu negocio puede tener una lista de precios personalizada por sector 💰\n\n'
          'La Central configura tus tarifas especiales. Consúltanos si necesitas ajustes.',
      keywords: ['precio', 'precios', 'tarifa', 'lista precios', 'sector', 'descuento', 'especial'],
    ),
  ]),
  _FaqCategoria('🆘 Soporte', [
    _FaqItem(
      pregunta: 'Hay un problema con mi servicio',
      respuesta:
          'Lamentamos el inconveniente ⚡\n\n'
          'Cuéntanos qué sucedió y la Central lo gestiona de inmediato.',
      keywords: ['problema', 'inconveniente', 'queja', 'reclamo', 'error', 'fallo', 'mal servicio'],
      escalarACentral: true,
    ),
    _FaqItem(
      pregunta: 'Necesito hablar con la Central',
      respuesta:
          'Entendido, ya les avisamos 📞\n\n'
          'Escribe tu consulta aquí y te atendemos en breve.',
      keywords: ['hablar', 'central', 'asesor', 'urgente', 'ayuda', 'comunicar'],
      escalarACentral: true,
    ),
  ]),
];

// ------------------------------------------------------------------
// FAQs CENTRAL (respuestas rápidas pre-escritas)
// Para Central: tapping un item pre-rellena el campo de texto (no bot)
// En este set: pregunta = etiqueta corta, respuesta = texto a enviar
// ------------------------------------------------------------------
final _kFaqsCentral = <_FaqCategoria>[
  _FaqCategoria('✅ Confirmaciones', [
    _FaqItem(
      pregunta: '✅ Servicio asignado',
      respuesta: 'Tu servicio fue asignado. El mototaxista está en camino. 🏍️',
    ),
    _FaqItem(
      pregunta: '✅ Confirmando...',
      respuesta: 'Recibido, estamos confirmando tu servicio. Te notificamos en un momento.',
    ),
    _FaqItem(
      pregunta: '✅ Servicio finalizado',
      respuesta: 'Tu servicio ha finalizado. Recuerda calificarnos. ⭐ ¡Gracias por usar Serviexpress!',
    ),
  ]),
  _FaqCategoria('⏱️ Tiempos', [
    _FaqItem(
      pregunta: '⏱️ En camino',
      respuesta: 'El mototaxista ya va en camino. Pronto llega a tu ubicación. 🏍️',
    ),
    _FaqItem(
      pregunta: '⏱️ Tiempo estimado',
      respuesta: 'Estimamos una llegada en aproximadamente 5 a 15 minutos. ⏱️',
    ),
  ]),
  _FaqCategoria('❌ Sin Disponibilidad / Cancelado', [
    _FaqItem(
      pregunta: '❌ Sin disponibilidad',
      respuesta:
          'En este momento no tenemos disponibilidad en tu zona. '
          'Te avisamos tan pronto haya un mototaxista libre. 📡',
    ),
    _FaqItem(
      pregunta: '❌ Servicio cancelado',
      respuesta: 'Tu servicio fue cancelado. ¿Deseas que te asignemos uno nuevo? 🔄',
    ),
  ]),
  _FaqCategoria('📍 Confirmar Datos', [
    _FaqItem(
      pregunta: '📍 Confirmar dirección',
      respuesta: '¿Puedes confirmarme tu dirección exacta de recogida? 📍',
    ),
    _FaqItem(
      pregunta: '🗺️ Confirmar destino',
      respuesta: '¿Cuál es tu destino exacto? 🗺️',
    ),
  ]),
  _FaqCategoria('💰 Tarifas', [
    _FaqItem(
      pregunta: '💰 Informar tarifa',
      respuesta: 'La tarifa para ese trayecto es de \$___. ¿Confirmas el servicio? 💰',
    ),
    _FaqItem(
      pregunta: '🌙 Recargo nocturno',
      respuesta: 'En este momento aplica tarifa nocturna. El valor mínimo es \$___. 🌙',
    ),
  ]),
  _FaqCategoria('😊 Cierre', [
    _FaqItem(
      pregunta: '😊 Bienvenida',
      respuesta: '¡Hola! Bienvenido a Serviexpress. ¿En qué podemos ayudarte hoy? 😊',
    ),
    _FaqItem(
      pregunta: '👋 Hasta pronto',
      respuesta: 'Gracias por contactarte con Serviexpress. ¡Que tengas un excelente día! 👋',
    ),
  ]),
];

// ============================================================
class ChatScreen extends StatefulWidget {
  final String salaId;
  final int miId;
  final String miNombre;
  final String titulo;

  // Variables tácticas para el ping-pong de alarmas
  final int? servicioId;
  final int? usuarioId;
  final String? alarmaLocal;
  final String? alarmaDestino;

  /// ID del destinatario (usuarios.id) para push cuando Central escribe.
  final int? destinatarioId;

  /// Tipo de usuario — determina qué set de FAQs se muestra.
  /// Si se omite: Central (miId==0) → central; demás → cliente.
  final TipoFaqChat? tipoFaq;

  const ChatScreen({
    super.key,
    required this.salaId,
    required this.miId,
    required this.miNombre,
    required this.titulo,
    this.servicioId,
    this.usuarioId,
    this.alarmaLocal,
    this.alarmaDestino,
    this.destinatarioId,
    this.tipoFaq,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _sonidos = SonidoManager();

  // ---- Stream principal (últimos 100) ----
  late Stream<List<Map<String, dynamic>>> _streamMensajes;

  // ---- Paginación: mensajes anteriores cargados manualmente ----
  final List<Map<String, dynamic>> _mensajesAntiguos = [];
  bool _cargandoMas = false;
  bool _hayMas = true;
  // ---- Imagen ----
  bool _subiendoImagen = false;

  // ---- Indicador escribiendo ----
  String? _escribiendo;        // nombre de quien escribe (ajeno)
  Timer? _timerEscribiendo;   // apaga el indicador tras 3s sin broadcast
  Timer? _timerMiEscritura;   // debounce para no spamear broadcasts
  RealtimeChannel? _canalEscribiendo;

  // ---- Snapshot actual del stream (para cursor) ----
  List<Map<String, dynamic>> _mensajesStream = [];

  // ---- FAQ Chatbot ----
  bool _habilitarFaq = false;
  bool _esCentral = false;
  List<_FaqCategoria> _faqActual = const [];

  // ---- Read receipts ----
  DateTime? _leidoHastaPorOtro; // última vez que el OTRO leyó esta sala
  RealtimeChannel? _canalLecturas;

  @override
  void initState() {
    super.initState();
    _esCentral = widget.miId == 0;
    final tipo = widget.tipoFaq ??
        (widget.miId == 0 ? TipoFaqChat.central : TipoFaqChat.cliente);
    _faqActual = switch (tipo) {
      TipoFaqChat.cliente => _kFaqsCliente,
      TipoFaqChat.movil   => _kFaqsMovil,
      TipoFaqChat.local   => _kFaqsLocal,
      TipoFaqChat.central => _kFaqsCentral,
    };
    _habilitarFaq = true; // todos los tipos tienen soporte FAQ
    _streamMensajes = Supabase.instance.client
        .from('mensajes')
        .stream(primaryKey: ['id'])
        .eq('sala_id', widget.salaId)
        .order('created_at', ascending: false)
        .limit(100);

    _apagarMiNotificacion();
    _registrarLectura();
    _iniciarCanalEscribiendo();
    _cargarLecturaOtro();
    _iniciarCanalLecturas();

    // Listener de texto para emitir "escribiendo..."
    _msgCtrl.addListener(_alEscribir);
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_alEscribir);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _timerEscribiendo?.cancel();
    _timerMiEscritura?.cancel();
    _canalEscribiendo?.unsubscribe();
    _canalLecturas?.unsubscribe();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // READ RECEIPTS — ✓ enviado / ✓✓ visto
  // -----------------------------------------------------------------------
  int? get _otroUsuarioId =>
      widget.destinatarioId ?? (widget.miId != 0 ? 0 : null);

  Future<void> _cargarLecturaOtro() async {
    final otroId = _otroUsuarioId;
    if (otroId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('lecturas_chat')
          .select('leido_hasta')
          .eq('sala_id', widget.salaId)
          .eq('usuario_id', otroId)
          .maybeSingle();
      if (row != null && row['leido_hasta'] != null && mounted) {
        setState(() {
          _leidoHastaPorOtro =
              DateTime.tryParse(row['leido_hasta'].toString())?.toLocal();
        });
      }
    } catch (_) {}
  }

  void _iniciarCanalLecturas() {
    final otroId = _otroUsuarioId;
    if (otroId == null) return;
    _canalLecturas = Supabase.instance.client
        .channel('lecturas_${widget.salaId}_$otroId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'lecturas_chat',
          callback: (payload) {
            final rec = payload.newRecord;
            if (rec.isEmpty) return;
            // Solo nos importa la lectura del OTRO usuario en ESTA sala
            if (rec['sala_id']?.toString() != widget.salaId.toString()) return;
            if ((rec['usuario_id'] as num?)?.toInt() != otroId) return;
            if (rec['leido_hasta'] == null) return;
            final dt =
                DateTime.tryParse(rec['leido_hasta'].toString())?.toLocal();
            if (dt != null && mounted) {
              setState(() => _leidoHastaPorOtro = dt);
            }
          },
        )
        .subscribe();
  }

  // -----------------------------------------------------------------------
  // ALARMAS Y LECTURAS
  // -----------------------------------------------------------------------
  Future<void> _apagarMiNotificacion() async {
    if (widget.alarmaLocal == null) return;
    try {
      if (widget.servicioId != null) {
        await Supabase.instance.client
            .from('servicios')
            .update({widget.alarmaLocal!: false}).eq('id', widget.servicioId!);
      } else if (widget.usuarioId != null) {
        await Supabase.instance.client
            .from('usuarios')
            .update({widget.alarmaLocal!: false}).eq('id', widget.usuarioId!);
      }
    } catch (_) {}
  }

  Future<void> _encenderAlarmaDestino() async {
    if (widget.alarmaDestino == null) return;
    try {
      if (widget.servicioId != null) {
        await Supabase.instance.client
            .from('servicios')
            .update({widget.alarmaDestino!: true}).eq('id', widget.servicioId!);
      } else if (widget.usuarioId != null) {
        await Supabase.instance.client
            .from('usuarios')
            .update({widget.alarmaDestino!: true}).eq('id', widget.usuarioId!);
      }
    } catch (_) {}
  }

  /// Marca la sala como leída hasta ahora para este usuario.
  Future<void> _registrarLectura() async {
    try {
      await Supabase.instance.client.from('lecturas_chat').upsert({
        'sala_id': widget.salaId,
        'usuario_id': widget.miId,
        'leido_hasta': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'sala_id,usuario_id');
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // INDICADOR "ESCRIBIENDO..."
  // -----------------------------------------------------------------------
  void _iniciarCanalEscribiendo() {
    _canalEscribiendo = Supabase.instance.client
        .channel('typing_${widget.salaId}')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final nombre = payload['nombre']?.toString() ?? '';
            if (nombre.isEmpty || nombre == widget.miNombre) return;
            if (!mounted) return;
            setState(() => _escribiendo = nombre);
            _timerEscribiendo?.cancel();
            _timerEscribiendo = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _escribiendo = null);
            });
          },
        )
        .subscribe();
  }

  void _alEscribir() {
    if (_msgCtrl.text.isEmpty) return;
    // Debounce: solo emite si no hay otro timer pendiente
    if (_timerMiEscritura?.isActive ?? false) return;
    _canalEscribiendo?.sendBroadcastMessage(
      event: 'typing',
      payload: {'nombre': widget.miNombre},
    );
    _timerMiEscritura = Timer(const Duration(seconds: 2), () {});
  }

  // -----------------------------------------------------------------------
  // FAQ CHATBOT — Nivel 1 (botones) + Nivel 2 (palabras clave)
  // -----------------------------------------------------------------------

  /// Normaliza texto para comparar sin tildes ni mayúsculas.
  String _normalizar(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');

  /// Busca una respuesta FAQ por palabras clave en el texto libre.
  /// Solo aplica para usuarios no-Central (la Central no recibe respuestas de bot).
  _FaqItem? _detectarRespuestaFaq(String texto) {
    if (!_habilitarFaq || _esCentral) return null;
    final norm = _normalizar(texto);
    for (final cat in _faqActual) {
      for (final item in cat.items) {
        for (final kw in item.keywords) {
          if (norm.contains(kw)) return item;
        }
      }
    }
    return null;
  }

  /// Inserta un mensaje del bot (emisor_id = -1) con un pequeño delay natural.
  Future<void> _enviarMensajeBot(String respuesta) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    try {
      await Supabase.instance.client.from('mensajes').insert({
        'sala_id': widget.salaId,
        'emisor_id': -1,
        'emisor_nombre': 'Asistente 🤖',
        'mensaje': respuesta,
      });
      await _registrarLectura();
    } catch (_) {}
  }

  /// Cuando se toca un botón FAQ:
  /// - Usuarios: envía la pregunta y el bot responde.
  /// - Central: pre-rellena el campo de texto con la respuesta rápida (sin bot).
  Future<void> _seleccionarFaq(_FaqItem faq) async {
    // Modo Central: solo pre-rellenar el campo de texto
    if (_esCentral) {
      _msgCtrl.text = faq.respuesta;
      _msgCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: faq.respuesta.length),
      );
      return;
    }

    // Modo usuario: enviar pregunta + respuesta del bot
    try {
      await Supabase.instance.client.from('mensajes').insert({
        'sala_id': widget.salaId,
        'emisor_id': widget.miId,
        'emisor_nombre': widget.miNombre,
        'mensaje': faq.pregunta,
      });
      await _registrarLectura();
      if (faq.escalarACentral) {
        _enviarPush(faq.pregunta);
        await _encenderAlarmaDestino();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      return;
    }
    await _enviarMensajeBot(faq.respuesta);
  }

  /// Muestra el panel completo de FAQs / respuestas rápidas como BottomSheet.
  void _mostrarPanelFaq() {
    final titulo = _esCentral ? 'Respuestas rápidas' : 'Preguntas frecuentes';
    final subtitulo = _esCentral
        ? 'Toca una respuesta para pre-cargarla en el chat.'
        : 'Toca una pregunta y el Asistente responde al instante.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161616),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Colors.white12),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text(
              subtitulo,
              style: const TextStyle(fontSize: 13, color: Colors.white38),
            ),
            const SizedBox(height: 16),
            for (final cat in _faqActual) ...[
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: Text(
                  cat.nombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF3AF500)),
                ),
              ),
              for (final item in cat.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.pregunta,
                      style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  trailing: Icon(
                    _esCentral ? Icons.edit_outlined : Icons.arrow_forward_ios,
                    size: 12,
                    color: Colors.white30,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _seleccionarFaq(item);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // PAGINACIÓN
  // -----------------------------------------------------------------------
  Future<void> _cargarMas() async {
    if (_cargandoMas || !_hayMas) return;

    // El cursor es el created_at del mensaje más antiguo que tenemos
    final cursor = _mensajesAntiguos.isNotEmpty
        ? _mensajesAntiguos.last['created_at']?.toString()
        : (_mensajesStream.isNotEmpty
              ? _mensajesStream.last['created_at']?.toString()
              : null);

    if (cursor == null) return;

    setState(() => _cargandoMas = true);
    try {
      final rows = await Supabase.instance.client
          .from('mensajes')
          .select()
          .eq('sala_id', widget.salaId)
          .lt('created_at', cursor)
          .order('created_at', ascending: false)
          .limit(50);

      final nuevos = rows;
      if (nuevos.isEmpty) {
        setState(() => _hayMas = false);
      } else {
        setState(() => _mensajesAntiguos.addAll(nuevos));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  // -----------------------------------------------------------------------
  // ENVIAR TEXTO
  // -----------------------------------------------------------------------
  Future<void> _enviar() async {
    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;
    _msgCtrl.clear();

    // Sonido inmediato al enviar (no espera la BD)
    _sonidos.reproducirSuave(Sonidos.localChat);

    try {
      await Supabase.instance.client.from('mensajes').insert({
        'sala_id': widget.salaId,
        'emisor_id': widget.miId,
        'emisor_nombre': widget.miNombre,
        'mensaje': texto,
      });
      _enviarPush(texto);
      await _encenderAlarmaDestino();
      await _registrarLectura(); // actualizar lectura tras enviar
      // Nivel 2: detectar palabras clave y responder automáticamente
      final faqMatch = _detectarRespuestaFaq(texto);
      if (faqMatch != null) {
        await _enviarMensajeBot(faqMatch.respuesta);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // -----------------------------------------------------------------------
  // PUSH
  // -----------------------------------------------------------------------
  void _enviarPush(String texto) {
    final preview = texto.length > 70 ? '${texto.substring(0, 70)}…' : texto;
    if (widget.miId != 0) {
      if (widget.destinatarioId != null) {
        // No-central escribe a otro usuario con ID conocido
        // (móvil → cliente, cliente → móvil, local → móvil)
        // → push directo al destinatario, NO a la central
        MotorNotificaciones.dispararMisil(
          idDestino: widget.destinatarioId!.toString(),
          titulo: '💬 ${widget.miNombre}',
          mensaje: preview,
          urgente: false,
          sonido: 'movil_chat_central',
          canalAndroidId: MotorNotificaciones.canalChatMovilId,
          data: {'tipo': 'chat_movil'},
        );
      } else {
        // No-central sin destinatario específico → push a la central
        MotorNotificaciones.dispararACentral(
          titulo: '💬 ${widget.miNombre}',
          mensaje: preview,
          urgente: false,
          sonido: 'central_chat',
          canalAndroidId: MotorNotificaciones.canalChatCentralId,
        );
      }
    } else if (widget.destinatarioId != null) {
      // Central escribe → push al destinatario (móvil o local)
      MotorNotificaciones.dispararMisil(
        idDestino: widget.destinatarioId!.toString(),
        titulo: '💬 Central',
        mensaje: preview,
        urgente: false,
        sonido: 'movil_chat_central',
        canalAndroidId: MotorNotificaciones.canalChatMovilId,
        data: {'tipo': 'chat_movil'},
      );
    }
  }

  // -----------------------------------------------------------------------
  // IMÁGENES
  // -----------------------------------------------------------------------
  Future<void> _enviarImagen(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? imagen =
        await picker.pickImage(source: source, imageQuality: 50);
    if (imagen == null) return;

    setState(() => _subiendoImagen = true);
    try {
      final bytes = await imagen.readAsBytes();
      final ext = imagen.path.split('.').last.toLowerCase();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final filePath = '${widget.salaId}/$fileName';

      await Supabase.instance.client.storage
          .from('chat_images')
          .uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(contentType: 'image/$ext'),
          );

      final imageUrl = Supabase.instance.client.storage
          .from('chat_images')
          .getPublicUrl(filePath);

      await Supabase.instance.client.from('mensajes').insert({
        'sala_id': widget.salaId,
        'emisor_id': widget.miId,
        'emisor_nombre': widget.miNombre,
        'mensaje': '📷 Imagen adjunta',
        'image_url': imageUrl,
      });

      _enviarPush('📷 Imagen adjunta');
      await _encenderAlarmaDestino();
      await _registrarLectura();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir imagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _subiendoImagen = false);
    }
  }

  // -----------------------------------------------------------------------
  // UTILIDADES
  // -----------------------------------------------------------------------
  String _formatHora(String? isoStr) {
    if (isoStr == null) return '';
    try {
      final dt = DateTime.parse(isoStr).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  /// ✓ gris = enviado (en BD). ✓✓ verde = visto (el otro abrió el chat después).
  Widget _buildChecks(String? createdAt, Color baseColor) {
    bool visto = false;
    if (_leidoHastaPorOtro != null && createdAt != null) {
      final msgDt = DateTime.tryParse(createdAt)?.toLocal();
      if (msgDt != null) {
        visto = !_leidoHastaPorOtro!.isBefore(msgDt);
      }
    }
    final color = visto ? const Color(0xff3AF500) : baseColor;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.check, size: 11, color: color),
        if (visto)
          Positioned(
            left: 4,
            child: Icon(Icons.check, size: 11, color: color),
          ),
      ],
    );
  }

  Widget _buildBurbuja(Map<String, dynamic> m) {
    final emisorId = (m['emisor_id'] as num?)?.toInt();
    final esBot = emisorId == -1;
    final soyYo = !esBot && emisorId == widget.miId;
    final hora = _formatHora(m['created_at']?.toString());
    final tieneImagen = m['image_url'] != null;
    final textoMensaje = m['mensaje']?.toString() ?? '';
    // Si hay imagen y el texto es solo el placeholder, no duplicar
    final mostrarTexto = textoMensaje.isNotEmpty &&
        !(tieneImagen && textoMensaje == '📷 Imagen adjunta');

    // Colores según quién habla — tema oscuro moderno
    Color bubbleColor;
    Color borderColor;
    Color textColor;
    Color timeColor;
    Color nameColor;
    List<BoxShadow> sombras;

    if (esBot) {
      bubbleColor = const Color(0xFF1E1C08);
      borderColor = const Color(0xFF5A4500);
      textColor = const Color(0xFFFFE082);
      timeColor = const Color(0xFF9A7A20);
      nameColor = const Color(0xFF4CAF50);
      sombras = [BoxShadow(color: Colors.amber.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))];
    } else if (soyYo) {
      bubbleColor = const Color(0xFF0D2E0D);
      borderColor = const Color(0xFF3AF500);
      textColor = Colors.white;
      timeColor = Colors.white38;
      nameColor = Colors.white54;
      sombras = [BoxShadow(color: const Color(0xFF3AF500).withValues(alpha: 0.18), blurRadius: 10, offset: const Offset(0, 3))];
    } else {
      bubbleColor = const Color(0xFF1E1E1E);
      borderColor = const Color(0xFF333333);
      textColor = Colors.white;
      timeColor = Colors.white38;
      nameColor = const Color(0xFF3AF500);
      sombras = [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))];
    }

    return Align(
      alignment: soyYo ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 6,
          left: soyYo ? 40 : 0,
          right: soyYo ? 0 : 40,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: soyYo ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: soyYo ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: Border.all(color: borderColor, width: 0.8),
          boxShadow: sombras,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!soyYo)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  m['emisor_nombre']?.toString() ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: nameColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            if (tieneImagen)
              Padding(
                padding: EdgeInsets.only(bottom: mostrarTexto ? 8 : 0),
                child: GestureDetector(
                  onTap: () {
                    // Vista ampliada de la imagen
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: Colors.black,
                        insetPadding: EdgeInsets.zero,
                        child: Stack(
                          children: [
                            InteractiveViewer(
                              child: Image.network(
                                m['image_url'].toString(),
                                fit: BoxFit.contain,
                              ),
                            ),
                            Positioned(
                              top: 16, right: 16,
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      m['image_url'].toString(),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              height: 120,
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF3AF500),
                                ),
                              ),
                            ),
                      errorBuilder: (_, __, ___) => Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Icon(Icons.broken_image_rounded, size: 32, color: Colors.white30),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (mostrarTexto)
              Text(
                textoMensaje,
                style: TextStyle(fontSize: 14, color: textColor, height: 1.3),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (hora.isNotEmpty)
                    Text(
                      hora,
                      style: TextStyle(fontSize: 9, color: timeColor),
                    ),
                  if (soyYo && !esBot) ...[
                    const SizedBox(width: 4),
                    _buildChecks(m['created_at']?.toString(), timeColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // PANEL VACÍO — FAQ visible cuando aún no hay mensajes
  // -----------------------------------------------------------------------
  Widget _buildPanelVacio() {
    final icono = _esCentral ? Icons.bolt : Icons.support_agent;
    final titulo = _esCentral
        ? 'Respuestas rápidas'
        : '¡Hola! Soy el Asistente de Serviexpress';
    final subtitulo = _esCentral
        ? 'Toca una opción para pre-cargarla en el campo de texto.'
        : 'Puedo responderte al instante. Para temas más complejos,\nla Central te atiende.';
    final hintAbajo = _esCentral
        ? 'O escribe tu respuesta personalizada abajo ↓'
        : 'O escribe tu pregunta directamente abajo ↓';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1A1A1A),
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(icono, size: 34, color: const Color(0xFF3AF500)),
          ),
          const SizedBox(height: 16),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white38),
          ),
          const SizedBox(height: 26),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _esCentral ? 'Respuestas rápidas' : 'Preguntas frecuentes',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.white54,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in _faqActual)
                for (final item in cat.items)
                  ActionChip(
                    label: Text(
                      item.pregunta,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF1E1E1E),
                    side: const BorderSide(color: Color(0xFF3AF500), width: 0.8),
                    onPressed: () => _seleccionarFaq(item),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hintAbajo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white24),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: Text(
          widget.titulo,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_habilitarFaq)
            IconButton(
              icon: Icon(Icons.help_outline, color: Colors.white),
              tooltip: _esCentral ? 'Respuestas rápidas' : 'Preguntas frecuentes',
              onPressed: _mostrarPanelFaq,
            ),
        ],
      ),
      body: Column(
        children: [
          // ---- LISTA DE MENSAJES ----
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _streamMensajes,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _mensajesStream.isEmpty) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF3AF500)),
                  );
                }

                if (snapshot.hasData) {
                  _mensajesStream = snapshot.data!;
                }

                final todos = [
                  ..._mensajesStream,
                  ..._mensajesAntiguos,
                ];

                if (todos.isEmpty) {
                  return _habilitarFaq
                      ? _buildPanelVacio()
                      : const Center(
                          child: Text(
                            'No hay mensajes en este chat.',
                            style: TextStyle(color: Colors.white30, fontSize: 13),
                          ),
                        );
                }

                final totalItems = todos.length + (_hayMas ? 1 : 0);

                return ListView.builder(
                  controller: _scrollCtrl,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: totalItems,
                  itemBuilder: (context, index) {
                    if (index == todos.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Center(
                          child: _cargandoMas
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF3AF500))
                              : TextButton.icon(
                                  onPressed: _cargarMas,
                                  icon: const Icon(Icons.history,
                                      size: 16, color: Colors.white38),
                                  label: const Text(
                                    'Ver mensajes anteriores',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                  ),
                                ),
                        ),
                      );
                    }
                    return _buildBurbuja(todos[index]);
                  },
                );
              },
            ),
          ),

          // ---- INDICADOR "ESCRIBIENDO..." ----
          if (_escribiendo != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF161616),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF3AF500),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_escribiendo está escribiendo...',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white38,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          // ---- BOTÓN REINICIAR CONVERSACIÓN (solo usuarios con FAQ) ----
          if (_habilitarFaq && !_esCentral)
            InkWell(
              onTap: _mostrarPanelFaq,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 7),
                color: const Color(0xFF111111),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.home_outlined, size: 13, color: Colors.white24),
                    const SizedBox(width: 6),
                    const Text(
                      'Volver al inicio · Ver preguntas frecuentes',
                      style: TextStyle(fontSize: 11, color: Colors.white24),
                    ),
                  ],
                ),
              ),
            ),

          // ---- BARRA DE ENTRADA ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
            ),
            child: Row(
              children: [
                // Botón cámara
                _subiendoImagen
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF3AF500),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.camera_alt_rounded,
                                color: Colors.white54, size: 22),
                            tooltip: 'Tomar foto',
                            onPressed: () => _enviarImagen(ImageSource.camera),
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 2),
                          IconButton(
                            icon: const Icon(Icons.photo_rounded,
                                color: Colors.white54, size: 22),
                            tooltip: 'Elegir de galería',
                            onPressed: () => _enviarImagen(ImageSource.gallery),
                            padding: const EdgeInsets.all(6),
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviar(),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Escribe aquí...',
                      hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFF232323),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Colors.white12, width: 0.8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: Color(0xFF3AF500), width: 1),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: const Color(0xff3AF500),
                  radius: 21,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.black, size: 19),
                    onPressed: _enviar,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
