import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A thin strip of film-sprocket perforations, used as a section divider.
///
/// This is the app's one recurring visual signature: a nod to 35mm film
/// stock, reused everywhere a plain `Divider` would otherwise go (under the
/// app bar, between the day selector and the film list). Deliberately quiet
/// - a single muted-tone row, not a decorative flourish.
class FilmPerforationDivider extends StatelessWidget {
  const FilmPerforationDivider({super.key, this.height = 10});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _PerforationPainter()),
    );
  }
}

class _PerforationPainter extends CustomPainter {
  const _PerforationPainter();

  static const double _holeSpacing = 18;
  static const double _holeSize = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.hairline;
    final holeCount = (size.width / _holeSpacing).floor();
    final startX = (size.width - (holeCount - 1) * _holeSpacing) / 2;
    final centerY = size.height / 2;

    for (var i = 0; i < holeCount; i++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(startX + i * _holeSpacing, centerY),
          width: _holeSize,
          height: _holeSize,
        ),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PerforationPainter oldDelegate) => false;
}
