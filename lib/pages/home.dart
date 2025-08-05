// Página principal de la aplicación
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'proyectos.dart';
import 'mapa.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _paginaActual = 0;
  String? userIdActual;
  String? userEmailActual;

  @override
  void initState() {
    super.initState();
    userIdActual = Supabase.instance.client.auth.currentUser?.id;
    userEmailActual = Supabase.instance.client.auth.currentUser?.email;
    _registrarUsuarioSiNoExiste();
    setState(() {});
  }

  Future<void> _registrarUsuarioSiNoExiste() async {
    if (userIdActual == null || userEmailActual == null) return;

    final uid = userIdActual!;
    final email = userEmailActual!;
    final username = email.split('@').first;

    try {
      final existe = await Supabase.instance.client
          .from('users')
          .select('id_user')
          .eq('id_user', uid)
          .maybeSingle();

      if (existe == null) {
        await Supabase.instance.client.rpc(
          'registrar_usuario',
          params: {
            'p_id_user': uid,
            'p_email': email,
            'p_username': username,
            'p_empresa_id': null,
          },
        );

        print('✅ Usuario registrado en la tabla users');
      } else {
        print('ℹ️ Usuario ya estaba registrado');
      }
    } catch (e) {
      print('❌ Error registrando usuario: $e');
    }
  }

  Future<List<dynamic>> _obtenerMisProyectos(String userIdActual) async {
    if (userIdActual == null) return <dynamic>[];
    return await Supabase.instance.client
        .from('territories')
        .select()
        .eq('creador', userIdActual)
        .order('created_at', ascending: false);
  }

  Future<List<dynamic>> _obtenerInvitaciones(String? userIdActual) async {
    if (userIdActual == null) return <dynamic>[];

    final response = await Supabase.instance.client
        .from('territories')
        .select()
        .filter('participantes', 'cs', '["$userIdActual"]')
        .neq('creador', userIdActual)
        .neq('finalizado', true)
        .order('created_at', ascending: false);

    return response;
  }

  @override
  Widget build(BuildContext context) {
    if (userIdActual == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapeo de Terrenos RT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await FlutterForegroundTask.stopService();

                final currentUserId = userIdActual;
                if (currentUserId != null) {
                  await Supabase.instance.client
                      .from('locations')
                      .update({'status': false})
                      .eq('id_user', currentUserId);
                }

                await Supabase.instance.client.auth.signOut();
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Error al cerrar sesión. Intente nuevamente.',
                      ),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _paginaActual,
        children: [
          _buildMisProyectos(userIdActual!),
          _buildInvitaciones(userIdActual!),
          const CrearProyectoPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _paginaActual,
        onTap: (index) => setState(() => _paginaActual = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: 'Mis Proyectos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mail),
            label: 'Invitaciones',
          ),

          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Nuevo'),
        ],
        type: BottomNavigationBarType.fixed,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _obtenerUbicacionesUsuarios() async {
    final response = await Supabase.instance.client
        .from('users')
        .select('id_user, username, latitude, longitude, status')
        .eq('status', true);

    final data = response as List<dynamic>? ?? [];
    return data
        .where((item) => item['latitude'] != null && item['longitude'] != null)
        .map<Map<String, dynamic>>((item) {
          return {
            'id_user': item['id_user'],
            'username': item['username'] ?? '',
            'latitude': item['latitude'],
            'longitude': item['longitude'],
            'status': item['status'],
          };
        })
        .toList();
  }

  Widget _buildUsuariosMapa() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _obtenerUbicacionesUsuarios(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final usuarios = snapshot.data!;
        return MapaPage(
          proyectoId: 'usuarios_mapa',
          colaborativo: false,
          usuarios: usuarios,
        );
      },
    );
  }

  Widget _buildMisProyectos(String userIdActual) {
    return FutureBuilder<List<dynamic>>(
      future: _obtenerMisProyectos(userIdActual),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final territorios = snapshot.data!;
        if (territorios.isEmpty) {
          return const Center(child: Text('No tienes proyectos aún'));
        }

        final proyectosEnProceso = territorios
            .where((t) => t['finalizado'] != true)
            .toList();
        final proyectosFinalizados = territorios
            .where((t) => t['finalizado'] == true)
            .toList();

        return ListView(
          children: [
            if (proyectosEnProceso.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Proyectos en proceso',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...proyectosEnProceso.map(
                (territorio) => _buildProyectoCard(
                  territorio,
                  esFinalizado: false,
                  context: context,
                ),
              ),
            ],
            if (proyectosFinalizados.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  'Proyectos finalizados',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...proyectosFinalizados.map(
                (territorio) => _buildProyectoCard(
                  territorio,
                  esFinalizado: true,
                  context: context,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildProyectoCard(
    Map<String, dynamic> territorio, {
    required bool esFinalizado,
    required BuildContext context,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListTile(
        title: Text(territorio['nombre'] ?? ''),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Descripción: ${territorio['properties'] ?? ''}'),
            Text(
              'Colaborativo: ${territorio['colaborativo'] == true ? 'Sí' : 'No'}',
            ),
            Text(
              'Área: ${territorio['area'] != null ? '${(territorio['area'] as num).toStringAsFixed(2)} m²' : 'No calculada'}',
            ),
            Text(
              'Fecha creación: ${_formatearFecha(territorio['created_at'])}',
            ),
            if (territorio['imagen_poligono'] != null &&
                (territorio['imagen_poligono'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    territorio['imagen_poligono'],
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Text('No se pudo cargar la imagen'),
                  ),
                ),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: esFinalizado
            ? const Icon(Icons.lock, color: Colors.grey)
            : IconButton(
                icon: const Icon(Icons.map),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MapaPage(
                        proyectoId: territorio['id'],
                        colaborativo: territorio['colaborativo'] ?? false,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildInvitaciones(String userIdActual) {
    return FutureBuilder<List<dynamic>>(
      future: _obtenerInvitaciones(userIdActual),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final territorios = snapshot.data!;
        if (territorios.isEmpty) {
          return const Center(child: Text('No tienes invitaciones aún'));
        }

        return ListView.builder(
          itemCount: territorios.length,
          itemBuilder: (context, index) {
            final territorio = territorios[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListTile(
                title: Text(territorio['nombre'] ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Descripción: ${territorio['propieties'] ?? ''}'),
                    Text(
                      'Colaborativo: ${territorio['colaborativo'] == true ? 'Sí' : 'No'}',
                    ),
                    Text(
                      'Área: ${territorio['area'] != null ? '${(territorio['area'] as num).toStringAsFixed(2)} m²' : 'No calculada'}',
                    ),
                    Text(
                      'Fecha creación: ${_formatearFecha(territorio['created_at'])}',
                    ),
                    if (territorio['imagen_poligono'] != null &&
                        (territorio['imagen_poligono'] as String).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            territorio['imagen_poligono'],
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Text('No se pudo cargar la imagen'),
                          ),
                        ),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.map),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapaPage(
                          proyectoId: territorio['id'],
                          colaborativo: territorio['colaborativo'] ?? false,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatearFecha(String? fecha) {
    if (fecha == null) return '';
    final date = DateTime.tryParse(fecha);
    if (date == null) return '';
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
