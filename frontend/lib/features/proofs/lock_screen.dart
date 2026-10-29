import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/at_colors.dart';
import '../../core/theme/at_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/widgets.dart';

// OWNER: Subhiyyah - the lock screen (design: Lock), GET /commitment/lockStatus
// a navy focus page: the lock with a swaying key, what is owed, then «تبرّع وافتح التطبيق» (the donation steps)
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  // the navy page (the same in light and dark)
  static const _raised = Color(0xFF13285A);
  static const _line = Color(0xFF22386B);
  static const _ink = Color(0xFFEDF1FA);
  static const _muted = Color(0xFFB7C5E8);
  static const _goldLight = Color(0xFFF1DCA6);

  static String _why(Object? reason) => switch (reason) {
        'LOST_DAY' => 'فاتت مرة',
        'WITHDRAWAL' => 'انسحاب',
        'GROUP_COLLECTIVE' => 'تسوية المجموعة',
        _ => 'خصم',
      };

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final text = Theme.of(context).textTheme;
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.deep,
      body: SafeArea(
        child: AsyncView<Map<String, dynamic>>(
          load: () async => Map<String, dynamic>.from(await api.get('/api/v1/commitment/lockStatus') as Map),
          builder: (context, status, reload) {
            final penalties = (status['penalties'] as List?) ?? const [];
            final total = status['totalToDonate'] as num?;
            return LayoutBuilder(
              builder: (context, box) => RefreshIndicator(
                onRefresh: reload,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Space.s5, Space.s6, Space.s5, Space.s6),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - Space.s6 * 2),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: Space.s8),
                          const Center(child: _LockArt()),
                          const SizedBox(height: Space.s6),
                          Text('التطبيق معلّق مؤقتًا',
                              textAlign: TextAlign.center, style: text.headlineMedium!.copyWith(color: _ink, fontWeight: FontWeight.w800)),
                          const SizedBox(height: Space.s2),
                          Text(
                            'هدفك يستاهل فرصة ثانية، تبرّع لإحسان.. وبالحالتين خير.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium!.copyWith(color: _muted, height: 1.75),
                          ),
                          const SizedBox(height: Space.s6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: 14),
                            decoration: BoxDecoration(color: _raised, borderRadius: BorderRadius.circular(Radii.card)),
                            child: Column(
                              children: [
                                for (final p in penalties) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          [_why((p as Map)['reason']), if (p['commitmentTitle'] != null) '${p['commitmentTitle']}'].join(' · '),
                                          style: text.bodySmall!.copyWith(color: _ink),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(money(p['amount'] as num?), style: text.labelLarge!.copyWith(color: _ink, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                Container(height: 1, color: _line),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: Text('المطلوب', style: text.labelLarge!.copyWith(color: _ink, fontWeight: FontWeight.w700))),
                                    RiyalAmount(total, color: _goldLight, style: text.headlineMedium!.copyWith(fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: Space.s8),
                          AtButton('تبرّع وكمّل أهدافك', kind: AtButtonKind.gold, onPressed: () => context.push('/proofs/donations')),
                          const SizedBox(height: Space.s2),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: _muted, minimumSize: const Size.fromHeight(44)),
                            onPressed: () => context.push('/requests'),
                            child: const Text('اعتراض على الخصم'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: _muted.withValues(alpha: 0.7)),
                            onPressed: () => context.read<AuthState>().logout(),
                            child: const Text('تسجيل الخروج'),
                          ),
                        ],
                      ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// the lock on a navy circle, and a gold key swaying beside it
class _LockArt extends StatefulWidget {
  const _LockArt();

  @override
  State<_LockArt> createState() => _LockArtState();
}

class _LockArtState extends State<_LockArt> with SingleTickerProviderStateMixin {
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _sway.stop();
    } else if (!_sway.isAnimating) {
      _sway.repeat();
    }
  }

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'قفل',
      child: SizedBox(
        width: 260,
        height: 240,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 240, height: 240, decoration: const BoxDecoration(color: LockScreen._raised, shape: BoxShape.circle)),
            const Positioned(top: 40, child: CustomPaint(size: Size(140, 170), painter: _LockPainter())),
            // the key hangs from a string and sways: rotate(-10deg) -> rotate(10deg)
            Positioned(
              top: 0,
              right: 36,
              child: AnimatedBuilder(
                animation: _sway,
                builder: (context, child) => Transform.rotate(
                  angle: math.sin(_sway.value * 2 * math.pi) * 10 * math.pi / 180,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
                child: const CustomPaint(size: Size(48, 96), painter: _KeyPainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockPainter extends CustomPainter {
  const _LockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final shackle = Paint()
      ..color = const Color(0xFF7DA6FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(34, 76)
      ..lineTo(34, 50)
      ..arcToPoint(const Offset(106, 50), radius: const Radius.circular(36))
      ..lineTo(106, 76);
    canvas.drawPath(path, shackle);
    canvas.drawRRect(RRect.fromLTRBR(10, 72, 130, 168, const Radius.circular(22)), Paint()..color = const Color(0xFF1C46C9));
    canvas.drawRRect(RRect.fromLTRBR(10, 72, 130, 92, const Radius.circular(10)), Paint()..color = const Color(0xFF2F6BF2));
    final hole = Paint()..color = const Color(0xFF0A1A3A);
    canvas.drawCircle(const Offset(70, 112), 11, hole);
    canvas.drawRRect(RRect.fromLTRBR(65, 112, 75, 138, const Radius.circular(5)), hole);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _KeyPainter extends CustomPainter {
  const _KeyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(const Offset(24, 0), const Offset(24, 14), Paint()
      ..color = const Color(0xFF7A869C)
      ..strokeWidth = 2);
    final gold = Paint()
      ..color = const Color(0xFFF1DCA6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(24, 30), 14, gold);
    canvas.drawLine(const Offset(24, 44), const Offset(24, 86), gold);
    canvas.drawLine(const Offset(24, 66), const Offset(35, 66), gold);
    canvas.drawLine(const Offset(24, 79), const Offset(32, 79), gold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
