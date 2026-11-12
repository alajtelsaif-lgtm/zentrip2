const fs = require("node:fs");
const path = require("node:path");
const {
  AlignmentType,
  BorderStyle,
  Document,
  Footer,
  HeadingLevel,
  PageNumber,
  Packer,
  Paragraph,
  ShadingType,
  TextRun,
} = require("docx");

const root = path.resolve(__dirname, "..");
const outputDir = path.join(root, "generated-artifacts");
const outputPath = path.join(outputDir, "Zentrip-MySQL-to-PostgreSQL-Ar.docx");
const colors = {
  ink: "243447",
  muted: "617181",
  blue: "243D8F",
  pale: "EEF2FA",
  line: "D7DFEA",
};

function runs(text, options = {}) {
  const pieces = text.split(/([A-Za-z][A-Za-z0-9_./:+-]*|\d+(?:\.\d+)?)/g).filter(Boolean);
  return pieces.map((piece) => {
    const isLtr = /^[A-Za-z0-9]/.test(piece);
    return new TextRun({
      text: piece,
      font: "Arial",
      size: options.size || 22,
      bold: options.bold || false,
      color: options.color || colors.ink,
      rightToLeft: !isLtr,
      italics: options.italics || false,
    });
  });
}

function paragraph(text, options = {}) {
  return new Paragraph({
    heading: options.heading,
    bidirectional: true,
    alignment: options.alignment || AlignmentType.RIGHT,
    spacing: {
      before: options.before ?? 0,
      after: options.after ?? 150,
      line: 330,
    },
    keepNext: options.keepNext,
    indent: options.indent,
    shading: options.fill
      ? { type: ShadingType.CLEAR, fill: options.fill }
      : undefined,
    border: options.bottomBorder
      ? {
          bottom: {
            style: BorderStyle.SINGLE,
            size: 5,
            color: colors.line,
            space: 5,
          },
        }
      : undefined,
    children: runs(text, {
      size: options.size,
      bold: options.bold,
      color: options.color,
      italics: options.italics,
    }),
  });
}

function bullet(text) {
  return new Paragraph({
    bidirectional: true,
    alignment: AlignmentType.RIGHT,
    indent: { right: 360, hanging: 180 },
    spacing: { after: 105, line: 315 },
    children: [
      ...runs("• ", { size: 22, bold: true, color: colors.blue }),
      ...runs(text, { size: 21 }),
    ],
  });
}

function sectionTitle(text) {
  return paragraph(text, {
    heading: HeadingLevel.HEADING_1,
    size: 27,
    bold: true,
    color: colors.blue,
    before: 160,
    after: 100,
    keepNext: true,
    bottomBorder: true,
  });
}

function callout(label, text) {
  return [
    paragraph(label, {
      size: 21,
      bold: true,
      color: colors.blue,
      fill: colors.pale,
      before: 80,
      after: 45,
    }),
    paragraph(text, {
      size: 20,
      color: colors.ink,
      fill: colors.pale,
      after: 160,
    }),
  ];
}

async function main() {
  fs.mkdirSync(outputDir, { recursive: true });
  const children = [
    paragraph("الانتقال من MySQL إلى PostgreSQL في مشروع Zentrip", {
      heading: HeadingLevel.TITLE,
      size: 34,
      bold: true,
      color: colors.blue,
      alignment: AlignmentType.CENTER,
      before: 160,
      after: 80,
      keepNext: true,
    }),
    paragraph("مسار التنفيذ، العقبات التقنية، والمزايا المتحققة", {
      size: 22,
      color: colors.muted,
      alignment: AlignmentType.CENTER,
      after: 220,
    }),
    paragraph(
      "يمثل الانتقال من MySQL إلى PostgreSQL في Zentrip تغييرًا في طبقة التخزين والاتصال، وليس مجرد تبديل اسم محرك قاعدة البيانات. فقد تطلبت مواءمة إعدادات خدمة Spring Boot، وتعريف المخطط، وصياغة الاستعلامات، وآلية الاختبار مع PostgreSQL المستضافة عبر Supabase. ويعرض هذا النص ما تسنده سجلات المشروع وكوده الحالي، مع التمييز بين التغييرات المحلية وما ثبت تطبيقه على قاعدة الإنتاج.",
      { size: 22, after: 180 },
    ),

    sectionTitle("1. نطاق الانتقال في المشروع"),
    paragraph(
      "تشير سجلات التطوير إلى أن خدمة Zentrip الخلفية كانت مهيأة في مرحلة سابقة للاتصال بـ MySQL. ثم جرى تحويل إعدادات الاتصال في Java وSpring Boot إلى مشغل PostgreSQL وعنوان اتصال Supabase، مع نقل بيانات الاتصال إلى متغيرات بيئية. كما عُدّل تعريف الجداول والاستعلامات لتتوافق مع PostgreSQL. يتصل تطبيق Flutter بالخدمة الخلفية عبر واجهات REST API؛ ولا يتصل مباشرة بقاعدة البيانات في مسار التطبيق المعتاد.",
      { size: 21 },
    ),
    ...callout(
      "حدود ما يمكن تأكيده",
      "توثّق الملفات انتقال إعدادات الخدمة الخلفية والمخطط والاستعلامات واختبارات PostgreSQL، لكنها لا تثبت تنفيذ تصدير شامل لكل سجلات MySQL القديمة واستيرادها إلى Supabase. لذلك يصف هذا القسم انتقال التطبيق والمخطط، ولا يدّعي اكتمال نقل بيانات إنتاجية تاريخية.",
    ),

    sectionTitle("2. مراحل تنفيذ التغيير"),
    bullet(
      "تحديث اعتماد JDBC: استبدال مشغل MySQL بمشغل PostgreSQL، وضبط عنوان الاتصال وبيانات المستخدم وكلمة المرور عبر الإعدادات البيئية بدل تضمينها في الشيفرة."
    ),
    bullet(
      "مواءمة تعريف المخطط: تحويل الأنواع والبنى القديمة إلى صيغ PostgreSQL، مثل استخدام BIGSERIAL للمفاتيح المتزايدة، وTEXT للنصوص الطويلة، وJSONB للبيانات المرنة، وTIMESTAMPTZ للتواريخ ذات المنطقة الزمنية."
    ),
    bullet(
      "ترجمة الاستعلامات: استبدال تعليمات MySQL الخاصة بعمليات JSON والتحديث عند التعارض وحساب الفترات الزمنية بمقابلات PostgreSQL."
    ),
    bullet(
      "مراجعة عمليات الحجز والمخزون: الحفاظ على حدود المعاملات والقيود المرجعية، والتحقق من أن تحديثات التوافر والحجز تتراجع معًا عند الفشل."
    ),
    bullet(
      "إنشاء تحقق متوافق مع المحرك المستهدف: تشغيل المخطط وسلسلة الترحيلات على PostgreSQL حقيقي في قاعدة اختبار مؤقتة ومعزولة، بدل الاكتفاء بمحاكاة الاستعلامات."
    ),

    sectionTitle("3. العقبات والمشكلات التي ظهرت"),
    bullet(
      "اختلاف لهجات SQL: ظهرت استعلامات تستخدم دوال MySQL مثل JSON_EXTRACT وJSON_SET وJSON_OBJECT وDATE_SUB، إضافة إلى أنواع UNSIGNED وصيغ التحديث عند التعارض. لم تكن هذه الصيغ قابلة للتشغيل مباشرة على PostgreSQL، فاستبدلت بمشغلات JSONB، ودوال jsonb_set وjsonb_build_object، وحساب الفترات الزمنية، وصيغة ON CONFLICT."
    ),
    bullet(
      "اختلاف تمثيل البيانات: احتاجت أنواع مثل LONGTEXT وحقول JSON والمفاتيح AUTO_INCREMENT إلى تمثيل مناسب في PostgreSQL. كما تطلبت بعض الحقول مراجعة الدقة الزمنية، والقيود، والقيم الافتراضية حتى لا يتغير معنى البيانات."
    ),
    bullet(
      "اختلاف التعامل مع المفاتيح المولّدة: تختلف نتائج JDBC عند استرجاع المعرّفات التي ينشئها المحرك. لذلك لم يكن كافيًا أن ينجح الإدراج في قاعدة البيانات؛ بل وجب التحقق من استلام التطبيق للمعرّف الصحيح وربطه بسجلات الحجز أو الرحلة."
    ),
    bullet(
      "قصور الاختبارات المحاكية: قبل التحقق بقاعدة PostgreSQL حقيقية، أمكن لبعض المحاكاة قبول استعلامات غير صالحة لهذا المحرك، كما بقيت تأكيدات اختبارية تتوقع SQL خاصًا بـ MySQL. استلزم ذلك تحديث الاختبارات وتشغيل تكامل فعلي مع PostgreSQL."
    ),
    bullet(
      "تفاصيل JSON وتحديث المخزون: كشفت اختبارات PostgreSQL عن فروق في تحديث حقول JSONB وإسناد القيم المتعددة، وهي فروق لم تكشفها الاختبارات المبنية على توقعات نصية فقط."
    ),
    bullet(
      "التعامل مع القيم الفارغة في الاستيراد: أثناء استيراد بيانات المطارات، تعامل PostgreSQL COPY مع بعض الحقول الفارغة غير المحاطة بعلامات اقتباس على أنها NULL. أدى ذلك إلى تعارض مع أعمدة غير قابلة للقيمة الفارغة، فاستلزم تطبيع الحقول الاختيارية والتحقق من القيم قبل الإدراج."
    ),
    bullet(
      "الصلاحيات وحالة الترحيلات في Supabase: تطلب استخدام سياسات RLS وأدوار تشغيل قاعدة البيانات عناية خاصة. وتُظهر مراجعة المشروع أن نجاح الترحيلات على قاعدة محلية مؤقتة لا يثبت أن كل التغييرات أو السياسات طُبقت على قاعدة Supabase الحية؛ لذلك يلزم فحص مخطط الإنتاج وحالته قبل أي تحديث."
    ),

    sectionTitle("4. المزايا التي أتاحها PostgreSQL للمشروع"),
    bullet(
      "التوافق المباشر مع Supabase: أصبحت قاعدة المشروع متوافقة مع محرك PostgreSQL الذي تستضيفه Supabase، مع إبقاء الوصول من خلال الخدمة الخلفية وإدارة بيانات الاتصال خارج تطبيق Flutter."
    ),
    bullet(
      "إدارة البيانات المرنة: يتيح JSONB تخزين خصائص القوائم وتفاصيل بعض الحجوزات بصيغة منظمة قابلة للاستعلام والتحديث. ويستخدم المخطط الحالي JSONB وعمليات مثل jsonb_set، كما يضيف فهارس GIN لبعض حقول البحث والسمات."
    ),
    bullet(
      "سلامة العلاقات: تدعم المفاتيح الخارجية والقيود الفريدة والأنواع الصريحة التحقق من اتساق العلاقات بين المستخدمين والرحلات والحجوزات والقوائم. وتساعد المعاملات على تنفيذ التغييرات المرتبطة بالحجز والمخزون كوحدة واحدة."
    ),
    bullet(
      "تحسين البحث في بعض الحقول: يستخدم المخطط امتداد pg_trgm وفهارس GIN على حقول مثل عنوان القائمة والمدينة والسمات، بما يتيح دعم البحث النصي التقريبي في هذه البيانات."
    ),
    bullet(
      "إمكان تطبيق صلاحيات على مستوى الصف: يوفّر PostgreSQL وSupabase سياسات RLS، ويحتوي المشروع على ترحيلات واختبارات محلية لهذا الجانب. لكن اكتمال هذه الميزة في الإنتاج يتطلب التحقق من تطبيق الترحيلات والأذونات على قاعدة Supabase الحية."
    ),
    bullet(
      "تحقق أقرب إلى بيئة التشغيل: أصبح بالإمكان اختبار المخطط والترحيلات والاستعلامات باستخدام PostgreSQL نفسه، ما يقلل مخاطر اكتشاف أخطاء اللهجة بعد النشر."
    ),

    sectionTitle("5. التحقق والنتيجة"),
    paragraph(
      "يسجل تقرير التحقق الخاص بالمشروع، المؤرخ في 4 نوفمبر 2026، نجاح 230 اختبارًا في مجموعة PostgreSQL والخلفية دون إخفاقات، منها 34 اختبار تكامل لترحيلات PostgreSQL على قاعدة مؤقتة محلية. ويؤكد التقرير أن هذه الاختبارات استخدمت بيانات اصطناعية ولم تكتب إلى قاعدة Supabase الإنتاجية. كما ينبه إلى أن بعض الترحيلات وحالة الصلاحيات في قاعدة Supabase تحتاج إلى مراجعة وتطبيق منفصلين.",
      { size: 21 },
    ),
    ...callout(
      "الاستنتاج العملي",
      "أثبت الانتقال أن كود الخلفية والمخطط يمكن تشغيلهما واختبارهما على PostgreSQL، وأتاح الاستفادة من JSONB والقيود والفهارس وسياسات RLS. لكنه لا يُعد وحده دليلًا على اكتمال مزامنة مخطط الإنتاج أو نقل كل البيانات القديمة؛ فذلك يحتاج إلى خطة نقل بيانات موثقة، ونسخة احتياطية، ومقارنة للمخطط، ثم تحقق بعد التطبيق.",
    ),

    sectionTitle("6. خلاصة"),
    paragraph(
      "أظهر انتقال Zentrip من MySQL إلى PostgreSQL أن تغيير محرك قاعدة البيانات يتطلب معالجة متكاملة تشمل الاتصال والمخطط والاستعلامات وإدارة المفاتيح والاختبارات والصلاحيات. وكانت أبرز الصعوبات ناتجة عن اعتماد الاستعلامات القديمة على خصائص MySQL، وعن الفروق التي لا تكشفها المحاكاة وحدها. وبعد معالجة هذه الفروق، صار مسار الخلفية متوافقًا مع PostgreSQL المستضاف عبر Supabase، وأصبح اختبار الترحيلات والتعامل مع البيانات المنظمة والعلاقات أكثر وضوحًا. وتبقى دقة وصف المرحلة مرتبطة بالتفريق بين نجاح التوافق المحلي وبين اكتمال الترحيل الفعلي لقاعدة الإنتاج وبياناتها.",
      { size: 21 },
    ),

    sectionTitle("مصادر التوثيق داخل المشروع"),
    bullet(
      "سجل التحقق من قاعدة البيانات: DATABASE_VERIFICATION.md، ويتضمن نتائج اختبار PostgreSQL وحدود التحقق من قاعدة الإنتاج."
    ),
    bullet(
      "ملف تعريف الخلفية ومخطط قاعدة البيانات: backend/README.md وbackend/src/main/resources/schema.sql."
    ),
    bullet(
      "سجل أعمال تحويل MySQL إلى Supabase/PostgreSQL المحفوظ ضمن ملفات المشروع."
    ),
  ];

  const document = new Document({
    creator: "Zentrip",
    title: "الانتقال من MySQL إلى PostgreSQL في مشروع Zentrip",
    subject: "عرض أكاديمي لمسار الانتقال والعقبات والمزايا",
    description: "نص عربي أكاديمي مبني على توثيق Zentrip وكوده الحالي.",
    styles: {
      default: {
        document: {
          run: { font: "Arial", size: 22, color: colors.ink },
          paragraph: { bidirectional: true, spacing: { after: 100 } },
        },
      },
      paragraphStyles: [
        {
          id: "Title",
          name: "Title",
          basedOn: "Normal",
          run: { font: "Arial", size: 34, bold: true, color: colors.blue },
          paragraph: { bidirectional: true, alignment: AlignmentType.CENTER },
        },
        {
          id: "Heading1",
          name: "Heading 1",
          basedOn: "Normal",
          next: "Normal",
          run: { font: "Arial", size: 27, bold: true, color: colors.blue },
          paragraph: { bidirectional: true, alignment: AlignmentType.RIGHT },
        },
      ],
    },
    sections: [
      {
        properties: {
          page: {
            size: { width: 11906, height: 16838 },
            margin: { top: 1050, right: 1180, bottom: 1050, left: 1180 },
          },
        },
        footers: {
          default: new Footer({
            children: [
              new Paragraph({
                bidirectional: true,
                alignment: AlignmentType.CENTER,
                children: [
                  ...runs("Zentrip | ", { size: 16, color: colors.muted }),
                  new TextRun({ children: [PageNumber.CURRENT], font: "Arial", size: 16 }),
                ],
              }),
            ],
          }),
        },
        children,
      },
    ],
  });

  const buffer = await Packer.toBuffer(document);
  fs.writeFileSync(outputPath, buffer);
  console.log(`Generated ${path.relative(root, outputPath)} (${buffer.length} bytes)`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
