import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/at_colors.dart';
import '../../core/theme/at_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'commitment_widgets.dart';
import 'commitments_api.dart';
import '../learn_quest/book_suggestions.dart';

// OWNER: Turki - a new goal with the AI plan
// step 1: the member writes the goal and its end date, the AI suggests a task for every week (nothing is saved)
// step 2: he changes what he wants, then the plan is saved and the goal starts right away
class GoalPlanScreen extends StatefulWidget {
  const GoalPlanScreen({super.key});

  @override
  State<GoalPlanScreen> createState() => _GoalPlanScreenState();
}

class _WeekDraft {
  final TextEditingController title;
  int times;

  _WeekDraft(String title, this.times) : title = TextEditingController(text: title);
}

class _GoalPlanScreenState extends State<GoalPlanScreen> {
  late final _api = CommitmentsApi(context.read<ApiClient>());
  final _goal = TextEditingController();
  DateTime? _endDate;
  DateTime _start = dateOnly(DateTime.now()); // week 1 starts today or later
  bool get _later => _start.isAfter(dateOnly(DateTime.now()));

  // step 2
  JsonMap? _plan;
  final _title = TextEditingController();
  final _amount = TextEditingController(text: '5'); // the least Ehsan takes
  final _target = TargetDraft();
  String _proofMethod = 'PHOTO';
  List<Map<String, dynamic>>? _catalog; // the methods the admin left on

  @override
  void initState() {
    super.initState();
    ProofCatalog.load(context.read<ApiClient>()).then((list) {
      if (mounted) setState(() => _catalog = list);
    }).catchError((_) {});
  }

  List<String> get _methods => ProofCatalog.methods(_catalog, ['PHOTO', 'TIMER', 'QUIZ', 'LOCATION']);
  List<_WeekDraft> _weeks = [];

  bool _busy = false;

  @override
  void dispose() {
    _goal.dispose();
    _title.dispose();
    _amount.dispose();
    _target.dispose();
    for (final w in _weeks) {
      w.title.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate != null && !_endDate!.isBefore(_start) ? _endDate! : _start.add(const Duration(days: 28)),
      firstDate: _start, // it can end the day it starts (today too)
      lastDate: now.add(const Duration(days: 364)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _suggest() async {
    if (_goal.text.trim().isEmpty || _endDate == null) {
      showMessage(context, 'اكتب هدفك واختر تاريخ نهايته.');
      return;
    }
    setState(() => _busy = true);
    try {
      final plan = await _api.suggestPlan(_goal.text.trim(), _endDate!, startDate: _later ? _start : null);
      if (!mounted) return;
      for (final w in _weeks) {
        w.title.dispose();
      }
      setState(() {
        _plan = plan;
        _title.text = '${plan['title'] ?? _goal.text.trim()}';
        final method = '${plan['proofMethod'] ?? ''}';
        _proofMethod = _methods.contains(method) ? method : 'PHOTO';
        _weeks = ((plan['weeks'] as List?) ?? const [])
            .map((w) => _WeekDraft('${(w as Map)['title'] ?? ''}', ((w['timesPerWeek'] ?? 1) as int).clamp(1, 7)))
            .toList();
        if (_weeks.isEmpty) _weeks = [_WeekDraft(_title.text, 3)];
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (_title.text.trim().isEmpty) return showMessage(context, 'اكتب عنوان الهدف.');
    if (amount == null || amount < 5) return showMessage(context, 'أقل مبلغ لكل مرة ٥ ريال.');
    if (_weeks.any((w) => w.title.text.trim().isEmpty)) return showMessage(context, 'كل أسبوع يحتاج مهمة.');
    final targetError = _target.check(_proofMethod);
    if (targetError != null) return showMessage(context, targetError);

    setState(() => _busy = true);
    try {
      await _api.addWithPlan({
        'title': _title.text.trim(),
        'description': _goal.text.trim(),
        'proofMethod': _proofMethod,
        'amountPerTime': amount,
        'weeks': _weeks.map((w) => {'title': w.title.text.trim(), 'timesPerWeek': w.times}).toList(),
        ..._target.toCommitmentJson(_proofMethod),
        if (_later) 'startDate': isoDate(_start),
      });
      if (!mounted) return;
      showMessage(context, _later ? 'تمام، الهدف يبدأ ${weekDaysAr[_start.weekday % 7]} ${arabicDigits(isoDate(_start))}.' : 'بدأ الهدف، الأسبوع الأول يخلص هالسبت.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('هدف جديد')),
      body: _plan == null ? _askStep(context) : _planStep(context),
    );
  }

  // today + n days, at midnight (so the chip stays selected)
  DateTime _quick(int days) => _start.add(Duration(days: days));

  Widget _askStep(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(Space.s4),
      children: [
        const SizedBox(height: Space.s4),
        Text('وش هدفك؟', style: text.headlineLarge!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: Space.s1),
        Row(children: [
          Icon(Icons.auto_awesome_rounded, size: 16, color: context.colors.primary),
          const SizedBox(width: 6),
          Expanded(child: Text('الذكاء يقسّمه مراحل أسبوع بأسبوع', style: text.labelSmall)),
        ]),
        const SizedBox(height: Space.s4),
        TextField(
          controller: _goal,
          maxLength: 300,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'أبي أخلص كتاب في البرمجة', counterText: ''),
        ),
        BookSuggestions(title: _goal), // Learn Quest: books for a reading goal
        const SizedBox(height: Space.s4),
        Text('متى يبدأ؟', style: text.labelLarge),
        const SizedBox(height: Space.s2),
        StartDatePicker(
          value: _start,
          onChanged: (d) => setState(() {
            final length = _endDate?.difference(_start);
            _start = d;
            if (length != null) _endDate = d.add(length); // the same length from the new start
          }),
        ),
        const SizedBox(height: Space.s4),
        Text('متى ينتهي؟', style: text.labelLarge),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, days) in const [('أسبوعين', 14), ('شهر', 30), ('٣ شهور', 90)])
              ChoiceChip(
                label: Text(label),
                showCheckmark: false,
                selected: _endDate != null && _quick(days) == _endDate,
                onSelected: (_) => setState(() => _endDate = _quick(days)),
              ),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(_endDate == null ? 'تاريخ ثاني' : arabicDigits(isoDate(_endDate!))),
              onPressed: _pickDate,
            ),
          ],
        ),
        const SizedBox(height: Space.s6),
        AtButton('اقترح لي خطة', loading: _busy, icon: const Icon(Icons.auto_awesome_rounded, size: 18), onPressed: _suggest),
      ],
    );
  }

  Widget _planStep(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    final amount = parseAmount(_amount.text) ?? 0;
    final note = _plan?['note'];
    return ListView(
      padding: const EdgeInsets.all(Space.s4),
      children: [
        if (note != null && '$note'.isNotEmpty)
          AppCard(
            color: c.primarySoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome_rounded, color: c.primary, size: 20),
                const SizedBox(width: Space.s2),
                Expanded(child: Text('$note', style: text.bodySmall!.copyWith(color: c.ink))),
              ],
            ),
          ),
        const SizedBox(height: Space.s4),
        TextField(controller: _title, maxLength: 100, decoration: const InputDecoration(labelText: 'عنوان الهدف', counterText: '')),
        const SizedBox(height: Space.s4),
        Text('كيف تثبت؟', style: text.labelLarge),
        const SizedBox(height: Space.s2),
        ProofMethodGrid(
          methods: _methods,
          value: _proofMethod,
          onChanged: (v) => setState(() {
            _proofMethod = v;
            if (v == 'TIMER' && _target.minutes.text.isEmpty) _target.minutes.text = '30';
          }),
        ),
        if (_proofMethod == 'LOCATION' || _proofMethod == 'TIMER') ...[
          const SizedBox(height: Space.s3),
          TargetFields(proofMethod: _proofMethod, draft: _target),
        ],
        const SizedBox(height: Space.s4),
        Row(children: [
          Text('كم تتعهّد لكل مرة؟', style: text.labelLarge),
          const SizedBox(width: 6),
          Text('أقل شي ٥', style: text.labelSmall),
        ]),
        const SizedBox(height: Space.s2),
        AmountChips(controller: _amount, onChanged: () => setState(() {})),
        SectionTitle('الخطة (${arabicDigits(_weeks.length)} أسابيع)'),
        ...List.generate(_weeks.length, (i) {
          final w = _weeks[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.s3),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('الأسبوع ${arabicDigits(i + 1)}', style: text.titleSmall)),
                      TimesStepper(value: w.times, onChanged: (v) => setState(() => w.times = v)),
                    ],
                  ),
                  const SizedBox(height: Space.s2),
                  TextField(controller: w.title, decoration: const InputDecoration(labelText: 'مهمة الأسبوع')),
                  const SizedBox(height: Space.s1),
                  Row(children: [
                    Icon(Icons.trending_down_rounded, size: 14, color: c.goldText),
                    const SizedBox(width: 4),
                    Text('أقصى خصم ', style: text.labelSmall),
                    RiyalAmount(w.times * amount, style: text.labelSmall!.copyWith(color: c.goldText, fontWeight: FontWeight.w700)),
                  ]),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: Space.s2),
        AtButton('أتعهّد بهالهدف', icon: const Icon(Icons.flag_rounded, size: 20), loading: _busy, onPressed: _save),
        const SizedBox(height: Space.s2),
        AtButton('اكتب الهدف من جديد', kind: AtButtonKind.text, onPressed: _busy ? null : () => setState(() => _plan = null)),
      ],
    );
  }
}
