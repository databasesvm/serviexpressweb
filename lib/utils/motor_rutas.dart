import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class MotorRutas {
  // 1. GEOCODIFICADOR: Convierte el texto del cliente en Coordenadas exactas
  static Future<Map<String, double>?> obtenerCoordenadas(
    String direccion,
  ) async {
    try {
      // Anclamos la búsqueda a Norte de Santander para que no tire resultados de otros países
      final query = Uri.encodeComponent(
        '$direccion, Norte de Santander, Colombia',
      );
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1',
      );

      // Límite de 6 s: el buscador público puede tardar o no responder, y
      // nunca debe dejar la app colgada.
      final response = await http.get(
        url,
        headers: {
          'User-Agent':
              'ServiexpressApp/1.0', // El radar libre nos exige identificarnos
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          return {
            'lat': double.parse(data[0]['lat']),
            'lng': double.parse(data[0]['lon']),
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('Falla satelital (Geo): $e');
      return null;
    }
  }

  // 2. CALCULADORA OSRM: Mide distancia y tiempo estimado de viaje real
  static Future<Map<String, dynamic>?> calcularRuta({
    required double latOrigen,
    required double lngOrigen,
    required double latDestino,
    required double lngDestino,
  }) async {
    try {
      // OSRM lee al revés: Longitud primero, Latitud después
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$lngOrigen,$latOrigen;$lngDestino,$latDestino?overview=false',
      );

      // Límite de 4 s: el servidor público de rutas a veces no responde.
      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final ruta = data['routes'][0];
          final distanciaMetros = ruta['distance'] as num;
          final duracionSegundos = ruta['duration'] as num;

          return {
            'distancia_km': (distanciaMetros / 1000).toDouble(),
            'tiempo_minutos': (duracionSegundos / 60)
                .ceil(), // Redondea al minuto siguiente
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('Falla satelital (OSRM): $e');
      return null;
    }
  }
}
