import 'package:flutter/material.dart';
import 'package:serviexpress_app/screens/guest_delivery_form.dart';
import 'package:serviexpress_app/screens/guest_mototaxi_form.dart';
import 'package:serviexpress_app/screens/guest_shopping_form.dart';
import 'package:serviexpress_app/screens/guest_food_form.dart';
import 'package:serviexpress_app/screens/registro_screen.dart';
import 'package:serviexpress_app/screens/login_screen.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';
import 'package:serviexpress_app/utils/tema_serviexpress.dart';
import 'package:serviexpress_app/utils/alta_demanda.dart';
import 'package:serviexpress_app/utils/seguimiento_pedido.dart';

class GuestHomeScreen extends StatelessWidget {
  const GuestHomeScreen({super.key});

  void _ir(BuildContext context, Widget pantalla) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));

  @override
  Widget build(BuildContext context) {
    final margen = margenSE(context);
    return Scaffold(
      backgroundColor: kFondoSE,
      appBar: AppBar(
        backgroundColor: kFondoSE,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('ServiExpress',
            style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: ContenidoSE(
          anchoMax: 640,
          child: ListView(
            padding: EdgeInsets.fromLTRB(margen, 4, margen, 28),
            children: [
              // ── Saludo ──────────────────────────────────────────────────
              Text('¿Qué necesitas hoy?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: angostoSE(context) ? 24 : 28,
                      fontWeight: FontWeight.w800,
                      height: 1.1)),
              const SizedBox(height: 6),
              const Text('Pide rápido sin registrarte. Elige un servicio:',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 16),
              const BannerAltaDemanda(margin: EdgeInsets.only(bottom: 12)),

              // ── Servicios ───────────────────────────────────────────────
              GrillaServiciosSE(mosaicos: [
                MosaicoServicioSE(
                  estilo: EstiloServicio.mototaxi,
                  subtitulo: 'Transporte rápido y seguro',
                  onTap: () => _ir(context, const GuestMototaxiForm()),
                ),
                MosaicoServicioSE(
                  estilo: EstiloServicio.paqueteria,
                  subtitulo: 'Llevar o traer un paquete o documento',
                  onTap: () => _ir(context, const GuestDeliveryForm()),
                ),
                MosaicoServicioSE(
                  estilo: EstiloServicio.comida,
                  subtitulo: 'Te la traemos del restaurante',
                  onTap: () => _ir(context, const GuestFoodForm()),
                ),
                MosaicoServicioSE(
                  estilo: EstiloServicio.compras,
                  subtitulo: 'Danos tu lista, hacemos la fila',
                  onTap: () => _ir(context, const GuestShoppingForm()),
                ),
              ]),
              const SizedBox(height: 16),

              // ── Rastrear pedido ─────────────────────────────────────────
              TarjetaSE(
                acento: EstiloServicio.paqueteria.color,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                onTap: () => _ir(context, const GuestTrackingScreen()),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: EstiloServicio.paqueteria.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.location_on_rounded,
                        color: EstiloServicio.paqueteria.color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Mis pedidos',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87)),
                      SizedBox(height: 2),
                      Text('Mira el precio, tu Móvil y en qué va tu pedido.',
                          style: TextStyle(color: Colors.black54, fontSize: 13)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.black38),
                ]),
              ),
              const SizedBox(height: 10),

              // ── Crear cuenta: beneficios bien visibles ──────────────────
              BeneficiosRegistroSE(
                onRegistrar: () => _ir(context, const RegistroScreen(soloCliente: true)),
              ),
              Center(
                child: TextButton(
                  // En la web de invitados (/form) esta es la PRIMERA pantalla:
                  // no hay nada atrás. Antes hacía "pop" → el navegador volvía
                  // atrás, recargaba la página y se quedaba en el logo.
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      _ir(context, const LoginScreen());
                    }
                  },
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Ya tengo cuenta → Iniciar sesión',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
