import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/at_colors.dart';
import '../../core/theme/at_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';
import 'proof_widgets.dart';
import 'proofs_api.dart';

// the admin tools: member accounts (suspend, restore, a pardon card) and blocking proof methods

// ---------- members ----------
class AdminMembersScreen extends StatefulWidget {
  const AdminMembersScreen({super.key});

  @override
  State<AdminMembersScreen> createState() => _AdminMembersScreenState();
}

class _AdminMembersScreenState extends State<AdminMembersScreen> {
  late final ApiClient _api = context.read<ApiClient>();
  final _search = TextEditingController();
  late Future<List<Json>> _members = _load();

  Future<List<Json>> _load() async =>
      ProofsApi.maps(await _api.get('/api/v1/admin/members', query: {'query': _search.text.trim()}));

  void _reload() => setState(() {
      _members = _load();
    });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(Json member) async {
    final changed = await showAtSheet<bool>(context, builder: (_) => _MemberSheet(member: member));
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأعضاء')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s3),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'اسم، إيميل أو جوال',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(onPressed: _reload, icon: const Icon(Icons.arrow_back_rounded)),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Json>>(
              future: _members,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const LoadingView();
                if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
                final members = snap.data!;
                if (members.isEmpty) return const EmptyView(message: 'ما لقينا أحد', icon: Icons.person_search_rounded);
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s8),
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(height: Space.s2),
                    itemBuilder: (context, i) => _MemberRow(member: members[i], onTap: () => _open(members[i])),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// the state of an account as a small colored label
(String, Color, Color) _accountState(BuildContext context, Json m) {
  final c = context.colors;
  if (m['accountStatus'] == 'SUSPENDED') return ('موقوف', c.danger, c.dangerSoft);
  if (m['accountStatus'] == 'DEACTIVATED') return ('معطّل منه', c.inkMuted, c.surfaceSunken);
  if (m['accountBanned'] == true) return ('محظور', c.danger, c.dangerSoft);
  if (m['isLocked'] == true) return ('معلّق', c.warning, c.warningSoft);
  return ('نشط', c.success, c.successSoft);
}

class _MemberRow extends StatelessWidget {
  final Json member;
  final VoidCallback onTap;

  const _MemberRow({required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final name = '${member['name'] ?? '-'}';
    final (label, fg, bg) = _accountState(context, member);
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.line)),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: c.primarySoft,
                child: Text(name.isEmpty ? '؟' : name.characters.first, style: text.titleMedium!.copyWith(color: c.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('${member['email'] ?? ''}', style: text.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TagPill(label, fg: fg, bg: bg),
            ],
          ),
        ),
      ),
    );
  }
}

// one member: his numbers, and the three things the admin can do
class _MemberSheet extends StatefulWidget {
  final Json member;

  const _MemberSheet({required this.member});

  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  bool _busy = false;

  Json get m => widget.member;
  bool get _suspended => m['accountStatus'] == 'SUSPENDED';

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showMessage(context, done);
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) proofError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _suspend() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('توقف الحساب؟'),
        content: const Text('ما يقدر يدخل لين ترجّعه، وبياناته تبقى.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('أوقفه', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = context.read<ApiClient>();
    await _run(() => api.put('/api/v1/admin/members/${m['id']}/suspend'), 'وقّفنا الحساب');
  }

  Future<void> _restore() async {
    final api = context.read<ApiClient>();
    await _run(() => api.put('/api/v1/admin/members/${m['id']}/restore'), 'رجع الحساب');
  }

  Future<void> _giveCard() async {
    final reason = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('بطاقة عفو هدية'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLength: 255,
          decoration: const InputDecoration(hintText: 'السبب، مثل: خلل تقني'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('أعطه')),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (sent != true || !mounted) return;
    if (text.isEmpty) {
      showMessage(context, 'اكتب السبب');
      return;
    }
    final api = context.read<ApiClient>();
    await _run(() => api.post('/api/v1/admin/members/${m['id']}/grace-day', query: {'reason': text}), 'وصلته البطاقة');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, fg, bg) = _accountState(context, m);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(icon: Icons.person_rounded, title: '${m['name'] ?? '-'}', subtitle: '${m['email'] ?? ''} · ${m['phone'] ?? ''}'),
          Row(
            children: [
              TagPill(label, fg: fg, bg: bg),
              const SizedBox(width: 8),
              TagPill(levelsAr['${m['level']}'] ?? '${m['level'] ?? '-'}', fg: c.primary, bg: c.primarySoft, icon: Icons.military_tech_rounded),
              const SizedBox(width: 8),
              TagPill('${arabicDigits(m['points'] ?? 0)} نقطة', fg: c.pardonText, bg: c.pardonSoft),
            ],
          ),
          const SizedBox(height: Space.s4),
          if (_busy) const LinearProgressIndicator(),
          RowGroup(children: [
            ActionRow(
              icon: Icons.confirmation_number_rounded,
              title: 'أعطه بطاقة عفو',
              subtitle: 'هدية لمدة ٤ أسابيع',
              tone: c.pardon,
              onTap: _busy ? null : _giveCard,
            ),
            if (_suspended)
              ActionRow(icon: Icons.lock_open_rounded, title: 'رجّع الحساب', tone: c.success, onTap: _busy ? null : _restore)
            else if (m['accountStatus'] != 'DEACTIVATED')
              ActionRow(
                icon: Icons.block_rounded,
                title: 'أوقف الحساب',
                subtitle: 'ما يقدر يدخل لين ترجّعه',
                danger: true,
                onTap: _busy ? null : _suspend,
              ),
          ]),
        ],
      ),
    );
  }
}

// ---------- proof methods ----------
// the admin blocks a method: new habits and goals can't pick it, the running ones keep it
class AdminProofMethodsScreen extends StatefulWidget {
  const AdminProofMethodsScreen({super.key});

  @override
  State<AdminProofMethodsScreen> createState() => _AdminProofMethodsScreenState();
}

class _AdminProofMethodsScreenState extends State<AdminProofMethodsScreen> {
  late final ApiClient _api = context.read<ApiClient>();
  late Future<List<Json>> _methods = _load();

  Future<List<Json>> _load() async => ProofsApi.maps(await _api.get('/api/v1/admin/proof-methods'));

  void _reload() {
    setState(() {
      _methods = _load();
    });
  }

  Future<void> _toggle(Json m) async {
    try {
      await _api.put('/api/v1/admin/proof-methods/${m['id']}/toggle');
      _reload();
    } catch (error) {
      if (mounted) proofError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('طرق الإثبات')),
      body: FutureBuilder<List<Json>>(
        future: _methods,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(message: friendlyError(snap.error!), onRetry: _reload);
          final methods = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(Space.s4),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final m in methods)
                      SwitchListTile.adaptive(
                        value: m['enabled'] == true,
                        onChanged: (_) => _toggle(m),
                        secondary: IconTile(
                          methodIcon('${m['code']}'),
                          size: 40,
                          fg: m['enabled'] == true ? c.primary : c.inkSubtle,
                          bg: m['enabled'] == true ? c.primarySoft : c.surfaceSunken,
                        ),
                        title: Text('${m['nameAr']}'),
                        subtitle: Text(m['enabled'] == true ? 'متاحة' : 'محجوبة'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s3),
              Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.inkSubtle),
                const SizedBox(width: 6),
                Expanded(child: Text('الحجب للتعهّدات الجديدة بس، والشغّالة تكمل', style: Theme.of(context).textTheme.labelSmall)),
              ]),
            ],
          );
        },
      ),
    );
  }
}
