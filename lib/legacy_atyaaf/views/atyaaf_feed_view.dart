import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../controllers/atyaaf_controller.dart';
import '../models/atyaaf_video_model.dart';

class AtyaafFeedView extends StatefulWidget {
  const AtyaafFeedView({super.key});
  @override
  State<AtyaafFeedView> createState() => _AtyaafFeedViewState();
}

class _AtyaafFeedViewState extends State<AtyaafFeedView> {
  late final AtyaafController controller;
  late final PageController pageController;
  @override
  void initState() {
    super.initState();
    controller = AtyaafController();
    pageController = PageController();
    unawaited(controller.loadVideos());
  }
  @override
  void dispose() {
    pageController.dispose();
    controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.isLoading && controller.videos.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          if (controller.errorMessage != null && controller.videos.isEmpty) {
            return Center(
              child: Text(
                controller.errorMessage!,
                style: const TextStyle(color: Colors.white),
              ),
            );
          }
          if (controller.videos.isEmpty) {
            return const Center(
              child: Text('لا توجد فيديوهات حالياً', style: TextStyle(color: Colors.white)),
            );
          }
          return PageView.builder(
            controller: pageController,
            scrollDirection: Axis.vertical,
            itemCount: controller.videos.length,
            onPageChanged: (index) async {
              controller.setCurrentIndex(index);
              await controller.preloadAdjacentVideos(index);
              final video = controller.videos[index];
              await controller.playActiveVideo(video.id);
            },
            itemBuilder: (context, index) {
              final video = controller.videos[index];
              final isActive = controller.currentIndex == index;
              return AtyaafVideoTile(
                video: video,
                isActive: isActive,
                controller: controller,
              );
            },
          );
        },
      ),
    );
  }
}
class AtyaafVideoTile extends StatefulWidget {
  const AtyaafVideoTile({
    super.key,
    required this.video,
    required this.isActive,
    required this.controller,
  });
  final AtyaafVideoModel video;
  final bool isActive;
  final AtyaafController controller;
  @override
  State<AtyaafVideoTile> createState() => _AtyaafVideoTileState();
}
class _AtyaafVideoTileState extends State<AtyaafVideoTile> {
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }
  Future<void> _initialize() async {
    await widget.controller.initializeController(
      widget.video,
      autoPlay: widget.isActive,
    );
    if (widget.isActive) {
      await widget.controller.playActiveVideo(widget.video.id);
    } else {
      await widget.controller.pauseVideo(widget.video.id);
    }
  }
  @override
  void didUpdateWidget(covariant AtyaafVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        unawaited(widget.controller.playActiveVideo(widget.video.id));
      } else {
        unawaited(widget.controller.pauseVideo(widget.video.id));
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final playerController = widget.controller.controllerFor(widget.video.id);
    return GestureDetector(
      onTap: () async {
        await widget.controller.playActiveVideo(widget.video.id);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (playerController != null && playerController.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: playerController.value.size.width,
                height: playerController.value.size.height,
                child: VideoPlayer(playerController),
              ),
            )
          else
            CachedNetworkImage(
              imageUrl: widget.video.thumbnailUrl.isNotEmpty
                  ? widget.video.thumbnailUrl
                  : 'https://images.unsplash.com/photo-1516280440614-37939bbacd81?auto=format&fit=crop&w=900&q=80',
              fit: BoxFit.cover,
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.video.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        final ref = widget.video.relatedContentRef;
                        if (ref != null && ref.isNotEmpty) {
                          Navigator.pushNamed(context, ref);
                        }
                      },
                      icon: const Icon(Icons.link_rounded),
                      label: const Text('انتقال للمحتوى المرتبط'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B61FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      onPressed: () async {
                        await widget.controller.toggleFavorite(widget.video.id);
                      },
                      icon: Icon(
                        widget.controller.isFavorite(widget.video.id)
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                      ),
                      color: Colors.white,
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
