import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'storage_service.dart';

/// Channel avatar with a letter fallback — used everywhere a channel is
/// shown (home feed, player, channel screens).
class ChannelAvatar extends StatelessWidget {
  final String avatarUrl;
  final String name;
  final double radius;

  const ChannelAvatar({
    super.key,
    required this.avatarUrl,
    required this.name,
    this.radius = 17,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (avatarUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.9,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: avatarUrl,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: radius * 2,
            height: radius * 2,
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) => Container(
            width: radius * 2,
            height: radius * 2,
            color: theme.colorScheme.primaryContainer,
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.9,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal video row used in search results, related videos,
/// channel listings and history.
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
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    width: 140,
                    height: 80,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                        width: 140, height: 80, color: Colors.grey[800]),
                    errorWidget: (_, __, ___) => Container(
                      width: 140,
                      height: 80,
                      color: Colors.grey[800],
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                  if (video.duration != null &&
                      video.duration!.inSeconds > 0)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text(
                            formatDuration(video.duration!),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                ],
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

/// Big YouTube-style home tile: full-width thumbnail with the title and
/// channel info underneath.
class YouTubeVideoTile extends StatelessWidget {
  final VideoItem video;
  final VoidCallback onTap;

  const YouTubeVideoTile({super.key, required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      if (video.uploader.isNotEmpty) video.uploader,
      if (video.viewCount != null) '${formatViews(video.viewCount)} views',
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: video.thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image, size: 44),
                  ),
                ),
                if (video.duration != null &&
                    video.duration!.inSeconds > 0)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        child: Text(
                          formatDuration(video.duration!),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChannelAvatar(
                  avatarUrl: video.uploaderAvatarUrl,
                  name: video.uploader,
                  radius: 17,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[500] ??
                              theme.colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Music row with thumbnail, title, uploader and a like button.
class MusicListTile extends StatelessWidget {
  final VideoItem song;
  final bool liked;
  final VoidCallback onTap;
  final VoidCallback onToggleLike;

  const MusicListTile({
    super.key,
    required this.song,
    required this.liked,
    required this.onTap,
    required this.onToggleLike,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: song.thumbnailUrl.isEmpty
            ? Container(
                width: 52,
                height: 52,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note),
              )
            : CachedNetworkImage(
                imageUrl: song.thumbnailUrl,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 52,
                  height: 52,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.music_note),
                ),
              ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song.uploader,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        onPressed: onToggleLike,
        icon: Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          color: liked ? Colors.red : null,
        ),
        tooltip: liked ? 'Remove from liked songs' : 'Like song',
      ),
      onTap: onTap,
    );
  }
}

class ChannelTile extends StatelessWidget {
  final ChannelItem channel;
  final VoidCallback onTap;

  const ChannelTile({super.key, required this.channel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ChannelAvatar(
        avatarUrl: channel.thumbnailUrl,
        name: channel.name,
        radius: 26,
      ),
      title: Text(channel.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: channel.subscriberCount != null
          ? Text('${channel.subscriberCount} subscribers',
              style: TextStyle(color: Colors.grey[500], fontSize: 12))
          : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

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
              isSubscribed
                  ? Icons.notifications_active
                  : Icons.notifications_none,
              color: isSubscribed ? Colors.red : Colors.grey,
            ),
            tooltip: isSubscribed ? 'Unsubscribe' : 'Subscribe',
            onPressed: () => storage.toggleSubscribe(
              channelUrl: channelUrl,
              channelName: channelName,
              thumbnail: thumbnail,
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              onPressed: () => storage.toggleSubscribe(
                channelUrl: channelUrl,
                channelName: channelName,
                thumbnail: thumbnail,
              ),
              icon: Icon(isSubscribed ? Icons.check : Icons.add, size: 18),
              label: Text(isSubscribed ? 'Subscribed' : 'Subscribe'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isSubscribed ? Colors.grey[800] : Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
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

/// Live search suggestions shown while the user types.
class SuggestionList extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onSelected;
  final String hintText;

  const SuggestionList({
    super.key,
    required this.suggestions,
    required this.onSelected,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            hintText,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: suggestions.length,
      itemBuilder: (context, index) => ListTile(
        dense: true,
        leading: const Icon(Icons.search),
        title: Text(
          suggestions[index],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => onSelected(suggestions[index]),
      ),
    );
  }
}

/// Search landing page: recent searches (history) followed by live
/// suggestions. While typing, matching history entries appear first,
/// exactly like the official app.
class SearchHistoryAndSuggestions extends StatelessWidget {
  final TextEditingController controller;
  final List<String> suggestions;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchFromHistory;
  final String emptyHint;

  const SearchHistoryAndSuggestions({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.onSearch,
    required this.onSearchFromHistory,
    this.emptyHint = 'Search to get started',
  });

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final history = storage.getSearchHistory();
    final query = controller.text.trim().toLowerCase();

    // Matching history entries float to the top while typing.
    final historyMatches = query.isEmpty
        ? history.take(10).toList()
        : history
            .where((entry) => entry.toLowerCase().contains(query))
            .take(3)
            .toList();
    // Do not repeat a history entry that is also a live suggestion.
    final uniqueSuggestions =
        suggestions.where((s) => !historyMatches.contains(s)).toList();

    if (historyMatches.isEmpty && uniqueSuggestions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            query.isEmpty && history.isEmpty ? emptyHint : 'No matches',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (historyMatches.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recent searches',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: () => storage.clearSearchHistory(),
                    child: const Text('Clear all'),
                  ),
              ],
            ),
          ),
          for (final entry in historyMatches)
            ListTile(
              dense: true,
              leading: const Icon(Icons.history),
              title: Text(
                entry,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove',
                onPressed: () => storage.removeSearchQuery(entry),
              ),
              onTap: () => onSearchFromHistory(entry),
            ),
          if (uniqueSuggestions.isNotEmpty)
            const Divider(height: 16, indent: 20, endIndent: 20),
        ],
        if (uniqueSuggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              query.isEmpty ? 'Suggestions' : 'Search suggestions',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        for (final suggestion in uniqueSuggestions)
          ListTile(
            dense: true,
            leading: const Icon(Icons.search),
            title: Text(
              suggestion,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              controller.text = suggestion;
              controller.selection = TextSelection.collapsed(
                offset: controller.text.length,
              );
              onSearch();
            },
          ),
      ],
    );
  }
}

// ═══════════════════════ SKELETONS ═══════════════════════

/// One animated shimmer placeholder box. Needs a repeating [Animation]
/// (owned by the skeleton screen) so only one ticker runs per screen.
class ShimmerBox extends StatelessWidget {
  final Animation<double> animation;
  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerBox({
    super.key,
    required this.animation,
    required this.height,
    this.width,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF232323) : Colors.grey.shade300;
    final highlight = isDark ? const Color(0xFF3C3C3C) : Colors.grey.shade100;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-2.0 + 4.0 * t, 0),
              end: Alignment(-1.0 + 4.0 * t, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton for the YouTube-style home feed (big tiles).
class VideoFeedSkeleton extends StatefulWidget {
  final int count;

  const VideoFeedSkeleton({super.key, this.count = 4});

  @override
  State<VideoFeedSkeleton> createState() => _VideoFeedSkeletonState();
}

class _VideoFeedSkeletonState extends State<VideoFeedSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: List.generate(widget.count, (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ShimmerBox(
                  animation: _controller,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.zero,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      animation: _controller,
                      width: 34,
                      height: 34,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerLine(animation: _controller, height: 15),
                          const SizedBox(height: 8),
                          ShimmerLine(animation: _controller, height: 12, width: 130),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )),
    );
  }
}

/// Skeleton for compact list rows (search results, related lists).
class ListSkeleton extends StatefulWidget {
  final int count;

  const ListSkeleton({super.key, this.count = 8});

  @override
  State<ListSkeleton> createState() => _ListSkeletonState();
}

class _ListSkeletonState extends State<ListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.count,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ShimmerBox(
              animation: _controller,
              width: 140,
              height: 80,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLine(animation: _controller, height: 15),
                  const SizedBox(height: 8),
                  ShimmerLine(animation: _controller, height: 12, width: 120),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for music rows (square thumb + two lines).
class MusicListSkeleton extends StatefulWidget {
  final int count;

  const MusicListSkeleton({super.key, this.count = 10});

  @override
  State<MusicListSkeleton> createState() => _MusicListSkeletonState();
}

class _MusicListSkeletonState extends State<MusicListSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: widget.count,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ShimmerBox(
              animation: _controller,
              width: 52,
              height: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerLine(animation: _controller, height: 14),
                  const SizedBox(height: 8),
                  ShimmerLine(animation: _controller, height: 11, width: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single shimmer text line with a random-ish width so rows do not look
/// copy-pasted.
class ShimmerLine extends StatelessWidget {
  final Animation<double> animation;
  final double height;
  final double? width;

  const ShimmerLine({
    super.key,
    required this.animation,
    required this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    // Deterministic pseudo-random width from the animation identity.
    final seed = identityHashCode(this) % 60;
    final w = width ?? (200.0 + seed.toDouble());
    return ShimmerBox(
      animation: animation,
      width: w,
      height: height,
      borderRadius: BorderRadius.circular(4),
    );
  }
}

// ═══════════════════════ FORMATTERS ═══════════════════════

String formatDuration(Duration duration) {
  if (duration.isNegative) return '';
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (minutes >= 60) {
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// 1234567 → "1.2M", 45200 → "45K"
String formatViews(int? count) {
  if (count == null) return '';
  if (count >= 1000000000) {
    return '${(count / 1000000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}B';
  }
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}K';
  }
  return count.toString();
}
