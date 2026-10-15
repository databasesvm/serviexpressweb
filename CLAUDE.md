Para Servicios de ServiExpress (No aplica para FN)servicios y notificaciones de 30s Master, 30 segundos despues al #1 Paradero, 30s mas al cercano 1km, 30 segundos mas a todos los conectados siempre y cuando su rango permita llevar mas servicios
 
30s Master, 30s después al #1 paradero, 30s después al más cercano 1km, 30 segundos después a todos los disponibles respetando los rangos y todo lo que ya está. En total serían 2 minutos para que lleguen hasta todos los conectados

Al liberar el servicio se reinicia el servicio y las notificaciones

Con los servicios de FN La Cascada es asi:
T=0: Push a Masters (aceptan voluntariamente). 
T+30s: OFERTA (nunca se auto-asigna) al móvil no-Master más cercano a la sede (o al #1 del paradero si la central eligió modo paradero). Recibe el aviso y ve la tarjeta; tiene el "tiempo para aceptar" de Gestión. Si no lo acepta pasa a FASE 3/4, SIN sanción.
T+60s: Push a no-Masters dentro de 2km (excl. fase2)
T+90s: Push al resto global

REGLA GENERAL: ningún servicio (SE, FN ni paradero) se auto-asigna. Siempre es una oferta que el móvil acepta voluntariamente. La única excepción es la asignación directa que hace a propósito la central, el local o la sede.
Los tiempos de todas las fases se configuran en Gestión (central).


Con los servicios SE Debe funcionar asi:

Con los servicios SE Debe funcionar asi:

Fase 1: T=0: Push a Masters (aceptan voluntariamente).
Fase 2: T+30s: #1 Paradero. Si acepta, se acaba la cascada. Si no lo acepta, este movil de #1 lo expulsa del paradero y pasa a Fase 3/4 Si no hay moviles en paradero lo salta — el servicio queda para FASE 3/4
Fase 3: T+60s: Push a no-Masters dentro de 1km Si nadie lo acepta pasa a F4
Fase 4: T+90s: Push al resto global

Esto ocurre con todos los servicios creados de SE bien sea por la central en todos sus opciones, local en todas sus opciones, cliente en todas sus opciones.


DISEÑO OFICIAL DE LA APP (todas las pantallas EXCEPTO FN)
Kit único en lib/utils/tema_serviexpress.dart. Toda pantalla nueva o rediseñada debe usarlo; no inventar estilos aparte.
- Fondo negro #0D0D0D (kFondoSE) con tarjetas claras (blancas) redondeadas (radio 18) y sombra suave del color de acento.
- Un color por tipo de servicio, igual en todas las pantallas (EstiloServicio.deTipo):
  Mototaxi verde marca #3AF500 (íconos sobre blanco en #1E8E00), Paquetería azul #2F80ED, Comida naranja #FF8A00, Compras morado #9B51E0.
- Encabezado con ícono grande + título + frase corta (EncabezadoSE).
- Tarjetas con número de paso, línea de color bajo el título (BloqueSE); tarjetas de servicio con franja del color (TarjetaSE franja:true); etiquetas de color (EtiquetaSE).
- Campos gris claro #F3F4F6 sin borde, radio 12, foco del color del servicio (temaFormularioSE).
- Botón principal grande (54 px) del color del servicio, fijo abajo en formularios; se esconde con el teclado (BotonPrincipalSE / ScaffoldServicioSE).
- Responsive: márgenes compactos en celulares < 380 px; contenido centrado con ancho máximo 560 px en PC (ContenidoSE); mosaicos 2 columnas en celular / 4 en ancho (GrillaServiciosSE).
- Texto de cotización: "La Central te dice el precio antes de enviar el Móvil."
REGLAS AL APLICARLO:
- Solo cambia la APARIENCIA, nunca la lógica.
- Móvil: la tarjeta de servicio debe mostrar/ocultar EXACTAMENTE la misma información que hoy (el móvil no ve la info completa antes de aceptar). Mantener tamaño del botón ACEPTAR, barra de tiempo y colores de alerta (rojo del turno #1, etc.).
- Central: panel de control y monitor conservan su diseño compacto; el kit se aplica a formularios y ventanas.
- FN (sede, supervisor, panel FN, facturación y red de direcciones FN) queda FUERA.