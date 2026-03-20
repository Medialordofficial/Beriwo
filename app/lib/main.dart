import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BeriwoApp());
}

class BeriwoApp extends StatelessWidget {
  const BeriwoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()..init()),
        ChangeNotifierProvider(create: (_) => ChatService()),
      ],
      child: MaterialApp(
        title: 'Beriwo',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark, // Default to true elite dark mode
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4318FF),
            brightness: Brightness.light,
          ),
          textTheme: GoogleFonts.interTextTheme(),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFF030303),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4318FF),
            brightness: Brightness.dark,
            surface: const Color(0xFF0A0A0A),
            primary: const Color(0xFF4318FF),
          ),
          textTheme: GoogleFonts.interTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF030303),
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          useMaterial3: true,
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (auth.isLoggedIn) {
      return const ChatScreen();
    }
    return const LoginScreen();
  }
}
