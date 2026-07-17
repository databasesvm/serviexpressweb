# Especificación: Panel de Farmanorte (FN) — ServiExpress

## Contexto del proyecto

ServiExpress es una app Flutter + Supabase con sistema multi-rol (`master`, `central`, `movil`, `local`, `cliente`, `invitado`). Se necesita crear un **nuevo tipo de panel/rol: `sede_fn`** (o similar), para la franquicia de farmacias **Farmanorte**, que tiene múltiples sedes en Cúcuta, Los Patios y Villa del Rosario.

El panel es **similar al panel del local**, pero con finalidad distinta: cada sede de FN solicita servicios de domicilio **siempre pasando por cotización de la central** (similar al botón de la central "crear servicio de Farmanorte", pero iniciado por la propia sede).

### Cómo funciona hoy (proceso que se reemplaza)

Actualmente todo se maneja por un grupo de WhatsApp donde están todas las sedes aliadas, sus coordinadores y supervisores de ventas. Por ahí escriben solicitando, ejemplo:

> — Farmanorte 32: "Buenas cuanto sale recoger fn 32 y entregar CONDOMINIO PALMA DORADA CASA 49 efectivo traer 250.000 por favor"
> — Farmanorte 107: "Calle 7 # 12-119 urb Santa María del Rosario, casa R15, La Parada Villa del Rosario a esta dirección"

La central responde con el precio, ellos confirman y se envía el móvil. Los jefes/supervisores auditan el movimiento porque ven todo el grupo. **El panel debe replicar y superar esa dinámica**: solicitud estructurada, cotización, confirmación, trazabilidad y auditoría para sus supervisores — sin llamadas ni WhatsApp.

---

## 1. Usuarios y roles del lado de Farmanorte

- **Sede FN**: cada sede tiene su propio usuario/panel identificado por un **código de sede** (ej: `FN293`). Todos los servicios que cree quedan bajo su código. Crea servicios, aprueba/rechaza cotizaciones, ve su historial.
- **Supervisor FN (auditor)**: usuario para coordinadores y supervisores de ventas de Farmanorte. **Solo lectura** (no crea servicios). Puede:
  - Ver en tiempo real los servicios activos de **todas las sedes** (o de las sedes que tenga asignadas), con su estado en vivo — el equivalente digital a "ver el grupo de WhatsApp".
  - Ver el historial consolidado de todas las sedes, con los mismos filtros y exportaciones.
  - Ver la auditoría de ediciones de facturas (quién cambió qué y cuándo).
  - Dashboard de consumo: total de domicilios por sede, por periodo, valor acumulado, comparativos.
  - Nota: esta auditoría es **para ellos** — la central ya tiene la suya propia.
- **Gestión de sedes — YA EXISTE PARCIALMENTE**: la central ya tiene un **panel de Farmanorte** donde añade las sedes de FN, y colocó **manualmente las coordenadas de Google Maps** de las sedes registradas. NO duplicar esta gestión: **reutilizar y extender ese panel existente**. **Regla fija: las sedes de FN SIEMPRE son creadas e ingresadas al sistema por la central** — FN nunca crea ni registra sedes en el catálogo. Los usuarios `sede_fn` deben vincularse a esos registros de sede ya creados. Campos a asegurar/extender: nombre, código, dirección, teléfono, coordenadas/URL de Maps (ya existentes) y lo nuevo que se necesite (credenciales del usuario de la sede, estado activo, etc.). Añadir además un campo de **tipo de sede**: *solicitante* (tiene usuario y panel) o *solo recogida* (validada únicamente como punto de recogida, sin usuario).
- **Cobertura (regla por recogida, no solo por solicitante)**: más adelante FN podría querer registrar sedes que están **fuera de la cobertura de la empresa**. Añadir a cada sede un campo/indicador de cobertura (dentro / fuera / por evaluar). La cobertura se evalúa **por cada recogida y el destino del servicio**, no solo por quién lo solicita:
  - **Caso clave — solicitante en cobertura + recogida fuera de cobertura o desconocida**: el servicio NO se bloquea (hoy por WhatsApp igual lo pedirían y la central decide). Flujo:
    1. Al añadir esa recogida, la sede solicitante ve un aviso: *"esta recogida está fuera de cobertura / no registrada — la cotización puede tener recargo, demorar más o ser rechazada"*.
    2. La solicitud llega a la central con **alerta prominente** marcando exactamente cuál(es) recogida(s) están fuera de cobertura o son desconocidas, con el minimapa para dimensionar el trayecto.
    3. La central decide manualmente: cotiza con el recargo que considere, o rechaza con motivo "fuera de cobertura".
    4. Si el servicio avanza, **el móvil NO ve ninguna marca de "fuera de cobertura"**: en su card la recogida aparece como cualquier otra, con su ubicación GPS. La condición de cobertura es información interna de la central (y del historial/auditoría), nunca del móvil.
  - **Recogida en sede FN no habitual/no registrada**: la sede solicitante tiene la **obligación de indicar dónde queda** esa sede de recogida, con **al menos UNA** de estas opciones: link/coordenadas GPS (lo ideal), dirección escrita, o como mínimo una descripción de dónde queda. El formulario no permite continuar sin ninguna de las tres. Para ingresarla usa el **mismo formulario del panel de SEDES FN ya creado** (nombre, código, ubicación y todos los datos necesarios para el servicio). Si no hay GPS, el minimapa de la central la muestra como "pendiente de ubicar" y la central ve la dirección/descripción tal cual (y puede colocarle las coordenadas al validarla). Esa sede entra como **"sede de recogida pendiente de validación"**. Luego la central decide si la **valida para futuras recogidas** (queda disponible en el selector para todas las sedes) — pero esa validación **NUNCA la convierte en sede solicitante**: los usuarios solicitantes solo los crea la central. Si no la valida, queda únicamente como dato histórico de ese servicio.
  - Los servicios con recogidas fuera de cobertura o pendientes de validación **nunca entran al tarifario automático**: siempre cotización manual.

## 2. Creación del servicio (formulario de la sede FN)

La sede llena TODOS los datos del servicio para quitarle fricción y protocolo al móvil:

- **Sede solicitante** (autocompletada según el usuario logueado).
- **Recogidas** (una o varias):
  - **Selección de una o más sedes FN** como puntos de recogida (selector de sedes registradas, con su ubicación ya guardada).
  - **Recogida en sede FN no habitual/no registrada**: se ingresa con el mismo formulario del panel de SEDES FN — nombre, código y **ubicación: link GPS, dirección escrita o al menos una descripción de dónde queda (mínimo una de las tres, obligatoria)** — y entra como sede de recogida pendiente de validación por la central (ver regla de cobertura en la sección 1).
  - **Compra de producto en otra droguería/farmacia externa**: opción de añadir como recogida una farmacia/droguería que no es FN, donde el móvil debe **comprar un producto** (nombre del establecimiento, ubicación/URL, producto a comprar, valor aproximado).
- **¿Es con datáfono?** (sí/no).
- **Tipo de entrega**:
  - Solo entregar el producto.
  - Hay que **pagar el producto** (a veces la compra supera el saldo del móvil y le toca ir, regresar y pagar la factura — este dato es crítico para que el móvil se prepare).
- **Datos de la factura** (número, valor, etc.).
- **Instrucciones adicionales** (texto libre).

Toda esta información debe aparecer **completa para la central y para el móvil**.

## 3. Flujo del servicio (estados)

1. **FN crea el servicio** con toda la información → llega a la **central**.
2. **La central coloca el precio** y envía la **cotización** a la sede que solicitó.
   - **Minimapa para cotizar (importante)**: en la vista de cotización de la central debe haber un **botón que abra un minimapa** (o algo igual de práctico) mostrando la(s) sede(s) de recogida con sus coordenadas ya registradas, las recogidas externas (droguerías) y el destino de entrega. Objetivo: que la central se ubique rápidamente sin tener que recordar dónde queda cada sede ni buscar en otra app, y pueda dar la **cotización correcta** de un vistazo. Extra útil: mostrar distancia estimada del trayecto como referencia.
   - La cotización se cuadra **manualmente** por la central en la primera fase. Nota de negocio: hay tarifas de convenio en horario **7:00 am – 10:59 pm**; fuera de ese horario el precio sube **$2.000–$3.000**. El precio depende de la combinación de recogidas (no es lo mismo FN X → Barrio X que FN X → Barrio X con recogida en otra FN X).
   - **Tarifario automático (evolutivo, NO descartado)**: las sedes más frecuentes casi siempre piden a los mismos lugares o similares, así que el sistema debe **aprender de las cotizaciones históricas por ruta** (sede + combinación de recogidas + destino + franja horaria). Fases: (1) todo manual, guardando cada cotización como dato; (2) sugerencia de precio a la central para rutas ya conocidas, la central confirma con un tap; (3) para rutas frecuentes y consolidadas dentro del horario de convenio, cotización automática instantánea a la sede, con opción de la central de intervenir/ajustar. Fuera del horario de convenio (11:00 pm – 6:59 am) siempre se cuadra manualmente, igual que cualquier servicio con recogidas fuera de cobertura o pendientes de validación. Diseñar el esquema de datos desde el inicio pensando en esto (tabla de rutas/tarifas aprendidas).
3. **La sede FN aprueba o rechaza** la cotización:
   - **Si aprueba**: el servicio pasa a solicitar móvil, tal cual funciona con el local. El turno le llega a los móviles **con el tag de FN**.
   - **Si rechaza**: aparece un modal "**¿Por qué rechazas la cotización?**" con:
     - Opciones predefinidas de motivo (ej: precio muy alto, ya no se necesita, error en los datos, otro).
     - Opción de **renegociar**: la sede coloca un **precio sugerido** y lo envía a la central. Si la central aprueba el precio sugerido, el servicio se envía al radar de FN (solicitar móvil). Si la central lo rechaza, puede contraofertar o cerrar el servicio.
4. **Móvil toma el servicio**: el card muestra toda la información (recogidas con ubicación, compras en farmacias externas, datáfono, si debe pagar producto, instrucciones). **El móvil no ve marcas de cobertura**: todas las recogidas se le muestran igual, con su ubicación GPS.
5. **Creación automática de la factura para el móvil** (solo cuando el servicio lo pidió FN desde su panel): cuando el móvil presiona el botón **"Llegué a la sede"** o **"Recogiendo"**, la factura se **crea automáticamente** con los datos que la sede FN ya llenó (número de factura, valor, etc.). El móvil no digita nada: solo confirma o ajusta si hay diferencia.
   - **Aviso de confianza al móvil**: como el móvil está acostumbrado al método anterior (reportar la factura él mismo), el sistema debe **avisarle claramente** que la factura ya fue generada/cargada automáticamente con los datos de la sede — ej. un banner o mensaje en el card tipo "✓ Factura #____ cargada automáticamente por FN293" — para que se sienta seguro de que no le falta ningún paso.

### ⚠️ Doble origen del servicio — comportamiento distinto

| Origen del servicio | Reporte de factura |
|---|---|
| **Creado por la CENTRAL** (botón existente de crear servicio Farmanorte) | Funciona **exactamente como ya está implementado**: el móvil reporta la factura manualmente. No se toca este flujo. |
| **Creado por la SEDE FN** desde su panel | La factura se genera automáticamente con los datos de FN al presionar "Llegué a la sede"/"Recogiendo", con el aviso de confianza al móvil. |

El sistema debe distinguir el origen del servicio y aplicar el flujo correspondiente sin romper lo existente.

## 4. Recogidas adicionales después de solicitar (re-cotización)

- La sede FN **NO puede editar las recogidas** después de pedir el servicio.
- Lo que SÍ puede hacer es **añadir una recogida adicional a un servicio activo**, y eso dispara una **nueva cotización de ese mismo servicio**.
  - Ejemplo: FN293 pide "recoger en FN82 y llevar a Tamarindo Contemporáneo". Se cotiza, se aprueba y se envía al radar. Minutos después se da cuenta de que también debe pasar por FN107. Al añadir esa recogida, **el mismo servicio vuelve a cotizarse** (la central pone el nuevo precio o el adicional, la sede aprueba, y el servicio continúa con la recogida agregada).
  - La central y el móvil deben ver claramente que el servicio fue **modificado y re-cotizado** (recogida nueva resaltada, nuevo valor).

## 5. Cancelación y reporte de problemas

- La sede FN **puede cancelar el servicio solo durante los primeros 5 minutos** después de aprobado.
- **Después de 5 minutos NO puede cancelar**: en su lugar debe **reportar un problema** con el servicio para que la central lo atienda.
  - Razón: evitar que por apuro cancelen cuando el móvil ya va llegando. Pero puede pasar que el cliente final ya no quiera el producto (frecuente cuando el cliente paga en efectivo al recibir), y para eso está el reporte de problema.
- El reporte de problema debe notificar a la central en tiempo real con el motivo.

## 6. Trazabilidad en vivo para la sede (para que NO llamen a la central)

La sede (y el supervisor FN) debe ver el estado del servicio en tiempo real, identificando al móvil asignado **por su número — "Móvil ##" (ej: "Móvil 07") — NUNCA por el nombre personal del conductor**. Regla general: en todas las vistas del lado de FN (sede, supervisor, historial, exportes) el móvil siempre se muestra como "Móvil ##":

**en cotización → cotizado → aprobado → buscando móvil → móvil asignado → móvil en camino a la sede → en recogida (móvil en sede / recogiendo producto) → en ruta → entregado**

El objetivo explícito es que Farmanorte nunca necesite llamar a la central para preguntar "¿dónde va el domicilio?".

### Gestión de expectativas de tiempo — el problema del "¿demora? ¿ya viene?"

Contexto real: la base principal de la empresa está en **Trapiches**. Hay **2 sedes FN cercanas** donde el móvil llega en **menos de 5 minutos** (excepto en momentos de alta demanda); a las demás sedes de FN en Cúcuta el móvil demora **mínimo 15 minutos** (más si el móvil conduce despacio, eso depende de cada quien). Aun así, a los 2 minutos de pedir ya preguntan "¿demora?", "¿ya viene en camino?", o piden todo "urgente" — y el móvil demora lo que deba demorar porque **la seguridad es primero**. La razón real detrás de la pregunta (confesada por ellos): saber si los móviles están ocupados con otro domicilio para buscar otras opciones.

El sistema ataca esto con **gestión de expectativas e información**, no con velocidad:

- **ETA mínimo comunicado de 15 minutos (piso configurable por sede)**: al asignarse el móvil, la sede ve *"Tiempo estimado de llegada a tu sede: mínimo 15 min"* con un **contador visible**. Cada sede tiene un campo `eta_base` en el catálogo (editable solo por la central); para las 2 sedes cercanas a la base puede configurarse un piso menor (ej. 10 min) o dejarse en 15 para subprometer y sobreentregar. **Importante: es gestión de expectativa, NO un retraso artificial** — el móvil sale y llega como siempre; si llega en 5 minutos, mejor.
- **El contador arranca en "móvil asignado"**: la fase "buscando móvil" depende de la demanda y no cuenta dentro del ETA; la UI debe dejarlo claro.
- **Toggle de "Alta demanda" controlado por la central**: la central tiene un botón toggle en su panel. Al activarlo, TODAS las sedes FN ven un banner claro en el formulario de creación y en sus servicios activos: *"⚠ Alta demanda: habrá demora en asignar y realizar los servicios"*. Esto anticipa la queja: se les avisó desde el principio y aun así decidieron solicitar. Cada servicio creado mientras el toggle está activo queda **marcado con el sello "solicitado bajo alta demanda"** (visible en el detalle del servicio y en el historial) — es el comprobante ante cualquier reclamo posterior de demora. Al desactivar el toggle, el banner desaparece para todos en tiempo real.
- **Sin "urgente" ni "prioritario" — regla fija de negocio**: el formulario NO incluye opción de urgencia y NO existe ningún tipo de servicio prioritario, ni pagado ni gratuito. **Todos los servicios son y serán iguales siempre**, y se atienden por su orden.
- **Registro del tiempo real de llegada**: cada servicio guarda la hora de asignación del móvil y la hora de "Llegué a la sede". El historial y el dashboard del supervisor FN muestran el **tiempo promedio de llegada por sede** — la prueba con datos de que se cumple, el mejor antídoto contra la percepción de demora.

Con el estado "móvil en camino a la sede" + ETA con contador + el toggle de alta demanda, la pregunta "¿ya viene?" queda respondida en pantalla antes de que la hagan — y si reclaman demora en alta demanda, el sello del servicio prueba que fueron avisados.

## 7. Edición de factura (post-servicio, solo sobre el historial)

- Esta edición es **sobre la factura que queda montada en el historial**, NO para editar el servicio después de solicitado (eso está cubierto en la sección 4 con la re-cotización).
- Casos: se equivocaron en el valor/número, o el precio cambió a última hora.
- **Quién puede editar**: la sede FN **y también la central** (la central puede ver y editar las facturas del historial de FN).
- Todo cambio queda **registrado con auditoría** (quién cambió — sede o central —, cuándo, valor anterior → valor nuevo), visible para la central y para el supervisor FN.

## 8. Historial / conciliación de facturación

Farmanorte necesita un historial que les sirva como **soporte del gasto de domicilios** que le pagan a ServiExpress:

- Listado de todos los servicios de la sede; el **supervisor FN** ve el consolidado de todas las sedes; **la central también puede ver y editar** este historial.
- **Filtros**: por fecha (rango), número de factura, sede, estado, valor, móvil, etc.
- **Agrupación** (por día, semana, quincena, mes, sede).
- **Exportación/descarga** en un formato que les facilite comparar con las facturas físicas y reportarlas: **Excel/CSV y PDF** (el PDF puede funcionar como una "relación de cobro" con totales por periodo/sede).
- Cada registro debe mostrar: fecha/hora, código de sede, número de factura, valor del domicilio, valor del producto (si aplica), recogidas, número del móvil que lo hizo (Móvil ##), tiempo de llegada del móvil a la sede, estado final, y marca de si fue editado (con enlace a la auditoría).

## 9. Requisitos transversales

- **Tiempo real**: usar los patrones existentes del proyecto (Supabase Realtime / StreamController / lógica de reconexión WebSocket ya implementada) para que cotizaciones, aprobaciones, estados y turnos fluyan sin recargar.
- **Notificaciones/sonido**: reutilizar el sistema de sonido existente para avisar a la central cuando llega una solicitud FN, a la sede cuando llega la cotización o cambia el estado, y al móvil cuando le llega el turno con tag FN.
- El panel debe ser **muy práctico** para las tres partes: sede FN, central y móvil. La idea es que todo fluya.

## 10. Propuesta de valor (por qué a FN le conviene — debe reflejarse en el diseño)

El sistema debe ser una propuesta difícil de rechazar para Farmanorte:

- **Para las sedes FN**: piden en segundos sin escribir párrafos en WhatsApp, precio claro antes de confirmar, trazabilidad en vivo con tiempo estimado de llegada y contador (sin tener que llamar ni preguntar "¿ya viene?"), historial que les sirve de soporte contable listo para descargar y conciliar con facturas físicas.
- **Para sus supervisores/coordinadores**: visibilidad total en tiempo real de todas las sedes (mejor que leer un grupo de WhatsApp), auditoría de cambios, reportes consolidados por periodo y por sede para controlar el gasto.
- **Para la central**: solicitudes estructuradas y completas (adiós interpretar mensajes), control total del precio (cotización manual con convenio 7:00am–10:59pm y recargo nocturno), menos llamadas, historial editable y auditado para resolver disputas rápido.
- **Para el móvil**: card con toda la información desde el inicio (recogidas ubicadas, si hay datáfono, si debe pagar producto), factura auto-creada al presionar "Llegué a la sede/Recogiendo" con aviso claro de que ya quedó cargada — cero fricción, cero digitación y sin dudas de si le falta un paso.

---

## Ideas adicionales sugeridas (a evaluar)

1. **Plantillas de servicio frecuente**: guardar combinaciones frecuentes (recogidas + condiciones) para crear en 2 taps. Combinan muy bien con el tarifario por rutas aprendidas: plantilla + ruta conocida = cotización casi instantánea dentro del horario de convenio.
2. **Tarifario por rutas aprendidas**: ya incluido en el flujo principal (sección 3) como evolución por fases — asegurarse de que el esquema de datos lo soporte desde el día uno.
3. **Consecutivo interno por sede**: cada servicio con un número tipo `FN293-0045` para que su contabilidad lo cruce fácil con las facturas físicas.
4. **Corte automático quincenal/mensual**: generar automáticamente el reporte consolidado del periodo listo para descargar.
5. **Validación anti-duplicados**: alertar si la misma sede crea dos servicios con el mismo número de factura.
6. **Timeout de renegociación**: si la central no responde a un precio sugerido en X minutos, notificar/escalar para que el servicio no quede en limbo.
7. **Adjuntar foto de la factura** (opcional) al crear el servicio o al editarla en el historial, como soporte adicional.
8. **Distancia como insumo del tarifario aprendido**: como las sedes ya tienen coordenadas, el sistema puede calcular la distancia real del trayecto (recogidas → destino) y usarla tanto en el minimapa de la central como en el aprendizaje de tarifas por ruta.
9. **Indicador de horario de convenio en el formulario**: mostrarle a la sede si está pidiendo dentro del horario de convenio (7:00am–10:59pm) o fuera de él, para que sepa de antemano que el precio será mayor.

---

## Instrucción para la implementación

Antes de escribir código: revisar cómo está implementado el panel del **local**, el flujo de **cotización de la central** y el **panel de Farmanorte que ya existe en la central** (donde ya están registradas las sedes con sus coordenadas de Google Maps), y reutilizar al máximo esos componentes, tablas y patrones (roles, RLS en Supabase, StreamControllers, sonidos, cards del móvil). Proponer primero el esquema de base de datos (tablas nuevas/campos nuevos, estados, tabla de auditoría de facturas, tabla de recogidas por servicio con soporte de re-cotización, y en el catálogo de sedes los campos de tipo de sede, estado de validación, cobertura y `eta_base`) y el flujo de pantallas de los tres roles (sede FN, supervisor FN, y las vistas nuevas en central y móvil), para validarlo antes de implementar.
