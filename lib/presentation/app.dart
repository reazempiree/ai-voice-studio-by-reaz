import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_controller.dart';
import '../domain/models.dart';
import '../data/pocket_model_store.dart';
import 'components.dart';
import 'theme.dart';

class VoiceStudioApp extends StatelessWidget {
  const VoiceStudioApp({super.key, required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'কণ্ঠ · AI Voice Studio',
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
    home: StudioHome(controller: controller),
  );
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key, required this.controller});
  final AppController controller;
  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  int _tab = 0;
  late final TextEditingController _editor;
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _uploadConsent = false;
  bool _hideToken = true;
  String? _previewId;
  Timer? _modelRefresh;
  bool _refreshingModels = false;
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _editor = TextEditingController(text: c.text);
    _url = TextEditingController(text: c.backendUrl);
    _token = TextEditingController(text: c.token);
    _modelRefresh = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_tab != 4 ||
          _refreshingModels ||
          !c.models.any(
            (model) => [
              'downloading',
              'verifying',
            ].contains(model['status'] ?? model['state']),
          )) {
        return;
      }
      _refreshingModels = true;
      try {
        await c.refreshModels();
      } finally {
        _refreshingModels = false;
      }
    });
  }

  @override
  void dispose() {
    _modelRefresh?.cancel();
    _editor.dispose();
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  void _navigate(int tab) {
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = tab;
      _previewId = null;
    });
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String label = 'নিশ্চিত করুন',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message, style: const TextStyle(height: 1.8)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ফিরে যান'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label),
            ),
          ],
        ),
      ) ??
      false;

  Future<String?> _nameDialog(String title, String initial) =>
      showDialog<String>(
        context: context,
        builder: (context) => _NameDialog(title: title, initial: initial),
      );

  Future<void> _import({VoiceProfile? replace}) async {
    final result = await showModalBottomSheet<_ImportDetails>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _ImportSheet(profile: replace, requiresTranscript: !c.isLocal),
    );
    if (result == null) {
      return;
    }
    if (replace == null) {
      await c.importProfile(
        name: result.name,
        referenceText: result.transcript,
        consent: result.consent,
      );
    } else {
      await c.replaceProfile(
        replace,
        referenceText: result.transcript,
        consent: result.consent,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: studioInk,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Color(0xFFD8C08D),
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'কণ্ঠ',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: .4),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'গোপনীয়তা ও তথ্য',
            icon: const Icon(Icons.shield_outlined),
            onPressed: _privacy,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (c.error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: NoticePanel(
                  message: c.error,
                  error: true,
                  action: IconButton(
                    tooltip: 'বার্তা বন্ধ করুন',
                    onPressed: c.clearError,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: switch (_tab) {
                    0 => _dashboard(),
                    1 => _generate(),
                    2 => _library(),
                    3 => _history(),
                    _ => _settings(),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _navigate,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'মূলপাতা',
          ),
          NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: 'তৈরি করুন',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: 'কণ্ঠ',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'ইতিহাস',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'সেটিংস',
          ),
        ],
      ),
    ),
  );

  Widget _scroll(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    children: children,
  );

  Widget _dashboard() => _scroll([
    const StudioSection(
      title: 'আপনার কণ্ঠ, আপনার গল্প',
      subtitle: 'বাংলা ও ইংরেজি লেখাকে নিজের অনুমোদিত কণ্ঠে রূপ দিন।',
    ),
    Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: studioInk,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14282824),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.multitrack_audio_rounded,
            color: Color(0xFFD8C08D),
            size: 42,
          ),
          const SizedBox(height: 22),
          const Text(
            'শব্দে থাকুক\nআপনার স্বর',
            style: TextStyle(
              fontSize: 29,
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'কণ্ঠের নমুনা সংরক্ষণ করুন। লেখা দিন।\nসংশ্লেষিত অডিও তৈরি ও রপ্তানি করুন।',
            style: TextStyle(color: Color(0xFFD8D5CD), height: 1.9),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD8C08D),
              foregroundColor: studioInk,
            ),
            onPressed: () => _navigate(1),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('শুরু করুন'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    NoticePanel(
      message: c.isLocal
          ? 'ফোনে ইংরেজি কণ্ঠ ক্লোনিং: মডেল একবার নামানোর পর সার্ভার বা টোকেন ছাড়াই তৈরি করুন। বাংলা ফোনের মডেলে সমর্থিত নয়।'
          : 'সংযুক্ত নিজস্ব সার্ভারে কণ্ঠ সংশ্লেষণ হবে। নমুনা পাঠানোর আগে আপনার অনুমতি নেওয়া হবে।',
    ),
    const SizedBox(height: 24),
    LayoutBuilder(
      builder: (context, constraints) {
        final items = [
          _DashboardTile(
            icon: Icons.auto_awesome_outlined,
            title: 'কণ্ঠ ক্লোনিং',
            subtitle: 'নমুনা থেকে নতুন কথা',
            onTap: () => _navigate(1),
          ),
          _DashboardTile(
            icon: Icons.text_fields_rounded,
            title: 'লেখা থেকে কথা',
            subtitle: 'বাংলা ও ইংরেজি',
            onTap: () => _navigate(1),
          ),
          _DashboardTile(
            icon: Icons.mic_none_rounded,
            title: 'কণ্ঠের সংগ্রহ',
            subtitle: '${c.profiles.length}টি সংরক্ষিত কণ্ঠ',
            onTap: () => _navigate(2),
          ),
          _DashboardTile(
            icon: Icons.library_music_outlined,
            title: 'অডিওর ইতিহাস',
            subtitle: '${c.history.length}টি সংরক্ষিত অডিও',
            onTap: () => _navigate(3),
          ),
        ];
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final item in items)
              SizedBox(
                width: constraints.maxWidth < 360
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 14) / 2,
                child: item,
              ),
          ],
        );
      },
    ),
    const SizedBox(height: 24),
    const Row(
      children: [
        Icon(Icons.lock_outline, size: 17, color: studioGold),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'কোনো বিজ্ঞাপন নেই · কোনো অ্যাকাউন্ট নেই',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
        ),
      ],
    ),
  ]);

  Widget _generate() {
    final selectedExists = c.profiles.any((p) => p.id == c.selectedProfileId);
    return _scroll([
      const StudioSection(
        title: 'নতুন অডিও তৈরি',
        subtitle: 'আপনার অনুমোদিত কণ্ঠের নমুনা দিয়ে লেখা থেকে কথা তৈরি করুন।',
      ),
      SegmentedButton<String>(
        key: const Key('inference-mode'),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
        segments: const [
          ButtonSegment(
            value: 'local',
            label: Text('ফোনে • ইংরেজি'),
            icon: Icon(Icons.smartphone, size: 17),
          ),
          ButtonSegment(
            value: 'server',
            label: Text('নিজস্ব সার্ভার'),
            icon: Icon(Icons.dns_outlined, size: 17),
          ),
        ],
        selected: {c.inferenceMode},
        onSelectionChanged: c.busy
            ? null
            : (values) {
                _uploadConsent = false;
                c.setInferenceMode(values.first);
              },
      ),
      const SizedBox(height: 18),
      if (c.isLocal)
        const NoticePanel(
          message:
              'কণ্ঠের নমুনা ও লেখা ফোনেই থাকবে। নমুনার প্রথম ১২ সেকেন্ড ব্যবহার হবে। ফোনে একবারে সর্বোচ্চ ১৫০০ অক্ষরের ইংরেজি লেখা দিন।',
        ),
      if (c.isLocal) const SizedBox(height: 18),
      if (c.profiles.isEmpty) ...[
        EmptyPanel(
          icon: Icons.mic_none_rounded,
          title: 'আগে একটি কণ্ঠ যোগ করুন',
          message: c.isLocal
              ? 'পরিষ্কার ৩–৩০ সেকেন্ডের রেকর্ডিং বাছুন। ফোনের ইংরেজি মডেলের জন্য প্রতিলিপি প্রয়োজন নেই।'
              : 'পরিষ্কার ৩–৩০ সেকেন্ডের রেকর্ডিং ও তার হুবহু লেখা প্রস্তুত রাখুন।',
          action: FilledButton.icon(
            onPressed: c.busy ? null : _import,
            icon: const Icon(Icons.add),
            label: const Text('কণ্ঠ যোগ করুন'),
          ),
        ),
        const SizedBox(height: 20),
      ] else ...[
        DropdownButtonFormField<String>(
          key: ValueKey('profile-${c.selectedProfileId}-${c.profiles.length}'),
          initialValue: selectedExists ? c.selectedProfileId : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'কোন কণ্ঠে তৈরি হবে'),
          items: c.profiles
              .map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: c.busy ? null : c.selectProfile,
        ),
        const SizedBox(height: 16),
      ],
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'bn', label: Text('বাংলা')),
          ButtonSegment(value: 'en', label: Text('ইংরেজি')),
        ],
        selected: {c.language},
        onSelectionChanged: c.busy
            ? null
            : (values) => c.setLanguage(values.first),
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('generation-text'),
        controller: _editor,
        enabled: !c.busy,
        minLines: 7,
        maxLines: 14,
        maxLength: c.isLocal ? 1500 : 3000,
        onChanged: c.setText,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: 'আপনার লেখা',
          alignLabelWithHint: true,
          hintText: 'এখানে বাংলা বা ইংরেজিতে লিখুন…',
          helperText: c.isLocal
              ? 'ফোনে সর্বোচ্চ ১৫০০ অক্ষর • শুধু ইংরেজি'
              : 'একবারে সর্বোচ্চ ৩০০০ অক্ষর',
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (!mounted || data?.text == null) {
                      return;
                    }
                    final pasted = data!.text!;
                    _editor.text = pasted;
                    c.setText(pasted);
                  },
            icon: const Icon(Icons.content_paste, size: 18),
            label: const Text('পেস্ট'),
          ),
          TextButton.icon(
            onPressed: c.busy || c.text.isEmpty
                ? null
                : () {
                    _editor.clear();
                    c.setText('');
                  },
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('মুছুন'),
          ),
        ],
      ),
      if (!c.isLocal)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _uploadConsent,
          onChanged: c.busy
              ? null
              : (value) => setState(() => _uploadConsent = value ?? false),
          title: const Text(
            'এই কাজের জন্য নমুনা ও লেখা আমার নির্বাচিত সার্ভারে পাঠাতে সম্মতি দিচ্ছি।',
            style: TextStyle(fontSize: 13, height: 1.8),
          ),
          subtitle: const Text(
            'ফোনের বাইরে প্রক্রিয়াকরণ হবে। এটি অফলাইন ক্লোনিং নয়।',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
        ),
      const SizedBox(height: 12),
      if (c.busy) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        c.status.isEmpty ? 'প্রক্রিয়া চলছে…' : c.status,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                LinearProgressIndicator(
                  value: c.progress > 0 ? c.progress.clamp(0.0, 1.0) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: c.cancel,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('কাজ বাতিল করুন'),
                ),
              ],
            ),
          ),
        ),
      ] else
        FilledButton.icon(
          key: const Key('generate-button'),
          onPressed:
              c.profiles.isEmpty ||
                  c.generationBlockReason.isNotEmpty ||
                  (!c.isLocal && !_uploadConsent)
              ? null
              : () => c.generate(uploadConsent: !c.isLocal && _uploadConsent),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('অডিও তৈরি করুন'),
        ),
      const SizedBox(height: 16),
      if (c.generationBlockReason.isNotEmpty) ...[
        NoticePanel(message: c.generationBlockReason),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (c.isLocal && c.language != 'en')
              TextButton.icon(
                key: const Key('choose-offline-english'),
                onPressed: c.busy ? null : () => c.setLanguage('en'),
                icon: const Icon(Icons.translate),
                label: const Text('ফোনে ইংরেজি বেছে নিন'),
              ),
            OutlinedButton.icon(
              key: const Key('generation-setup'),
              onPressed: c.busy ? null : () => _navigate(4),
              icon: const Icon(Icons.settings_outlined),
              label: Text(c.isLocal ? 'ফোনের মডেল দেখুন' : 'সার্ভার সেটিংস'),
            ),
          ],
        ),
      ],
      if (c.latest != null) ...[
        const SizedBox(height: 24),
        const StudioSection(
          title: 'সর্বশেষ অডিও',
          subtitle: 'এটি কৃত্রিমভাবে তৈরি কণ্ঠ।',
        ),
        _recordCard(c.latest!, alwaysPreview: true),
      ],
    ]);
  }

  Widget _library() => _scroll([
    StudioSection(
      title: 'কণ্ঠের সংগ্রহ',
      subtitle: 'নমুনা আপনার ফোনে সংরক্ষিত থাকে।',
      action: IconButton.filled(
        tooltip: 'কণ্ঠ যোগ করুন',
        onPressed: c.busy ? null : _import,
        icon: const Icon(Icons.add),
      ),
    ),
    if (c.profiles.isEmpty)
      EmptyPanel(
        icon: Icons.record_voice_over_outlined,
        title: 'আপনার প্রথম কণ্ঠ',
        message:
            'নিজের বা স্পষ্ট অনুমতি পাওয়া কারও কণ্ঠ যোগ করুন। MP3, WAV ও সমর্থিত M4A ফাইল ব্যবহার করা যাবে।',
        action: FilledButton.icon(
          onPressed: c.busy ? null : _import,
          icon: const Icon(Icons.upload_file),
          label: const Text('রেকর্ডিং বাছুন'),
        ),
      ),
    for (final profile in c.profiles) ...[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFF0EBDF),
                    foregroundColor: studioGold,
                    child: Text(
                      profile.name.isEmpty
                          ? 'ক'
                          : profile.name.characters.first,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_date(profile.createdAt)} · ${profile.durationSeconds.toStringAsFixed(1)} সেকেন্ড',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'কণ্ঠের বিকল্প',
                    enabled: !c.busy,
                    onSelected: (value) => _profileAction(profile, value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('নাম বদলান')),
                      PopupMenuItem(
                        value: 'replace',
                        child: Text('নমুনা বদলান'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('মুছে ফেলুন')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                profile.referenceText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black54,
                  height: 1.7,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _previewId = _previewId == profile.id
                          ? null
                          : profile.id,
                    ),
                    icon: Icon(
                      _previewId == profile.id
                          ? Icons.expand_less
                          : Icons.play_arrow_rounded,
                    ),
                    label: const Text('নমুনা শুনুন'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: c.busy
                        ? null
                        : () {
                            c.selectProfile(profile.id);
                            _navigate(1);
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('ব্যবহার করুন'),
                  ),
                ],
              ),
              if (_previewId == profile.id)
                AudioPanel(key: ValueKey(profile.path), path: profile.path),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
    ],
  ]);

  Future<void> _profileAction(VoiceProfile profile, String action) async {
    switch (action) {
      case 'rename':
        final name = await _nameDialog('কণ্ঠের নাম বদলান', profile.name);
        if (name != null) {
          await c.renameProfile(profile, name);
        }
      case 'replace':
        await _import(replace: profile);
      case 'delete':
        if (await _confirm(
          'কণ্ঠ মুছে ফেলবেন?',
          '“${profile.name}” ও এর স্থানীয় নমুনা মুছে যাবে। আগে তৈরি অডিও ইতিহাসে থাকবে।',
          label: 'মুছে ফেলুন',
        )) {
          if (_previewId == profile.id && mounted) {
            setState(() => _previewId = null);
          }
          await c.deleteProfile(profile);
        }
    }
  }

  Widget _history() => _scroll([
    const StudioSection(
      title: 'অডিওর ইতিহাস',
      subtitle: 'আপনার তৈরি কৃত্রিম কণ্ঠের স্থানীয় সংগ্রহ।',
    ),
    if (c.history.isEmpty)
      EmptyPanel(
        icon: Icons.library_music_outlined,
        title: 'এখনও অডিও নেই',
        message:
            'অডিও তৈরি হলে এখানে সংরক্ষিত হবে। পরে শুনতে, ভাগ করতে বা রপ্তানি করতে পারবেন।',
        action: FilledButton(
          onPressed: () => _navigate(1),
          child: const Text('অডিও তৈরি করুন'),
        ),
      ),
    for (final record in c.history) ...[
      _recordCard(record),
      const SizedBox(height: 14),
    ],
  ]);

  Widget _recordCard(AudioRecord record, {bool alwaysPreview = false}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.audio_file_outlined,
                color: studioGold,
                size: 29,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  record.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'অডিওর বিকল্প',
                onSelected: (value) async {
                  if (value == 'rename') {
                    final name = await _nameDialog(
                      'অডিওর নাম বদলান',
                      record.name,
                    );
                    if (name != null) {
                      await c.renameRecord(record, name);
                    }
                  } else if (value == 'delete' &&
                      await _confirm(
                        'অডিও মুছে ফেলবেন?',
                        'এই অডিও ও ইতিহাসের সংশ্লিষ্ট তথ্য স্থায়ীভাবে মুছে যাবে।',
                        label: 'মুছে ফেলুন',
                      )) {
                    if (_previewId == record.id && mounted) {
                      setState(() => _previewId = null);
                    }
                    await c.deleteRecord(record);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('নাম বদলান')),
                  PopupMenuItem(value: 'delete', child: Text('মুছে ফেলুন')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${record.profileName} · ${record.language == 'bn' ? 'বাংলা' : 'ইংরেজি'} · ${record.durationSeconds.toStringAsFixed(1)} সেকেন্ড',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            _date(record.createdAt),
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Text(
            record.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(height: 1.8),
          ),
          const SizedBox(height: 12),
          const Text(
            'কৃত্রিমভাবে তৈরি কণ্ঠ',
            style: TextStyle(fontSize: 11, color: studioGold),
          ),
          if (!alwaysPreview)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                  () => _previewId = _previewId == record.id ? null : record.id,
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('অডিও শুনুন'),
              ),
            ),
          if (alwaysPreview || _previewId == record.id)
            AudioPanel(key: ValueKey(record.wavPath), path: record.wavPath),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _export(record, 'wav'),
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('WAV'),
              ),
              OutlinedButton.icon(
                onPressed: () => _export(record, 'mp3'),
                icon: const Icon(Icons.save_alt, size: 18),
                label: const Text('MP3'),
              ),
              IconButton.outlined(
                tooltip: 'অডিও ভাগ করুন',
                onPressed: () => c.shareRecord(record),
                icon: const Icon(Icons.share_outlined, size: 20),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _export(AudioRecord record, String format) async {
    if (format == 'mp3' &&
        !await _confirm(
          'MP3 রূপান্তরে অনুমতি',
          'MP3 তৈরি করতে এই কৃত্রিম অডিও আপনার নির্বাচিত সার্ভারে পাঠানো হবে। এটি ফোনে রূপান্তর হয় না। মূল কণ্ঠের নমুনা পাঠানো হবে না। স্থানীয়ভাবে রপ্তানি করতে WAV বেছে নিন।',
          label: 'পাঠিয়ে রূপান্তর করুন',
        )) {
      return;
    }
    await c.exportRecord(record, format: format);
  }

  Widget _settings() => _scroll([
    const StudioSection(
      title: 'সেটিংস',
      subtitle: 'আপনার তথ্য, আপনার নিয়ন্ত্রণে।',
    ),
    const NoticePanel(
      message:
          'ফোনে ইংরেজি কণ্ঠ তৈরি করতে নিচের মডেলটি নামান। বাংলা তৈরির জন্য এখনও উপযুক্ত মডেলসহ আলাদা সার্ভার প্রয়োজন। কোনো মূল্যযুক্ত সেবা বা পরীক্ষামূলক ক্রেডিট ব্যবহার করা হয় না।',
    ),
    const SizedBox(height: 22),
    _localModelManager(),
    const SizedBox(height: 22),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'নিজস্ব সার্ভার সংযোগ',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'বিশ্বস্ত স্থানীয় নেটওয়ার্কের ঠিকানা দিন। পাবলিক নেটওয়ার্কে HTTPS ব্যবহার করুন। টোকেনটি এই ফোনে সুরক্ষিতভাবে রাখা হবে।',
              style: TextStyle(
                color: Colors.black54,
                height: 1.8,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _url,
              enabled: !c.connecting && !c.busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'সার্ভারের ঠিকানা',
                hintText: 'https://আপনার-সার্ভার',
                helperText: 'শেষে /v1 যোগ করার প্রয়োজন নেই',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              enabled: !c.connecting && !c.busy,
              obscureText: _hideToken,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'ব্যক্তিগত সংযোগ টোকেন',
                suffixIcon: IconButton(
                  tooltip: _hideToken ? 'টোকেন দেখুন' : 'টোকেন লুকান',
                  onPressed: () => setState(() => _hideToken = !_hideToken),
                  icon: Icon(
                    _hideToken
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: c.connecting || c.busy
                  ? null
                  : () async {
                      c.clearError();
                      await c.saveSettings(url: _url.text, token: _token.text);
                      if (c.error.isEmpty) {
                        await c.connect();
                      }
                    },
              icon: c.connecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.link),
              label: Text(
                c.connecting
                    ? 'সংযোগ পরীক্ষা চলছে…'
                    : 'সংরক্ষণ ও সংযোগ পরীক্ষা',
              ),
            ),
            if (c.capabilities != null) ...[
              const SizedBox(height: 16),
              NoticePanel(
                message: c.capabilities!.available
                    ? 'সার্ভার প্রস্তুত। উপলব্ধ ভাষা: ${c.capabilities!.languages.map((l) => l == 'bn'
                          ? 'বাংলা'
                          : l == 'en'
                          ? 'ইংরেজি'
                          : l).join(', ')}'
                    : 'সার্ভার সংযুক্ত, কিন্তু প্রয়োজনীয় মডেল এখনও প্রস্তুত নয়। নিচে মডেলের অবস্থা দেখুন।',
              ),
              if (c.capabilities!.reason.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text(
                    'কারিগরি বিস্তারিত',
                    style: TextStyle(fontSize: 12),
                  ),
                  children: [
                    SelectableText(
                      c.capabilities!.reason,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    ),
    const SizedBox(height: 22),
    _modelManager(),
    const SizedBox(height: 22),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('নতুন সংস্করণ', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            const Text(
              'শুধু আপনার অনুরোধে GitHub Releases পরীক্ষা করা হবে। কোনো সংস্করণ স্বয়ংক্রিয়ভাবে ইনস্টল হবে না।',
              style: TextStyle(
                color: Colors.black54,
                height: 1.8,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: c.checkForUpdate,
              icon: const Icon(Icons.system_update_alt),
              label: const Text('হালনাগাদ খুঁজুন'),
            ),
            if (c.updateUrl != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: c.openUpdate,
                icon: const Icon(Icons.open_in_new),
                label: const Text('রিলিজের পাতা খুলুন'),
              ),
            ],
          ],
        ),
      ),
    ),
    if (c.status.isNotEmpty && !c.busy) ...[
      const SizedBox(height: 16),
      NoticePanel(message: c.status),
    ],
    const SizedBox(height: 22),
    ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: Colors.white,
      leading: const Icon(Icons.privacy_tip_outlined),
      title: const Text('গোপনীয়তা ও ব্যবহার'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _privacy,
    ),
    const SizedBox(height: 16),
    Center(
      child: TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'কণ্ঠ · AI Voice Studio',
          applicationVersion: '0.2.0',
          applicationLegalese: 'কণ্ঠ অনুমতি নিয়ে ব্যবহার করুন।',
        ),
        child: const Text('ওপেন সোর্স লাইসেন্স'),
      ),
    ),
  ]);

  Widget _localModelManager() => Card(
    key: const Key('local-model-manager'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ফোনের ইংরেজি মডেল',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            'Pocket TTS · ইংরেজি কণ্ঠ ক্লোনিং',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'ডাউনলোড ৯৮.৩ মেগাবাইট; স্থাপনের পর প্রায় ১৯৮.৩ মেগাবাইট। স্থাপনের সময় অন্তত ৬০০ মেগাবাইট খালি রাখুন। একবার নামানোর পর ইংরেজি কণ্ঠ ও WAV রপ্তানিতে ইন্টারনেট, সার্ভার বা টোকেন লাগবে না। বাংলা এই মডেলে সমর্থিত নয়।',
            style: TextStyle(fontSize: 12, height: 1.8, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Text(
            c.pocket.ready
                ? 'যাচাইকৃত মডেল প্রস্তুত'
                : c.pocket.status.isEmpty
                ? 'এখনও মডেল নামানো হয়নি'
                : c.pocket.status,
            style: const TextStyle(fontSize: 13, height: 1.8),
          ),
          if (c.pocket.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                c.pocket.error,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  height: 1.8,
                ),
              ),
            ),
          if (c.pocket.busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: c.pocket.progress > 0
                  ? c.pocket.progress.clamp(0, 1)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              c.pocket.status,
              style: const TextStyle(fontSize: 12, height: 1.8),
            ),
            TextButton.icon(
              key: const Key('cancel-local-model'),
              onPressed: c.pocket.cancel,
              icon: const Icon(Icons.stop),
              label: const Text('নামানো বাতিল করুন'),
            ),
          ] else ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!c.pocket.ready)
                  FilledButton.icon(
                    key: const Key('download-local-model'),
                    onPressed: c.busy
                        ? null
                        : () async {
                            final accepted = await _confirm(
                              'ফোনের মডেল নামাবেন?',
                              'ডাউনলোড: ${PocketModelStore.totalDownloadBytes} বাইট (প্রায় ৯৮.৩ মেগাবাইট)। স্থাপনের পর প্রায় ১৯৮.৩ মেগাবাইট; অন্তত ৬০০ মেগাবাইট খালি রাখুন।\n\n${PocketModelStore.license}\n\nশুধু নিজের বা অনুমোদিত কণ্ঠ ব্যবহার করুন। ডাউনলোডের SHA-256 এবং প্রতিটি স্থাপিত ফাইল যাচাই হবে। এই পুরোনো পরিমাণায়িত মডেলটি শুধু ইংরেজির জন্য।',
                              label: 'সম্মত, নামান',
                            );
                            if (accepted) {
                              await c.downloadPocket();
                            }
                          },
                    icon: const Icon(Icons.download),
                    label: const Text('মডেল নামান'),
                  ),
                if (c.pocket.ready)
                  OutlinedButton.icon(
                    key: const Key('use-local-model'),
                    onPressed: c.busy
                        ? null
                        : () {
                            c.setInferenceMode('local');
                            c.setLanguage('en');
                            _navigate(1);
                          },
                    icon: const Icon(Icons.smartphone),
                    label: const Text('ফোনে ইংরেজি তৈরি করুন'),
                  ),
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.pocket.inspect,
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('ফাইল যাচাই'),
                ),
                TextButton.icon(
                  key: const Key('remove-local-model'),
                  onPressed: c.busy
                      ? null
                      : () async {
                          if (await _confirm(
                            'ফোনের মডেল মুছবেন?',
                            'মডেল ও অসম্পূর্ণ ডাউনলোড মুছে যাবে। সংরক্ষিত কণ্ঠ, লেখা ও অডিওর ইতিহাস অক্ষত থাকবে।',
                            label: 'মডেল মুছুন',
                          )) {
                            await c.removePocket();
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('মডেল মুছুন'),
                ),
              ],
            ),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('উৎস ও লাইসেন্স', style: TextStyle(fontSize: 12)),
            children: const [
              SelectableText(
                '${PocketModelStore.license}\n${PocketModelStore.attributionUrl}',
                style: TextStyle(fontSize: 12, height: 1.8),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _modelManager() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'সার্ভারের মডেল',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'মডেলের অবস্থা দেখুন',
                onPressed: c.backendUrl.isEmpty ? null : c.refreshModels,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'মডেল সার্ভারে নামবে, ফোনে নয়। বড় ফাইল নামানোর আগে আকার ও লাইসেন্স দেখুন। অসম্পূর্ণ ডাউনলোড পুনরায় শুরু করা যাবে; যাচাই না হলে মডেল ব্যবহার হবে না।',
            style: TextStyle(color: Colors.black54, height: 1.8, fontSize: 12),
          ),
          if (c.models.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 18),
              child: Text(
                'সংযোগের পর মডেলের তালিকা পেতে উপরের বোতাম চাপুন।',
                style: TextStyle(fontSize: 12),
              ),
            ),
          for (final model in c.models) _modelCard(model),
        ],
      ),
    ),
  );

  Widget _modelCard(Map<String, dynamic> model) {
    final id = model['id']?.toString() ?? '';
    final name = model['name']?.toString() ?? id;
    final state = (model['state'] ?? model['status'] ?? 'missing').toString();
    final total = (model['total_bytes'] as num?)?.toInt() ?? 0;
    final received = (model['downloaded_bytes'] as num?)?.toInt() ?? 0;
    final downloading = state == 'downloading' || state == 'verifying';
    final ready = state == 'ready' || state == 'installed';
    final stateLabel = switch (state) {
      'ready' || 'installed' => 'যাচাইকৃত মডেল প্রস্তুত',
      'downloading' => 'ডাউনলোড চলছে',
      'verifying' => 'অখণ্ডতা যাচাই চলছে',
      'error' || 'failed' => 'সম্পন্ন হয়নি',
      'cancelled' => 'বাতিল করা হয়েছে',
      _ => 'এখনও ইনস্টল হয়নি',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            stateLabel,
            style: const TextStyle(color: studioGold, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            'আকার: ${total > 0 ? _bytes(total) : 'সার্ভার থেকে যাচাই প্রয়োজন'}',
            style: const TextStyle(fontSize: 12),
          ),
          if (model['license'] != null)
            Text(
              'লাইসেন্স: ${model['license']}',
              style: const TextStyle(fontSize: 12),
            ),
          if (downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: total > 0 ? (received / total).clamp(0.0, 1.0) : null,
            ),
            const SizedBox(height: 6),
            Text(
              '${_bytes(received)} / ${_bytes(total)}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
          if ((model['error']?.toString() ?? '').isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'সমস্যার বিস্তারিত',
                style: TextStyle(fontSize: 12),
              ),
              children: [
                SelectableText(
                  model['error'].toString(),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!ready && !downloading)
                OutlinedButton.icon(
                  onPressed: id.isEmpty
                      ? null
                      : () async {
                          final plan = await c.planModel(id);
                          if (plan == null || !mounted) {
                            return;
                          }
                          final size =
                              ((plan['bytes'] ?? plan['total_bytes']) as num?)
                                  ?.toInt() ??
                              0;
                          if (size <= 0) {
                            return;
                          }
                          final license =
                              plan['license']?.toString() ??
                              model['license']?.toString() ??
                              'সার্ভারে বিস্তারিত দেখুন';
                          if (await _confirm(
                            'মডেল ডাউনলোড করবেন?',
                            '$name মডেলটি সার্ভারে প্রায় ${_bytes(size)} জায়গা নেবে। লাইসেন্স: $license। সার্ভারে মডেলের প্রকাশিত Python কোড চালানো হবে। উৎস ও লাইসেন্স পর্যালোচনা করে সম্মতি দিলে শুরু করুন।',
                            label: 'সম্মতি দিয়ে ডাউনলোড',
                          )) {
                            await c.downloadModel(id);
                          }
                        },
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(
                    state == 'error' ||
                            state == 'failed' ||
                            state == 'cancelled'
                        ? 'আবার চেষ্টা'
                        : 'ডাউনলোড',
                  ),
                ),
              if (downloading)
                OutlinedButton(
                  onPressed: () => c.cancelModel(id),
                  child: const Text('বাতিল'),
                ),
              if (ready || received > 0)
                TextButton.icon(
                  onPressed: downloading
                      ? null
                      : () async {
                          if (await _confirm(
                            'মডেল মুছে ফেলবেন?',
                            'সার্ভারের এই মডেল ও এর ডাউনলোড করা ফাইল মুছে যাবে। পুনরায় ব্যবহার করতে আবার ডাউনলোড প্রয়োজন হবে।',
                            label: 'মুছে ফেলুন',
                          )) {
                            await c.removeModel(id);
                          }
                        },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('মডেল মুছুন'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _privacy() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .75,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.all(24),
        children: [
          const StudioSection(title: 'গোপনীয়তা ও দায়িত্ব'),
          const Text(
            'নিজের বা স্পষ্ট অনুমতি পাওয়া ব্যক্তির কণ্ঠই ব্যবহার করুন। কাউকে প্রতারিত করতে, পরিচয় নকল করতে বা অনুমতি ছাড়া কণ্ঠ ব্যবহার করতে এই অ্যাপ ব্যবহার করবেন না।\n\nকণ্ঠের নমুনা, লেখা ও তৈরি অডিও আপনার ফোনে স্থানীয়ভাবে সংরক্ষিত থাকে। অ্যাকাউন্ট, বিজ্ঞাপন, বিশ্লেষণ বা ট্র্যাকিং নেই।\n\nফোনে ইংরেজি মোডে মডেল নামানোর পর নমুনা ও লেখা বাইরে পাঠানো হয় না। বাংলা বা ঐচ্ছিক সার্ভার মোডে আপনার নির্বাচিত নিজস্ব সার্ভারে নমুনা ও লেখা পাঠানোর আগে আলাদা সম্মতি নেওয়া হয়। শুধু বিশ্বাসযোগ্য সার্ভার ব্যবহার করুন। স্থানীয় নেটওয়ার্কে HTTP এনক্রিপ্ট করা নয়; গোপন রেকর্ডিংয়ের জন্য HTTPS ব্যবহার করুন।\n\nকণ্ঠের সংগ্রহ থেকে নমুনা ও ইতিহাস থেকে তৈরি অডিও মুছে ফেলা যায়। রপ্তানি বা অন্য অ্যাপে ভাগ করা কপি আলাদাভাবে মুছতে হবে। সার্ভার নিজের নিয়ন্ত্রণে রাখুন এবং তার সংরক্ষিত তথ্যও মুছুন।\n\nসব তৈরি কণ্ঠ কৃত্রিম। অডিও ভাগ করার সময় শ্রোতাকে জানিয়ে দিন।\n\nহালনাগাদ পরীক্ষা শুধু বোতাম চাপলে GitHub-এ অনুরোধ পাঠায়। কোনো অ্যাপ বা মডেল গোপনে ডাউনলোড হয় না।',
            style: TextStyle(height: 1.9),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('বুঝেছি'),
          ),
        ],
      ),
    ),
  );
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 29, color: studioGold),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.black54,
                fontSize: 11,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ImportDetails {
  const _ImportDetails(this.name, this.transcript, this.consent);
  final String name, transcript;
  final bool consent;
}

class _ImportSheet extends StatefulWidget {
  const _ImportSheet({this.profile, required this.requiresTranscript});
  final VoiceProfile? profile;
  final bool requiresTranscript;
  @override
  State<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends State<_ImportSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _transcript;
  bool _consent = false;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile?.name ?? '');
    _transcript = TextEditingController(
      text: widget.profile?.referenceText ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _transcript.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StudioSection(
              title: widget.profile == null
                  ? 'নতুন কণ্ঠ যোগ করুন'
                  : 'নমুনা বদলান',
              subtitle:
                  'ফাইল বাছার আগে কণ্ঠের তথ্য দিন। রেকর্ডিং এখন শুধু এই ফোনে থাকবে।',
            ),
            if (widget.profile == null) ...[
              TextFormField(
                controller: _name,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'কণ্ঠের নাম'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'একটি নাম লিখুন।'
                    : null,
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _transcript,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: widget.requiresTranscript
                    ? 'রেকর্ডিংয়ে যা বলা হয়েছে'
                    : 'রেকর্ডিংয়ের লেখা (ঐচ্ছিক)',
                alignLabelWithHint: true,
                helperText: widget.requiresTranscript
                    ? 'সার্ভারের মডেলের জন্য শব্দে শব্দে হুবহু লিখুন।'
                    : 'ফোনের ইংরেজি মডেলে প্রয়োজন নেই; পরে সার্ভারে ব্যবহার করলে লাগবে।',
              ),
              validator: (value) =>
                  widget.requiresTranscript &&
                      (value == null || value.trim().isEmpty)
                  ? 'নমুনার হুবহু লেখা দিন।'
                  : null,
            ),
            const SizedBox(height: 16),
            const NoticePanel(
              message:
                  'পরিষ্কার ৩–৩০ সেকেন্ডের MP3, WAV বা সমর্থিত M4A ব্যবহার করুন। গান, শব্দদূষণ ও একাধিক বক্তার রেকর্ডিং এড়িয়ে চলুন।',
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              title: const Text(
                'এই কণ্ঠ আমার নিজের অথবা ব্যবহারের স্পষ্ট অনুমতি আমার আছে।',
                style: TextStyle(fontSize: 13, height: 1.8),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('import-select-file'),
                onPressed: !_consent
                    ? null
                    : () {
                        if (_form.currentState!.validate()) {
                          Navigator.pop(
                            context,
                            _ImportDetails(
                              _name.text.trim(),
                              _transcript.text.trim(),
                              _consent,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.upload_file),
                label: const Text('রেকর্ডিং বাছুন'),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('বাতিল'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _date(DateTime time) {
  final t = time.toLocal();
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _bytes(int bytes) {
  if (bytes >= 1073741824) {
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }
  if (bytes >= 1048576) {
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _input;
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _input,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'নাম'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('বাতিল'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text),
        child: const Text('সংরক্ষণ'),
      ),
    ],
  );
}
