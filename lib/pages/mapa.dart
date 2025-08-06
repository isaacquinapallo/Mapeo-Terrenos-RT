import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mapeo_terrenos_rt/pages/home.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' hide LocationAccuracy;
import 'dart:async';

class MapaPage extends StatefulWidget {
  final String proyectoId;
  final bool colaborativo;
  final List<Map<String, dynamic>>? usuarios;

  const MapaPage({
    super.key,
    required this.proyectoId,
    required this.colaborativo,
    this.usuarios,
  });

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  GoogleMapController? mapController;
  List<LatLng> puntos = [];
  final Set<Polygon> _poligonos = {};
  final Set<Marker> _marcadores = {};
  final Set<Polyline> _polilineas = {};
  LatLng? ubicacionActual;
  bool cargandoUbicacion = false;
  bool finalizado = false;
  String? creadorId;
  String? userIdActual;
  late final StreamSubscription<Position> _posStreamSub;
  bool mostrarCoordenadas = false;
  bool mostrarBarraLateral = true;
  bool get esMapaGeneralUsuarios => widget.proyectoId == 'usuarios_mapa';
  bool esUUIDValido(String id) {
    final uuidRegExp = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegExp.hasMatch(id);
  }

  Future<void> _capturarUbicacion() async {
    try {
      bool servicioHabilitado = await Geolocator.isLocationServiceEnabled();
      if (!servicioHabilitado) {
        await _mostrarDialogoPermiso(
          context,
          'Servicio de ubicación deshabilitado',
          'Por favor activa el servicio de ubicación para continuar.',
          abrirConfiguracion: true,
        );
        return;
      }

      LocationPermission permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
        if (permiso == LocationPermission.denied) {
          await _mostrarDialogoPermiso(
            context,
            'Permiso de ubicación denegado',
            'Necesitamos el permiso de ubicación para usar esta función.',
          );
          return;
        }
      }

      if (permiso == LocationPermission.deniedForever) {
        await _mostrarDialogoPermiso(
          context,
          'Permiso de ubicación denegado permanentemente',
          'Por favor habilita el permiso manualmente en la configuración.',
          abrirConfiguracion: true,
        );
        return;
      }

      Position posicion = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      final nuevaUbicacion = LatLng(posicion.latitude, posicion.longitude);
      setState(() {
        puntos.add(nuevaUbicacion);
        _dibujarPoligono();
      });

      await Supabase.instance.client.from('puntos').insert({
        'creador': userIdActual,
        'latitud': nuevaUbicacion.latitude,
        'longitud': nuevaUbicacion.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'proyecto_id': widget.proyectoId,
      });
    } catch (e) {
      print("Error al obtener ubicación: $e");
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📍 Ubicación marcada exitosamente.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _mostrarDialogoPermiso(
    BuildContext context,
    String titulo,
    String mensaje, {
    bool abrirConfiguracion = false,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text(titulo),
          content: Text(mensaje),
          actions: [
            if (abrirConfiguracion)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await openAppSettings();
                },
                child: const Text('Abrir configuración'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> verificarYActivarGPS() async {
  Location location = Location();

  bool servicioActivo = await location.serviceEnabled();
  if (!servicioActivo) {
    servicioActivo = await location.requestService();
  }

  if (!servicioActivo) {
    // El usuario no quiso activar el GPS
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor activa el GPS para continuar')),
      );
    }
  }
}

  @override
  void initState() {
    userIdActual = Supabase.instance.client.auth.currentUser?.id;
    super.initState();
    _verificarPermisoGPS();
    _obtenerUbicacion();
    _iniciarTrackingUbicacion();
    _iniciarActualizacionPoligonoColaborativo();

    if (widget.proyectoId == 'usuarios_mapa' && widget.usuarios != null) {
      _cargarMarcadoresUsuarios(widget.usuarios!);
    }

    if (widget.colaborativo) {
      _cargarPuntosColaborativos();
      _iniciarActualizacionPuntosColaborativos();
    }

    _cargarCreador();
  }

  Future<void> _cargarCreador() async {
    if (widget.proyectoId == 'usuarios_mapa') return;

    try {
      final response = await Supabase.instance.client
          .from('territories')
          .select('creador')
          .eq('id', widget.proyectoId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          creadorId = response['creador'];
        });
      }
    } catch (e) {
      print('Error al cargar el creador: $e');
    }
  }

  @override
  void dispose() {
    _posStreamSub.cancel();
    mapController?.dispose();
    super.dispose();
  }

  void _cargarMarcadoresUsuarios(List<Map<String, dynamic>> usuarios) {
    _marcadores.clear();
    for (final usuario in usuarios) {
      final lat = usuario['latitude'];
      final lng = usuario['longitude'];
      if (lat != null && lng != null) {
        _marcadores.add(
          Marker(
            markerId: MarkerId(usuario['id_user']),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: usuario['username'] ?? 'Usuario'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
          ),
        );
      }
    }
    setState(() {});
  }

  void _iniciarActualizacionPoligonoColaborativo() {
    Future.doWhile(() async {
      if (!finalizado && mounted) {
        await _cargarPuntosColaborativos();
        _dibujarPoligono();
        await Future.delayed(const Duration(seconds: 2));
        return true;
      }
      return false;
    });
  }

  void _iniciarActualizacionPuntosColaborativos() {
    Future.doWhile(() async {
      if (!finalizado && mounted) {
        await _cargarPuntosColaborativos();
        _dibujarPoligono();
        await Future.delayed(const Duration(seconds: 5));
        return true;
      }
      return false;
    });
  }

  Future<void> _verificarPermisoGPS() async {
    final permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  Future<void> _obtenerUbicacion() async {
    setState(() => cargandoUbicacion = true);
    try {
      Position pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          ubicacionActual = LatLng(pos.latitude, pos.longitude);
          cargandoUbicacion = false;
        });
      }
    } catch (e) {
      print('Error al obtener ubicación: $e');
    }
  }

  Future<void> _cargarPuntosColaborativos() async {
    if (widget.proyectoId == 'usuarios_mapa') return;

    try {
      final puntosDB = await Supabase.instance.client
          .from('puntos')
          .select('latitud,longitud')
          .eq('proyecto_id', widget.proyectoId);

      if (mounted) {
        setState(() {
          puntos = List<LatLng>.from(
            puntosDB.map((p) => LatLng(p['latitud'], p['longitud'])),
          );
        });
      }

      if (puntos.isNotEmpty && mapController != null) {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(puntos.last, 18),
        );
      }
    } catch (e) {
      print('Error al cargar puntos: $e');
    }
  }

  void _dibujarPoligono() {
    _marcadores.clear();
    for (int i = 0; i < puntos.length; i++) {
      final punto = puntos[i];
      final lat = punto.latitude.toStringAsFixed(6);
      final lng = punto.longitude.toStringAsFixed(6);

      _marcadores.add(
        Marker(
          markerId: MarkerId('punto_$i'),
          position: punto,
          infoWindow: InfoWindow(
            title: 'Punto ${i + 1}',
            snippet: 'Lat: $lat\nLng: $lng',
          ),
        ),
      );
    }

    _polilineas.clear();
    if (puntos.length > 1) {
      _polilineas.add(
        Polyline(
          polylineId: const PolylineId('linea1'),
          points: puntos,
          color: Colors.blue,
          width: 3,
        ),
      );
    }

    _poligonos.clear();
    if (puntos.length > 2) {
      final puntosPoligono = List<LatLng>.from(puntos);
      if (puntosPoligono.first != puntosPoligono.last) {
        puntosPoligono.add(puntosPoligono.first);
      }

      _poligonos.add(
        Polygon(
          polygonId: const PolygonId('poligono1'),
          points: puntosPoligono,
          fillColor: const Color.fromARGB(100, 33, 150, 243),
          strokeColor: Colors.blue,
          strokeWidth: 3,
        ),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _iniciarTrackingUbicacion() {
    _posStreamSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((Position pos) async {
          if (!mounted) return;

          setState(() {
            ubicacionActual = LatLng(pos.latitude, pos.longitude);
          });

          if (userIdActual != null) {
            try {
              final existeUsuario = await Supabase.instance.client
                  .from('users')
                  .select('id_user')
                  .eq('id_user', userIdActual!)
                  .maybeSingle();

              if (existeUsuario != null) {
                await Supabase.instance.client.from('locations').upsert({
                  'id_user': userIdActual,
                  'latitude': pos.latitude,
                  'longitude': pos.longitude,
                  'timestamp': DateTime.now().toIso8601String(),
                  'status': true,
                }, onConflict: 'id_user');
              } else {
                print('❌ Usuario no existe en public.users.');
              }
            } catch (e) {
              print('Error actualizando location: $e');
            }
          }
        });
  }

  double _calcularArea() {
    if (puntos.length < 3) return 0.0;
    List<LatLng> poly = List.from(puntos);
    if (poly.first != poly.last) {
      poly.add(poly.first);
    }

    double total = 0.0;
    const earthRadius = 6378137.0;

    for (int i = 0; i < poly.length - 1; i++) {
      final p1 = poly[i];
      final p2 = poly[i + 1];
      total +=
          (p2.longitude * pi / 180 - p1.longitude * pi / 180) *
          (2 + sin(p1.latitude * pi / 180) + sin(p2.latitude * pi / 180));
    }

    return (total * earthRadius * earthRadius / 2).abs();
  }

  LatLng _calcularPuntoMedio() {
    if (puntos.isEmpty) return const LatLng(0, 0);

    double sumaLat = 0;
    double sumaLng = 0;

    for (final punto in puntos) {
      sumaLat += punto.latitude;
      sumaLng += punto.longitude;
    }

    return LatLng(sumaLat / puntos.length, sumaLng / puntos.length);
  }

  String _determinarTipoFigura() {
    final numPuntos = puntos.length - 1;
    if (!_esPoligonoRegular()) return 'Polígono Irregular';

    switch (numPuntos) {
      case 3:
        return 'Triángulo';
      case 4:
        return 'Cuadrado';
      case 5:
        return 'Pentágono';
      case 6:
        return 'Hexágono';
      case 7:
        return 'Heptágono';
      case 8:
        return 'Octágono';
      case 9:
        return 'Nonágono';
      case 10:
        return 'Decágono';
      default:
        return 'Círculo';
    }
  }

  bool _esPoligonoRegular() {
    if (puntos.length < 4) return true;

    final distancias = <double>[];

    for (int i = 0; i < puntos.length - 1; i++) {
      final dx = puntos[i + 1].latitude - puntos[i].latitude;
      final dy = puntos[i + 1].longitude - puntos[i].longitude;
      distancias.add(sqrt(dx * dx + dy * dy));
    }

    final primera = distancias.first;
    return distancias.every((d) => (d - primera).abs() <= 0.01);
  }

  double _determinarZoomDesdeArea(double area) {
    if (area < 500) return 19;
    if (area < 2000) return 18;
    if (area < 10000) return 17;
    if (area < 50000) return 16;
    if (area < 200000) return 15;
    return 14;
  }

  void _mostrarArea() {
    final area = _calcularArea();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Área del Territorio'),
        content: Text('El área calculada es: ${area.toStringAsFixed(2)} m²'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  LatLng _calcularCentro(List<LatLng> puntos) {
    double lat = 0.0;
    double lng = 0.0;

    for (var punto in puntos) {
      lat += punto.latitude;
      lng += punto.longitude;
    }

    return LatLng(lat / puntos.length, lng / puntos.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa del Territorio'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildGoogleMap(),
          ..._buildCoordenadasWidgets(),
          _buildMarcarUbicacionButton(),
          _buildFinalizarButton(),
          _buildMostrarAreaButton(),
          _buildBotonBorrarDesdeSupabase(),
        ],
      ),
    );
  }

  Widget _buildMostrarAreaButton() {
    return Positioned(
      bottom: 20,
      left: 20,
      child: FloatingActionButton.extended(
        heroTag: 'areaBtn',
        onPressed: _mostrarArea,
        label: const Text('Mostrar Área'),
        icon: const Icon(Icons.area_chart),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _borrarPuntosDesdeSupabase() async {
    try {
      await Supabase.instance.client
          .from('puntos')
          .delete()
          .eq('proyecto_id', widget.proyectoId);

      setState(() {
        puntos.clear();
        _marcadores.clear();
        _poligonos.clear();
        _polilineas.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Puntos eliminados de Supabase')),
      );
    } catch (e) {
      print('Error al borrar puntos: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error al borrar puntos')));
    }
  }

  Widget _buildBotonBorrarDesdeSupabase() {
    // Solo el creador puede ver este botón
    if (userIdActual != creadorId) return const SizedBox.shrink();

    return Positioned(
      bottom: 160, 
      left: 20,
      child: FloatingActionButton.extended(
        heroTag: 'borrarSupabaseBtn',
        onPressed: () async {
          final confirmar = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('¿Borrar puntos del proyecto?'),
              content: const Text(
                'Esto eliminará todos los puntos guardados en Supabase para este proyecto.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Borrar'),
                ),
              ],
            ),
          );

          if (confirmar == true) {
            await _borrarPuntosDesdeSupabase();
          }
        },
        icon: const Icon(Icons.delete),
        label: const Text('Borrar'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _buildGoogleMap() {
    return Stack(
      children: [
        GoogleMap(
          onMapCreated: (controller) {
            mapController = controller;
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _cargarPuntosColaborativos().then((_) => _dibujarPoligono());
              }
            });
          },
          initialCameraPosition: CameraPosition(
            target: ubicacionActual ?? const LatLng(-0.22985, -78.52495),
            zoom: 16,
          ),
          myLocationEnabled: !finalizado,
          myLocationButtonEnabled: !finalizado,
          polygons: _poligonos,
          markers: _marcadores,
          polylines: _polilineas,
          mapType: MapType.normal,
        ),
      ],
    );
  }

  Widget _buildMarcarUbicacionButton() {
    return Positioned(
      bottom: 90,
      left: 20,
      child: FloatingActionButton.extended(
        heroTag: 'marcarBtn',
        onPressed: cargandoUbicacion || finalizado || esMapaGeneralUsuarios
            ? null
            : _capturarUbicacion,
        label: const Text('Marcar'),
        icon: const Icon(Icons.add_location_alt),
        backgroundColor: Colors.green,
        elevation: 6,
      ),
    );
  }

  Positioned _buildFinalizarButton() {
    return Positioned(
      bottom: 20,
      right: 20,
      child: ElevatedButton.icon(
        onPressed:
            (puntos.length > 2 &&
                !finalizado &&
                userIdActual == creadorId &&
                !esMapaGeneralUsuarios)
            ? () async {
                if (puntos.isNotEmpty && puntos.first != puntos.last) {
                  setState(() {
                    puntos.add(puntos.first);
                  });
                  _dibujarPoligono();
                }
                final area = _calcularArea();
                final puntoMedio = _calcularPuntoMedio();
                final tipoFigura = _determinarTipoFigura();

                try {
                  await Supabase.instance.client
                      .from('territories')
                      .update({
                        'area': area,
                        'latitude': puntoMedio.latitude,
                        'longitude': puntoMedio.longitude,
                        'polygon': tipoFigura,
                      })
                      .eq('id', widget.proyectoId);

                  if (context.mounted) {
                    _mostrarModalFinalizar(context);
                  }
                } catch (e) {
                  print('Error al finalizar el territorio: $e');
                }
              }
            : null,
        icon: const Icon(Icons.check_circle),
        label: const Text('Terminar'),
      ),
    );
  }

  void _mostrarModalFinalizar(BuildContext context) {
    bool cargandoImagen = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Finalizar Mapeo'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: cargandoImagen
                        ? const Center(child: CircularProgressIndicator())
                        : const Center(
                            child: Text(
                              'Se generará una captura del mapa con las líneas y el área completa.',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () async {
                    setStateDialog(() => cargandoImagen = true);

                    try {
                      setState(() => finalizado = true);
                      _dibujarPoligonoConZIndex();

                      final Set<Marker> marcadoresOriginales = Set.from(
                        _marcadores,
                      );
                      setState(() => _marcadores.clear());

                      final area = _calcularArea();
                      final puntoMedio = _calcularCentro(puntos);
                      final zoom = _determinarZoomDesdeArea(area);

                      await mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(puntoMedio, zoom),
                      );

                      final Uint8List? captura = await mapController
                          ?.takeSnapshot();

                      setState(() => _marcadores.addAll(marcadoresOriginales));

                      if (captura != null) {
                        final fileName =
                            'mapa_id_${widget.proyectoId}_${DateTime.now().millisecondsSinceEpoch}.png';

                        await Supabase.instance.client.storage
                            .from('bucket-mapas')
                            .uploadBinary(fileName, captura);

                        final imageUrl = Supabase.instance.client.storage
                            .from('bucket-mapas')
                            .getPublicUrl(fileName);

                        await Supabase.instance.client
                            .from('territories')
                            .update({
                              'imagen_poligono': imageUrl,
                              'finalizado': true,
                            })
                            .eq('id', widget.proyectoId);

                        if (context.mounted) {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/home',
                            (route) => false,
                          );
                        }
                      } else {
                        throw Exception('No se pudo capturar el mapa');
                      }
                    } catch (e) {
                      print('Error al capturar o subir la imagen: $e');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Error al capturar o subir la imagen',
                            ),
                          ),
                        );
                      }
                    } finally {
                      setStateDialog(() => cargandoImagen = false);
                    }
                  },
                  child: const Text('Capturar y Subir'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Regresar al Proyecto'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _dibujarPoligonoConZIndex() {
    _poligonos.clear();
    if (puntos.length > 2) {
      final puntosPoligono = List<LatLng>.from(puntos);
      if (puntosPoligono.first != puntosPoligono.last) {
        puntosPoligono.add(puntosPoligono.first);
      }

      _poligonos.add(
        Polygon(
          polygonId: const PolygonId('poligono1'),
          points: puntosPoligono,
          fillColor: const Color.fromARGB(100, 33, 150, 243),
          strokeColor: Colors.blue,
          strokeWidth: 3,
          zIndex: 1,
        ),
      );
    }

    _polilineas.clear();
    if (puntos.length > 1) {
      _polilineas.add(
        Polyline(
          polylineId: const PolylineId('linea1'),
          points: puntos,
          color: Colors.blue,
          width: 3,
          zIndex: 1,
        ),
      );
    }

    if (mounted) {
      setState(() {});
    }
  }


  List<Widget> _buildCoordenadasWidgets() {
    if (mapController == null || puntos.isEmpty) return [];

    return puntos.asMap().entries.map((entry) {
      final punto = entry.value;

      return FutureBuilder<ScreenCoordinate>(
        future: mapController!.getScreenCoordinate(punto),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Container();
          final coord = snapshot.data!;
          return Positioned(
            top: coord.y.toDouble() - 40,
            left: coord.x.toDouble() - 60, // Ajuste para centrar el texto
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '(${punto.latitude.toStringAsFixed(5)}, ${punto.longitude.toStringAsFixed(5)})',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          );
        },
      );
    }).toList();
  }
}
