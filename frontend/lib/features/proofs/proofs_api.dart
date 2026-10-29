import 'dart:convert';
import 'dart:typed_data';
import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/utils/format.dart';

typedef Json = Map<String, dynamic>;

class ProofsApi {
  final ApiClient client;
  ProofsApi(this.client);

  Future<Json> workspace() async => Map<String, dynamic>.from(
    await client.get('/api/v1/proof-workspace/my') as Map,
  );
  Future<List<Json>> activities() async =>
      maps(await client.get('/api/v1/commitment-week/today'));
  Future<Json> state(int id) async => Map<String, dynamic>.from(
    await client.get('/api/v1/proof-attempt/$id') as Map,
  );

  Future<int> cameraUpload(
    String kind,
    Uint8List bytes, {
    int? proofId,
    String mime = 'image/jpeg',
  }) async {
    checkImage(bytes);
    final ticket =
        await client.post(
              '/api/v1/proof-attempt/capture',
              query: {'kind': kind, 'proofId': proofId},
            )
            as Map;
    await client.post(
      '/api/v1/proof-attempt/capture/${ticket['captureId']}',
      body: {
        'token': ticket['token'],
        'imageData': 'data:$mime;base64,${base64Encode(bytes)}',
      },
    );
    return ticket['captureId'] as int;
  }

  Future<String> attachment(
    String section,
    Uint8List bytes,
    String mime,
  ) async {
    checkImage(bytes);
    final ticket = await client.post('/api/v1/$section/attachment') as Map;
    final result =
        await client.post(
              '/api/v1/$section/attachment/${ticket['captureId']}',
              body: {
                'token': ticket['token'],
                'imageData': 'data:$mime;base64,${base64Encode(bytes)}',
              },
            )
            as Map;
    return result['reference'] as String;
  }

  void checkImage(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
      throw ApiException(400, 'اختر صورة حجمها أقل من ٢ ميغابايت.');
    }
  }

  static List<Json> maps(dynamic value) => (value as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

const methodNames = {
  'PHOTO': 'صورة مباشرة',
  'QUIZ': 'اختبار قصير',
  'TIMER': 'جلسة تركيز',
  'LOCATION': 'زيارة مكان',
  'STEPS': 'مجموع خطوات اليوم',
};
const excuseNames = {
  'SICK': 'ظرف صحي',
  'TRAVEL': 'سفر',
  'EMERGENCY': 'ظرف طارئ',
  'OTHER': 'ظرف آخر',
};
const kindNames = {
  'PROOF': 'إثبات نشاط',
  'EXCUSE': 'عذر',
  'OBJECTION': 'اعتراض',
  'DONATION': 'إثبات تبرع',
};

DateTime riyadhNow() => DateTime.now().toUtc().add(const Duration(hours: 3));
DateTime? serverInstant(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return DateTime.tryParse(
    RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(text) ? text : '$text+03:00',
  );
}

String friendlyError(Object error) {
  final raw = error is ApiException ? error.message : '$error';
  if (RegExp(r'[\u0600-\u06FF]').hasMatch(raw)) return raw;
  // the location proof (PlaceVisitService)
  final far = RegExp(
    r'You are (\d+) meters from the place, the allowed is (\d+)',
  ).firstMatch(raw);
  if (far != null) {
    return 'أنت بعيد عن المكان اللي اخترته بـ ${arabicDigits(far.group(1))} متر، لازم تكون داخل ${arabicDigits(far.group(2))} متر عشان تسجّل وصولك.';
  }
  if (raw.contains('Set the place of this commitment first')) {
    return 'حدّد مكان هذا التعهّد أول، بعدها تقدر تسجّل وصولك.';
  }
  if (raw.contains('No open visit')) {
    return 'ما سجّلت وصولك لهذا المكان، سجّل وصولك أول.';
  }
  if (raw.contains('already') && raw.contains('visit')) {
    return 'عندك زيارة مفتوحة، سجّل مغادرتك أول.';
  }
  if (raw.contains('No location task left this week')) {
    return 'خلّصت مرات هذا الأسبوع لهذي المهمة.';
  }
  if (raw.contains('no running week')) {
    return 'هذا التعهّد ما عنده أسبوع شغّال الحين.';
  }
  if (raw.contains('Quiz topic is unclear')) {
    return 'حدّد موضوع النشاط بشكل أوضح ثم أعد التجهيز. لم تُحتسب عليك محاولة.';
  }
  if (raw.contains('Quiz generation timed out')) {
    return 'تأخر تجهيز الأسئلة. أعد المحاولة؛ لم تُحتسب عليك محاولة اختبار.';
  }
  if (raw.contains('no quiz attempt') || raw.contains('Quiz generation')) {
    return 'تعذر تجهيز الأسئلة الآن. حاول لاحقًا، لم تُحتسب عليك محاولة.';
  }
  if (raw.contains('Only one retry')) {
    return 'استخدمت المحاولة والإعادة لهذا النشاط.';
  }
  if (raw.contains('already has') || raw.contains('already succeeded')) {
    return 'لهذا النشاط طلب سابق. افتح السجل لمتابعته.';
  }
  if (raw.contains('Wait until')) {
    return 'انتظر انتهاء مراجعة الطلب السابق لنفس النشاط.';
  }
  if (raw.contains('ended') ||
      raw.contains('expired') ||
      raw.contains('closed')) {
    return 'انتهت مهلة هذا النشاط أو الطلب.';
  }
  if (raw.contains('Could not connect to Gmail')) {
    return 'تعذر ربط Gmail. تأكد من البريد وكلمة مرور التطبيقات.';
  }
  if (raw.contains('No bank email')) {
    return 'ما لقينا رسالة تحويل بنكي مناسبة حتى الآن. جرّب لاحقًا.';
  }
  if (raw.contains('No pending penalties')) {
    return 'ما عليك مبلغ ينتظر التبرع حاليًا.';
  }
  if (raw.contains('Unauthorized')) return 'سجّل الدخول مرة ثانية للمتابعة.';
  if (raw.contains('Forbidden') || raw.contains('Not your')) {
    return 'هذا الإجراء غير متاح لهذا الحساب.';
  }
  if (raw.contains('before') || raw.contains('different captures')) {
    return 'التقط صورة البداية والنهاية بشكل مستقل وفي وقت النشاط.';
  }
  // an error we have no Arabic text for: show the reason from the server, so it can be fixed
  if (raw.trim().isNotEmpty) return 'ما اكتمل الطلب: $raw';
  return 'ما اكتمل الطلب. تأكد من البيانات وحاول مرة ثانية.';
}
