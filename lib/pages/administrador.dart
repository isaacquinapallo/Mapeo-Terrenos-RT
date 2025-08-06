import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdministrarUsuariosPage extends StatefulWidget {
  const AdministrarUsuariosPage({super.key});

  @override
  State<AdministrarUsuariosPage> createState() =>
      _AdministrarUsuariosPageState();
}

class _AdministrarUsuariosPageState extends State<AdministrarUsuariosPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> usuarios = [];

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  Future<void> _cargarUsuarios() async {
    final data = await supabase
        .from('users')
        .select('id_user, username, tipo')
        .order('username', ascending: true);

    setState(() {
      usuarios = List<Map<String, dynamic>>.from(data);
    });
  }

  Future<void> _eliminarUsuario(String idUsuario) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .delete()
          .eq('id_user', idUsuario)
          .select(); // 👈 importante para obtener el registro eliminado

      if (response != null && response is List && response.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Usuario eliminado con éxito')),
        );
        await _cargarUsuarios(); // Recargar usuarios
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontró el usuario para eliminar'),
          ),
        );
      }
    } catch (error) {
      print('Error al eliminar usuario: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar usuario: $error')),
      );
    }
    _cargarUsuarios();
  }

  Future<void> _cambiarTipo(String idUser, String tipoActual) async {
    String nuevoTipo = tipoActual == 'user' ? 'administrador' : 'user';

    try {
      await supabase
          .from('users')
          .update({'tipo': nuevoTipo})
          .eq('id_user', idUser);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Tipo cambiado a $nuevoTipo')));

      _cargarUsuarios();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cambiando tipo: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: usuarios.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: usuarios.length,
              itemBuilder: (context, index) {
                final usuario = usuarios[index];
                final idUser = usuario['id_user'];
                final username = usuario['username'];
                final tipo = usuario['tipo'];

                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    title: Text(username),
                    subtitle: Text(
                      'Tipo: ${tipo == 'user' ? 'Topógrafo' : (tipo == 'administrador' ? 'Administrador' : 'Topógrafo')}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _eliminarUsuario(idUser),
                          child: const Text('Eliminar'),
                        ),
                        const SizedBox(width: 8),
                        if (tipo == 'user' || tipo == 'administrador')
                          TextButton(
                            onPressed: () => _cambiarTipo(idUser, tipo),
                            child: Text(
                              tipo == 'user' ? 'Ascender' : 'Degradar',
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
