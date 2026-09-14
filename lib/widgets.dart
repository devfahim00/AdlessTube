import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'storage_service.dart';

class VideoTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const VideoTile({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                width: 140,
                height: 80,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(width: 140, height: 80, color: Colors.grey[800]),
                errorWidget: (_, __, ___) => Container(
                  width: 140,
                  height: 80,
                  color: Colors.grey[800],
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.uploader,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subscribe / Unsubscribe button (channel name এর পাশে)
class SubscribeButton extends StatelessWidget {
  final String channelUrl;
  final String channelName;
  final String thumbnail;
  final bool compact;

  const SubscribeButton({
    super.key,
    required this.channelUrl,
    required this.channelName,
    this.thumbnail = '',
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final isSubscribed = storage.isSubscribed(channelUrl);

    return compact
        ? IconButton(
            icon: Icon(
              isSubscribed ? Icons.notifications_active : Icons.notifications_none,
              color: isSubscribed ? Colors.red : Colors.grey,
            ),
            tooltip: isSubscribed ? 'Unsubscribe' : 'Subscribe',
            onPressed: () => storage.toggleSubscribe(
              channelUrl: channelUrl,
              channelName: channelName,
              thumbnail: thumbnail,
            ),
          )
        : ElevatedButton.icon(
            onPressed: () => storage.toggleSubscribe(
              channelUrl: channelUrl,
              channelName: channelName,
              thumbnail: thumbnail,
            ),
            icon: Icon(isSubscribed ? Icons.check : Icons.add),
            label: Text(isSubscribed ? 'Subscribed' : 'Subscribe'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isSubscribed ? Colors.grey[800] : Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
  }
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
