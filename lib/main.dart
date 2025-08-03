import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

import 'pages/login.dart';
import 'pages/home.dart';
import 'pages/mapa.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
  await Supabase.initialize(
    url: 'https://vsarwwlboedncyyzgpcz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzYXJ3d2xib2VkbmN5eXpncGN6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQwOTg2MjUsImV4cCI6MjA2OTY3NDYyNX0.KypF7mPm2BMkoYXnYPZFKpER_WrJrq7GHvgcTqWUyf4',
  );
} else {
  await dotenv.load(fileName: 'assets/.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
}


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return MaterialApp(
      title: 'Mapeo de Terrenos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.green,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.green,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(255, 0, 126, 9),
          foregroundColor: Colors.white,
        ),
      ),
      themeMode: ThemeMode.system,
      initialRoute: user == null ? '/login' : '/home',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomePage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/mapa') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => MapaPage(
              proyectoId: args['proyectoId'],
              colaborativo: args['colaborativo'],
            ),
          );
        }
        return null;
      },
    );
  }
}
