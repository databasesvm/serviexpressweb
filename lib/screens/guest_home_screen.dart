import 'package:flutter/material.dart';
import 'package:serviexpress_app/screens/guest_delivery_form.dart';
import 'package:serviexpress_app/screens/guest_mototaxi_form.dart';
import 'package:serviexpress_app/screens/guest_shopping_form.dart';
import 'package:serviexpress_app/screens/guest_food_form.dart'; // <-- EL NUEVO DE COMIDA
import 'package:serviexpress_app/screens/registro_screen.dart';
import 'package:serviexpress_app/screens/guest_tracking_screen.dart';

class GuestHomeScreen extends StatelessWidget {
  const GuestHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'ServiExpress | Servicio Rápido',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        iconTheme: IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Qué necesitas hoy?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pide rápido sin registrarte. Selecciona el tipo de servicio:',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 16),

            // --- BOTÓN RASTREAR PEDIDO ACTIVO ---
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuestTrackingScreen()),
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xff3AF500), width: 1.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Color(0xff3AF500), size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📍 Rastrear mi pedido',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '¿Ya pediste? Toca aquí para ver el estado.',
                            style: TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        color: Color(0xff3AF500), size: 16),
                  ],
                ),
              ),
            ),

            _construirBotonServicio(
              context,
              titulo: '📦 Envío / Recogida',
              descripcion: 'Llevar o traer un paquete, documento o encomienda.',
              colorBase: Colors.blue[700]!,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GuestDeliveryForm(),
                ),
              ),
            ),

            _construirBotonServicio(
              context,
              titulo: '🍔 Pedir Comida',
              descripcion:
                  'Buscamos tu comida en el restaurante y te la llevamos.',
              colorBase: Colors.red[600]!,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GuestFoodForm()),
              ),
            ),

            _construirBotonServicio(
              context,
              titulo: '🛒 Compras y Encargos',
              descripcion: 'Danos tu lista y nosotros hacemos la fila por ti.',
              colorBase: Colors.orange[800]!,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GuestShoppingForm(),
                ),
              ),
            ),

            _construirBotonServicio(
              context,
              titulo: '🏍️ Mototaxi',
              descripcion: 'Transporte rápido y seguro para ti o un conocido.',
              colorBase: const Color(0xff3AF500),
              textColor: Colors.black,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GuestMototaxiForm(),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // BANNER CARTA DE RESTAURANTES
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xff1a1a1a), Color(0xff2d2d2d)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xff3AF500), width: 1),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xff3AF500).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.restaurant_menu, color: Color(0xff3AF500), size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🍔 Pide directo del menú',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Explora la carta de restaurantes y pide con domicilio a tu puerta.',
                              style: TextStyle(color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _FeatureChip(icon: Icons.storefront, label: 'Ver menú completo'),
                      const SizedBox(width: 8),
                      _FeatureChip(icon: Icons.shopping_cart, label: 'Carrito y checkout'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _FeatureChip(icon: Icons.location_on, label: 'Dirección guardada'),
                      const SizedBox(width: 8),
                      _FeatureChip(icon: Icons.track_changes, label: 'Seguimiento en vivo'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xff3AF500),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('CREAR MI CUENTA GRATIS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegistroScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Ya tengo cuenta → Iniciar sesión', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _construirBotonServicio(
    BuildContext context, {
    required String titulo,
    required String descripcion,
    required Color colorBase,
    Color textColor = Colors.white,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colorBase,
        borderRadius: BorderRadius.circular(12),
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        descripcion,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: textColor.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
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
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
