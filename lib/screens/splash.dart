import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'home_shell.dart';

class SplashScreen extends StatefulWidget {
  final bool navigateOnComplete;
  final Duration duration;

  const SplashScreen({
    super.key,
    this.navigateOnComplete = false,
    this.duration = const Duration(milliseconds: 650),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  late final AnimationController _pulseController;

  Offset? _touchOffset;
  Offset _currentGlow = const Offset(0.5, 0.45);
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    // 1. Clean subtle entrance fade & micro-scale
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _fade = CurvedAnimation(parent: _enterController, curve: Curves.easeOut);

    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
    );

    _enterController.forward();

    // 2. Gentle ambient breathing pulse (low CPU/GPU, refined)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    // 3. Optional standalone auto-navigation
    if (widget.navigateOnComplete) {
      _navTimer = Timer(widget.duration, () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, __, ___) => const HomeShell(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _enterController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (size.width > 0 && size.height > 0) {
      setState(() {
        _touchOffset = event.localPosition;
        final target = Offset(
          (event.localPosition.dx / size.width).clamp(0.1, 0.9),
          (event.localPosition.dy / size.height).clamp(0.1, 0.9),
        );
        // Smooth light interpolation
        _currentGlow = Offset(
          _currentGlow.dx + (target.dx - _currentGlow.dx) * 0.25,
          _currentGlow.dy + (target.dy - _currentGlow.dy) * 0.25,
        );
      });
    }
  }

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (size.width > 0 && size.height > 0) {
      setState(() {
        _touchOffset = event.localPosition;
        _currentGlow = Offset(
          (event.localPosition.dx / size.width).clamp(0.1, 0.9),
          (event.localPosition.dy / size.height).clamp(0.1, 0.9),
        );
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    setState(() {
      _touchOffset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _onPointerDown(e, size),
        onPointerMove: (e) => _onPointerMove(e, size),
        onPointerUp: _onPointerUp,
        child: AnimatedBuilder(
          animation: Listenable.merge([_enterController, _pulseController]),
          builder: (context, _) {
            final pulse = _pulseController.value;
            final glowOpacity = (0.07 + pulse * 0.05).clamp(0.0, 1.0);
            final touchBoost = _touchOffset != null ? 0.04 : 0.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // 1. Minimal Interactive Ambient Radial Glow
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(
                          (_currentGlow.dx - 0.5) * 1.6,
                          (_currentGlow.dy - 0.5) * 1.6,
                        ),
                        radius: 0.85,
                        colors: [
                          AppColors.accent.withValues(
                            alpha: (glowOpacity + touchBoost).clamp(0.0, 1.0),
                          ),
                          Colors.purple.withValues(
                            alpha: ((glowOpacity + touchBoost) * 0.35).clamp(
                              0.0,
                              1.0,
                            ),
                          ),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),

                // 2. Compact & Minimal Center Content
                Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Compact Logo with Subtle Breathing Aura
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.14 * (0.8 + pulse * 0.35),
                                  ),
                                  blurRadius: 36,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/Lloopin.png',
                              height: 64,
                              fit: BoxFit.contain,
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Compact Display Tagline
                          Text(
                            'Because one play is never enough.',
                            textAlign: TextAlign.center,
                            style: AppFonts.display(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white.withValues(alpha: 0.92),
                              letterSpacing: 0.8,
                            ),
                          ),

                          const SizedBox(height: 22),

                          // Minimal Acoustic Wave Dots
                          _buildMinimalEqualizer(pulse),
                        ],
                      ),
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

  Widget _buildMinimalEqualizer(double pulse) {
    const count = 4;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(count, (i) {
        final phase = sin((pulse * 2 * pi) + (i * 0.85)).abs();
        final height = 4.0 + phase * 10.0;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2.5),
          width: 3.0,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: AppColors.accent.withValues(alpha: 0.85),
          ),
        );
      }),
    );
  }
}
