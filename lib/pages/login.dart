import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool isLogin = true;
  bool isLoading = false;
  bool obscurePassword = true;

  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> authenticate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final username = usernameController.text.trim();

    try {
      if (isLogin) {
        final session = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (session.user != null) {
          showMessage("¡Inicio de sesión exitoso!");

          // Verifica si ya tiene fila en la tabla users, si no la crea
          final userId = session.user!.id;
          final existingUser = await supabase
              .from('users')
              .select()
              .eq('id_user', userId)
              .maybeSingle();

          if (existingUser == null) {
            await supabase.from('users').insert({
              'id_user': userId,
              'email': email,
              'username': username.isNotEmpty ? username : email.split('@')[0],
            });
          }

          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
        );

        if (response.user != null) {
          // Actualizar el display name (si está disponible)
          await supabase.auth.updateUser(
            UserAttributes(data: {'full_name': username}),
          );

          showMessage(
            "¡Registro exitoso! Revisa tu correo y confirma tu cuenta antes de iniciar sesión.",
          );
        } else {
          showMessage("No se pudo crear el usuario.");
        }
      }
    } on AuthException catch (e) {
      showMessage("Error: ${e.message}");
    } catch (e) {
      showMessage("Error inesperado: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Colors.green.shade800;
    final light = Colors.green.shade100;

    return Scaffold(
      backgroundColor: light,
      appBar: AppBar(
        title: const Text('Bienvenido', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: primary,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/icon.png', height: 200),
                    const SizedBox(height: 12),
                    Text(
                      'Mapeo Terrenos RT',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.email),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Ingrese su correo'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (!isLogin)
                      Column(
                        children: [
                          TextFormField(
                            controller: usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre de usuario',
                              prefixIcon: Icon(Icons.person),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Ingrese un nombre de usuario'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    TextFormField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) => (value == null || value.length < 6)
                          ? 'Mínimo 6 caracteres'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            onPressed: authenticate,
                            icon: const Icon(Icons.login, color: Colors.white),
                            label: Text(
                              isLogin ? 'Iniciar sesión' : 'Registrarse',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? "¿No tienes cuenta? Regístrate"
                            : "¿Ya tienes cuenta? Inicia sesión",
                        style: const TextStyle(color: Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
