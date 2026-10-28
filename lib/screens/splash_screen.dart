import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../pages/map_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;

  late final AnimationController _animationController;
  late final Animation<double> _brandOpacity;
  late final Animation<double> _truckProgress;

  static const int _animationDurationMs = 3000;
  static const int _routeStartMs = 3000;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: _animationDurationMs,
      ),
    );

    // The logo and large title fade in, then remain fixed at the top
    // throughout the truck journey.
    _brandOpacity = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 12,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1),
        weight: 88,
      ),
    ]).animate(_animationController);

    // The truck travels at a consistent speed from right to left.
    // Linear progress avoids slowing down near the end.
    _truckProgress = CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    );

    _animationController.forward();

    // After the 4-second truck animation, load the app with a short,
    // smooth ease-out fade/zoom. Authentication-based routing is unchanged.
    _timer = Timer(
      const Duration(milliseconds: _routeStartMs),
      () {
        if (!mounted) return;

        final Widget destination =
            FirebaseAuth.instance.currentUser == null
                ? const HomePage()
                : const MapPage();

        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            pageBuilder: (_, animation, secondaryAnimation) =>
                destination,
            transitionDuration: const Duration(milliseconds: 450),
            reverseTransitionDuration: Duration.zero,
            transitionsBuilder:
                (_, animation, secondaryAnimation, child) {
              final easeOutAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              );

              final scaleAnimation = Tween<double>(
                begin: 0.98,
                end: 1.0,
              ).animate(easeOutAnimation);

              return FadeTransition(
                opacity: easeOutAnimation,
                child: ScaleTransition(
                  scale: scaleAnimation,
                  child: child,
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF282038),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );

            final truckWidth = (screenSize.width * 0.58)
                .clamp(195.0, 230.0)
                .toDouble();

            final truckHeight = truckWidth * (115 / 220);

            final roadY = screenSize.height * 0.65;

            // Keep the truck's wheels aligned with the road.
            final truckTop = roadY - truckHeight * (85 / 115);

            return AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                final truckProgress = _truckProgress.value;

                // Start with most of the truck outside the right edge,
                // making it appear to enter the phone screen.
                final truckStartLeft =
                    screenSize.width - truckWidth * 0.1;

                // Finish just beyond the left edge.
                final truckEndLeft = -truckWidth * 0.9;

                // Linear movement keeps the truck speed consistent.
                final truckLeft = truckStartLeft +
                    (truckEndLeft - truckStartLeft) * truckProgress;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Lighter purple city background and straight road.
                    CustomPaint(
                      // Lane markings move in the opposite direction
                      // to reinforce the truck's right-to-left motion.
                      painter: _RoadScenePainter(
                        roadProgress: truckProgress,
                      ),
                    ),

                    // Large branding area at the top.
                    Positioned(
                      top: screenSize.height * 0.035,
                      left: 16,
                      right: 16,
                      child: Opacity(
                        opacity: _brandOpacity.value
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFC4B0FF)
                                        .withValues(alpha: 0.25),
                                    blurRadius: 30,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                'assets/images/BetterRoutes.png',
                                fit: BoxFit.contain,
                              ),
                            ),

                            const SizedBox(height: 10),

                            const Text(
                              'Better Journey',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 29,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              'Smarter routes. Better journeys.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white
                                    .withValues(alpha: 0.95),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Truck: fixed size, horizontal movement only.
                    Positioned(
                      left: truckLeft,
                      top: truckTop,
                      child: SizedBox(
                        width: truckWidth,
                        height: truckHeight,
                        // The truck illustration faces left, matching
                        // its direction of travel.
                        child: const CustomPaint(
                          painter: _TruckPainter(),
                        ),
                      ),
                    ),

                    // Existing bottom branding is preserved.
                    Positioned(
                      bottom: 18,
                      left: 12,
                      right: 12,
                      child: Opacity(
                        opacity: (1 - truckProgress * 0.25)
                            .clamp(0.0, 1.0)
                            .toDouble(),
                        child: const Text(
                          'YOUR JOURNEY, OPTIMIZED',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Straight road with light purple highlights and a subtle 3D effect.
class _RoadScenePainter extends CustomPainter {
  const _RoadScenePainter({
    required this.roadProgress,
  });

  final double roadProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // Lightened purple background.
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF514568),
          Color(0xFF40334F),
          Color(0xFF30243F),
        ],
        stops: [0, 0.58, 1],
      ).createShader(bounds);

    canvas.drawRect(bounds, background);

    // Soft ambient light.
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.43),
      size.width * 0.48,
      Paint()
        ..color = const Color(0xFFD3C1FF)
            .withValues(alpha: 0.09),
    );

    _drawCity(canvas, size);

    final roadY = size.height * 0.65;
    final roadHeight = (size.height * 0.18)
        .clamp(112.0, 145.0)
        .toDouble();

    final roadRect = Rect.fromLTWH(
      -24,
      roadY - roadHeight / 2,
      size.width + 48,
      roadHeight,
    );

    // Road shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        roadRect.shift(const Offset(0, 8)),
        const Radius.circular(8),
      ),
      Paint()
        ..color = const Color(0xFF17111F)
            .withValues(alpha: 0.45),
    );

    // Outer lavender edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        roadRect.inflate(4),
        const Radius.circular(10),
      ),
      Paint()
        ..color = const Color(0xFFC7B0F8)
            .withValues(alpha: 0.65),
    );

    // Asphalt gradient creates shallow surface depth.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        roadRect,
        const Radius.circular(7),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF756582),
            Color(0xFF564563),
            Color(0xFF493754),
          ],
        ).createShader(roadRect),
    );

    // Upper road highlight.
    canvas.drawLine(
      Offset(0, roadRect.top + 4),
      Offset(size.width, roadRect.top + 4),
      Paint()
        ..color = const Color(0xFFF0E8FF)
            .withValues(alpha: 0.65)
        ..strokeWidth = 2,
    );

    // Lower edge adds a subtle raised-road impression.
    canvas.drawLine(
      Offset(0, roadRect.bottom - 3),
      Offset(size.width, roadRect.bottom - 3),
      Paint()
        ..color = const Color(0xFF251B31)
            .withValues(alpha: 0.85)
        ..strokeWidth = 4,
    );

    // Dashed lane markings move left-to-right on screen.
    final dashWidth = (size.width * 0.12)
        .clamp(28.0, 48.0)
        .toDouble();

    final dashGap = (size.width * 0.08)
        .clamp(20.0, 34.0)
        .toDouble();

    final cycle = dashWidth + dashGap;

    final offset = (roadProgress * cycle * 3.0) % cycle;

    final dashPaint = Paint()
      ..color = const Color(0xFFFFFCFF)
          .withValues(alpha: 0.95);

    for (
      var x = -cycle + offset;
      x < size.width + cycle;
      x += cycle
    ) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x,
            roadY - 2.3,
            dashWidth,
            4.6,
          ),
          const Radius.circular(2.3),
        ),
        dashPaint,
      );
    }

    // Moving highlights reinforce the road-motion illusion.
    final streakPaint = Paint()
      ..color = const Color(0xFFD9C7FF)
          .withValues(alpha: 0.28)
      ..strokeWidth = 1.4;

    for (var i = 0; i < 5; i++) {
      final y = roadRect.top +
          roadHeight * (0.23 + i * 0.13);

      final streakX =
          ((i * size.width * 0.23) +
                      roadProgress * size.width * 0.72) %
                  (size.width + 72) -
              36;

      canvas.drawLine(
        Offset(streakX, y),
        Offset(streakX + 32 + i * 3.0, y),
        streakPaint,
      );
    }
  }

  void _drawCity(Canvas canvas, Size size) {
    final baseY = size.height * 0.55;

    final buildingPaint = Paint()
      ..color = const Color(0xFF78698C)
          .withValues(alpha: 0.62);

    final buildings = <Rect>[
      Rect.fromLTWH(
        0,
        baseY - size.height * 0.10,
        size.width * 0.10,
        size.height * 0.10,
      ),
      Rect.fromLTWH(
        size.width * 0.10,
        baseY - size.height * 0.17,
        size.width * 0.09,
        size.height * 0.17,
      ),
      Rect.fromLTWH(
        size.width * 0.20,
        baseY - size.height * 0.12,
        size.width * 0.08,
        size.height * 0.12,
      ),
      Rect.fromLTWH(
        size.width * 0.30,
        baseY - size.height * 0.21,
        size.width * 0.10,
        size.height * 0.21,
      ),
      Rect.fromLTWH(
        size.width * 0.42,
        baseY - size.height * 0.14,
        size.width * 0.075,
        size.height * 0.14,
      ),
      Rect.fromLTWH(
        size.width * 0.51,
        baseY - size.height * 0.18,
        size.width * 0.10,
        size.height * 0.18,
      ),
      Rect.fromLTWH(
        size.width * 0.63,
        baseY - size.height * 0.12,
        size.width * 0.075,
        size.height * 0.12,
      ),
      Rect.fromLTWH(
        size.width * 0.72,
        baseY - size.height * 0.20,
        size.width * 0.10,
        size.height * 0.20,
      ),
      Rect.fromLTWH(
        size.width * 0.84,
        baseY - size.height * 0.15,
        size.width * 0.08,
        size.height * 0.15,
      ),
      Rect.fromLTWH(
        size.width * 0.93,
        baseY - size.height * 0.11,
        size.width * 0.11,
        size.height * 0.11,
      ),
    ];

    for (var i = 0; i < buildings.length; i++) {
      final rect = buildings[i];

      canvas.drawRect(
        rect,
        Paint()
          ..color = i.isEven
              ? const Color(0xFF877796)
                  .withValues(alpha: 0.65)
              : buildingPaint.color,
      );

      // Subtle windows.
      final windowPaint = Paint()
        ..color = const Color(0xFFE4D9FF)
            .withValues(alpha: 0.40);

      final windowWidth =
          (size.width * 0.012).clamp(2.0, 4.0).toDouble();

      final windowHeight =
          (size.height * 0.008).clamp(3.0, 6.0).toDouble();

      for (var row = 0; row < 3; row++) {
        for (var col = 0; col < 2; col++) {
          final x = rect.left +
              rect.width * (0.24 + col * 0.42);

          final y = rect.top +
              size.height * (0.035 + row * 0.032);

          if (x + windowWidth < rect.right &&
              y + windowHeight < rect.bottom) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  x,
                  y,
                  windowWidth,
                  windowHeight,
                ),
                const Radius.circular(1),
              ),
              windowPaint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant _RoadScenePainter oldDelegate,
  ) {
    return oldDelegate.roadProgress != roadProgress;
  }
}

/// Left-facing vector truck with fixed dimensions.
class _TruckPainter extends CustomPainter {
  const _TruckPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    canvas.scale(
      size.width / 220,
      size.height / 115,
    );

    // Ground shadow.
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(112, 100),
        width: 178,
        height: 15,
      ),
      Paint()
        ..color = const Color(0xFF15101D)
            .withValues(alpha: 0.40),
    );

    // Cargo body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(78, 19, 124, 61),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF9674E8),
    );

    // Top surface.
    final cargoTop = Path()
      ..moveTo(78, 19)
      ..lineTo(91, 9)
      ..lineTo(213, 9)
      ..lineTo(202, 19)
      ..close();

    canvas.drawPath(
      cargoTop,
      Paint()..color = const Color(0xFFC5B0FF),
    );

    // Body highlight.
    canvas.drawLine(
      const Offset(88, 25),
      const Offset(192, 25),
      Paint()
        ..color = const Color(0xFFF0E9FF)
            .withValues(alpha: 0.75)
        ..strokeWidth = 3,
    );

    // Route illustration on the cargo body.
    final routePaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final routePath = Path()
      ..moveTo(112, 57)
      ..lineTo(125, 44)
      ..lineTo(139, 53)
      ..lineTo(154, 40);

    canvas.drawPath(routePath, routePaint);

    canvas.drawCircle(
      const Offset(112, 57),
      3.2,
      Paint()..color = Colors.white,
    );

    canvas.drawCircle(
      const Offset(154, 40),
      3.2,
      Paint()..color = Colors.white,
    );

    // Front cab on the left.
    final cab = Path()
      ..moveTo(20, 47)
      ..lineTo(38, 20)
      ..quadraticBezierTo(42, 13, 50, 13)
      ..lineTo(68, 13)
      ..quadraticBezierTo(75, 13, 80, 20)
      ..lineTo(99, 41)
      ..lineTo(99, 80)
      ..lineTo(20, 80)
      ..close();

    canvas.drawPath(
      cab,
      Paint()..color = const Color(0xFFB9A0FF),
    );

    // Cab roof.
    final cabTop = Path()
      ..moveTo(38, 20)
      ..lineTo(48, 8)
      ..lineTo(70, 8)
      ..lineTo(80, 20)
      ..lineTo(68, 14)
      ..lineTo(50, 14)
      ..close();

    canvas.drawPath(
      cabTop,
      Paint()..color = const Color(0xFFE2D6FF),
    );

    // Windshield.
    final windshield = Path()
      ..moveTo(39, 26)
      ..lineTo(50, 20)
      ..lineTo(68, 20)
      ..lineTo(83, 40)
      ..lineTo(30, 40)
      ..close();

    canvas.drawPath(
      windshield,
      Paint()..color = const Color(0xFF403552),
    );

    // Glass reflection.
    canvas.drawLine(
      const Offset(48, 23),
      const Offset(66, 38),
      Paint()
        ..color = const Color(0xFFEDE5FF)
            .withValues(alpha: 0.78)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );

    // Door seam.
    canvas.drawLine(
      const Offset(75, 45),
      const Offset(75, 76),
      Paint()
        ..color = const Color(0xFF7959C1)
        ..strokeWidth = 2,
    );

    // Door handle.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(59, 49, 8, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = Colors.white,
    );

    // Headlight at the front left.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 66, 9, 7),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFFE8AC),
    );

    // Front bumper.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(12, 76, 24, 8),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFEDE5FF),
    );

    // Lower chassis.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(24, 79, 180, 8),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF625078),
    );

    // Wheels and hubs.
    for (final center in const [
      Offset(52, 85),
      Offset(164, 85),
    ]) {
      canvas.drawCircle(
        center,
        17,
        Paint()..color = const Color(0xFF17131F),
      );

      canvas.drawCircle(
        center,
        10,
        Paint()..color = const Color(0xFF81718F),
      );

      canvas.drawCircle(
        center,
        5,
        Paint()..color = const Color(0xFFE7DBFF),
      );

      canvas.drawCircle(
        center,
        2,
        Paint()..color = const Color(0xFF9674E8),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _TruckPainter oldDelegate,
  ) {
    return false;
  }
}