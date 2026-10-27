import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'theme.dart';

class StudioSection extends StatelessWidget {
  const StudioSection({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black54,
                    height: 1.7,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 42, color: studioGold),
          const SizedBox(height: 18),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, height: 1.8),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class NoticePanel extends StatelessWidget {
  const NoticePanel({
    super.key,
    required this.message,
    this.error = false,
    this.action,
  });
  final String message;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFBEDEA) : const Color(0xFFF0EBDF),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.error_outline : Icons.info_outline,
          color: error ? Colors.red.shade800 : studioGold,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: const TextStyle(height: 1.8))),
        if (action != null) action!,
      ],
    ),
  );
}

String clockLabel(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class AudioPanel extends StatefulWidget {
  const AudioPanel({super.key, required this.path, this.onError});
  final String path;
  final ValueChanged<String>? onError;
  @override
  State<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<AudioPanel> {
  final _player = AudioPlayer();
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AudioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _player.setFilePath(widget.path);
      if (mounted) {
        setState(() => _loading = false);
      }
    } on Exception {
      const message =
          'অডিও চালানো যাচ্ছে না। ফাইলটি ক্ষতিগ্রস্ত বা এই যন্ত্রে সমর্থিত নয়।';
      if (mounted) {
        setState(() {
          _loading = false;
          _error = message;
        });
      }
      widget.onError?.call(message);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return NoticePanel(message: _error!, error: true);
    }
    return StreamBuilder<Duration?>(
      stream: _player.durationStream,
      builder: (context, durationSnapshot) {
        final duration =
            durationSnapshot.data ?? _player.duration ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final max = duration.inMilliseconds.toDouble();
            return Column(
              children: [
                Slider(
                  value: position.inMilliseconds.toDouble().clamp(
                    0.0,
                    max > 0 ? max : 1.0,
                  ),
                  max: max > 0 ? max : 1.0,
                  onChanged: max > 0
                      ? (value) =>
                            _player.seek(Duration(milliseconds: value.toInt()))
                      : null,
                  semanticFormatterCallback: (value) =>
                      clockLabel(Duration(milliseconds: value.toInt())),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(clockLabel(position)),
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (context, snapshot) {
                        final state = snapshot.data;
                        final ended =
                            state?.processingState == ProcessingState.completed;
                        final playing = state?.playing ?? false;
                        return IconButton.filled(
                          tooltip: ended
                              ? 'আবার শুনুন'
                              : playing
                              ? 'বিরতি'
                              : 'শুনুন',
                          onPressed: () async {
                            try {
                              if (ended) {
                                await _player.seek(Duration.zero);
                              }
                              if (playing && !ended) {
                                await _player.pause();
                              } else {
                                await _player.play();
                              }
                            } on Exception {
                              if (mounted) {
                                setState(
                                  () => _error =
                                      'অডিও চালানো যায়নি। আবার চেষ্টা করুন।',
                                );
                              }
                            }
                          },
                          icon: Icon(
                            ended
                                ? Icons.replay
                                : playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        );
                      },
                    ),
                    Text(clockLabel(duration)),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
