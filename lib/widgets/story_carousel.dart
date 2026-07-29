import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/story.dart';

class StoryCarousel extends StatefulWidget {
  final List<Story> stories;
  final void Function(Story) onStoryTap;

  const StoryCarousel({super.key, required this.stories, required this.onStoryTap});

  @override
  State<StoryCarousel> createState() => _StoryCarouselState();
}

class _StoryCarouselState extends State<StoryCarousel> {
  late final PageController _pageController;
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.72);
    _pageController.addListener(() {
      setState(() {
        _page = _pageController.page ?? _page;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;
    final borderGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        theme.colorScheme.primary.withOpacity(0.7),
        theme.colorScheme.secondary.withOpacity(0.55),
      ],
    );

    return SizedBox(
      height: 360,
      child: PageView.builder(
        controller: _pageController,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        scrollDirection: Axis.horizontal,
        itemCount: widget.stories.length + 1,
        padEnds: false,
        itemBuilder: (context, index) {
          final isCreateCard = index == 0;
          final cardIndex = index - 1;
          final scale = _calculateScale(index);

          return Transform.scale(
            scale: scale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: isCreateCard
                  ? _CreateStoryCard(
                      gradient: borderGradient,
                      surfaceColor: surface,
                      textColor: onSurface,
                    )
                  : _StoryCard(
                      story: widget.stories[cardIndex],
                      onTap: () => widget.onStoryTap(widget.stories[cardIndex]),
                      gradient: borderGradient,
                      surfaceColor: surface,
                      textColor: onSurface,
                    ),
            ),
          );
        },
      ),
    );
  }

  double _calculateScale(int index) {
    final difference = (index - _page).abs();
    return (1 - (difference * 0.12)).clamp(0.86, 1.0);
  }
}

class _StoryCard extends StatelessWidget {
  final Story story;
  final VoidCallback onTap;
  final Gradient gradient;
  final Color surfaceColor;
  final Color textColor;

  const _StoryCard({
    required this.story,
    required this.onTap,
    required this.gradient,
    required this.surfaceColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(story.timestamp);
    final progress = _storyProgress(story.timestamp);
    return Semantics(
      button: true,
      label: 'قصة ${story.username}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: gradient,
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(20, 24, 48, 0.18),
                blurRadius: 32,
                offset: Offset(0, 18),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              children: [
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      color: surfaceColor.withOpacity(0.28),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withOpacity(0.14), width: 1.2),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  left: 14,
                  child: Hero(
                    tag: 'story-${story.id}',
                    child: Container(
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        image: DecorationImage(
                          image: CachedNetworkImageProvider(story.imageUrl),
                          fit: BoxFit.cover,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.18),
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.22),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 14,
                            right: 14,
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [Color(0xFF66FFB3), Color(0xFF1EE8B9)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1EE8B9).withOpacity(0.32),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            bottom: 14,
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withAlpha(71), width: 1.5),
                                gradient: const LinearGradient(
                                  colors: [Color(0x66FFFFFF), Color(0x19FFFFFF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: story.imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.white24),
                                  errorWidget: (context, url, error) => Container(color: Colors.white24),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  left: 20,
                  right: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              story.username,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.circle, size: 10, color: Colors.greenAccent.shade400),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          color: textColor.withAlpha((0.78 * 255).round()),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.white.withAlpha(31),
                          valueColor: AlwaysStoppedAnimation(Colors.white.withAlpha(235)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return '${diff.inMinutes} د';
    if (diff.inDays < 1) return '${diff.inHours} س';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  double _storyProgress(DateTime timestamp) {
    final age = DateTime.now().difference(timestamp).inMinutes;
    return (1 - ((age % 60) / 60)).clamp(0.05, 1.0);
  }
}

class _CreateStoryCard extends StatefulWidget {
  final Gradient gradient;
  final Color surfaceColor;
  final Color textColor;

  const _CreateStoryCard({
    required this.gradient,
    required this.surfaceColor,
    required this.textColor,
  });

  @override
  State<_CreateStoryCard> createState() => _CreateStoryCardState();
}

class _CreateStoryCardState extends State<_CreateStoryCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 4))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final alignment = Alignment.lerp(Alignment.topLeft, Alignment.bottomRight, _controller.value)!;

        return Container(
          width: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: widget.gradient,
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(18, 22, 42, 0.18),
                blurRadius: 38,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Stack(
              children: [
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: widget.surfaceColor.withOpacity(0.26),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: alignment,
                        radius: 1.2,
                        colors: [
                          widget.textColor.withOpacity(0.12),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OrganicGlowPainter(color: widget.textColor.withOpacity(0.18)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFFFFF), Color(0xFFCFD8FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.32),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add, color: Color(0xFF0D1B4A), size: 30),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create Story',
                        style: TextStyle(
                          color: widget.textColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Capture your premium moment with elegant style.',
                        style: TextStyle(
                          color: widget.textColor.withOpacity(0.72),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white24,
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: 0.58,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF9E7CFF), Color(0xFF63F2FF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OrganicGlowPainter extends CustomPainter {
  final Color color;

  _OrganicGlowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.drawCircle(Offset(size.width * 0.18, size.height * 0.3), 56, paint);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.5), 42, paint);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.68, size.height * 0.18), width: 92, height: 52), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
