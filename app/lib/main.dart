import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/dashboard_service.dart';
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
        ChangeNotifierProvider(create: (_) => DashboardService()),
      ],
      child: MaterialApp(
        title: 'Beriwo — Your Autonomous AI Operator',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.light,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFF7F7F9),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1B3A5C),
            brightness: Brightness.light,
            surface: const Color(0xFFFFFFFF),
            onSurface: const Color(0xFF111827),
            primary: const Color(0xFF1B3A5C),
            secondary: const Color(0xFFC5A55A),
            outline: const Color(0xFFE5E7EB),
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
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

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _resumeTriggered = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final chat = context.watch<ChatService>();

    // Show loading screen while AuthService.init() is processing the redirect
    if (auth.loading) {
      return _buildLoadingScreen('Initializing...');
    }

    if (auth.isLoggedIn) {
      // One-time: schedule the resume call after the current frame
      if (!_resumeTriggered && auth.pendingResumeConversationId != null) {
        _resumeTriggered = true;
        final convoId = auth.pendingResumeConversationId!;
        chat.loadPendingMessage();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          auth.clearPendingResume();
          chat.resumeAfterAuth(
            auth.refreshToken ?? '',
            accessToken: auth.accessToken,
            conversationId: convoId,
          );
        });
      }

      // ChatScreen handles all states internally:
      //   messages.isEmpty && sending  → "Resuming your session..." spinner
      //   messages.isEmpty && !sending → empty state with suggestions
      //   messages.isNotEmpty          → message list
      return const ChatScreen();
    }
    return const LoginScreen();
  }

  Widget _buildLoadingScreen(String message) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
