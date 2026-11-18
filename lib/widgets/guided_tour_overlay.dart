import '../theme/app_palette.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/guided_tour_service.dart';

/// Overlay widget that renders the spotlight cutout and tooltip card over its child.
class GuidedTourOverlay extends ConsumerStatefulWidget {
  const GuidedTourOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends ConsumerState<GuidedTourOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    ref.listenManual(
      guidedTourNotifierProvider.select((tour) => tour.isActive),
      (_, active) {
        if (active) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Rect? _getRectForTarget(GlobalKey targetKey) {
    final ctx = targetKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    try {
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached || !renderBox.hasSize) {
        return null;
      }

      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      return position & size;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tourState = ref.watch(guidedTourNotifierProvider);
    final tourNotifier = ref.read(guidedTourNotifierProvider.notifier);

    if (!tourState.isActive || tourState.currentStep == null) {
      return widget.child;
    }

    final currentStep = tourState.currentStep!;
    final targetRect = _getRectForTarget(currentStep.targetKey);
    final screenSize = MediaQuery.sizeOf(context);

    // Padding around highlighted target
    const padding = 8.0;
    final paddedRect =
        targetRect != null
            ? RRect.fromRectAndRadius(
              targetRect.inflate(padding),
              const Radius.circular(12),
            )
            : null;

    return Stack(
      children: [
        widget.child,

        // 1. Dark spotlight background with hole cutout
        Positioned.fill(
          child: CustomPaint(
            painter: _SpotlightPainter(
              targetRect: paddedRect,
              overlayColor: Colors.black.withValues(alpha: 0.78),
            ),
          ),
        ),

        // 2. Animated focus border around the target element
        if (paddedRect != null)
          Positioned(
            left: paddedRect.left,
            top: paddedRect.top,
            width: paddedRect.width,
            height: paddedRect.height,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final opacity = 0.4 + (_pulseController.value * 0.6);
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppPalette.text.withValues(alpha: opacity),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppPalette.text.withValues(alpha: opacity * 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

        // 3. Floating Tooltip Card
        _buildTooltipCard(
          context: context,
          screenSize: screenSize,
          targetRect: paddedRect,
          currentStep: currentStep,
          tourState: tourState,
          notifier: tourNotifier,
        ),
      ],
    );
  }

  Widget _buildTooltipCard({
    required BuildContext context,
    required Size screenSize,
    required RRect? targetRect,
    required GuidedTourStep currentStep,
    required GuidedTourState tourState,
    required GuidedTourNotifier notifier,
  }) {
    // Calculate card positioning
    double cardTop;
    final cardHeightEstimate = 220.0;
    final margin = 16.0;

    if (targetRect == null) {
      cardTop = (screenSize.height - cardHeightEstimate) / 2;
    } else {
      if (currentStep.tooltipPosition == TooltipPosition.top &&
          targetRect.top - cardHeightEstimate - margin > 40) {
        cardTop = targetRect.top - cardHeightEstimate - margin;
      } else if (targetRect.bottom + cardHeightEstimate + margin <
          screenSize.height - 40) {
        cardTop = targetRect.bottom + margin;
      } else {
        // Fallback: place above or below whichever has more space
        if (targetRect.top > screenSize.height / 2) {
          cardTop = (targetRect.top - cardHeightEstimate - margin).clamp(
            40.0,
            screenSize.height - 240.0,
          );
        } else {
          cardTop = (targetRect.bottom + margin).clamp(
            40.0,
            screenSize.height - 240.0,
          );
        }
      }
    }

    return Positioned(
      top: cardTop,
      left: margin,
      right: margin,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppPalette.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppPalette.text.withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step Indicator Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.text.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppPalette.text.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'STEP ${tourState.currentStepIndex + 1} OF ${tourState.steps.length}',
                          style: GoogleFonts.spaceMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.text,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.close,
                          color: AppPalette.muted,
                          size: 18,
                        ),
                        onPressed: notifier.completeTour,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Step Title
                  Text(
                    currentStep.title,
                    style: GoogleFonts.spaceMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Step Description
                  Text(
                    currentStep.description,
                    style: GoogleFonts.spaceMono(
                      fontSize: 12,
                      color: AppPalette.muted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Action Buttons Footer
                  Row(
                    children: [
                      // Skip Tour Button
                      TextButton(
                        onPressed: notifier.completeTour,
                        style: TextButton.styleFrom(
                          foregroundColor: AppPalette.muted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          'Skip',
                          style: GoogleFonts.spaceMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),

                      // Back Button
                      if (!tourState.isFirstStep)
                        OutlinedButton(
                          onPressed: notifier.previousStep,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppPalette.border),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            'Back',
                            style: GoogleFonts.spaceMono(fontSize: 12),
                          ),
                        ),
                      if (!tourState.isFirstStep) const SizedBox(width: 8),

                      // Next / Got It Button
                      ElevatedButton(
                        onPressed: notifier.nextStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.text,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          tourState.isLastStep ? 'Got It!' : 'Next',
                          style: GoogleFonts.spaceMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws a dark translucent background with a hole cutout over the target element.
class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.targetRect, required this.overlayColor});

  final RRect? targetRect;
  final Color overlayColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;

    if (targetRect == null) {
      canvas.drawRect(Offset.zero & size, paint);
      return;
    }

    final backgroundPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(targetRect!);

    final combinedPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.overlayColor != overlayColor;
  }
}
