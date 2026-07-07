package com.example.serviexpress_app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

class ServiMotoApp : Application() {

    companion object {
        // v2: IDs nuevos — garantizan que Android crea el canal FRESCO con
        // alerta.mp3. Los IDs viejos (a26379a9 / 63802a9e) quedaron sin sonido
        // porque Android bloquea cambios en canales ya registrados.
        const val CHANNEL_ALERTA_ID = "serviexpress_alerta_v2"
        const val CHANNEL_ZONA_ID   = "serviexpress_zona_v2"
        // Canal exclusivo de pánico — reproduce panico.mp3
        const val CHANNEL_PANICO_ID = "serviexpress_panico_v1"
        // Canal por defecto de OneSignal (Dashboard y pushes sin canal explícito)
        const val CHANNEL_ONESIGNAL_DEFAULT = "OneSignal_channel_id"
    }

    override fun onCreate() {
        super.onCreate()
        registrarCanalesNotificacion()
    }

    private fun registrarCanalesNotificacion() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

        // URI → res/raw/alerta.mp3 (sin extensión)
        val alertaUri: Uri = Uri.parse("android.resource://$packageName/raw/alerta")
        val audioAttr: AudioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()

        // IMPORTANTE: Android bloquea cambios de sonido en canales ya registrados.
        // Solución: borrar canales previos antes de recrearlos con alerta.mp3.
        // Los canales v2 son IDs nuevos (nunca existieron) — no necesitan delete.
        // OneSignal_channel_id SÍ necesita delete porque el SDK lo crea sin sonido.
        // También limpiamos los IDs viejos si quedan en el sistema.
        listOf(
            CHANNEL_ONESIGNAL_DEFAULT,               // SDK de OneSignal lo crea sin sonido
            "a26379a9-df0b-4d1e-8679-20ee949f7c59", // ID viejo CHANNEL_ALERTA
            "63802a9e-afed-4b02-83b8-55376cea49f0"  // ID viejo CHANNEL_ZONA
        ).forEach { nm.deleteNotificationChannel(it) }

        val panicoUri: Uri = Uri.parse("android.resource://$packageName/raw/panico")
        val audioAttrPanico: AudioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()

        // Canal ALERTA CRÍTICA (v2) — T=0, paradero, misiles, +2min/+5min
        // ID nuevo → se crea fresco, Android aplica alerta.mp3 sin restricciones
        val canalAlerta = NotificationChannel(
            CHANNEL_ALERTA_ID,
            "Alertas de Servicio",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Avisos urgentes de nuevos servicios disponibles."
            setSound(alertaUri, audioAttr)
            enableVibration(true)
            enableLights(true)
            setShowBadge(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        // Canal ZONAL (v2) — cron Supabase +2min/+5min
        val canalZona = NotificationChannel(
            CHANNEL_ZONA_ID,
            "Alertas de Proximidad",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Servicios disponibles en tu zona o a nivel global."
            setSound(alertaUri, audioAttr)
            enableVibration(true)
            enableLights(true)
            setShowBadge(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        // Canal OneSignal default — Dashboard y pushes sin canal explícito.
        // Recién borrado arriba → se recrea fresco con alerta.mp3 ANTES de
        // que el SDK de OneSignal intente recrearlo sin sonido.
        val canalOneSignalDefault = NotificationChannel(
            CHANNEL_ONESIGNAL_DEFAULT,
            "Notificaciones",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notificaciones generales de ServiExpress."
            setSound(alertaUri, audioAttr)
            enableVibration(true)
            enableLights(true)
            setShowBadge(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        // Canal PÁNICO — reproduce panico.mp3, prioridad máxima
        val canalPanico = NotificationChannel(
            CHANNEL_PANICO_ID,
            "Alertas de Pánico",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alertas de emergencia urgente (pánico)."
            setSound(panicoUri, audioAttrPanico)
            enableVibration(true)
            enableLights(true)
            setShowBadge(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }

        nm.createNotificationChannel(canalAlerta)
        nm.createNotificationChannel(canalZona)
        nm.createNotificationChannel(canalPanico)
        nm.createNotificationChannel(canalOneSignalDefault)
    }
}
