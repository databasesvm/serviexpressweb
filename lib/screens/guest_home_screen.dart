import 'package:flutter/material.dart';
import 'package:serviexpress_app/screens/guest_delivery_form.dart';
import 'package:serviexpress_app/screens/guest_mototaxi_form.dart';
import 'package:serviexpress_app/screens/guest_shopping_form.dart';
import 'package:serviexpress_app/screens/guest_food_form.dart';
import 'package:serviexpress_app/screens/registro_screen.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';
import 'package:serviexpress_app/utils/tema_serviexpress.dart';
import 'package:serviexpress_app/utils/alta_demanda.dart';

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
                      Text('Rastrear mi pedido',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15, color: Colors.black87)),
                      SizedBox(height: 2),
                      Text('¿Ya pediste? Mira el estado aquí.',
                          style: TextStyle(color: Colors.black54, fontSize: 12)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.black38),
                ]),
              ),
              const SizedBox(height: 10),

              // ── Crear cuenta ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(kRadioTarjetaSE),
                  border: Border.all(color: kVerdeSE.withValues(alpha: 0.5)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kVerdeSE.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.restaurant_menu, color: kVerdeSE, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Pide directo del menú',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Crea tu cuenta y explora la carta de los restaurantes.',
                            style: TextStyle(color: Colors.white60, fontSize: 12)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Wrap(spacing: 8, runSpacing: 8, children: [
                    _FeatureChip(icon: Icons.storefront, label: 'Menú completo'),
                    _FeatureChip(icon: Icons.shopping_cart, label: 'Carrito'),
                    _FeatureChip(icon: Icons.location_on, label: 'Dirección guardada'),
                    _FeatureChip(icon: Icons.track_changes, label: 'Seguimiento en vivo'),
                  ]),
                  const SizedBox(height: 14),
                  BotonPrincipalSE(
                    texto: 'CREAR MI CUENTA GRATIS',
                    icono: Icons.person_add_rounded,
                    onPressed: () => _ir(context, const RegistroScreen()),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Ya tengo cuenta → Iniciar sesión',
                          style: TextStyle(color: Colors.white60, fontSize: 13)),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
