import 'package:flutter/material.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/theme/app_theme.dart';

/// A film poster thumbnail that opens [PosterViewer] full screen on tap.
///
/// Shared by the film card and the film info sheet, which used to each
/// carry their own copy of the same image/placeholder/error code. With no
/// poster URL at all it's a plain, non-tappable placeholder - there would be
/// nothing to open. A URL that failed to load here stays tappable: the
/// viewer requests it again, so a transient network blip isn't final.
class PosterThumbnail extends StatelessWidget {
  const PosterThumbnail({
    super.key,
    required this.url,
    required this.width,
    required this.height,
  });

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.surfaceElevated,
    );
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: url == null
          ? placeholder
          : GestureDetector(
              onTap: () => showPosterViewer(context, url),
              child: Image.network(
                url,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
              ),
            ),
    );
  }
}

/// Opens [url] full screen, zoomable. Deliberately a fade rather than a
/// Hero flight from the thumbnail: two cards on the same screen can share
/// one poster URL (18tickets lists the same film twice under disambiguated
/// titles), and duplicate Hero tags within a route are a hard assertion.
Future<void> showPosterViewer(BuildContext context, String url) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, _, _) => PosterViewer(url: url),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class PosterViewer extends StatefulWidget {
  const PosterViewer({super.key, required this.url});

  final String url;

  @override
  State<PosterViewer> createState() => _PosterViewerState();
}

class _PosterViewerState extends State<PosterViewer>
    with SingleTickerProviderStateMixin {
  static const _maxScale = 5.0;
  static const _doubleTapScale = 2.5;

  final _controller = TransformationController();
  // Created eagerly in initState, not as a lazy `late final` field: a lazy
  // one is first touched in dispose() whenever the poster is closed without
  // ever being double-tapped, and creating a ticker during unmount looks up
  // an already-deactivated ancestor - an error on every plain open/close.
  late final AnimationController _zoomAnimation;
  Animation<Matrix4>? _zoomTween;
  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => _controller.value = _zoomTween!.value);
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Double tap zooms in on the tapped spot, or back out if already zoomed -
  /// pinch alone is awkward one-handed, which is how a phone held in a
  /// cinema queue usually is.
  void _onDoubleTap() {
    final zoomedIn = _controller.value.getMaxScaleOnAxis() > 1.01;
    final Matrix4 target;
    if (zoomedIn) {
      target = Matrix4.identity();
    } else {
      final p = _doubleTapPosition;
      target = Matrix4.identity()
        ..translateByDouble(
          -p.dx * (_doubleTapScale - 1),
          -p.dy * (_doubleTapScale - 1),
          0,
          1,
        )
        ..scaleByDouble(_doubleTapScale, _doubleTapScale, 1, 1);
    }
    _zoomTween = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOut));
    _zoomAnimation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTapPosition = d.localPosition,
              onDoubleTap: _onDoubleTap,
              child: InteractiveViewer(
                transformationController: _controller,
                maxScale: _maxScale,
                child: Center(
                  child: Image.network(
                    widget.url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : const CircularProgressIndicator(),
                    errorBuilder: (_, _, _) => Text(
                      t.posterLoadError,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.close),
                  tooltip: t.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
