package com.example.serviexpress_app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

class ServiMotoApp : Application() {

    companion object {
        // ── CANALES EXISTENTES ───────────────────────────────────────────────
        const val CHANNEL_ALERTA_ID         = "serviexpress_alerta_v2"
        const val CHANNEL_ZONA_ID           = "serviexpress_zona_v2"
        const val CHANNEL_PANICO_ID         = "serviexpress_panico_v1"
        const val CHANNEL_ONESIGNAL_DEFAULT = "OneSignal_channel_id"

        // ── CANALES NUEVOS ───────────────────────────────────────────────────
        // Masters (rango MASTER) — sonido más suave, reciben muchas alertas
        const val CHANNEL_MASTER_ID         = "serviexpress_master_v1"
        // Aviso de inactividad 5h45min al móvil
        const val CHANNEL_INACTIVIDAD_ID    = "serviexpress_inactividad_v1"
        // Chat: móvil recibe mensaje de central o cliente
        const val CHANNEL_CHAT_MOVIL_ID     = "serviexpress_chat_movil_v1"
        // Chat: central recibe mensaje de móvil, local o cliente
        const val CHANNEL_CHAT_CENTRAL_ID   = "serviexpress_chat_central_v1"
        // Chat: local recibe mensaje
        const val CHANNEL_CHAT_LOCAL_ID     = "serviexpress_chat_local_v1"
        // Central: nueva cotización recibida
        const val CHANNEL_COTIZACION_ID     = "serviexpress_cotizacion_v1"
        // Central: radar activo
        const val CHANNEL_RADAR_ID          = "serviexpress_radar_v1"
        // Central: demora reportada
        const val CHANNEL_DEMORA_ID         = "serviexpress_demora_v1"
        // Central: problema reportado
        const val CHANNEL_PROBLEMA_ID       = "serviexpress_problema_v1"
        // Central: servicio caducado
        const val CHANNEL_CADUCADO_ID       = "serviexpress_caducado_v1"
        // Central: servicio cancelado
        const val CHANNEL_CANCELADO_ID      = "serviexpress_cancelado_v1"
        // FN / Local / Cliente: respuesta de cotización
        const val CHANNEL_FN_COTIZACION_ID  = "serviexpress_fn_cotizacion_v1"
    }

    override fun onCreate() {
        super.onCreate()
        registrarCanalesNotificacion()
    }

    private fun uri(nombre: String): Uri =
        Uri.parse("android.resource://$packageName/raw/$nombre")

    private fun audioAttr(): AudioAttributes = AudioAttributes.Builder()
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
        .build()

    private fun crearCanal(
        id: String,
        nombre: String,
        descripcion: String,
        importancia: Int,
        sonidoUri: Uri,
        vibracion: Boolean = true,
        luces: Boolean = true,
    ): NotificationChannel = NotificationChannel(id, nombre, importancia).apply {
        this.description = descripcion
        setSound(sonidoUri, audioAttr())
        enableVibration(vibracion)
        enableLights(luces)
        setShowBadge(true)
        lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
    }

    private fun registrarCanalesNotificacion() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        // Limpiar canales obsoletos (Android bloquea cambios de sonido en canales ya registrados)
        listOf(
            CHANNEL_ONESIGNAL_DEFAULT,
            "a26379a9-df0b-4d1e-8679-20ee949f7c59",
            "63802a9e-afed-4b02-83b8-55376cea49f0"
        ).forEach { nm.deleteNotificationChannel(it) }

        val HI  = NotificationManager.IMPORTANCE_HIGH
        val MED = NotificationManager.IMPORTANCE_DEFAULT

        listOf(
            // ── ALERTAS CRÍTICAS ────────────────────────────────────────────
            crearCanal(CHANNEL_ALERTA_ID,        "Alertas de Servicio",     "Avisos urgentes de nuevos servicios.",          HI,  uri("alerta")),
            crearCanal(CHANNEL_ZONA_ID,           "Alertas de Proximidad",   "Servicios en tu zona o global.",                HI,  uri("alerta")),
            crearCanal(CHANNEL_PANICO_ID,         "Alertas de Pánico",       "Emergencias urgentes (pánico).",                HI,  uri("panico")),
            // Recrea el default de OneSignal fresco antes de que el SDK lo registre sin sonido
            crearCanal(CHANNEL_ONESIGNAL_DEFAULT, "Notificaciones",          "Notificaciones generales de ServiExpress.",     HI,  uri("alerta")),

            // ── MASTERS ─────────────────────────────────────────────────────
            crearCanal(CHANNEL_MASTER_ID,         "Alertas Master",          "Servicios disponibles — rango Master.",         HI,  uri("master")),

            // ── INACTIVIDAD ─────────────────────────────────────────────────
            crearCanal(CHANNEL_INACTIVIDAD_ID,    "Aviso de Inactividad",    "Recordatorio de sesión prolongada.",            MED, uri("movil_inactividad")),

            // ── CHAT ────────────────────────────────────────────────────────
            crearCanal(CHANNEL_CHAT_MOVIL_ID,     "Chat — Móvil",            "Mensajes de chat recibidos por el móvil.",      MED, uri("movil_chat_central")),
            crearCanal(CHANNEL_CHAT_CENTRAL_ID,   "Chat — Central",          "Mensajes de chat recibidos por la central.",    MED, uri("central_chat")),
            crearCanal(CHANNEL_CHAT_LOCAL_ID,     "Chat — Local",            "Mensajes de chat recibidos por el local.",      MED, uri("local_chat")),

            // ── CENTRAL: EVENTOS OPERATIVOS ─────────────────────────────────
            crearCanal(CHANNEL_COTIZACION_ID,     "Cotización",              "Nueva cotización recibida.",                    HI,  uri("central_cotizacion")),
            crearCanal(CHANNEL_RADAR_ID,          "Radar",                   "Alerta de radar activo.",                       HI,  uri("central_radar")),
            crearCanal(CHANNEL_DEMORA_ID,         "Demora",                  "Demora reportada en servicio.",                 HI,  uri("central_demora")),
            crearCanal(CHANNEL_PROBLEMA_ID,       "Problema",                "Problema reportado en servicio.",               HI,  uri("central_problema")),
            crearCanal(CHANNEL_CADUCADO_ID,       "Caducado",                "Servicio caducado sin asignar.",                HI,  uri("central_caducado")),
            crearCanal(CHANNEL_CANCELADO_ID,      "Cancelado",               "Servicio cancelado.",                           HI,  uri("central_cancelado")),

            // ── FN / LOCAL / CLIENTE ────────────────────────────────────────
            crearCanal(CHANNEL_FN_COTIZACION_ID,  "Respuesta Cotización",    "Central respondió tu cotización.",              MED, uri("fn_cotizacion")),
        ).forEach { nm.createNotificationChannel(it) }
    }
}
