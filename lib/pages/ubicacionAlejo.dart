import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

/////// NO SE USO NADA DE ESTO, PERO LO DEJO POR SI SE NECESITA EN EL FUTURO ///////
class UbicacionPage extends StatefulWidget {
  const UbicacionPage({super.key});

  @override
  State<UbicacionPage> createState() => _UbicacionPageState();
}

class _UbicacionPageState extends State<UbicacionPage> {
  final supabase = Supabase.instance.client;
  final Duration updateInterval = Duration(seconds: 10);
  Timer? _locationTimer;

  LatLng? userPosition;
  GoogleMapController? mapController;
  List<LatLng> puntosTerreno = [];
  Polygon? poligono;
  double area = 0.0;

  @override
  void initState() {
    super.initState();
    _obtenerUbicacionYComenzarSeguimiento();
  }

  Future<void> _obtenerUbicacionYComenzarSeguimiento() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      userPosition = LatLng(position.latitude, position.longitude);
    });

    // Inicia el envío periódico de ubicación
    _locationTimer = Timer.periodic(updateInterval, (_) async {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await supabase.from('ubicaciones').insert({
        'usuario_id': supabase.auth.currentUser?.id,
        'latitud': pos.latitude,
        'longitud': pos.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print("Ubicación enviada: ${pos.latitude}, ${pos.longitude}");
    });
  }

  double calcularArea(List<LatLng> puntos) {
    if (puntos.length < 3) return 0.0;
    double area = 0.0;

    for (int i = 0; i < puntos.length; i++) {
      final j = (i + 1) % puntos.length;
      area += puntos[i].latitude * puntos[j].longitude;
      area -= puntos[j].latitude * puntos[i].longitude;
    }

    return (area.abs() * 111139 * 111139 / 2); // Aproximación en m²
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Ubicación'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              _locationTimer?.cancel();
              await supabase.auth.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: userPosition == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: GoogleMap(
                    onMapCreated: (controller) => mapController = controller,
                    initialCameraPosition: CameraPosition(
                      target: userPosition!,
                      zoom: 17,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    onTap: (LatLng latLng) {
                      setState(() {
                        puntosTerreno.add(latLng);
                        area = calcularArea(puntosTerreno);

                        poligono = Polygon(
                          polygonId: const PolygonId('terreno'),
                          points: puntosTerreno,
                          strokeColor: Colors.green,
                          strokeWidth: 2,
                          fillColor: Colors.green.withOpacity(0.3),
                        );
                      });
                    },
                    polygons: poligono != null ? {poligono!} : {},
                    markers: puntosTerreno
                        .map(
                          (p) => Marker(
                            markerId: MarkerId(p.toString()),
                            position: p,
                          ),
                        )
                        .toSet(),
                  ),
                ),
                if (puntosTerreno.length >= 3)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Área estimada: ${area.toStringAsFixed(2)} m²',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
              ],
            ),
    );
  }
}
