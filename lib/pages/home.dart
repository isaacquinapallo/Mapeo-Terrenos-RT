import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'proyectos.dart';
import 'administrador.dart';
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
  String? rolUsuario;

  late Future<List<dynamic>> invitacionesFuture;

  @override
  void initState() {
    super.initState();
    userIdActual = Supabase.instance.client.auth.currentUser?.id;
    userEmailActual = Supabase.instance.client.auth.currentUser?.email;
    _obtenerRolUsuario();
    _registrarUsuarioSiNoExiste();

    if (userIdActual != null) {
      invitacionesFuture = _obtenerInvitaciones(userIdActual!);
    } else {
      invitacionesFuture = Future.value([]);
    }

    setState(() {});
  }

  Future<void> _obtenerRolUsuario() async {
    if (userIdActual == null) return;

    final userData = await Supabase.instance.client
        .from('users')
        .select('tipo')
        .eq('id_user', userIdActual!)
        .maybeSingle();

    setState(() {
      rolUsuario = userData?['tipo'];
      print('Rol del usuario: $rolUsuario');
      print('ID actual: $userIdActual');
    });
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
          params: {'p_id_user': uid, 'p_email': email, 'p_username': username},
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
    return await Supabase.instance.client
        .from('territories')
        .select()
        .eq('creador', userIdActual)
        .order('created_at', ascending: false);
  }

  Future<List<dynamic>> _obtenerInvitaciones(String userIdActual) async {
    final response = await Supabase.instance.client
        .from('territories')
        .select()
        .filter('participantes', 'cs', '{${userIdActual}}')
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
        backgroundColor: Colors.teal.shade700,
        title: const Text(
          '📍 Mapeo de Terrenos',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: () {
              setState(() {
                if (userIdActual != null) {
                  invitacionesFuture = _obtenerInvitaciones(userIdActual!);
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
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
          _buildInvitaciones(),
          const CrearProyectoPage(),
          if (rolUsuario == 'administrador') const AdministrarUsuariosPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _paginaActual,
        onTap: (index) => setState(() => _paginaActual = index),
        selectedItemColor: Colors.teal.shade700,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_open, size: 26),
            label: 'Mis Proyectos',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mark_email_unread, size: 26),
            label: 'Invitaciones',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline, size: 26),
            label: 'Nuevo',
          ),
          if (rolUsuario == 'administrador')
            BottomNavigationBarItem(
              icon: Icon(Icons.manage_accounts, size: 26),
              label: 'Usuarios',
            ),
        ],
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
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    territorio['nombre'] ?? '',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Eliminar proyecto',
                  onPressed: () async {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('¿Eliminar proyecto?'),
                        content: const Text(
                          '¿Estás seguro de que deseas eliminar este proyecto? Esta acción no se puede deshacer.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text(
                              'Eliminar',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirmar == true) {
                      try {
                        await Supabase.instance.client
                            .from('territories')
                            .delete()
                            .eq('id', territorio['id']);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Proyecto eliminado exitosamente'),
                            ),
                          );
                          setState(() {}); // Recargar los proyectos
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Error al eliminar proyecto: $e',
                                style: const TextStyle(color: Colors.white),
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('📝 ${territorio['properties'] ?? ''}'),
            Text(
              '👥 Colaborativo: ${territorio['colaborativo'] == true ? 'Sí' : 'No'}',
            ),
            Text(
              '📐 Área: ${territorio['area'] != null ? '${(territorio['area'] as num).toStringAsFixed(2)} m²' : 'No calculada'}',
            ),
            Text('📅 Fecha: ${_formatearFecha(territorio['created_at'])}'),
            if (territorio['imagen_poligono'] != null &&
                (territorio['imagen_poligono'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    territorio['imagen_poligono'],
                    height: 100,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Text('No se pudo cargar la imagen'),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: TextButton.icon(
                icon: const Icon(Icons.map),
                label: const Text('Ver Mapa'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.teal.shade600,
                ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildInvitaciones() {
    return FutureBuilder<List<dynamic>>(
      future: invitacionesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Text('Error al cargar invitaciones: ${snapshot.error}'),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No tienes invitaciones aún'));
        }

        final territorios = snapshot.data!;

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
