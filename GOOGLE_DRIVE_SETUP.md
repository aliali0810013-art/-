# SINDAR — إعداد Google Drive لإصدار Android النهائي

> هذا الإعداد يتم مرة واحدة لكل شهادة توقيع. ميزة النسخ هي **backup / restore** وليست مزامنة لحظية بين عدة أجهزة. مجلد App Data مخفي ولا يظهر كملف عادي في My Drive.

## 1. إنشاء شهادة توقيع ثابتة (مرة واحدة)

على Windows، افتح PowerShell وفيه Java JDK وشغّل:

```powershell
keytool -genkeypair -v -keystore sindar-release.jks -alias sindar -keyalg RSA -keysize 3072 -validity 10000
```

احتفظ بملف `sindar-release.jks` وكلمات مروره خارج GitHub واحتفظ بنسخة آمنة منه. تغيير الملف سيمنع التحديث العادي ويغيّر SHA-1.

في GitHub repository > Settings > Secrets and variables > Actions أضف الأسرار الأربعة:

| Secret | Value |
| --- | --- |
| `SINDAR_KEYSTORE_BASE64` | ناتج الأمر التالي في PowerShell |
| `SINDAR_KEYSTORE_PASSWORD` | كلمة مرور ملف JKS |
| `SINDAR_KEY_ALIAS` | `sindar` |
| `SINDAR_KEY_PASSWORD` | كلمة مرور المفتاح |

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path ".\sindar-release.jks")))
```

لا تنسخ كلمات المرور أو keystore في محادثة أو ملف داخل المستودع.

ثم في GitHub Actions شغّل Android APK Build على فرع `sindar-phase1`. لن يُسمح ببناء إصدار نهائي إذا لم تضبط الأسرار الأربعة. افتح خطوة `Print APK signing certificate` في مهمتي `Build sindar_app` و`Build sindar_admin` وتأكد من تطابق SHA-1 مع شهادة التوقيع الدائمة.

## 2. إعداد Google Cloud

1. افتح https://console.cloud.google.com/ واختر أو أنشئ مشروعًا.
2. من **APIs & Services > Library** فعّل **Google Drive API**.
3. من **Google Auth Platform** اضبط Branding / Audience. إن كان التطبيق في وضع Testing أضف بريد Google الذي سيجرب النسخ ضمن **Test users**. للنشر الأوسع أكمل متطلبات النشر لدى Google حسب نوع الجمهور والصلاحيات.
4. من **Clients > Create Client** أنشئ **Android** باسم SINDAR Android:
   - **Package name:** `com.sindar.sindar_app`
   - **SHA-1:** نفس القيمة التي طبعتها خطوة GitHub Actions للإصدار النهائي الموقع بالشهادة الثابتة.
5. أنشئ **OAuth Client** آخر من نوع **Web application** في **نفس المشروع**.
6. تم دمج Web Client ID العام بمصدر تطبيق العميل مرة واحدة. لا يُطلب من العملاء إدخاله؛ يتولى كل عميل تسجيل الدخول إلى Gmail الخاص به. لا تضع Web Client Secret داخل التطبيق.

لا يحتاج هذا التكامل إلى `google-services.json`، ولا يحتاج إلى API key أو سيرفر خاص.

## 3. من داخل تطبيق سِندار

1. ثبّت **sindar_app.apk** الموقع بالشهادة التي أضفت SHA-1 الخاص بها، ثم فعّل ترخيص المنشأة.
2. افتح **الإعدادات > النسخ الاحتياطي والمزامنة**.
3. اضغط **ربط** وحدد حساب Google الخاص بالعميل. امنح الموافقة لصلاحية بيانات التطبيق في Drive. **لا يحتاج العميل إلى Web Client ID أو Google Cloud.**
4. اضغط **نسخ احتياطي الآن** ثم تحقق من تاريخ النسخة السحابية وحجمها.
5. اختبر استعادة نسخة على **جهاز اختبار** أولاً، وليس على بيانات الإنتاج.
6. اختر جدولة النسخ: يدوي أو كل 6 ساعات تقريبًا أو يومي أو أسبوعي؛ تنفيذ المهام الخلفية يتأثر باتصال الشبكة وسياسات Android.

## معالجة الأعطال

- **ApiException: 10 / DEVELOPER_ERROR:** راجع Package name، SHA-1 والتوقيع النهائي، وأن عميل Android وWeb موجودان في مشروع Cloud نفسه.
- **OAuth Testing:** تأكد من وجود Gmail في قائمة Test users ومن قبول شاشة الموافقة.
- **تغيّر مشروع Google Cloud:** تحديث Web Client ID المدمج في إصدار جديد من تطبيق العميل وإعادة اختبار Google Sign-In؛ لا تطلب إدخاله من كل عميل.
- **فشل الشبكة:** Google Play services والاتصال الفعلي بخدمات Google ضروريان، وقد تؤثر ظروف الشبكة المحلية.
- **فشل الاستعادة:** يلزم تفعيل هوية الترخيص نفسها التي شفرت بها النسخة.
- **لا أرى الملف في Drive:** النسخة محفوظة في `appDataFolder` المخفي الخاص بالتطبيق وليس داخل `My Drive`.

لا تُفعّل عمليات الاعتماد لعدة مستخدمين على نفس قاعدة النسخ باعتبارها live sync. النسخ الحالية تحفظ أرشيفًا واحدًا يُستبدل في كل عملية رفع ناجحة.
