import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

const _navy = Color(0xFF1B3A5C);
const _gold = Color(0xFFC5A55A);
const _darkBg = Color(0xFF0F1F33);

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  bool _isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width > 800;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF7F7F9,
      ), // Very light, dropbox-esque background
      body: Column(
        children: [
          _buildNavbar(context),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildHero(context),
                  _buildFeatures(context),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavbar(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isDesktop = _isDesktop(context);

    return Container(
      height: 80,
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 64 : 24),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F7F9),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'B',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    TextSpan(
                      text: '.',
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                fontFamily: 'Georgia',
                letterSpacing: 0.5,
              ),
              children: [
                TextSpan(
                  text: 'Ber',
                  style: TextStyle(color: _navy),
                ),
                TextSpan(
                  text: '!',
                  style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: 'wo',
                  style: TextStyle(color: _navy),
                ),
              ],
            ),
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: auth.loading ? null : () => auth.login(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            child: auth.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Get started',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isDesktop = _isDesktop(context);

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_darkBg, _navy],
        ),
      ),
      padding: EdgeInsets.only(
        top: isDesktop ? 160 : 100,
        bottom: isDesktop ? 180 : 100,
        left: isDesktop ? 64 : 24,
        right: isDesktop ? 64 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: isDesktop
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              // Large logo
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: isDesktop ? 56 : 36,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Georgia',
                    letterSpacing: 1,
                  ),
                  children: const [
                    TextSpan(
                      text: 'Ber',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextSpan(
                      text: '!',
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: 'wo',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'The Autonomous AI Agent\nfor your Workspace.',
                textAlign: isDesktop ? TextAlign.left : TextAlign.center,
                style: TextStyle(
                  fontSize: isDesktop ? 72 : 42,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF9FAFB),
                  height: 1.1,
                  letterSpacing: -2.0,
                ),
              ),
              const SizedBox(height: 32),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Text(
                  'Meet Beriwo. A fully autonomous AI colleague that safely reads your emails, manages your schedule, and searches your documents. Built with enterprise-grade security and cross-session memory.',
                  textAlign: isDesktop ? TextAlign.left : TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Color(0xFF9CA3AF),
                    height: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 56),
              Row(
                mainAxisAlignment: isDesktop
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: auth.loading ? null : () => auth.login(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _darkBg,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    child: const Text(
                      'Deploy Your Agent',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 64),
              Wrap(
                spacing: 32,
                runSpacing: 16,
                alignment: isDesktop
                    ? WrapAlignment.start
                    : WrapAlignment.center,
                children: [
                  _buildTechBadge('Powered by Genkit'),
                  _buildTechBadge('Secured by Auth0 Token Vault'),
                  _buildTechBadge('Driven by Gemini 2.5 Flash'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTechBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        border: Border.all(color: _navy.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFeatures(BuildContext context) {
    final isDesktop = _isDesktop(context);
    final features = [
      (
        "Autonomous Pipeline",
        "Beriwo doesn't just chat. It plans, executes secure tool calls, reflects on results, and synthesizes perfect responses in a seamless loop.",
        Icons.account_tree_outlined,
      ),
      (
        "Zero-Trust Architecture",
        "Powered by Auth0 Token Vault. Your Google APIs run via secure proxies, ensuring credentials never touch the language model.",
        Icons.shield_outlined,
      ),
      (
        "Consent-Gated Execution",
        "Complete transparency. Beriwo reads autonomously but stops and asks explicitly for your approval before writing documents or creating events.",
        Icons.gpp_good_outlined,
      ),
      (
        "Persistent Memory",
        "It remembers. Cross-session memory builds a profile of your contexts, routines, and nuances, dynamically shaping how it supports you.",
        Icons.memory_outlined,
      ),
    ];

    return Container(
      color: const Color(0xFFF7F7F9),
      padding: EdgeInsets.symmetric(
        vertical: 120,
        horizontal: isDesktop ? 64 : 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why Beriwo?',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 72),
              Wrap(
                spacing: 64,
                runSpacing: 64,
                alignment: WrapAlignment.spaceBetween,
                children: features
                    .map(
                      (f) => SizedBox(
                        width: isDesktop ? 400 : double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _navy.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(f.$3, color: _navy, size: 28),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              f.$1,
                              style: const TextStyle(
                                color: Color(0xFF111827),
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              f.$2,
                              style: const TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final isDesktop = _isDesktop(context);
    return Container(
      color: _darkBg,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Wrap(
            alignment: isDesktop
                ? WrapAlignment.spaceBetween
                : WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 16,
            children: const [
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      'BERIWO // Authorized to Act',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Built for Auth0 Hackathon 2026',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
