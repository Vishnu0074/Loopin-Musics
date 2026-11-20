import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum LoopinSnackBarType { info, success, error }

class CustomSnackBar {
  CustomSnackBar._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
    Widget? action,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    _dismissCurrent();

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isTablet = screenWidth >= 600;
    final maxWidth = isTablet ? 520.0 : screenWidth - 32;
    final baseTint = isError ? const Color(0xFFB3261E) : AppColors.accent;

    _currentEntry = OverlayEntry(
      builder: (overlayContext) => IgnorePointer(
        ignoring: action == null,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                12 + mediaQuery.viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            baseTint.withValues(alpha: 0.45),
                            baseTint.withValues(alpha: 0.28),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isError
                                ? Icons.error_outline
                                : Icons.check_circle_outline,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: const TextStyle(
                                shadows: <Shadow>[
                                  Shadow(
                                    color: Color.fromARGB(255, 124, 123, 123),
                                    offset: Offset(0, 0),
                                    blurRadius: 20,
                                  ),
                                ],
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          if (action != null) ...[
                            const SizedBox(width: 8),
                            action,
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_currentEntry!);
    _dismissTimer = Timer(duration, _dismissCurrent);
  }

  static void hide() => _dismissCurrent();

  static void _dismissCurrent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

/// LoopinSnackBar adapter maintaining backwards compatibility with call sites
/// across the application while using the CustomSnackBar presentation style.
class LoopinSnackBar {
  static void show(
    BuildContext context,
    String message, {
    LoopinSnackBarType type = LoopinSnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    Widget? action,
  }) {
    CustomSnackBar.show(
      context,
      message: message,
      isError: type == LoopinSnackBarType.error,
      duration: duration,
      action: action,
    );
  }

  static void dismiss() => CustomSnackBar.hide();
}
