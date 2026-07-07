# ServiExpress / ServiMoto — Briefing de Traspaso a Cowork

> Este documento resume meses de desarrollo hecho en una conversación de Chat con Claude. Pégalo como instrucciones del Proyecto en Cowork, o súbelo a la carpeta del proyecto, para que Claude tenga contexto real desde el primer mensaje.

---

## 1. Qué es esto

App de logística de última milla para Cúcuta, Colombia (Norte de Santander). Conecta una Central (despachador humano), Locales (negocios que piden domicilios), Móviles (motociclistas repartidores) y Clientes (registrados o invitados) para paquetería, comida, compras y mototaxi.

**Stack:** Flutter (frontend, multiplataforma) + Supabase/PostgreSQL (backend, auth propia — no Supabase Auth nativo) + OneSignal (notificaciones push) + Google Maps Platform (geocodificación, en proceso de integrar).

**Roles:** `master`, `central`, `movil`, `local`, `cliente`, `invitado` (no registrado).

---

## 2. Reglas de trabajo que Claude debe seguir

- **Antes de reescribir cualquier archivo que NO sea `central_screen.dart`, `movil_screen.dart`, o `local_screen.dart`**, pedir al usuario que lo reenvíe — puede haber cambiado fuera de esta conversación.
- **Siempre verificar balance de llaves/paréntesis** después de cada edición de un archivo `.dart` grande, antes de darlo por terminado.
- El proyecto usa **autenticación propia** (tabla `usuarios` con columna `contrasena` hasheada), no Supabase Auth — cualquier solución que asuma `auth.users`/GoTrue no aplica aquí.
- **RLS está desactivado** durante pruebas — debe activarse antes de producción real.
- Las contraseñas se hashean con una función compartida en `lib/utils/auth_helper.dart` (`hashContrasena`).

---

## 3. Conexión a Supabase

Proyecto real: **Servimoto Express 247** (`oukiofdtargjrclualgm`, región us-east-1). Si Cowork tiene el MCP de Supabase conectado, puede consultar/aplicar cambios directamente — varias piezas de esta sesión (cron jobs, funciones, columnas) ya están aplicadas **directo en producción**, no solo en archivos `.sql` sueltos.

Cron jobs activos: `archivar-servicios-cada-2h`, `levantar-suspensiones` (*/5min), `limpiar-servicios-caducados` (*/5min), `deteccion-continua-zona-cada-1min`.

---

## 4. Arquitectura y decisiones clave (para no reinventarlas)

### Embudo táctico de despacho (quién ve qué servicio y cuándo)
- **T=0**: Masters en línea (ven todo, sin importar rango/posición) + el #1 de cada paradero — ambos deben estar **completamente libres** (cero servicios activos), sin importar el cupo de su rango.
- **+2min**: ola Zonal — abre a 1km del origen (si hay coordenadas), aplicando ya el cupo real por rango.
- **+5min**: ola Global — abre a todos los conectados, mismo cupo por rango.
- El cupo múltiple (Elite=2, Leyenda=3, Master=∞) **solo aplica en las olas +2min/+5min y en Enrutar** — nunca en el turno inicial de Master/paradero.
- Regla de capacidad: Novato y Pro reciben CERO alertas si tienen un servicio activo (la reciben al terminar). Esto vive centralizado en la función SQL `moviles_elegibles_notificacion()`.
- **Detección continua** (no disparo único): un cron corre cada minuto, recalculando elegibilidad fresca — cubre tanto a quien entra al radio de 1km como a quien se conecta después.

### Candado atómico de aceptación
`tomar_servicio_candado(p_servicio_id, p_movil_id, ...)` — única función que debe usarse para asignar un servicio a un moto. Bloquea la fila del usuario (`FOR UPDATE`), valida cupo por rango, y asigna de forma atómica. **Nunca hacer un `UPDATE` directo de `movil_id`** fuera de esta función.

### Enrutar (antes "Doble Enganche")
Dos servicios pueden viajar con el mismo moto sin mezclar sus datos — se enlazan con `ruta_grupo_id` (no se fusionan en una fila). Al aceptar uno, el candado atómico asigna el compañero de ruta automáticamente si hay cupo. Disponible desde Local y Cliente, siempre visible en la tarjeta de servicio activo (botón "ENRUTAR"), no solo cuando el sistema detecta similitud.

### Rangos y beneficios
`NOVATO → PRO → ELITE → LEYENDA → MASTER`, con cupos de servicios simultáneos 1/1/2/3/∞. Mapeo debe coincidir EXACTO entre `movil_screen.dart` (`_limitePorRango`) y la función SQL `tomar_servicio_candado`.

### Numeración de servicios
- `servicios.id` = consecutivo global, lo ve Central.
- `numero_cliente`, `numero_local`, `numero_movil` = consecutivos independientes por actor, calculados vía triggers (`numeracion_por_actor.sql`). Cada uno ve solo el suyo en su propia pantalla.

### Directorio de lugares (`lugares_conocidos`)
Sistema que se autoalimenta: cada vez que un moto marca "llegué" o "finalicé" con su GPS dentro de 200m del punto reclamado, y con un mínimo de tiempo transcurrido físicamente razonable (anti-fraude), ese punto confirma/crea una entrada en el directorio. Normaliza sinónimos (condominio≈conjunto) y usa similitud de texto (`pg_trgm`) para typos. **10 confirmaciones** = confianza alta. Antes de eso, mostrar como rango de precio, no como número fijo — nunca dejar que el sistema cobre solo sin que un humano confirme.

### Roadmap de autonomía progresiva (en curso)
Fase 1 (cimientos de datos) — completada. Fase 2 (sugerencia con un toque) y Fase 3 (despacho automático) — pendientes. Pánico, disputas, KYC y suspensiones **nunca se automatizan**, por diseño, no por límite técnico.

---

## 5. Estado actual — completado y verificado

- Sistema de pánico (alerta, ubicación 24h validada, detener manualmente, auto-cierre al volver a trabajar)
- Reconexión en tiempo real anti-parpadeo en las 4 pantallas principales (Móvil, Central, Local, Cliente)
- Identidad numérica del moto (`movil##`) separada del nombre real
- Sistema de paraderos con geocercas, horarios (Memos = nocturno 4pm-11:59pm), auto-expulsión
- Suspensión con duración real (chips 1h/6h/1d/3d/semana/indefinido) + auto-expiración por cron
- Sistema de calificaciones recalculado en SQL (mediana, no promedio simple — protege contra outliers)
- Panel de Móvil rediseñado: pestañas Radar/Perfil, perfil completo (foto, correo editable, contraseña con verificación, pagos Nequi/Daviplata/Bancolombia estructurados, documentos "próximamente")
- Perfil del moto visible y enlazado en Central (completo), Local (inline + botón), Cliente registrado (sin nombre real), invitado (solo número + pagos)
- WhatsApp corregido en todos lados (bug real: usaba el número de operación en vez del teléfono real)
- Sesión real tipo Instagram/Facebook — entrada instantánea sin tocar la red, con migración automática desde el modelo viejo
- Login rediseñado (logo real, mostrar/ocultar contraseña, jerarquía visual)
- Sistema de notificaciones reconstruido: 3 olas correctamente nombradas y temporizadas, sonidos auditados contra el catálogo real, canal urgente confirmado en todos los disparos relevantes
- Autocompletado de direcciones en Central (locales registrados + coordenadas selladas), con Memos como fallback de coordenadas
- Panel de Central reorganizado: pestaña "Gestión" nueva, AppBar de 10 acciones a 3
- Formularios de Central y Local corregidos (ancho apretado en celular)
- `tipo_servicio` ahora se guarda de verdad (antes se perdía al crear el servicio) — tarjetas hablan distinto para mototaxi vs. entregas
- Archivado automático cada 2h de servicios terminados, filtro de monitor, historial completo por fecha
- Enrutar — casos completos (pedidos pendientes + sumar a moto en curso)

## 6. Pendiente

**Bloqueado en el usuario:**
- API Key de Google Maps Platform (estrategia ya decidida: Autocompletar + Geocodificación + Rutas, cuota diaria configurada, directorio propio como primer filtro)
- Sonidos disponibles en la carpeta de assets (qué hay, para qué sirve cada uno)

**Sin construir:**
- Reclutamiento de móviles más fácil (sin definir aún)

**En pausa por decisión explícita del usuario:**
- Correo electrónico / recuperación de contraseña (sin proveedor elegido todavía)
- Documentos del móvil (cédula, licencia, placa, SOAT) — verificación manual por Central, no KYC automatizado de terceros
- Portal de pagos — pasarela elegida: **Wompi** (mejor integración con Nequi, menor comisión, mejor conversión móvil). Falta confirmar RUT/registro formal del negocio, tabla de % de comisión por rango, y si el modelo semanal actual ($60.000/semana, multa $20.000) convive con el nuevo de comisión diaria o se reemplaza gradualmente.

**Bug viejo sin información para diagnosticar:**
- Pantalla negra al cancelar en tablet (ocurrió una sola vez en la prueba piloto)

---

## 7. Archivos canónicos (versión más reciente de cada uno)

Los `.dart` y `.sql` más recientes están en los outputs de la conversación de Chat — pídele al usuario que los suba a la carpeta del proyecto en Cowork, o ábrelos desde el historial de esa conversación. Los nombres de archivo coinciden con su ruta real en `lib/` del proyecto Flutter (`screens/`, `utils/`).

**Pantallas principales:** `movil_screen.dart`, `central_screen.dart`, `local_screen.dart`, `cliente_screen.dart`, `login_screen.dart`, `registro_screen.dart`, `guest_tracking_screen.dart`

**Utilidades:** `onesignal_api.dart`, `sonido_manager.dart`, `motor_rutas.dart`, `permisos_criticos.dart`, `panico_widgets.dart`, `widgets_compartidos.dart`

**Configuración:** `main.dart`, `pubspec.yaml`, `AndroidManifest.xml`

**SQL aplicado** (mayoría ya corrida directo en producción vía MCP — ver sección 3): scripts de pánico, candado atómico, registro, perfil completo, suspensión, calificaciones, motor de tarifas, directorio de lugares, elegibilidad de notificación, archivado automático, numeración por actor, detección continua zonal/global, Enrutar (`ruta_grupo_id`).

---

## 8. Cómo seguir

1. Confirma con el usuario qué archivos de la lista de arriba tiene más actualizados en su computadora vs. lo que dice este resumen.
2. Si vas a tocar `central_screen.dart`, `movil_screen.dart`, o `local_screen.dart`, puedes asumir que la versión que está en la carpeta del proyecto es la vigente — son los únicos 3 archivos exentos de pedir confirmación primero.
3. Para cualquier otro archivo, pide confirmación de que sigue vigente antes de sobreescribirlo.
4. Si tienes el MCP de Supabase conectado, verifica el estado real de la base de datos antes de asumir que algo falta — varias cosas de esta lista ya están aplicadas en producción aunque no exista un archivo `.sql` correspondiente guardado en la carpeta.
