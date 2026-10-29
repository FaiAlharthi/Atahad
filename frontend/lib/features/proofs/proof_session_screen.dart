import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/at_colors.dart';
import '../../core/theme/at_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'camera_capture_screen.dart';
import 'proof_widgets.dart';
import 'quiz_text.dart';
import 'proofs_api.dart';
import 'request_forms.dart';
import 'visit_screen.dart';

class ProofStartScreen extends StatefulWidget {
  final Json? activity;
  final int? weekId;
  final int? taskId;
  const ProofStartScreen({super.key, this.activity, this.weekId, this.taskId});
  @override
  State<ProofStartScreen> createState() => _ProofStartScreenState();
}

class _ProofStartScreenState extends State<ProofStartScreen> {
  late final ProofsApi _api = ProofsApi(context.read<ApiClient>());
  late final Future<Json> _activity = _load();
  final _minutes = TextEditingController(text: '25');
  bool _withPhotos = false;
  bool _busy = false;
  int? _beforeId;
  CapturedImage? _before;
  DateTime? _beforeTaken;
  Future<Json> _load() async {
    final tasks = widget.activity == null
        ? await _api.activities()
        : [widget.activity!];
    final task = tasks.firstWhere(
      (t) =>
          widget.activity != null ||
          (t['weekId'] == widget.weekId && t['goalTaskId'] == widget.taskId),
    );
    if (task['proofMethod'] == 'TIMER') {
      try {
        final value =
            await _api.client.get(
                  '/api/v1/proof-attempt/suggest/${task['weekId']}',
                  query: {'goalTaskId': task['goalTaskId']},
                )
                as Map;
        if (mounted) _minutes.text = '${value['suggestedMinutes']}';
      } catch (_) {}
    }
    return task;
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _takeBefore() async {
    final photo = await takeProofPhoto(context, 'صورة البداية');
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final id = await _api.cameraUpload(
        'BEFORE',
        photo.bytes,
        mime: photo.mime,
      );
      if (mounted) {
        setState(() {
          _before = photo;
          _beforeId = id;
          _beforeTaken = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted) proofError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(Json activity) async {
    final duration = int.tryParse(_minutes.text);
    if (activity['proofMethod'] == 'TIMER' &&
        (duration == null || duration < 1 || duration > 600)) {
      showMessage(context, 'اختر مدة من دقيقة إلى ٦٠٠ دقيقة.');
      return;
    }
    if (_withPhotos &&
        (_beforeId == null ||
            _beforeTaken == null ||
            DateTime.now().difference(_beforeTaken!).inMinutes >= 5)) {
      showMessage(context, 'التقط صورة البداية، ثم ابدأ خلال خمس دقائق.');
      return;
    }
    setState(() => _busy = true);
    try {
      final proof =
          await _api.client.post(
                '/api/v1/proof-attempt/start/${activity['weekId']}',
                body: {
                  'goalTaskId': activity['goalTaskId'],
                  'beforeAfter': _withPhotos,
                  'beforeCaptureId': _withPhotos ? _beforeId : null,
                  if (activity['proofMethod'] == 'TIMER')
                    'targetMinutes': duration,
                },
              )
              as Map;
      if (mounted) {
        context.pushReplacement(
          '/proofs/session/${proof['id']}?started=1&title=${Uri.encodeComponent('${activity['title']}')}',
        );
      }
    } catch (error) {
      if (mounted) proofError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: _activity,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ProofPage(title: 'إثبات النشاط', child: LoadingView());
      }
      if (snapshot.hasError) {
        return const ProofPage(
          title: 'إثبات النشاط',
          child: ErrorView(
            message: 'هذا النشاط غير متاح الآن. ارجع لليوم وحدّث القائمة.',
          ),
        );
      }
      final task = snapshot.data!;
      if (task['proofMethod'] == 'LOCATION') {
        return VisitScreen(activity: task);
      }
      final method = task['proofMethod'] as String?;
      final c = context.colors;
      final text = Theme.of(context).textTheme;
      // the steps of this method in three short lines with icons, instead of a paragraph
      final steps = switch (method) {
        'TIMER' => const [
            (Icons.timer_outlined, 'اختر المدة'),
            (Icons.play_arrow_rounded, 'ابدأ وخلك بالتطبيق'),
            (Icons.verified_rounded, 'تكمّلها = إثباتك'),
          ],
        'QUIZ' => const [
            (Icons.photo_library_outlined, 'صوّر الصفحات (اختياري)'),
            (Icons.quiz_outlined, '٤ أسئلة سهلة'),
            (Icons.verified_rounded, '٣ صح = إثباتك'),
          ],
        _ => const [
            (Icons.directions_run_rounded, 'سوّ النشاط'),
            (Icons.photo_camera_outlined, 'صوّر بالكاميرا مباشرة'),
            (Icons.verified_rounded, 'الذكاء يراجعها'),
          ],
      };
      return ProofPage(
        title: 'إثبات النشاط',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.s5, Space.s4, Space.s5, Space.s6),
          children: [
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: c.primarySoft,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.primarySoft.withValues(alpha: 0.6), spreadRadius: 10)],
                ),
                child: Icon(methodIcon(method), size: 42, color: c.primary),
              ),
            ),
            const SizedBox(height: Space.s5),
            ActivityHeading(
              title: '${task['title']}',
              goalTitle: task['goalTitle'] as String?,
              taskTitle: task['taskTitle'] as String?,
              style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.s2),
            Center(child: TagPill(methodNames[method] ?? '', fg: c.primary, bg: c.primarySoft, icon: methodIcon(method))),
            const SizedBox(height: Space.s5),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.line)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, (icon, line)) in steps.indexed)
                    Expanded(
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconTile(icon, size: 44),
                              PositionedDirectional(
                                top: -6,
                                start: -6,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle, border: Border.all(color: c.surface, width: 2)),
                                  child: Text(arabicDigits(i + 1), style: text.labelSmall!.copyWith(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1.1)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(line, style: text.labelSmall!.copyWith(color: c.inkMuted, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.s5),
            if (method == 'TIMER') ...[
              Text('كم دقيقة؟', style: text.labelLarge),
              const SizedBox(height: Space.s2),
              Row(
                children: [
                  for (final (i, m) in const [15, 25, 45, 60].indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: SizedBox(width: double.infinity, child: Text(arabicDigits(m), textAlign: TextAlign.center)),
                        selected: _minutes.text == '$m',
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _minutes.text = '$m'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: Space.s2),
              TextFormField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.timer_outlined), suffixText: 'دقيقة', hintText: 'أو اكتب المدة'),
              ),
              const SizedBox(height: Space.s4),
            ],
            AppCard(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: IconTile(Icons.compare_rounded, size: 40, fg: c.pardon, bg: c.pardonSoft),
                    title: const Text('صور قبل وبعد'),
                    subtitle: const Text('اختياري'),
                    value: _withPhotos,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _withPhotos = value),
                  ),
                  if (_withPhotos) ...[
                    const SizedBox(height: 8),
                    Text('صوّر قبل تبدأ، وبعد ما تخلص', style: text.labelSmall),
                    const SizedBox(height: 12),
                    if (_before != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: ClipRRect(borderRadius: BorderRadius.circular(Radii.md), child: Image.memory(_before!.bytes, height: 180)),
                      ),
                    AtButton(
                      _before == null
                          ? 'التقط صورة البداية'
                          : 'أعد صورة البداية',
                      kind: AtButtonKind.outline,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      loading: _busy,
                      onPressed: _takeBefore,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            AtButton(
              task['proofMethod'] == 'TIMER'
                  ? 'ابدأ الجلسة'
                  : 'ابدأ توثيق النشاط',
              loading: _busy,
              onPressed: () => _start(task),
            ),
            const SizedBox(height: 8),
            AtButton(
              'عندي عذر بدل الإثبات',
              kind: AtButtonKind.text,
              onPressed: _busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExcuseFormScreen(activities: [task]),
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class ProofSessionScreen extends StatefulWidget {
  final int proofId;
  final String title;
  final bool justStarted;
  const ProofSessionScreen({
    super.key,
    required this.proofId,
    required this.title,
    this.justStarted = false,
  });
  @override
  State<ProofSessionScreen> createState() => _ProofSessionScreenState();
}

class _ProofSessionScreenState extends State<ProofSessionScreen> {
  late final ProofsApi _api = ProofsApi(context.read<ApiClient>());
  Json? _state;
  Object? _error;
  bool _busy = false;
  bool _syncing = false;
  bool _photoSubmitted = false;
  Timer? _poll;
  Timer? _clock;
  Timer? _welcomeTimer;
  bool _welcome = false;
  bool _justAccepted = false;
  final _extension = TextEditingController(text: '5');
  @override
  void initState() {
    super.initState();
    _welcome = widget.justStarted;
    _welcomeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _welcome = false);
    });
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_busy) _refresh(silent: true);
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _state?['timer'] != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _welcomeTimer?.cancel();
    _poll?.cancel();
    _clock?.cancel();
    _extension.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_syncing) return;
    _syncing = true;
    try {
      final state = await _api.state(widget.proofId);
      if (state['timer'] != null) {
        state['timer'] = await _api.client.post(
          '/api/v1/proof-attempt/timer/${state['timer']['id']}/state',
          body: {},
        );
        final fresh = await _api.state(widget.proofId);
        state['proof'] = fresh['proof'];
        state['evidence'] = fresh['evidence'];
        state['canObject'] = fresh['canObject'];
      }
      if (mounted) {
        // accepted while the member is watching: the check is drawn and the phone taps once
        final wasAccepted = _state != null && (_state!['proof'] as Map?)?['result'] == 'ACCEPTED';
        final nowAccepted = (state['proof'] as Map?)?['result'] == 'ACCEPTED';
        if (_state != null && !wasAccepted && nowAccepted) {
          _justAccepted = true;
          HapticFeedback.mediumImpact();
        }
        setState(() {
          _state = state;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && !silent) setState(() => _error = error);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (mounted) proofError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(String kind) async {
    final photo = await takeProofPhoto(
      context,
      kind == 'AFTER' ? 'صورة النهاية' : 'صورة إثبات النشاط',
    );
    if (photo == null || !mounted) return;
    await _run(() async {
      final id = await _api.cameraUpload(
        kind,
        photo.bytes,
        proofId: widget.proofId,
        mime: photo.mime,
      );
      if (kind == 'AFTER') {
        await _api.client.post(
          '/api/v1/proof-attempt/${widget.proofId}/after',
          body: {'afterCaptureId': id},
        );
      } else {
        await _api.client.post(
          '/api/v1/proof-attempt/${widget.proofId}/submit',
          body: {'evidenceData': '$id'},
        );
      }
      if (mounted) {
        if (kind == 'PHOTO') setState(() => _photoSubmitted = true);
        showMessage(context, 'تم إرفاق الإثبات بنجاح');
      }
    });
  }

  Future<void> _timerAction(String action, {Json body = const {}}) =>
      _run(() async {
        await _api.client.post(
          '/api/v1/proof-attempt/timer/${_state!['timer']['id']}/$action',
          body: body,
        );
      });
  int _elapsed(Json timer) {
    int seconds = (timer['elapsedSeconds'] as num).toInt();
    if (timer['status'] == 'RUNNING') {
      final started = serverInstant(timer['lastStartedAt']);
      final deadline = serverInstant(timer['deadline']);
      final now = DateTime.now();
      final end = deadline != null && now.isAfter(deadline) ? deadline : now;
      if (started != null) {
        seconds += math.max(0, end.difference(started).inSeconds);
      }
    }
    return math.min(
      seconds,
      (timer['requiredSeconds'] as num).toInt() +
          (timer['extensionSeconds'] as num).toInt(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_state == null) {
      return ProofPage(
        title: widget.title,
        child: _error == null
            ? const LoadingView()
            : ErrorView(message: friendlyError(_error!), onRetry: _refresh),
      );
    }
    final proof = Map<String, dynamic>.from(_state!['proof'] as Map);
    final evidence = ProofsApi.maps(_state!['evidence']);
    final accepted = proof['result'] == 'ACCEPTED';
    final hasPhoto =
        _photoSubmitted ||
        proof['primaryCaptureId'] != null ||
        '${proof['evidenceData'] ?? ''}'.startsWith('data:image/') ||
        evidence.any(
          (e) =>
              e['type'] == 'PHOTO' &&
              (e['decidedAt'] != null || e['result'] != 'PENDING'),
        );
    final deadline = serverInstant(proof['attemptDeadline']);
    final closed = deadline != null && !DateTime.now().isBefore(deadline);
    final photosWaiting = evidence.any(
      (e) => e['type'] == 'BEFORE_AFTER' && e['result'] == 'PENDING',
    );
    return ProofPage(
      title: 'توثيق إنجازك',
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: () => _refresh(),
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ActivityHeading(
            title: widget.title,
            goalTitle: _state!['goalTitle'] as String?,
            taskTitle: _state!['taskTitle'] as String?,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          StatusBadge.review(proof['result'] as String?),
          if (_welcome) ...[
            const SizedBox(height: 12),
            const ProofNotice('بداية موفقة'),
          ],
          const SizedBox(height: 20),
          if (accepted) ...[
            AcceptedMoment(animate: _justAccepted),
            const SizedBox(height: 16),
          ],
          if (accepted) ...[
            // the way back is the main action once it is accepted (design: ProofDone)
            AtButton('رجوع لليوم', icon: const Icon(Icons.event_available_rounded, size: 20), onPressed: () => context.go('/')),
            const SizedBox(height: 8),
          ],
          if (closed && !accepted)
            const ProofNotice('انتهت مهلة المحاولة، والنتيجة محفوظة بسجلك', icon: Icons.timer_off_outlined),
          if (_state!['timer'] != null)
            _timer(Map<String, dynamic>.from(_state!['timer'] as Map), closed),
          if (proof['type'] == 'PHOTO' &&
              !hasPhoto &&
              !accepted &&
              !closed) ...[
            const SizedBox(height: 24),
            const ProofNotice('صورة واضحة للنتيجة، بالكاميرا مباشرة', icon: Icons.photo_camera_outlined),
            const SizedBox(height: 16),
            AtButton(
              'التقط صورة الإثبات',
              loading: _busy,
              onPressed: () => _photo('PHOTO'),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
          ],
          if (proof['type'] == 'QUIZ' && !accepted && !closed)
            QuizPanel(
              proofId: widget.proofId,
              weekId: _state!['weekId'] as int,
              taskId: _state!['goalTaskId'] as int?,
              onSubmitted: () => _refresh(),
            ),
          if (photosWaiting && !accepted && !closed) ...[
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'صورك الإضافية',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  const Text('صورة البداية محفوظة ✓ صوّر النهاية بعد ما تخلص'),
                  const SizedBox(height: 16),
                  AtButton(
                    'التقط صورة النهاية',
                    kind: AtButtonKind.outline,
                    loading: _busy,
                    onPressed: () => _photo('AFTER'),
                  ),
                  AtButton(
                    'أكمل بدون الصور الإضافية',
                    kind: AtButtonKind.text,
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _api.client.post(
                              '/api/v1/proof-attempt/${widget.proofId}/skip-photos',
                              body: {},
                            );
                          }),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (evidence.isNotEmpty) Text('نتيجة كل دليل', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final item in evidence)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['type'] == 'BEFORE_AFTER'
                                ? 'صور قبل وبعد'
                                : methodNames[item['type']] ?? 'دليل النشاط',
                          ),
                        ),
                        StatusBadge.review(item['result'] as String?),
                      ],
                    ),
                    if (item['beforeCaptureId'] != null)
                      ExpansionTile(
                        title: const Text('عرض صور قبل وبعد'),
                        children: [
                          const Text('قبل النشاط'),
                          EvidenceImage('capture:${item['beforeCaptureId']}'),
                          if (item['afterCaptureId'] != null) ...[
                            const SizedBox(height: 12),
                            const Text('بعد النشاط'),
                            EvidenceImage('capture:${item['afterCaptureId']}'),
                          ],
                        ],
                      ),
                    if (item['reason'] != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${item['reason']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (proof['type'] == 'PHOTO' &&
              '${proof['evidenceData']}'.startsWith('data:image/'))
            EvidenceImage('${proof['evidenceData']}'),
          if (_state!['canObject'] == true) ...[
            const SizedBox(height: 14),
            AtButton(
              'اعترض على القرار',
              kind: AtButtonKind.outline,
              onPressed: () async {
                if (await editObjection(
                      context,
                      kind: 'PROOF',
                      targetId: widget.proofId,
                    ) &&
                    context.mounted) {
                  showMessage(context, 'وصل اعتراضك، تابع نتيجته من طلباتي.');
                  await _refresh();
                }
              },
            ),
          ],
          const SizedBox(height: 20),
          // go home, a page of its own has no way back
          if (!accepted)
            AtButton(
              'ارجع للرئيسية',
              kind: AtButtonKind.text,
              onPressed: () => context.go('/'),
            ),
        ],
      ),
    );
  }

  Widget _timer(Json timer, bool closed) {
    final elapsed = _elapsed(timer);
    final required = (timer['requiredSeconds'] as num).toInt();
    final total = required + (timer['extensionSeconds'] as num).toInt();
    final remaining = math.max(0, total - elapsed);
    final messages = '${timer['messages'] ?? ''}'.split('\n');
    final reached = timer['requiredReachedAt'] != null;
    final messageIndex = reached
        ? 2
        : elapsed >= required / 2
        ? 1
        : 0;
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    const ink = Color(0xFFEDF1FA);
    const soft = Color(0xFFB7C5E8);
    final status = switch (timer['status']) {
      'PAUSED' => reached ? 'اكتملت المدة' : 'متوقف مؤقتًا',
      'FINISHED' => 'اكتملت الجلسة',
      'EXPIRED' => 'انتهت المهلة',
      _ => 'جارٍ التركيز',
    };
    String clock(int seconds) => arabicDigits('${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}');
    return Column(
      children: [
        const SizedBox(height: 16),
        // the focus card (design: ProofTimer): navy, the big ring, the time in white
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s5, Space.s4, Space.s5),
          decoration: BoxDecoration(color: c.deep, borderRadius: BorderRadius.circular(28)),
          child: Column(
            children: [
              TagPill(status, fg: ink, bg: c.deepRaised, icon: timer['status'] == 'RUNNING' ? Icons.bolt_rounded : Icons.pause_rounded),
              const SizedBox(height: Space.s5),
              SizedBox(
                width: 230,
                height: 230,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: (elapsed / required).clamp(0, 1).toDouble(),
                        strokeWidth: 12,
                        backgroundColor: c.deepRaised,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF8FB4FF)),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(clock(remaining), style: text.displayLarge!.copyWith(color: ink, fontWeight: FontWeight.w800)),
                        Text('من ${clock(total)}', style: text.labelSmall!.copyWith(color: soft)),
                      ],
                    ),
                  ],
                ),
              ),
              if (messageIndex > 0) ...[
                const SizedBox(height: Space.s4),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.deepRaised, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 18, color: Color(0xFF8FB4FF)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          messageIndex < messages.length && messages[messageIndex].trim().isNotEmpty
                              ? messages[messageIndex]
                              : 'خذ وقتك، خطوة خطوة.',
                          style: text.bodySmall!.copyWith(color: ink, height: 1.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (!closed)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (timer['status'] == 'RUNNING')
                AtButton(
                  'خذ استراحة',
                  expand: false,
                  kind: AtButtonKind.outline,
                  onPressed: _busy ? null : () => _timerAction('pause'),
                  icon: const Icon(Icons.pause),
                ),
              if (timer['status'] == 'PAUSED' && elapsed < total)
                AtButton(
                  'كمّل الجلسة',
                  expand: false,
                  onPressed: _busy ? null : () => _timerAction('resume'),
                  icon: const Icon(Icons.play_arrow),
                ),
              if (timer['status'] == 'RUNNING' || timer['status'] == 'PAUSED')
                AtButton(
                  'أنهِ الجلسة',
                  expand: false,
                  kind: AtButtonKind.text,
                  onPressed: _busy ? null : () => _timerAction('finish'),
                ),
            ],
          ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: c.inkSubtle),
            const SizedBox(width: 4),
            Flexible(child: Text('الاستراحة ما تنحسب · تنتهي آخر اليوم', style: text.labelSmall, textAlign: TextAlign.center)),
          ],
        ),
        if (reached && !closed) ...[
          const SizedBox(height: 24),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  IconTile(Icons.more_time_rounded, size: 40),
                  const SizedBox(width: 10),
                  Expanded(child: Text('ودّك تكمّل؟', style: text.titleMedium)),
                  TagPill('إنجازك محفوظ', fg: c.success, bg: c.successSoft, icon: Icons.check_rounded),
                ]),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final m in const [10, 15, 30]) ...[
                      Expanded(
                        child: _ExtendChip(
                          label: '+${arabicDigits(m)}',
                          caption: 'دقيقة',
                          onTap: _busy ? null : () => _timerAction('extend', body: {'minutes': m}),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // any minutes, or until a time
                    Expanded(
                      child: _ExtendChip(
                        icon: Icons.tune_rounded,
                        caption: 'مدة ثانية',
                        onTap: _busy
                            ? null
                            : () async {
                                final minutes = await showAtSheet<int>(context, builder: (_) => const _ExtendSheet());
                                if (minutes != null && mounted) _timerAction('extend', body: {'minutes': minutes});
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (reached) ...[
          const SizedBox(height: 24),
          Text(
            'كيف كانت الجلسة؟',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final feeling in {
                'EASY': '😌 سهلة',
                'OK': '🙂 مناسبة',
                'TIRING': '😮‍💨 متعبة',
              }.entries)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(feeling.value),
                  selected: timer['feedback'] == feeling.key,
                  onSelected: _busy
                      ? null
                      : (_) => _timerAction(
                          'feedback',
                          body: {'feedback': feeling.key},
                        ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('اختياري', style: Theme.of(context).textTheme.labelSmall),
        ],
      ],
    );
  }
}

class QuizPanel extends StatefulWidget {
  final int proofId;
  final int weekId;
  final int? taskId;
  final Future<void> Function() onSubmitted;
  const QuizPanel({
    super.key,
    required this.proofId,
    required this.weekId,
    this.taskId,
    required this.onSubmitted,
  });
  @override
  State<QuizPanel> createState() => _QuizPanelState();
}

class _QuizPanelState extends State<QuizPanel> {
  final _topic = TextEditingController();
  bool _needsTopic = false;
  bool _generationFailed = false;
  final List<int> _pages = [];
  final Map<int, String?> _answers = {};
  Json? _quiz;
  bool _busy = false;
  String? _notice;
  Timer? _expiryClock;
  String? _pendingAction;
  @override
  void dispose() {
    _expiryClock?.cancel();
    _topic.dispose();
    super.dispose();
  }

  Duration? get _remaining {
    final end = serverInstant(_quiz?['expiresAt']);
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _page() async {
    if (_busy) return;
    if (_pages.length >= 6) {
      showMessage(context, 'يكفي حتى ست صور واضحة للصفحات.');
      return;
    }
    final photo = await takeProofPhoto(context, 'صفحة من المحتوى — اختياري');
    if (photo == null || !mounted) return;
    setState(() {
      _busy = true;
      _pendingAction = 'page';
    });
    try {
      final id = await ProofsApi(context.read<ApiClient>()).cameraUpload(
        'PAGE',
        photo.bytes,
        proofId: widget.proofId,
        mime: photo.mime,
      );
      if (mounted) {
        setState(() => _pages.add(id));
        showMessage(context, 'تم إرفاق الصفحة بنجاح');
      }
    } catch (error) {
      if (mounted) proofError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate({bool withoutImages = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pendingAction = withoutImages ? 'generateWithoutImages' : 'generate';
      _notice = null;
      _generationFailed = false;
    });
    final client = context.read<ApiClient>();
    final member = context.read<AuthState>().userId;
    try {
      final quiz = Map<String, dynamic>.from(
        await client.post(
              '/api/v1/quiz/create/$member/${widget.weekId}',
              query: {
                'goalTaskId': widget.taskId,
                if (_topic.text.trim().isNotEmpty) 'topic': _topic.text.trim(),
              },
              body: {
                'proofId': widget.proofId,
                'captureIds': withoutImages ? <int>[] : List<int>.of(_pages),
              },
            ).timeout(const Duration(seconds: 45))
            as Map,
      );
      if (!mounted) return;
      setState(() {
        _pages.clear();
        _answers.clear();
        _quiz = quiz['quizId'] == null ? null : quiz;
        _notice = quiz['quizId'] == null
            ? 'الصفحات غير واضحة. صوّر الجزئية مرة ثانية، أو جهّز أسئلة عامة بدون صور. لم تُحتسب عليك محاولة.'
            : null;
      });
      _expiryClock?.cancel();
      if (_quiz != null) {
        _expiryClock = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _generationFailed = true;
          _notice = error is TimeoutException
              ? 'تأخر تجهيز الأسئلة. أعد المحاولة؛ ما تحتاج تعيد رفع الصور.'
              : friendlyError(error);
          if (error is ApiException &&
              error.message.contains('Quiz topic is unclear')) {
            _needsTopic = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_remaining == Duration.zero) {
      setState(
        () => _notice =
            'انتهت مهلة الاختبار. جهّز اختبارًا جديدًا إذا كانت لديك محاولة متاحة.',
      );
      return;
    }
    final questions = ProofsApi.maps(_quiz!['questions']);
    if (questions.any((q) => _answers[q['number']] == null)) {
      showMessage(context, 'جاوب الأسئلة الأربعة أولًا.');
      return;
    }
    setState(() {
      _busy = true;
      _pendingAction = 'submit';
    });
    try {
      final letters = questions.map((q) => _answers[q['number']]!).join();
      await context.read<ApiClient>().post(
        '/api/v1/proof-attempt/${widget.proofId}/submit',
        body: {'evidenceData': '${_quiz!['quizId']}:$letters'},
      );
      await widget.onSubmitted();
      if (mounted) {
        setState(() {
          _expiryClock?.cancel();
          _quiz = null;
          _notice =
              'حفظنا الإجابات. راجع نتيجة الدليل بالأسفل؛ إذا ما نجحت المحاولة الأولى تقدر تطلب إعادة واحدة.';
        });
      }
    } catch (error) {
      if (mounted) proofError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'اختبار خفيف على إنجازك',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            '٤ أسئلة سهلة، والنجاح من ٣. صلاحية الاختبار ساعة من إصداره، وتوجد إعادة واحدة فقط.',
          ),
          const SizedBox(height: 16),
          if (_notice != null) ...[
            ProofNotice(_notice!),
            const SizedBox(height: 16),
          ],
          if (_busy &&
              (_pendingAction == 'generate' ||
                  _pendingAction == 'generateWithoutImages')) ...[
            const ProofNotice('جارٍ تجهيز الأسئلة… قد يستغرق حتى ٤٥ ثانية.'),
            const SizedBox(height: 12),
          ],
          if (_quiz == null) ...[
            if (_generationFailed) ...[
              AtButton(
                'إعادة المحاولة',
                onPressed: _busy ? null : () => _generate(
                  withoutImages: _pendingAction == 'generateWithoutImages',
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_needsTopic) ...[
              TextField(
                controller: _topic,
                enabled: !_busy,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'وضّح موضوع النشاط',
                  hintText: 'حدّد موضوع ما تعلّمته في هذا النشاط',
                ),
              ),
              const SizedBox(height: 12),
            ],
            AtButton(
              'صوّر صفحة — اختياري',
              kind: AtButtonKind.outline,
              onPressed: _busy ? null : _page,
            ),
            for (final id in _pages) EvidenceImage('capture:$id'),
            if (_pages.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text('صور مرفقة: ${arabicDigits(_pages.length)}'),
              ),
            const SizedBox(height: 10),
            if (_pages.isNotEmpty) ...[
              AtButton(
                'جهّز الأسئلة من الصور',
                loading: _busy && _pendingAction == 'generate',
                onPressed: _busy ? null : () => _generate(),
              ),
              const SizedBox(height: 10),
            ],
            AtButton(
              'جهّز الأسئلة بدون صور',
              kind: _pages.isEmpty
                  ? AtButtonKind.primary
                  : AtButtonKind.outline,
              loading: _busy && _pendingAction == 'generateWithoutImages',
              onPressed: _busy ? null : () => _generate(withoutImages: true),
            ),
          ] else ...[
            if (_remaining == Duration.zero)
              AtButton(
                'جهّز اختبارًا جديدًا',
                loading: _busy,
                onPressed: _generate,
              ),
            if (_remaining != null) ...[
              Text(
                _remaining == Duration.zero
                    ? 'انتهى وقت الاختبار'
                    : 'الوقت المتبقي: ${arabicDigits(_remaining!.inMinutes.toString().padLeft(2, '0'))}:${arabicDigits((_remaining!.inSeconds % 60).toString().padLeft(2, '0'))}',
              ),
              const SizedBox(height: 16),
            ],
            for (final (i, question) in ProofsApi.maps(
              _quiz!['questions'],
            ).indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 28, child: Text(arabicDigits(i + 1))),
                        Expanded(child: QuizQuestionText(
                          '${question['question']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: _answers[question['number']],
                      onChanged: (value) {
                        if (!_busy && _remaining != Duration.zero) {
                          setState(
                            () => _answers[question['number'] as int] = value,
                          );
                        }
                      },
                      child: Column(
                        children: [
                          for (final (option, text)
                              in (question['options'] as List).indexed)
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: 'ABC'[option],
                              title: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 26, child: Text('ABC'[option], textDirection: TextDirection.ltr)),
                                  Expanded(child: QuizQuestionText(quizOptionBody('$text'))),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            AtButton(
              'أرسل الإجابات',
              loading: _busy,
              onPressed: _remaining == Duration.zero ? null : _submit,
            ),
          ],
        ],
      ),
    ),
  );
}


// one choice of the extension: a number (or an icon) over a short caption
class _ExtendChip extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String caption;
  final VoidCallback? onTap;

  const _ExtendChip({this.label, this.icon, required this.caption, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.primarySoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 62,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(icon, size: 22, color: c.primary)
              else
                Text(label ?? '', style: text.titleMedium!.copyWith(color: c.primary, fontWeight: FontWeight.w800, height: 1.2)),
              Text(caption, style: text.labelSmall!.copyWith(color: c.primary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// «مدة ثانية»: by minutes (a big number with − and +) or until a clock time
class _ExtendSheet extends StatefulWidget {
  const _ExtendSheet();

  @override
  State<_ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends State<_ExtendSheet> {
  bool _byTime = false;
  int _minutes = 20;
  TimeOfDay? _until;

  // the minutes from now until the chosen time (tomorrow is not allowed: the session ends with the day)
  int? get _untilMinutes {
    final t = _until;
    if (t == null) return null;
    final now = TimeOfDay.now();
    final diff = (t.hour * 60 + t.minute) - (now.hour * 60 + now.minute);
    return diff > 0 ? diff : null;
  }

  String _clock(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    return '${arabicDigits(h)}:${arabicDigits(t.minute.toString().padLeft(2, '0'))} ${t.period == DayPeriod.am ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final result = _byTime ? _untilMinutes : _minutes;
    Widget round(IconData icon, VoidCallback? onTap) => Material(
          color: c.surfaceSunken,
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 52, height: 52, child: Icon(icon, color: c.primary))),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(icon: Icons.more_time_rounded, title: 'كم تبي تكمّل؟'),
          SegmentedPills<bool>(
            options: const [(false, 'بالدقائق'), (true, 'لين الساعة')],
            value: _byTime,
            onChanged: (v) => setState(() => _byTime = v),
          ),
          const SizedBox(height: Space.s5),
          if (!_byTime) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                round(Icons.remove_rounded, _minutes > 5 ? () => setState(() => _minutes -= 5) : null),
                SizedBox(
                  width: 130,
                  child: Column(
                    children: [
                      Text(arabicDigits(_minutes), style: text.headlineLarge!.copyWith(fontWeight: FontWeight.w800, color: c.ink)),
                      Text('دقيقة', style: text.labelSmall),
                    ],
                  ),
                ),
                round(Icons.add_rounded, _minutes < 240 ? () => setState(() => _minutes += 5) : null),
              ],
            ),
            const SizedBox(height: Space.s3),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final m in const [20, 45, 60, 90])
                  ChoiceChip(
                    label: Text(arabicDigits(m)),
                    showCheckmark: false,
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ],
            ),
          ] else ...[
            Material(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(Radii.card),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.card),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _until ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 30))),
                  );
                  if (picked != null) setState(() => _until = picked);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Column(
                    children: [
                      Icon(Icons.schedule_rounded, color: c.primary, size: 28),
                      const SizedBox(height: 6),
                      Text(_until == null ? 'اختر الساعة' : _clock(_until!),
                          style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w800, color: c.ink)),
                      if (_until != null)
                        Text(_untilMinutes == null ? 'اختر وقت بعد الحين' : 'يعني ${arabicDigits(_untilMinutes)} دقيقة',
                            style: text.labelSmall!.copyWith(color: _untilMinutes == null ? c.danger : null)),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.s5),
          AtButton(
            result == null ? 'مدّد' : 'مدّد ${arabicDigits(result)} دقيقة',
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            onPressed: result == null || result < 1 || result > 600 ? null : () => Navigator.pop(context, result),
          ),
        ],
      ),
    );
  }
}
