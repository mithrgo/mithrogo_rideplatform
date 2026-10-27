import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/flavors.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../onboarding/application/onboarding_controller.dart';

/// Picks up from the native launch splash (same yellow, same logo in the same spot),
/// animates the brand in, and restores the saved session. The router moves the user on.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Shortest time the splash stays up, so the animation plays even when there is no session.
  static const minimumDuration = Duration(milliseconds: 2000);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoSize = 96.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  // The logo starts exactly as the native splash drew it, then gives a small pop.
  late final Animation<double> _logoScale =
      TweenSequence([
        TweenSequenceItem(
          tween: Tween(
            begin: 1.0,
            end: 1.12,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 35,
        ),
        TweenSequenceItem(
          tween: Tween(
            begin: 1.12,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeInOut)),
          weight: 65,
        ),
      ]).animate(
        CurvedAnimation(parent: _controller, curve: const Interval(0, 0.35)),
      );

  late final Animation<double> _wheelTurn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.05, 0.45, curve: Curves.easeOutBack),
  );

  late final Animation<double> _textIn = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.25, 0.6, curve: Curves.easeOutCubic),
  );

  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _restore(firstRun: true),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore({bool firstRun = false}) async {
    setState(() => _error = null);
    try {
      if (ref.read(sessionControllerProvider).status == SessionStatus.unknown) {
        await ref
            .read(sessionControllerProvider.notifier)
            .restore(
              minimumWait: firstRun
                  ? Future<void>.delayed(SplashScreen.minimumDuration)
                  : null,
            );
      } else {
        // Signed in, but the profile failed to load: load it again.
        ref.invalidate(onboardingProvider);
      }
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A failed profile load keeps the captain here with a retry instead of a blank screen.
    final onboarding = ref.watch(onboardingProvider);
    final loadError = onboarding.hasError && !onboarding.isLoading
        ? userMessage(onboarding.error!)
        : null;
    final error = _error ?? loadError;

    return Scaffold(
      backgroundColor: AppColors.brand,
      body: Stack(
        children: [
          // Faint road lines sweeping across, for a sense of motion.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _textIn,
              builder: (context, _) =>
                  CustomPaint(painter: _RoadPainter(progress: _textIn.value)),
            ),
          ),
          // Centred on the full screen (not the safe area) to line up with the native splash.
          Center(
            child: ScaleTransition(
              scale: _logoScale,
              child: Container(
                width: _logoSize,
                height: _logoSize,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: AnimatedBuilder(
                  animation: _wheelTurn,
                  builder: (context, child) => Transform.translate(
                    // The scooter rolls in a touch from the left and settles.
                    offset: Offset((1 - _wheelTurn.value) * -6, 0),
                    child: child,
                  ),
                  child: const Icon(
                    Icons.two_wheeler,
                    size: 52,
                    color: AppColors.brand,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.only(top: _logoSize + 112),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(_textIn),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedWordmark(
                      word: Flavors.appName,
                      animation: CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.25, 0.9),
                      ),
                      style: theme.textTheme.displaySmall!.copyWith(
                        color: AppColors.ink,
                        fontSize: 40,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(0.75, 1),
                      ),
                      child: Text(
                        'Drive and earn on your terms',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                    if (!Flavors.isProd) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'DEV',
                          style: TextStyle(
                            color: AppColors.brand,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: error == null ? _loader() : _retry(theme, error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loader() {
    return FadeTransition(
      opacity: _textIn,
      child: const SizedBox(
        width: 28,
        child: LinearProgressIndicator(
          minHeight: 3,
          color: AppColors.ink,
          backgroundColor: Color(0x33111111),
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );
  }

  Widget _retry(ThemeData theme, String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.onInk,
          ),
          onPressed: _restore,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

/// "MithrGo" typed out letter by letter: each one pops up from below in turn,
/// "Go" lands heavier, and an underline swoosh draws in under the word at the end.
class _AnimatedWordmark extends StatelessWidget {
  const _AnimatedWordmark({
    required this.word,
    required this.animation,
    required this.style,
  });

  final String word;
  final Animation<double> animation;
  final TextStyle style;

  /// Where the bold tail ("Go") starts.
  int get _tailStart => word.endsWith('Go') ? word.length - 2 : word.length;

  @override
  Widget build(BuildContext context) {
    final letters = word.split('');
    // Letters take the first 75% of the animation, staggered; the swoosh takes the rest.
    const lettersShare = 0.75;
    final step = lettersShare / (letters.length + 2);

    return Semantics(
      label: word,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            final t = animation.value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < letters.length; i++)
                      _letter(
                        letters[i],
                        Curves.easeOutBack.transform(
                          ((t - i * step) / (step * 3)).clamp(0.0, 1.0),
                        ),
                        bold: i >= _tailStart,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                CustomPaint(
                  size: const Size(120, 10),
                  painter: _SwooshPainter(
                    progress: Curves.easeInOutCubic.transform(
                      ((t - lettersShare) / (1 - lettersShare)).clamp(0.0, 1.0),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _letter(String char, double v, {required bool bold}) {
    return Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - v) * 18),
        child: Transform.scale(
          scale: 0.6 + 0.4 * v,
          child: Text(
            char,
            style: bold ? style.copyWith(fontWeight: FontWeight.w900) : style,
          ),
        ),
      ),
    );
  }
}

class _SwooshPainter extends CustomPainter {
  _SwooshPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final path = Path()
      ..moveTo(0, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.5,
        -size.height * 0.2,
        size.width,
        size.height * 0.5,
      );
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = AppColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SwooshPainter old) => old.progress != progress;
}

/// Three soft diagonal "road" stripes that slide in behind the logo.
class _RoadPainter extends CustomPainter {
  _RoadPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0) return;
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.05 * progress)
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;
    final shift = (1 - progress) * size.width * 0.4;
    for (final f in const [0.18, 0.5, 0.82]) {
      final y = size.height * f;
      canvas.drawLine(
        Offset(-size.width * 0.2 - shift, y + size.height * 0.08),
        Offset(size.width * 1.2 - shift, y - size.height * 0.08),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RoadPainter old) => old.progress != progress;
}
