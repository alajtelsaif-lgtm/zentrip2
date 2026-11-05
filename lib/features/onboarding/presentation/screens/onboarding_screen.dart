import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../routes/app_routes.dart';

class OnboardingScreen extends StatefulWidget {
  static const String seenKey = 'onboarding_seen';
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  List<_Page> get _pages => [
        _Page(
          icon: Icons.auto_awesome_rounded,
          gradient: AppColors.skyGradient,
          title: AppLocalizations.of(context).onboardingTitle1,
          desc: AppLocalizations.of(context).onboardingDesc1,
        ),
        _Page(
          icon: Icons.place_rounded,
          gradient: AppColors.greenGradient,
          title: AppLocalizations.of(context).onboardingTitle2,
          desc: AppLocalizations.of(context).onboardingDesc2,
        ),
        _Page(
          icon: Icons.airplane_ticket_rounded,
          gradient: AppColors.sunsetGradient,
          title: AppLocalizations.of(context).onboardingTitle3,
          desc: AppLocalizations.of(context).onboardingDesc3,
        ),
      ];

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;

    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      await prefs
          .setBool(OnboardingScreen.seenKey, true)
          .timeout(const Duration(seconds: 2));
    } catch (error) {
      // Browser storage can be unavailable (for example, in a restricted
      // browser context). It must not keep the user trapped in onboarding.
      debugPrint('Could not persist onboarding completion: $error');
    }

    if (mounted) Navigator.pushReplacementNamed(context, AppRoutes.auth);
  }

  void _next() {
    if (_finishing) return;
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 650), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = _pages;
    final isLast = _currentPage == pages.length - 1;

    return Scaffold(
      body: Column(
        children: [
          // ── Skip ────────────────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: TextButton(
                onPressed: _finish,
                child: Text(l10n.onboardingSkip, style: const TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ),
          // ── Pages ───────────────────────────────────────────────────────
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: pages.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _OnboardingPage(page: pages[i]),
            ),
          ),
          // ── Indicators ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _currentPage == i ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: _currentPage == i ? AppColors.primary : AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            )),
          ),
          const SizedBox(height: 32),
          // ── Button ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _next,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLast ? AppColors.accentGreen : AppColors.primary,
                ),
                child: Text(isLast ? l10n.onboardingStart : l10n.onboardingNext),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Page {
  final IconData icon;
  final LinearGradient gradient;
  final String title;
  final String desc;
  const _Page({required this.icon, required this.gradient, required this.title, required this.desc});
}

class _OnboardingPage extends StatelessWidget {
  final _Page page;
  const _OnboardingPage({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(gradient: page.gradient, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: page.gradient.colors.first.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 16)),
            ]),
            child: Icon(page.icon, size: 60, color: Colors.white),
          )
              .animate(key: ValueKey(page.icon))
              .fade(duration: 650.ms)
              .scale(begin: const Offset(0.8, 0.8), duration: 650.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 40),
          Text(page.title, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))
              .animate(key: ValueKey('${page.icon}t')).fade(delay: 280.ms, duration: 450.ms).slideY(begin: 0.2, end: 0),
          const SizedBox(height: 14),
          Text(page.desc, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)
              .animate(key: ValueKey('${page.icon}d')).fade(delay: 460.ms, duration: 450.ms),
        ],
      ),
    );
  }
}
