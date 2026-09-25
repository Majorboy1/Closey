import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/closey_colors.dart';
import '../theme/closey_motion.dart';
import '../theme/closey_spacing.dart';
import '../widgets/closey_avatar.dart';

/// Swipeable photo gallery with tappable progress segments.
///
/// The Expo `DateCard` showed exactly one photo per profile, which is a real
/// product problem for a photo-forward dating app — you cannot evaluate
/// someone from a single image, and `photos[]` was already in the schema.
///
/// Tapping the left third goes back, the right two-thirds advances — the
/// convention every other dating app uses, so it needs no explanation.
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({
    super.key,
    required this.imageUrls,
    required this.name,
    this.aspectRatio,
    this.borderRadius = Radii.lg,
    this.showSegments = true,
    this.overlay,
    this.onTap,
  });

  final List<String> imageUrls;
  final String name;
  final double? aspectRatio;
  final double borderRadius;
  final bool showSegments;
  final Widget? overlay;
  final VoidCallback? onTap;

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  late final PageController _controller = PageController();
  int _index = 0;

  List<String> get _urls => widget.imageUrls.isEmpty
      ? [CloseyAvatar.illustratedUrl(widget.name)]
      : widget.imageUrls;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details) {
    widget.onTap?.call();
    if (details.localPosition.dx < context.size!.width * 0.32) {
      _go(_index - 1);
    } else {
      _go(_index + 1);
    }
  }

  void _go(int target) {
    if (target < 0 || target >= _urls.length) return;
    _controller.animateToPage(
      target,
      duration: context.motion(Motion.quick),
      curve: Motion.standard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AspectRatio(
      aspectRatio: widget.aspectRatio ?? 3 / 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTapUp: _handleTap,
              child: PageView.builder(
                controller: _controller,
                itemCount: _urls.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => CachedNetworkImage(
                  imageUrl: _urls[i],
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (_, _) => Container(color: c.surfaceSunken),
                  errorWidget: (_, _, _) => Container(
                    color: c.surfaceSunken,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.person_outline_rounded,
                      size: 48,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ),
            ),

            // Bottom scrim so overlay text always has contrast, regardless of
            // how bright the photo is. The Expo version used a fixed 18% wash
            // which was not enough on light photos and too much on dark ones.
            if (widget.overlay != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.72),
                      ],
                      stops: const [0.42, 1.0],
                    ),
                  ),
                ),
              ),

            if (widget.showSegments && _urls.length > 1)
              Positioned(
                top: Gap.md,
                left: Gap.md,
                right: Gap.md,
                child: Row(
                  children: List.generate(_urls.length, (i) {
                    final active = i == _index;
                    return Expanded(
                      child: AnimatedContainer(
                        duration: context.motion(Motion.quick),
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: active ? 0.95 : 0.35,
                          ),
                          borderRadius: Radii.pill,
                        ),
                      ),
                    );
                  }),
                ),
              ),

            if (widget.overlay != null)
              Positioned(
                left: Gap.xl,
                right: Gap.xl,
                bottom: Gap.xl,
                child: widget.overlay!,
              ),
          ],
        ),
      ),
    );
  }
}
