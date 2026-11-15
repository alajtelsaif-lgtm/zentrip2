import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'زنتريب'**
  String get appName;

  /// No description provided for @welcomeTitle.
  ///
  /// In ar, this message translates to:
  /// **'خطط بذكاء. سافر بخفة.'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'رفيقك الذكي للرحلة المثالية'**
  String get welcomeSubtitle;

  /// No description provided for @navHome.
  ///
  /// In ar, this message translates to:
  /// **'استكشف'**
  String get navHome;

  /// No description provided for @navTrips.
  ///
  /// In ar, this message translates to:
  /// **'رحلاتي'**
  String get navTrips;

  /// No description provided for @navChatbot.
  ///
  /// In ar, this message translates to:
  /// **'زن AI'**
  String get navChatbot;

  /// No description provided for @navNearby.
  ///
  /// In ar, this message translates to:
  /// **'قريب منك'**
  String get navNearby;

  /// No description provided for @navProfile.
  ///
  /// In ar, this message translates to:
  /// **'الملف'**
  String get navProfile;

  /// No description provided for @greeting.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بعودتك 👋'**
  String get greeting;

  /// No description provided for @whereNext.
  ///
  /// In ar, this message translates to:
  /// **'أين وجهتك القادمة؟'**
  String get whereNext;

  /// No description provided for @homeSearchTitle.
  ///
  /// In ar, this message translates to:
  /// **'خطط لرحلتك القادمة'**
  String get homeSearchTitle;

  /// No description provided for @homeDestinationLabel.
  ///
  /// In ar, this message translates to:
  /// **'الوجهة'**
  String get homeDestinationLabel;

  /// No description provided for @homeChooseDestination.
  ///
  /// In ar, this message translates to:
  /// **'اختر وجهة'**
  String get homeChooseDestination;

  /// No description provided for @homeTravelDateLabel.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ السفر'**
  String get homeTravelDateLabel;

  /// No description provided for @homeTravelersLabel.
  ///
  /// In ar, this message translates to:
  /// **'المسافرون'**
  String get homeTravelersLabel;

  /// No description provided for @homeSearchButton.
  ///
  /// In ar, this message translates to:
  /// **'ابحث'**
  String get homeSearchButton;

  /// No description provided for @homeNewIdeas.
  ///
  /// In ar, this message translates to:
  /// **'أفكار جديدة'**
  String get homeNewIdeas;

  /// No description provided for @homeOffers.
  ///
  /// In ar, this message translates to:
  /// **'العروض'**
  String get homeOffers;

  /// No description provided for @homeFeaturedOffer.
  ///
  /// In ar, this message translates to:
  /// **'عرض مميز'**
  String get homeFeaturedOffer;

  /// No description provided for @homeStartingFrom.
  ///
  /// In ar, this message translates to:
  /// **'يبدأ من'**
  String get homeStartingFrom;

  /// No description provided for @homePersonalizedTitle.
  ///
  /// In ar, this message translates to:
  /// **'إدارة التوصيات المخصصة'**
  String get homePersonalizedTitle;

  /// No description provided for @homePersonalizedMessage.
  ///
  /// In ar, this message translates to:
  /// **'خصص الاقتراحات حسب ميزانيتك وإيقاعك واهتماماتك.'**
  String get homePersonalizedMessage;

  /// No description provided for @homePersonalizedAction.
  ///
  /// In ar, this message translates to:
  /// **'تحديث التفضيلات'**
  String get homePersonalizedAction;

  /// No description provided for @homeOffersLoadError.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحميل العروض.'**
  String get homeOffersLoadError;

  /// No description provided for @homeNoOffers.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عروض متاحة الآن.'**
  String get homeNoOffers;

  /// No description provided for @homeNoDestinations.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر الوجهات هنا قريباً.'**
  String get homeNoDestinations;

  /// No description provided for @bookingScheduleConflict.
  ///
  /// In ar, this message translates to:
  /// **'لديك حجز آخر من هذا النوع يتداخل مع هذه الفترة.'**
  String get bookingScheduleConflict;

  /// No description provided for @quickActionFlights.
  ///
  /// In ar, this message translates to:
  /// **'رحلات جوية'**
  String get quickActionFlights;

  /// No description provided for @quickActionHotels.
  ///
  /// In ar, this message translates to:
  /// **'فنادق'**
  String get quickActionHotels;

  /// No description provided for @quickActionCars.
  ///
  /// In ar, this message translates to:
  /// **'تأجير سيارات'**
  String get quickActionCars;

  /// No description provided for @quickActionAttractions.
  ///
  /// In ar, this message translates to:
  /// **'أنشطة'**
  String get quickActionAttractions;

  /// No description provided for @quickActionTransfers.
  ///
  /// In ar, this message translates to:
  /// **'تاكسي'**
  String get quickActionTransfers;

  /// No description provided for @upcomingTrip.
  ///
  /// In ar, this message translates to:
  /// **'الرحلة القادمة'**
  String get upcomingTrip;

  /// No description provided for @noUpcomingTrip.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد رحلة قادمة'**
  String get noUpcomingTrip;

  /// No description provided for @startPlanningWithZen.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ التخطيط مع زن AI'**
  String get startPlanningWithZen;

  /// No description provided for @inspiredDestinations.
  ///
  /// In ar, this message translates to:
  /// **'وجهات مقترحة لك'**
  String get inspiredDestinations;

  /// No description provided for @viewAll.
  ///
  /// In ar, this message translates to:
  /// **'عرض الكل'**
  String get viewAll;

  /// No description provided for @featured.
  ///
  /// In ar, this message translates to:
  /// **'مميز'**
  String get featured;

  /// No description provided for @popular.
  ///
  /// In ar, this message translates to:
  /// **'الأكثر شعبية'**
  String get popular;

  /// No description provided for @perNight.
  ///
  /// In ar, this message translates to:
  /// **'/ليلة'**
  String get perNight;

  /// No description provided for @perPerson.
  ///
  /// In ar, this message translates to:
  /// **'/شخص'**
  String get perPerson;

  /// No description provided for @perDay.
  ///
  /// In ar, this message translates to:
  /// **'/يوم'**
  String get perDay;

  /// No description provided for @book.
  ///
  /// In ar, this message translates to:
  /// **'احجز الآن'**
  String get book;

  /// No description provided for @explore.
  ///
  /// In ar, this message translates to:
  /// **'استكشف'**
  String get explore;

  /// No description provided for @searchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن وجهات...'**
  String get searchHint;

  /// No description provided for @filterBy.
  ///
  /// In ar, this message translates to:
  /// **'فلترة حسب'**
  String get filterBy;

  /// No description provided for @sortBy.
  ///
  /// In ar, this message translates to:
  /// **'ترتيب حسب'**
  String get sortBy;

  /// No description provided for @priceRange.
  ///
  /// In ar, this message translates to:
  /// **'نطاق السعر'**
  String get priceRange;

  /// No description provided for @rating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم'**
  String get rating;

  /// No description provided for @clear.
  ///
  /// In ar, this message translates to:
  /// **'مسح'**
  String get clear;

  /// No description provided for @noResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج'**
  String get noResults;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In ar, this message translates to:
  /// **'جرب بحثاً مختلفاً أو عدّل الفلاتر'**
  String get tryDifferentSearch;

  /// No description provided for @emailLabel.
  ///
  /// In ar, this message translates to:
  /// **'البريد الإلكتروني'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور'**
  String get passwordLabel;

  /// No description provided for @nameLabel.
  ///
  /// In ar, this message translates to:
  /// **'الاسم الكامل'**
  String get nameLabel;

  /// No description provided for @phoneLabel.
  ///
  /// In ar, this message translates to:
  /// **'رقم الهاتف'**
  String get phoneLabel;

  /// No description provided for @phoneCountrySearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن دولة أو كود'**
  String get phoneCountrySearchHint;

  /// No description provided for @confirmPasswordLabel.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد كلمة المرور'**
  String get confirmPasswordLabel;

  /// No description provided for @login.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get login;

  /// No description provided for @signup.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء حساب'**
  String get signup;

  /// No description provided for @loginWelcome.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك في زنتريب'**
  String get loginWelcome;

  /// No description provided for @loginSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'سجّل دخولك لمتابعة رحلاتك الذكية'**
  String get loginSubtitle;

  /// No description provided for @forgotPassword.
  ///
  /// In ar, this message translates to:
  /// **'نسيت كلمة المرور؟'**
  String get forgotPassword;

  /// No description provided for @noAccountYet.
  ///
  /// In ar, this message translates to:
  /// **'ليس لديك حساب؟'**
  String get noAccountYet;

  /// No description provided for @createAccountNow.
  ///
  /// In ar, this message translates to:
  /// **'أنشئ حساباً الآن'**
  String get createAccountNow;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In ar, this message translates to:
  /// **'لديك حساب بالفعل؟'**
  String get alreadyHaveAccount;

  /// No description provided for @createAccountTitle.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء حساب جديد'**
  String get createAccountTitle;

  /// No description provided for @createAccountSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'انطلق في رحلتك الذكية معنا اليوم'**
  String get createAccountSubtitle;

  /// No description provided for @uploadPhoto.
  ///
  /// In ar, this message translates to:
  /// **'إضافة صورة شخصية'**
  String get uploadPhoto;

  /// No description provided for @changePhoto.
  ///
  /// In ar, this message translates to:
  /// **'تغيير الصورة'**
  String get changePhoto;

  /// No description provided for @agreeToTermsPrefix.
  ///
  /// In ar, this message translates to:
  /// **'أوافق على '**
  String get agreeToTermsPrefix;

  /// No description provided for @termsAndConditions.
  ///
  /// In ar, this message translates to:
  /// **'الشروط والأحكام'**
  String get termsAndConditions;

  /// No description provided for @andWord.
  ///
  /// In ar, this message translates to:
  /// **' و'**
  String get andWord;

  /// No description provided for @privacyPolicy.
  ///
  /// In ar, this message translates to:
  /// **'سياسة الخصوصية'**
  String get privacyPolicy;

  /// No description provided for @mustAcceptTerms.
  ///
  /// In ar, this message translates to:
  /// **'يجب قبول الشروط والأحكام للمتابعة'**
  String get mustAcceptTerms;

  /// No description provided for @demoLoginHint.
  ///
  /// In ar, this message translates to:
  /// **'وضع تجريبي: أي إيميل وباسورد هيشتغلوا'**
  String get demoLoginHint;

  /// No description provided for @mockVerifyCodeHint.
  ///
  /// In ar, this message translates to:
  /// **'وضع تجريبي: استخدم الكود 123456'**
  String get mockVerifyCodeHint;

  /// No description provided for @forgotPasswordTitle.
  ///
  /// In ar, this message translates to:
  /// **'نسيت كلمة المرور؟'**
  String get forgotPasswordTitle;

  /// No description provided for @forgotPasswordSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدخل بريدك الإلكتروني وسنرسل لك رمز التحقق'**
  String get forgotPasswordSubtitle;

  /// No description provided for @sendCode.
  ///
  /// In ar, this message translates to:
  /// **'إرسال رمز التحقق'**
  String get sendCode;

  /// No description provided for @verifyCodeTitle.
  ///
  /// In ar, this message translates to:
  /// **'التحقق من الرمز'**
  String get verifyCodeTitle;

  /// No description provided for @verifyCodeSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدخل الرمز المكوّن من 6 أرقام المرسل إلى بريدك'**
  String get verifyCodeSubtitle;

  /// No description provided for @verifyButton.
  ///
  /// In ar, this message translates to:
  /// **'تحقق'**
  String get verifyButton;

  /// No description provided for @resendCode.
  ///
  /// In ar, this message translates to:
  /// **'إعادة إرسال الرمز'**
  String get resendCode;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء كلمة مرور جديدة'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر كلمة مرور قوية لحماية حسابك'**
  String get resetPasswordSubtitle;

  /// No description provided for @resetPasswordTitleLine1.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تعيين'**
  String get resetPasswordTitleLine1;

  /// No description provided for @resetPasswordTitleLine2.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور'**
  String get resetPasswordTitleLine2;

  /// No description provided for @resetCodeInputHint.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رمز إعادة التعيين المكوّن من 6 أرقام'**
  String get resetCodeInputHint;

  /// No description provided for @demoPasswordResetNotice.
  ///
  /// In ar, this message translates to:
  /// **'للعرض التجريبي فقط: استخدم الرمز 123456. لن تتغير كلمة مرور أي حساب حقيقي.'**
  String get demoPasswordResetNotice;

  /// No description provided for @resetCodeInvalid.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رمز إعادة تعيين صحيحًا مكوّنًا من 6 أرقام'**
  String get resetCodeInvalid;

  /// No description provided for @resetPasswordFieldsRequired.
  ///
  /// In ar, this message translates to:
  /// **'أدخل كلمة المرور الجديدة وأكدها'**
  String get resetPasswordFieldsRequired;

  /// No description provided for @resetPasswordMinLength.
  ///
  /// In ar, this message translates to:
  /// **'استخدم 8 أحرف على الأقل'**
  String get resetPasswordMinLength;

  /// No description provided for @resetPasswordMismatch.
  ///
  /// In ar, this message translates to:
  /// **'كلمتا المرور غير متطابقتين'**
  String get resetPasswordMismatch;

  /// No description provided for @resetPasswordButton.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تعيين كلمة المرور'**
  String get resetPasswordButton;

  /// No description provided for @passwordResetSuccessTitle.
  ///
  /// In ar, this message translates to:
  /// **'اكتملت إعادة تعيين كلمة المرور'**
  String get passwordResetSuccessTitle;

  /// No description provided for @demoPasswordResetComplete.
  ///
  /// In ar, this message translates to:
  /// **'اكتمل العرض التجريبي. لم تتغير كلمة مرور أي حساب حقيقي.'**
  String get demoPasswordResetComplete;

  /// No description provided for @backToLogin.
  ///
  /// In ar, this message translates to:
  /// **'العودة إلى تسجيل الدخول'**
  String get backToLogin;

  /// No description provided for @showPassword.
  ///
  /// In ar, this message translates to:
  /// **'إظهار كلمة المرور'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In ar, this message translates to:
  /// **'إخفاء كلمة المرور'**
  String get hidePassword;

  /// No description provided for @saveNewPassword.
  ///
  /// In ar, this message translates to:
  /// **'حفظ كلمة المرور'**
  String get saveNewPassword;

  /// No description provided for @genericError.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ ما، حاول مجدداً'**
  String get genericError;

  /// No description provided for @bookingLoadError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل تفاصيل الحجز'**
  String get bookingLoadError;

  /// No description provided for @bookingLoadErrorSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'من فضلك ارجع وحاول تاني'**
  String get bookingLoadErrorSubtitle;

  /// No description provided for @goBack.
  ///
  /// In ar, this message translates to:
  /// **'رجوع'**
  String get goBack;

  /// No description provided for @noInternetError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الاتصال بالخادم. تحقق من الإنترنت'**
  String get noInternetError;

  /// No description provided for @noInternetTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد اتصال بالإنترنت'**
  String get noInternetTitle;

  /// No description provided for @noInternetSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'تحقق من إعدادات شبكة جهازك وحاول مجدداً'**
  String get noInternetSubtitle;

  /// No description provided for @retry.
  ///
  /// In ar, this message translates to:
  /// **'حاول مجدداً'**
  String get retry;

  /// No description provided for @accountCreatedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إنشاء حسابك بنجاح 🎉'**
  String get accountCreatedSuccess;

  /// No description provided for @codeSentSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إرسال رمز التحقق إلى بريدك الإلكتروني'**
  String get codeSentSuccess;

  /// No description provided for @codeInvalid.
  ///
  /// In ar, this message translates to:
  /// **'الرمز الذي أدخلته غير صحيح'**
  String get codeInvalid;

  /// No description provided for @passwordResetSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم تغيير كلمة المرور بنجاح'**
  String get passwordResetSuccess;

  /// No description provided for @sessionExpiredMessage.
  ///
  /// In ar, this message translates to:
  /// **'انتهت جلستك، يرجى تسجيل الدخول مجدداً'**
  String get sessionExpiredMessage;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In ar, this message translates to:
  /// **'هل أنت متأكد من تسجيل الخروج؟'**
  String get logoutConfirmMessage;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد'**
  String get confirm;

  /// No description provided for @close.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق'**
  String get close;

  /// No description provided for @done.
  ///
  /// In ar, this message translates to:
  /// **'تم'**
  String get done;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل'**
  String get edit;

  /// No description provided for @share.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة'**
  String get share;

  /// No description provided for @download.
  ///
  /// In ar, this message translates to:
  /// **'تحميل'**
  String get download;

  /// No description provided for @editProfileTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعديل الملف الشخصي'**
  String get editProfileTitle;

  /// No description provided for @saveChanges.
  ///
  /// In ar, this message translates to:
  /// **'حفظ التغييرات'**
  String get saveChanges;

  /// No description provided for @profileUpdatedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم تحديث ملفك الشخصي بنجاح'**
  String get profileUpdatedSuccess;

  /// No description provided for @changePasswordTitle.
  ///
  /// In ar, this message translates to:
  /// **'تغيير كلمة المرور'**
  String get changePasswordTitle;

  /// No description provided for @currentPasswordLabel.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور الحالية'**
  String get currentPasswordLabel;

  /// No description provided for @newPasswordLabel.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور الجديدة'**
  String get newPasswordLabel;

  /// No description provided for @passwordChangedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم تغيير كلمة المرور بنجاح'**
  String get passwordChangedSuccess;

  /// No description provided for @notificationSettingsTitle.
  ///
  /// In ar, this message translates to:
  /// **'إعدادات الإشعارات'**
  String get notificationSettingsTitle;

  /// No description provided for @notificationsTitle.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get notificationsTitle;

  /// No description provided for @notifBookingConfirmedTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم تأكيد الحجز'**
  String get notifBookingConfirmedTitle;

  /// No description provided for @notifBookingConfirmedBody.
  ///
  /// In ar, this message translates to:
  /// **'تم تأكيد حجز الفندق بتاعك في دبي'**
  String get notifBookingConfirmedBody;

  /// No description provided for @notifPriceDropTitle.
  ///
  /// In ar, this message translates to:
  /// **'انخفاض في السعر'**
  String get notifPriceDropTitle;

  /// No description provided for @notifPriceDropBody.
  ///
  /// In ar, this message translates to:
  /// **'أسعار الرحلات لإسطنبول رخصت'**
  String get notifPriceDropBody;

  /// No description provided for @notifTripReminderTitle.
  ///
  /// In ar, this message translates to:
  /// **'رحلة قريبة'**
  String get notifTripReminderTitle;

  /// No description provided for @notifTripReminderBody.
  ///
  /// In ar, this message translates to:
  /// **'رحلتك لبالي هتبدأ بعد 3 أيام'**
  String get notifTripReminderBody;

  /// No description provided for @notifPromoTitle.
  ///
  /// In ar, this message translates to:
  /// **'عرض خاص'**
  String get notifPromoTitle;

  /// No description provided for @notifPromoBody.
  ///
  /// In ar, this message translates to:
  /// **'خصم 20% على تأجير السيارات نهاية الأسبوع ده'**
  String get notifPromoBody;

  /// No description provided for @notifTripCancelledTitle.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء الرحلة'**
  String get notifTripCancelledTitle;

  /// No description provided for @notifEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد إشعارات حتى الآن'**
  String get notifEmptyTitle;

  /// No description provided for @notifEmptyHint.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر هنا تحديثات الحجوزات والرحلات.'**
  String get notifEmptyHint;

  /// No description provided for @notifMarkAllRead.
  ///
  /// In ar, this message translates to:
  /// **'تحديد الكل كمقروء'**
  String get notifMarkAllRead;

  /// No description provided for @notifNewSection.
  ///
  /// In ar, this message translates to:
  /// **'الجديد'**
  String get notifNewSection;

  /// No description provided for @notifEarlierSection.
  ///
  /// In ar, this message translates to:
  /// **'السابق'**
  String get notifEarlierSection;

  /// No description provided for @notifTimeAgoNow.
  ///
  /// In ar, this message translates to:
  /// **'الآن'**
  String get notifTimeAgoNow;

  /// No description provided for @notifTimeAgoMinutes.
  ///
  /// In ar, this message translates to:
  /// **'منذ {minutes} دقيقة'**
  String notifTimeAgoMinutes(Object minutes);

  /// No description provided for @notifUnreadCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد الإشعارات غير المقروءة: {count}'**
  String notifUnreadCount(Object count);

  /// No description provided for @notifTimeAgoHours.
  ///
  /// In ar, this message translates to:
  /// **'من {hours} ساعة'**
  String notifTimeAgoHours(Object hours);

  /// No description provided for @notifTimeAgoDays.
  ///
  /// In ar, this message translates to:
  /// **'من {days} يوم'**
  String notifTimeAgoDays(Object days);

  /// No description provided for @tripReminders.
  ///
  /// In ar, this message translates to:
  /// **'تذكيرات الرحلات'**
  String get tripReminders;

  /// No description provided for @tripRemindersDesc.
  ///
  /// In ar, this message translates to:
  /// **'احصل على إشعار قبل رحلاتك'**
  String get tripRemindersDesc;

  /// No description provided for @promotions.
  ///
  /// In ar, this message translates to:
  /// **'العروض والتخفيضات'**
  String get promotions;

  /// No description provided for @promotionsDesc.
  ///
  /// In ar, this message translates to:
  /// **'صفقات وعروض حصرية'**
  String get promotionsDesc;

  /// No description provided for @zenMessages.
  ///
  /// In ar, this message translates to:
  /// **'رسائل زن AI'**
  String get zenMessages;

  /// No description provided for @zenMessagesDesc.
  ///
  /// In ar, this message translates to:
  /// **'ردود المحادثة والاقتراحات'**
  String get zenMessagesDesc;

  /// No description provided for @generalUpdates.
  ///
  /// In ar, this message translates to:
  /// **'التحديثات العامة'**
  String get generalUpdates;

  /// No description provided for @generalUpdatesDesc.
  ///
  /// In ar, this message translates to:
  /// **'أخبار وتحديثات التطبيق'**
  String get generalUpdatesDesc;

  /// No description provided for @favorites.
  ///
  /// In ar, this message translates to:
  /// **'الأماكن المحفوظة'**
  String get favorites;

  /// No description provided for @savePlace.
  ///
  /// In ar, this message translates to:
  /// **'حفظ المكان'**
  String get savePlace;

  /// No description provided for @savedPlace.
  ///
  /// In ar, this message translates to:
  /// **'تم الحفظ'**
  String get savedPlace;

  /// No description provided for @removeSavedPlace.
  ///
  /// In ar, this message translates to:
  /// **'إزالة المكان المحفوظ'**
  String get removeSavedPlace;

  /// No description provided for @noFavorites.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد أماكن محفوظة'**
  String get noFavorites;

  /// No description provided for @noFavoritesSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'انقر على أيقونة الحفظ في أي وجهة لإضافتها هنا'**
  String get noFavoritesSubtitle;

  /// No description provided for @chatHistory.
  ///
  /// In ar, this message translates to:
  /// **'سجل المحادثات'**
  String get chatHistory;

  /// No description provided for @travelDocuments.
  ///
  /// In ar, this message translates to:
  /// **'وثائق السفر'**
  String get travelDocuments;

  /// No description provided for @appearance.
  ///
  /// In ar, this message translates to:
  /// **'المظهر'**
  String get appearance;

  /// No description provided for @language.
  ///
  /// In ar, this message translates to:
  /// **'اللغة'**
  String get language;

  /// No description provided for @currencyTitle.
  ///
  /// In ar, this message translates to:
  /// **'العملة'**
  String get currencyTitle;

  /// No description provided for @paymentTitle.
  ///
  /// In ar, this message translates to:
  /// **'الدفع'**
  String get paymentTitle;

  /// No description provided for @mockPaymentNotice.
  ///
  /// In ar, this message translates to:
  /// **'وضع تجريبي: حاكي نتيجة الدفع تحت'**
  String get mockPaymentNotice;

  /// No description provided for @simulateSuccessfulPayment.
  ///
  /// In ar, this message translates to:
  /// **'محاكاة دفع ناجح'**
  String get simulateSuccessfulPayment;

  /// No description provided for @simulateFailedPayment.
  ///
  /// In ar, this message translates to:
  /// **'محاكاة دفع فاشل'**
  String get simulateFailedPayment;

  /// No description provided for @paymentFailedMessage.
  ///
  /// In ar, this message translates to:
  /// **'لم تكتمل عملية الدفع'**
  String get paymentFailedMessage;

  /// No description provided for @orContinueWith.
  ///
  /// In ar, this message translates to:
  /// **'أو تابع باستخدام'**
  String get orContinueWith;

  /// No description provided for @continueWithGoogle.
  ///
  /// In ar, this message translates to:
  /// **'جوجل'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In ar, this message translates to:
  /// **'آبل'**
  String get continueWithApple;

  /// No description provided for @writeAReview.
  ///
  /// In ar, this message translates to:
  /// **'اكتب تقييمك'**
  String get writeAReview;

  /// No description provided for @reviewCommentHint.
  ///
  /// In ar, this message translates to:
  /// **'شاركنا تجربتك...'**
  String get reviewCommentHint;

  /// No description provided for @submitReview.
  ///
  /// In ar, this message translates to:
  /// **'إرسال التقييم'**
  String get submitReview;

  /// No description provided for @reviewSubmittedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'شكرًا! تم إرسال تقييمك'**
  String get reviewSubmittedSuccess;

  /// No description provided for @hotelGuestReviews.
  ///
  /// In ar, this message translates to:
  /// **'تقييمات النزلاء'**
  String get hotelGuestReviews;

  /// No description provided for @hotelNoGuestReviews.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تقييمات بعد. كن أول من يقيّم هذا الفندق.'**
  String get hotelNoGuestReviews;

  /// No description provided for @yourTicket.
  ///
  /// In ar, this message translates to:
  /// **'تذكرتك'**
  String get yourTicket;

  /// No description provided for @addToCalendar.
  ///
  /// In ar, this message translates to:
  /// **'إضافة للتقويم'**
  String get addToCalendar;

  /// No description provided for @addedToCalendarSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تمت الإضافة لتقويمك'**
  String get addedToCalendarSuccess;

  /// No description provided for @addedToCalendarFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذّرت الإضافة للتقويم'**
  String get addedToCalendarFailed;

  /// No description provided for @tripShareText.
  ///
  /// In ar, this message translates to:
  /// **'رحلتي: {origin} → {destination} في {date} (رحلة {flightNumber}). محجوزة عن طريق Zentrip!'**
  String tripShareText(
      Object date, Object destination, Object flightNumber, Object origin);

  /// No description provided for @itineraryTitle.
  ///
  /// In ar, this message translates to:
  /// **'مخطط الرحلة'**
  String get itineraryTitle;

  /// No description provided for @itineraryEmpty.
  ///
  /// In ar, this message translates to:
  /// **'مفيش حاجة مجدولة لسه — احجز رحلة عشان تشوفها هنا'**
  String get itineraryEmpty;

  /// No description provided for @visaFree.
  ///
  /// In ar, this message translates to:
  /// **'بدون تأشيرة'**
  String get visaFree;

  /// No description provided for @visaOnArrival.
  ///
  /// In ar, this message translates to:
  /// **'تأشيرة عند الوصول'**
  String get visaOnArrival;

  /// No description provided for @eVisa.
  ///
  /// In ar, this message translates to:
  /// **'تأشيرة إلكترونية مطلوبة'**
  String get eVisa;

  /// No description provided for @visaRequired.
  ///
  /// In ar, this message translates to:
  /// **'تأشيرة مطلوبة'**
  String get visaRequired;

  /// No description provided for @sampleDataLabel.
  ///
  /// In ar, this message translates to:
  /// **'بيانات تجريبية'**
  String get sampleDataLabel;

  /// No description provided for @destinationInfoUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'معلومات الطقس والتأشيرة غير متاحة حاليًا.'**
  String get destinationInfoUnavailable;

  /// No description provided for @destinationInfoPartial.
  ///
  /// In ar, this message translates to:
  /// **'بعض معلومات الوجهة غير متاحة.'**
  String get destinationInfoPartial;

  /// No description provided for @offlineBannerText.
  ///
  /// In ar, this message translates to:
  /// **'انت غير متصل — بنعرضلك آخر بيانات محفوظة'**
  String get offlineBannerText;

  /// No description provided for @security.
  ///
  /// In ar, this message translates to:
  /// **'الأمان وكلمة المرور'**
  String get security;

  /// No description provided for @logout.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get logout;

  /// No description provided for @deleteAccount.
  ///
  /// In ar, this message translates to:
  /// **'حذف الحساب'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'حذف الحساب نهائياً'**
  String get deleteAccountConfirmTitle;

  /// No description provided for @deleteAccountConfirmMessage.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف حسابك وجميع بياناتك بشكل نهائي. لا يمكن التراجع عن هذا الإجراء.'**
  String get deleteAccountConfirmMessage;

  /// No description provided for @darkMode.
  ///
  /// In ar, this message translates to:
  /// **'الوضع الليلي'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In ar, this message translates to:
  /// **'الوضع النهاري'**
  String get lightMode;

  /// No description provided for @systemDefault.
  ///
  /// In ar, this message translates to:
  /// **'إعداد النظام'**
  String get systemDefault;

  /// No description provided for @arabic.
  ///
  /// In ar, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @english.
  ///
  /// In ar, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @onboardingTitle1.
  ///
  /// In ar, this message translates to:
  /// **'خطط لرحلة أحلامك'**
  String get onboardingTitle1;

  /// No description provided for @onboardingDesc1.
  ///
  /// In ar, this message translates to:
  /// **'يساعدك زن AI في تصميم برنامج سفر مثالي يناسب ميزانيتك واهتماماتك وأسلوب سفرك.'**
  String get onboardingDesc1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In ar, this message translates to:
  /// **'اكتشف ما بالقرب منك'**
  String get onboardingTitle2;

  /// No description provided for @onboardingDesc2.
  ///
  /// In ar, this message translates to:
  /// **'استكشف المطاعم والمعالم والجواهر الخفية حولك — أينما كنت في العالم.'**
  String get onboardingDesc2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In ar, this message translates to:
  /// **'احجز كل شيء في مكان واحد'**
  String get onboardingTitle3;

  /// No description provided for @onboardingDesc3.
  ///
  /// In ar, this message translates to:
  /// **'رحلات جوية، فنادق، سيارات، وتوصيل — كل ذلك في تجربة سلسة وموحّدة.'**
  String get onboardingDesc3;

  /// No description provided for @onboardingNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get onboardingNext;

  /// No description provided for @onboardingStart.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الآن'**
  String get onboardingStart;

  /// No description provided for @onboardingSkip.
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get onboardingSkip;

  /// No description provided for @chatbotTitle.
  ///
  /// In ar, this message translates to:
  /// **'مساعد زن الذكي'**
  String get chatbotTitle;

  /// No description provided for @chatbotSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'مدعوم بالذكاء الاصطناعي'**
  String get chatbotSubtitle;

  /// No description provided for @chatbotWelcome.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً! أنا زن، مساعدك الذكي للسفر. أخبرني بوجهتك المفضلة وسأخطط لك رحلة مثالية ✨'**
  String get chatbotWelcome;

  /// No description provided for @chatbotInputHint.
  ///
  /// In ar, this message translates to:
  /// **'اسأل زن أي شيء...'**
  String get chatbotInputHint;

  /// No description provided for @chatbotSend.
  ///
  /// In ar, this message translates to:
  /// **'إرسال'**
  String get chatbotSend;

  /// No description provided for @newChat.
  ///
  /// In ar, this message translates to:
  /// **'محادثة جديدة'**
  String get newChat;

  /// No description provided for @chatHistoryTitle.
  ///
  /// In ar, this message translates to:
  /// **'سجل المحادثات'**
  String get chatHistoryTitle;

  /// No description provided for @noChatHistory.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد محادثات سابقة'**
  String get noChatHistory;

  /// No description provided for @noChatHistorySubtitle.
  ///
  /// In ar, this message translates to:
  /// **'ستظهر محادثاتك مع زن هنا'**
  String get noChatHistorySubtitle;

  /// No description provided for @clearChatTitle.
  ///
  /// In ar, this message translates to:
  /// **'محادثة جديدة'**
  String get clearChatTitle;

  /// No description provided for @clearChatMessage.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حفظ المحادثة الحالية وبدء محادثة جديدة. هل تريد المتابعة؟'**
  String get clearChatMessage;

  /// No description provided for @suggestItinerary.
  ///
  /// In ar, this message translates to:
  /// **'اقترح برنامجاً'**
  String get suggestItinerary;

  /// No description provided for @zenTyping.
  ///
  /// In ar, this message translates to:
  /// **'زن يفكر...'**
  String get zenTyping;

  /// No description provided for @quickPrompt1.
  ///
  /// In ar, this message translates to:
  /// **'خطط رحلة إلى إسطنبول'**
  String get quickPrompt1;

  /// No description provided for @quickPrompt2.
  ///
  /// In ar, this message translates to:
  /// **'أفضل وقت لزيارة بالي؟'**
  String get quickPrompt2;

  /// No description provided for @quickPrompt3.
  ///
  /// In ar, this message translates to:
  /// **'أفكار رحلات اقتصادية لأوروبا'**
  String get quickPrompt3;

  /// No description provided for @travelPreferencesTitle.
  ///
  /// In ar, this message translates to:
  /// **'تفضيلات السفر'**
  String get travelPreferencesTitle;

  /// No description provided for @travelPreferencesSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ تفضيلات السفر'**
  String get travelPreferencesSaved;

  /// No description provided for @travelPreferencesLoadError.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحميل تفضيلات السفر'**
  String get travelPreferencesLoadError;

  /// No description provided for @travelBudgetLabel.
  ///
  /// In ar, this message translates to:
  /// **'أسلوب الميزانية'**
  String get travelBudgetLabel;

  /// No description provided for @travelBudgetLow.
  ///
  /// In ar, this message translates to:
  /// **'اقتصادي'**
  String get travelBudgetLow;

  /// No description provided for @travelBudgetBalanced.
  ///
  /// In ar, this message translates to:
  /// **'متوازن'**
  String get travelBudgetBalanced;

  /// No description provided for @travelBudgetLuxury.
  ///
  /// In ar, this message translates to:
  /// **'فاخر'**
  String get travelBudgetLuxury;

  /// No description provided for @travelPaceLabel.
  ///
  /// In ar, this message translates to:
  /// **'وتيرة الرحلة'**
  String get travelPaceLabel;

  /// No description provided for @travelPaceRelaxed.
  ///
  /// In ar, this message translates to:
  /// **'هادئة'**
  String get travelPaceRelaxed;

  /// No description provided for @travelPaceBalanced.
  ///
  /// In ar, this message translates to:
  /// **'متوازنة'**
  String get travelPaceBalanced;

  /// No description provided for @travelPacePacked.
  ///
  /// In ar, this message translates to:
  /// **'مكثفة'**
  String get travelPacePacked;

  /// No description provided for @travelDurationLabel.
  ///
  /// In ar, this message translates to:
  /// **'مدة الرحلة: {days} أيام'**
  String travelDurationLabel(int days);

  /// No description provided for @travelersLabel.
  ///
  /// In ar, this message translates to:
  /// **'عدد المسافرين'**
  String get travelersLabel;

  /// No description provided for @travelDestinationLabel.
  ///
  /// In ar, this message translates to:
  /// **'الوجهة المفضلة (اختياري)'**
  String get travelDestinationLabel;

  /// No description provided for @travelDestinationHint.
  ///
  /// In ar, this message translates to:
  /// **'مثال: إسطنبول'**
  String get travelDestinationHint;

  /// No description provided for @travelInterestsLabel.
  ///
  /// In ar, this message translates to:
  /// **'ما الذي تستمتع به؟'**
  String get travelInterestsLabel;

  /// No description provided for @travelInterestCulture.
  ///
  /// In ar, this message translates to:
  /// **'الثقافة'**
  String get travelInterestCulture;

  /// No description provided for @travelInterestFood.
  ///
  /// In ar, this message translates to:
  /// **'الطعام'**
  String get travelInterestFood;

  /// No description provided for @travelInterestNature.
  ///
  /// In ar, this message translates to:
  /// **'الطبيعة'**
  String get travelInterestNature;

  /// No description provided for @travelInterestBeaches.
  ///
  /// In ar, this message translates to:
  /// **'الشواطئ'**
  String get travelInterestBeaches;

  /// No description provided for @travelInterestHistory.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get travelInterestHistory;

  /// No description provided for @travelInterestShopping.
  ///
  /// In ar, this message translates to:
  /// **'التسوق'**
  String get travelInterestShopping;

  /// No description provided for @travelInterestAdventure.
  ///
  /// In ar, this message translates to:
  /// **'المغامرة'**
  String get travelInterestAdventure;

  /// No description provided for @nearbyTitle.
  ///
  /// In ar, this message translates to:
  /// **'قريب منك'**
  String get nearbyTitle;

  /// No description provided for @nearbyAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get nearbyAll;

  /// No description provided for @nearbyLandmarks.
  ///
  /// In ar, this message translates to:
  /// **'معالم'**
  String get nearbyLandmarks;

  /// No description provided for @nearbyRestaurants.
  ///
  /// In ar, this message translates to:
  /// **'مطاعم'**
  String get nearbyRestaurants;

  /// No description provided for @nearbyCafes.
  ///
  /// In ar, this message translates to:
  /// **'مقاهي'**
  String get nearbyCafes;

  /// No description provided for @placesMapTitle.
  ///
  /// In ar, this message translates to:
  /// **'خريطة الأماكن'**
  String get placesMapTitle;

  /// No description provided for @nearbyHotels.
  ///
  /// In ar, this message translates to:
  /// **'فنادق'**
  String get nearbyHotels;

  /// No description provided for @nearbyAttractions.
  ///
  /// In ar, this message translates to:
  /// **'أنشطة'**
  String get nearbyAttractions;

  /// No description provided for @nearbySearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن أماكن قريبة...'**
  String get nearbySearchHint;

  /// No description provided for @noNearbyPlaces.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد أماكن'**
  String get noNearbyPlaces;

  /// No description provided for @noNearbyPlacesSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'جرب توسيع نطاق البحث أو غيّر الفلتر'**
  String get noNearbyPlacesSubtitle;

  /// No description provided for @locationPermissionTitle.
  ///
  /// In ar, this message translates to:
  /// **'الوصول إلى الموقع'**
  String get locationPermissionTitle;

  /// No description provided for @locationPermissionMessage.
  ///
  /// In ar, this message translates to:
  /// **'يحتاج زنتريب إلى موقعك لعرض الأماكن القريبة'**
  String get locationPermissionMessage;

  /// No description provided for @openSettings.
  ///
  /// In ar, this message translates to:
  /// **'فتح الإعدادات'**
  String get openSettings;

  /// No description provided for @distanceKm.
  ///
  /// In ar, this message translates to:
  /// **'{distance} كم'**
  String distanceKm(String distance);

  /// No description provided for @myTrips.
  ///
  /// In ar, this message translates to:
  /// **'رحلاتي'**
  String get myTrips;

  /// No description provided for @upcoming.
  ///
  /// In ar, this message translates to:
  /// **'القادمة'**
  String get upcoming;

  /// No description provided for @completed.
  ///
  /// In ar, this message translates to:
  /// **'المكتملة'**
  String get completed;

  /// No description provided for @cancelled.
  ///
  /// In ar, this message translates to:
  /// **'الملغاة'**
  String get cancelled;

  /// No description provided for @noUpcomingTrips.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد رحلات قادمة'**
  String get noUpcomingTrips;

  /// No description provided for @noUpcomingTripsSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'احجز رحلتك الأولى وستظهر هنا'**
  String get noUpcomingTripsSubtitle;

  /// No description provided for @bookingRef.
  ///
  /// In ar, this message translates to:
  /// **'رقم الحجز'**
  String get bookingRef;

  /// No description provided for @flightNumber.
  ///
  /// In ar, this message translates to:
  /// **'رقم الرحلة'**
  String get flightNumber;

  /// No description provided for @seatClass.
  ///
  /// In ar, this message translates to:
  /// **'درجة الجلوس'**
  String get seatClass;

  /// No description provided for @direct.
  ///
  /// In ar, this message translates to:
  /// **'مباشر'**
  String get direct;

  /// No description provided for @withStop.
  ///
  /// In ar, this message translates to:
  /// **'توقف واحد'**
  String get withStop;

  /// No description provided for @tripDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الرحلة'**
  String get tripDetails;

  /// No description provided for @checkIn.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الوصول'**
  String get checkIn;

  /// No description provided for @checkOut.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل المغادرة'**
  String get checkOut;

  /// No description provided for @passengers.
  ///
  /// In ar, this message translates to:
  /// **'المسافرون'**
  String get passengers;

  /// No description provided for @nights.
  ///
  /// In ar, this message translates to:
  /// **'ليالٍ'**
  String get nights;

  /// No description provided for @searchFlights.
  ///
  /// In ar, this message translates to:
  /// **'البحث عن رحلات'**
  String get searchFlights;

  /// No description provided for @selectAirportTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر مطاراً'**
  String get selectAirportTitle;

  /// No description provided for @cityTripoli.
  ///
  /// In ar, this message translates to:
  /// **'طرابلس'**
  String get cityTripoli;

  /// No description provided for @cityMisrata.
  ///
  /// In ar, this message translates to:
  /// **'مصراتة'**
  String get cityMisrata;

  /// No description provided for @cityBenghazi.
  ///
  /// In ar, this message translates to:
  /// **'بنغازي'**
  String get cityBenghazi;

  /// No description provided for @citySebha.
  ///
  /// In ar, this message translates to:
  /// **'سبها'**
  String get citySebha;

  /// No description provided for @selectDifferentAirports.
  ///
  /// In ar, this message translates to:
  /// **'يرجى اختيار مطارين مختلفين.'**
  String get selectDifferentAirports;

  /// No description provided for @from.
  ///
  /// In ar, this message translates to:
  /// **'من'**
  String get from;

  /// No description provided for @to.
  ///
  /// In ar, this message translates to:
  /// **'إلى'**
  String get to;

  /// No description provided for @departureDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ المغادرة'**
  String get departureDate;

  /// No description provided for @returnDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ العودة'**
  String get returnDate;

  /// No description provided for @travelClass.
  ///
  /// In ar, this message translates to:
  /// **'الدرجة'**
  String get travelClass;

  /// No description provided for @economy.
  ///
  /// In ar, this message translates to:
  /// **'اقتصادية'**
  String get economy;

  /// No description provided for @business.
  ///
  /// In ar, this message translates to:
  /// **'رجال الأعمال'**
  String get business;

  /// No description provided for @firstClass.
  ///
  /// In ar, this message translates to:
  /// **'الدرجة الأولى'**
  String get firstClass;

  /// No description provided for @oneWay.
  ///
  /// In ar, this message translates to:
  /// **'اتجاه واحد'**
  String get oneWay;

  /// No description provided for @roundTrip.
  ///
  /// In ar, this message translates to:
  /// **'ذهاب وعودة'**
  String get roundTrip;

  /// No description provided for @searchFlightsBtn.
  ///
  /// In ar, this message translates to:
  /// **'البحث عن رحلات'**
  String get searchFlightsBtn;

  /// No description provided for @flightResults.
  ///
  /// In ar, this message translates to:
  /// **'الرحلات المتاحة'**
  String get flightResults;

  /// No description provided for @flightSelectTitle.
  ///
  /// In ar, this message translates to:
  /// **'اختر الرحلة'**
  String get flightSelectTitle;

  /// No description provided for @flightDateLabel.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الرحلة'**
  String get flightDateLabel;

  /// No description provided for @flightCalendar.
  ///
  /// In ar, this message translates to:
  /// **'التقويم'**
  String get flightCalendar;

  /// No description provided for @flightAirlinesCount.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{لا توجد شركات طيران} =1{شركة طيران واحدة} =2{شركتا طيران} few{{count} شركات طيران} many{{count} شركة طيران} other{{count} شركة طيران}}'**
  String flightAirlinesCount(int count);

  /// No description provided for @flightFare.
  ///
  /// In ar, this message translates to:
  /// **'الأجرة'**
  String get flightFare;

  /// No description provided for @flightSeatsLabel.
  ///
  /// In ar, this message translates to:
  /// **'المقاعد'**
  String get flightSeatsLabel;

  /// No description provided for @flightPerPerson.
  ///
  /// In ar, this message translates to:
  /// **'لكل شخص'**
  String get flightPerPerson;

  /// No description provided for @flightDurationShort.
  ///
  /// In ar, this message translates to:
  /// **'{hours} س {minutes} د'**
  String flightDurationShort(int hours, int minutes);

  /// No description provided for @cheapest.
  ///
  /// In ar, this message translates to:
  /// **'الأرخص'**
  String get cheapest;

  /// No description provided for @fastest.
  ///
  /// In ar, this message translates to:
  /// **'الأسرع'**
  String get fastest;

  /// No description provided for @seatsLeft.
  ///
  /// In ar, this message translates to:
  /// **'{count} مقاعد متبقية'**
  String seatsLeft(int count);

  /// No description provided for @selectFlight.
  ///
  /// In ar, this message translates to:
  /// **'اختر'**
  String get selectFlight;

  /// No description provided for @searchHotels.
  ///
  /// In ar, this message translates to:
  /// **'البحث عن فنادق'**
  String get searchHotels;

  /// No description provided for @destination.
  ///
  /// In ar, this message translates to:
  /// **'الوجهة'**
  String get destination;

  /// No description provided for @hotelResults.
  ///
  /// In ar, this message translates to:
  /// **'الفنادق المتاحة'**
  String get hotelResults;

  /// No description provided for @hotelDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الفندق'**
  String get hotelDetails;

  /// No description provided for @amenities.
  ///
  /// In ar, this message translates to:
  /// **'المرافق'**
  String get amenities;

  /// No description provided for @reviews.
  ///
  /// In ar, this message translates to:
  /// **'التقييمات'**
  String get reviews;

  /// No description provided for @map.
  ///
  /// In ar, this message translates to:
  /// **'الخريطة'**
  String get map;

  /// No description provided for @selectRoom.
  ///
  /// In ar, this message translates to:
  /// **'اختر غرفة'**
  String get selectRoom;

  /// No description provided for @roomTypes.
  ///
  /// In ar, this message translates to:
  /// **'أنواع الغرف'**
  String get roomTypes;

  /// No description provided for @carRental.
  ///
  /// In ar, this message translates to:
  /// **'تأجير السيارات'**
  String get carRental;

  /// No description provided for @pickupLocation.
  ///
  /// In ar, this message translates to:
  /// **'موقع الاستلام'**
  String get pickupLocation;

  /// No description provided for @returnLocation.
  ///
  /// In ar, this message translates to:
  /// **'موقع الإرجاع'**
  String get returnLocation;

  /// No description provided for @pickupDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الاستلام'**
  String get pickupDate;

  /// No description provided for @returnDateCar.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الإرجاع'**
  String get returnDateCar;

  /// No description provided for @allCategories.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get allCategories;

  /// No description provided for @compact.
  ///
  /// In ar, this message translates to:
  /// **'كومباكت'**
  String get compact;

  /// No description provided for @suv.
  ///
  /// In ar, this message translates to:
  /// **'دفع رباعي'**
  String get suv;

  /// No description provided for @luxury.
  ///
  /// In ar, this message translates to:
  /// **'فاخرة'**
  String get luxury;

  /// No description provided for @van.
  ///
  /// In ar, this message translates to:
  /// **'فان'**
  String get van;

  /// No description provided for @automatic.
  ///
  /// In ar, this message translates to:
  /// **'أوتوماتيك'**
  String get automatic;

  /// No description provided for @manual.
  ///
  /// In ar, this message translates to:
  /// **'يدوي'**
  String get manual;

  /// No description provided for @seats.
  ///
  /// In ar, this message translates to:
  /// **'{count} مقاعد'**
  String seats(int count);

  /// No description provided for @perDayCar.
  ///
  /// In ar, this message translates to:
  /// **'/يوم'**
  String get perDayCar;

  /// No description provided for @bookCar.
  ///
  /// In ar, this message translates to:
  /// **'احجز الآن'**
  String get bookCar;

  /// No description provided for @attractions.
  ///
  /// In ar, this message translates to:
  /// **'الأنشطة'**
  String get attractions;

  /// No description provided for @allAttractions.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get allAttractions;

  /// No description provided for @landmark.
  ///
  /// In ar, this message translates to:
  /// **'معالم'**
  String get landmark;

  /// No description provided for @museum.
  ///
  /// In ar, this message translates to:
  /// **'متاحف'**
  String get museum;

  /// No description provided for @park.
  ///
  /// In ar, this message translates to:
  /// **'حدائق'**
  String get park;

  /// No description provided for @beach.
  ///
  /// In ar, this message translates to:
  /// **'شواطئ'**
  String get beach;

  /// No description provided for @restaurant.
  ///
  /// In ar, this message translates to:
  /// **'مطاعم'**
  String get restaurant;

  /// No description provided for @shopping.
  ///
  /// In ar, this message translates to:
  /// **'تسوق'**
  String get shopping;

  /// No description provided for @free.
  ///
  /// In ar, this message translates to:
  /// **'مجاني'**
  String get free;

  /// No description provided for @openNow.
  ///
  /// In ar, this message translates to:
  /// **'مفتوح الآن'**
  String get openNow;

  /// No description provided for @entryFee.
  ///
  /// In ar, this message translates to:
  /// **'رسوم الدخول'**
  String get entryFee;

  /// No description provided for @openingHours.
  ///
  /// In ar, this message translates to:
  /// **'مواعيد العمل'**
  String get openingHours;

  /// No description provided for @getDirections.
  ///
  /// In ar, this message translates to:
  /// **'الاتجاهات'**
  String get getDirections;

  /// No description provided for @transfers.
  ///
  /// In ar, this message translates to:
  /// **'خدمات التوصيل'**
  String get transfers;

  /// No description provided for @transferTitle.
  ///
  /// In ar, this message translates to:
  /// **'توصيل المطار'**
  String get transferTitle;

  /// No description provided for @transferSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'رحلات تاكسي سريعة وموثوقة ومريحة'**
  String get transferSubtitle;

  /// No description provided for @pickupPoint.
  ///
  /// In ar, this message translates to:
  /// **'نقطة الاستلام'**
  String get pickupPoint;

  /// No description provided for @dropoffPoint.
  ///
  /// In ar, this message translates to:
  /// **'نقطة التوصيل'**
  String get dropoffPoint;

  /// No description provided for @transferDate.
  ///
  /// In ar, this message translates to:
  /// **'التاريخ'**
  String get transferDate;

  /// No description provided for @transferTime.
  ///
  /// In ar, this message translates to:
  /// **'الوقت'**
  String get transferTime;

  /// No description provided for @sedan.
  ///
  /// In ar, this message translates to:
  /// **'سيدان'**
  String get sedan;

  /// No description provided for @minivan.
  ///
  /// In ar, this message translates to:
  /// **'ميني فان'**
  String get minivan;

  /// No description provided for @bus.
  ///
  /// In ar, this message translates to:
  /// **'باص'**
  String get bus;

  /// No description provided for @luxuryCar.
  ///
  /// In ar, this message translates to:
  /// **'فاخرة'**
  String get luxuryCar;

  /// No description provided for @bookTransfer.
  ///
  /// In ar, this message translates to:
  /// **'احجز التوصيل'**
  String get bookTransfer;

  /// No description provided for @driverInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومات السائق'**
  String get driverInfo;

  /// No description provided for @driverRating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم'**
  String get driverRating;

  /// No description provided for @attractionsTitle.
  ///
  /// In ar, this message translates to:
  /// **'المعالم السياحية'**
  String get attractionsTitle;

  /// No description provided for @carRentalTitle.
  ///
  /// In ar, this message translates to:
  /// **'تأجير السيارات'**
  String get carRentalTitle;

  /// No description provided for @searchHotelsBtn.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن الفنادق'**
  String get searchHotelsBtn;

  /// No description provided for @emptyPastTitle.
  ///
  /// In ar, this message translates to:
  /// **'استرجع رحلاتك السابقة'**
  String get emptyPastTitle;

  /// No description provided for @emptyPastSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'هنا يمكنك الرجوع إلى جميع رحلاتك السابقة واستلهام رحلاتك القادمة.'**
  String get emptyPastSubtitle;

  /// No description provided for @emptyCancelledTitle.
  ///
  /// In ar, this message translates to:
  /// **'أحياناً تتغير الخطط'**
  String get emptyCancelledTitle;

  /// No description provided for @emptyCancelledSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'هنا يمكنك الرجوع إلى جميع الرحلات التي ألغيتها. ربما في المرة القادمة!'**
  String get emptyCancelledSubtitle;

  /// No description provided for @termsLastUpdated.
  ///
  /// In ar, this message translates to:
  /// **'آخر تحديث: 1 أغسطس 2026'**
  String get termsLastUpdated;

  /// No description provided for @carPickupCityHint.
  ///
  /// In ar, this message translates to:
  /// **'مدينة الاستلام...'**
  String get carPickupCityHint;

  /// No description provided for @carPickupLocationRequired.
  ///
  /// In ar, this message translates to:
  /// **'أدخل مدينة الاستلام أو اسمح بالوصول إلى موقعك لتحديدها.'**
  String get carPickupLocationRequired;

  /// No description provided for @currentCityUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحديد مدينتك. أدخلها يدوياً أو أعد محاولة تحديد الموقع.'**
  String get currentCityUnavailable;

  /// No description provided for @useCurrentLocation.
  ///
  /// In ar, this message translates to:
  /// **'استخدم موقعي الحالي'**
  String get useCurrentLocation;

  /// No description provided for @carPickup.
  ///
  /// In ar, this message translates to:
  /// **'الاستلام'**
  String get carPickup;

  /// No description provided for @carDropoff.
  ///
  /// In ar, this message translates to:
  /// **'التسليم'**
  String get carDropoff;

  /// No description provided for @carType.
  ///
  /// In ar, this message translates to:
  /// **'نوع السيارة'**
  String get carType;

  /// No description provided for @carTypeAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get carTypeAll;

  /// No description provided for @carSearching.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث...'**
  String get carSearching;

  /// No description provided for @carSearchButton.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن سيارة'**
  String get carSearchButton;

  /// No description provided for @carResults.
  ///
  /// In ar, this message translates to:
  /// **'النتائج'**
  String get carResults;

  /// No description provided for @carNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد سيارات من الشركاء تطابق الموقع والتواريخ المحددة.'**
  String get carNoResults;

  /// No description provided for @carSeatsCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} مقاعد'**
  String carSeatsCount(Object count);

  /// No description provided for @carBagsCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} حقيبة'**
  String carBagsCount(Object count);

  /// No description provided for @carDaysCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} أيام'**
  String carDaysCount(Object count);

  /// No description provided for @carTransmissionAutoShort.
  ///
  /// In ar, this message translates to:
  /// **'أوتو'**
  String get carTransmissionAutoShort;

  /// No description provided for @carTransmissionManualShort.
  ///
  /// In ar, this message translates to:
  /// **'يدوي'**
  String get carTransmissionManualShort;

  /// No description provided for @carTransmissionAuto.
  ///
  /// In ar, this message translates to:
  /// **'أوتوماتيك'**
  String get carTransmissionAuto;

  /// No description provided for @carTransmissionManual.
  ///
  /// In ar, this message translates to:
  /// **'يدوي'**
  String get carTransmissionManual;

  /// No description provided for @carHasAc.
  ///
  /// In ar, this message translates to:
  /// **'مكيف هواء'**
  String get carHasAc;

  /// No description provided for @carNoAc.
  ///
  /// In ar, this message translates to:
  /// **'بدون مكيف'**
  String get carNoAc;

  /// No description provided for @carFuelElectric.
  ///
  /// In ar, this message translates to:
  /// **'كهربائي'**
  String get carFuelElectric;

  /// No description provided for @carFuelPetrol.
  ///
  /// In ar, this message translates to:
  /// **'بنزين'**
  String get carFuelPetrol;

  /// No description provided for @carFeatures.
  ///
  /// In ar, this message translates to:
  /// **'الميزات'**
  String get carFeatures;

  /// No description provided for @carPricePerDay.
  ///
  /// In ar, this message translates to:
  /// **'سعر اليوم'**
  String get carPricePerDay;

  /// No description provided for @carNumberOfDays.
  ///
  /// In ar, this message translates to:
  /// **'عدد الأيام'**
  String get carNumberOfDays;

  /// No description provided for @carInsurance.
  ///
  /// In ar, this message translates to:
  /// **'تأمين'**
  String get carInsurance;

  /// No description provided for @carServiceFee.
  ///
  /// In ar, this message translates to:
  /// **'رسوم الخدمة'**
  String get carServiceFee;

  /// No description provided for @carTotal.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get carTotal;

  /// No description provided for @carBooking.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الحجز...'**
  String get carBooking;

  /// No description provided for @carBookNow.
  ///
  /// In ar, this message translates to:
  /// **'احجز السيارة'**
  String get carBookNow;

  /// No description provided for @carBookedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'🚗 تم حجز السيارة بنجاح!'**
  String get carBookedSuccess;

  /// No description provided for @transferBookingTitle.
  ///
  /// In ar, this message translates to:
  /// **'حجز تاكسي'**
  String get transferBookingTitle;

  /// No description provided for @transferFromHint.
  ///
  /// In ar, this message translates to:
  /// **'من (مطار، فندق، عنوان)...'**
  String get transferFromHint;

  /// No description provided for @transferToHint.
  ///
  /// In ar, this message translates to:
  /// **'إلى (مطار، فندق، عنوان)...'**
  String get transferToHint;

  /// No description provided for @transferPassengers.
  ///
  /// In ar, this message translates to:
  /// **'ركاب'**
  String get transferPassengers;

  /// No description provided for @transferSearching.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث...'**
  String get transferSearching;

  /// No description provided for @transferSearchButton.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن تاكسي'**
  String get transferSearchButton;

  /// No description provided for @transferBookedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'🚕 تم حجز التاكسي بنجاح!'**
  String get transferBookedSuccess;

  /// No description provided for @transferUpToPassengers.
  ///
  /// In ar, this message translates to:
  /// **'حتى {count} ركاب'**
  String transferUpToPassengers(Object count);

  /// No description provided for @transferMinutes.
  ///
  /// In ar, this message translates to:
  /// **'{count} دقيقة'**
  String transferMinutes(Object count);

  /// No description provided for @transferPassengersCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} ركاب'**
  String transferPassengersCount(Object count);

  /// No description provided for @transferRouteTitle.
  ///
  /// In ar, this message translates to:
  /// **'من أين سيقلك التاكسي؟'**
  String get transferRouteTitle;

  /// No description provided for @transferPickupLabel.
  ///
  /// In ar, this message translates to:
  /// **'نقطة الانطلاق'**
  String get transferPickupLabel;

  /// No description provided for @transferDropoffLabel.
  ///
  /// In ar, this message translates to:
  /// **'الوجهة'**
  String get transferDropoffLabel;

  /// No description provided for @swapLocations.
  ///
  /// In ar, this message translates to:
  /// **'تبديل الانطلاق والوجهة'**
  String get swapLocations;

  /// No description provided for @transferChooseDate.
  ///
  /// In ar, this message translates to:
  /// **'اختر التاريخ'**
  String get transferChooseDate;

  /// No description provided for @transferChooseTime.
  ///
  /// In ar, this message translates to:
  /// **'اختر الوقت'**
  String get transferChooseTime;

  /// No description provided for @transferVehicleOptions.
  ///
  /// In ar, this message translates to:
  /// **'خيارات التاكسي'**
  String get transferVehicleOptions;

  /// No description provided for @transferRidePriceNote.
  ///
  /// In ar, this message translates to:
  /// **'السعر الإجمالي لهذه السيارة'**
  String get transferRidePriceNote;

  /// No description provided for @transferNoSuitableRides.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد خدمات نقل من الشركاء تطابق المواقع وعدد الركاب.'**
  String get transferNoSuitableRides;

  /// No description provided for @transferLocationRequired.
  ///
  /// In ar, this message translates to:
  /// **'أدخل موقع الانطلاق والوجهة.'**
  String get transferLocationRequired;

  /// No description provided for @transferRidePrivate.
  ///
  /// In ar, this message translates to:
  /// **'سيارة خاصة'**
  String get transferRidePrivate;

  /// No description provided for @taxiSelectPickupOnMap.
  ///
  /// In ar, this message translates to:
  /// **'حدد موقع الانطلاق على الخريطة'**
  String get taxiSelectPickupOnMap;

  /// No description provided for @taxiSelectDropoffOnMap.
  ///
  /// In ar, this message translates to:
  /// **'حدد الوجهة على الخريطة'**
  String get taxiSelectDropoffOnMap;

  /// No description provided for @taxiConfirmMapPoint.
  ///
  /// In ar, this message translates to:
  /// **'استخدم هذا الموقع'**
  String get taxiConfirmMapPoint;

  /// No description provided for @taxiMapAddressLookupFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحديد اسم المكان، تم اختيار الإحداثيات.'**
  String get taxiMapAddressLookupFailed;

  /// No description provided for @taxiLocationServiceDisabled.
  ///
  /// In ar, this message translates to:
  /// **'فعّل خدمات الموقع لعرض الخريطة بالقرب منك.'**
  String get taxiLocationServiceDisabled;

  /// No description provided for @taxiLocationPermissionDenied.
  ///
  /// In ar, this message translates to:
  /// **'اسمح بالوصول إلى الموقع لعرض الخريطة بالقرب منك.'**
  String get taxiLocationPermissionDenied;

  /// No description provided for @taxiLocationPermissionDeniedForever.
  ///
  /// In ar, this message translates to:
  /// **'تم حظر الوصول إلى الموقع. فعّله من إعدادات التطبيق لعرض الخريطة بالقرب منك.'**
  String get taxiLocationPermissionDeniedForever;

  /// No description provided for @taxiLocationUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحديد موقعك الحالي. تحقق من الإشارة وحاول مرة أخرى.'**
  String get taxiLocationUnavailable;

  /// No description provided for @taxiUseCurrentLocation.
  ///
  /// In ar, this message translates to:
  /// **'عرض موقعي الحالي على الخريطة'**
  String get taxiUseCurrentLocation;

  /// No description provided for @attractionSearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن مدينة أو دولة أو معلم...'**
  String get attractionSearchHint;

  /// No description provided for @attractionCountryFilter.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن الأماكن حسب الدولة'**
  String get attractionCountryFilter;

  /// No description provided for @attractionCountryLoadError.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحميل الأماكن. تحقق من الاتصال وحاول مرة أخرى.'**
  String get attractionCountryLoadError;

  /// No description provided for @attractionCityNotFound.
  ///
  /// In ar, this message translates to:
  /// **'لم نعثر على هذا المكان. تحقق من كتابة الاسم وحاول مرة أخرى.'**
  String get attractionCityNotFound;

  /// No description provided for @attractionCategoryAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get attractionCategoryAll;

  /// No description provided for @attractionTicketBookedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'🎫 تم حجز التذكرة بنجاح!'**
  String get attractionTicketBookedSuccess;

  /// No description provided for @attractionAbout.
  ///
  /// In ar, this message translates to:
  /// **'عن المكان'**
  String get attractionAbout;

  /// No description provided for @attractionVisitingHours.
  ///
  /// In ar, this message translates to:
  /// **'ساعات الزيارة'**
  String get attractionVisitingHours;

  /// No description provided for @attractionBestTimeToVisit.
  ///
  /// In ar, this message translates to:
  /// **'أفضل وقت للزيارة'**
  String get attractionBestTimeToVisit;

  /// No description provided for @attractionEntryFee.
  ///
  /// In ar, this message translates to:
  /// **'رسوم الدخول'**
  String get attractionEntryFee;

  /// No description provided for @attractionBooking.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الحجز...'**
  String get attractionBooking;

  /// No description provided for @attractionBookTicket.
  ///
  /// In ar, this message translates to:
  /// **'احجز تذكرة — {price}'**
  String attractionBookTicket(Object price);

  /// No description provided for @attractionOpenOnMap.
  ///
  /// In ar, this message translates to:
  /// **'افتح على الخريطة'**
  String get attractionOpenOnMap;

  /// No description provided for @attractionMapComingSoon.
  ///
  /// In ar, this message translates to:
  /// **'عرض الخريطة قيد التطوير قريباً'**
  String get attractionMapComingSoon;

  /// No description provided for @chatOnlineStatus.
  ///
  /// In ar, this message translates to:
  /// **'متصل بالذكاء الاصطناعي'**
  String get chatOnlineStatus;

  /// No description provided for @chatHistoryTooltip.
  ///
  /// In ar, this message translates to:
  /// **'سجل المحادثات'**
  String get chatHistoryTooltip;

  /// No description provided for @chatDeleteTitle.
  ///
  /// In ar, this message translates to:
  /// **'حذف المحادثة'**
  String get chatDeleteTitle;

  /// No description provided for @chatDeleteMessage.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد حذف هذه المحادثة نهائياً؟'**
  String get chatDeleteMessage;

  /// No description provided for @chatDeletedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف المحادثة'**
  String get chatDeletedSuccess;

  /// No description provided for @chatMessagesCount.
  ///
  /// In ar, this message translates to:
  /// **'رسالة'**
  String get chatMessagesCount;

  /// No description provided for @chatQuickPromptIstanbul.
  ///
  /// In ar, this message translates to:
  /// **'إسطنبول 7 أيام 🕌'**
  String get chatQuickPromptIstanbul;

  /// No description provided for @chatQuickPromptCheapest.
  ///
  /// In ar, this message translates to:
  /// **'أرخص وجهات ✈️'**
  String get chatQuickPromptCheapest;

  /// No description provided for @chatQuickPromptBudget.
  ///
  /// In ar, this message translates to:
  /// **'ميزانية \$1000 💰'**
  String get chatQuickPromptBudget;

  /// No description provided for @chatQuickPromptIstanbulText.
  ///
  /// In ar, this message translates to:
  /// **'أريد برنامج سفر كامل إلى إسطنبول لمدة 7 أيام'**
  String get chatQuickPromptIstanbulText;

  /// No description provided for @chatQuickPromptCheapestText.
  ///
  /// In ar, this message translates to:
  /// **'ما هي أرخص وجهات السفر من مصر هذا الشهر؟'**
  String get chatQuickPromptCheapestText;

  /// No description provided for @chatQuickPromptBudgetText.
  ///
  /// In ar, this message translates to:
  /// **'رحلة مميزة بميزانية 1000 دولار — اقترح لي وجهات'**
  String get chatQuickPromptBudgetText;

  /// No description provided for @chatConnectionError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الاتصال بالمساعد الذكي'**
  String get chatConnectionError;

  /// No description provided for @chatItineraryTitle.
  ///
  /// In ar, this message translates to:
  /// **'برنامج {destination} السياحي'**
  String chatItineraryTitle(Object destination);

  /// No description provided for @chatItineraryBudget.
  ///
  /// In ar, this message translates to:
  /// **'تكلفة تقديرية: {budget}'**
  String chatItineraryBudget(Object budget);

  /// No description provided for @chatItineraryReady.
  ///
  /// In ar, this message translates to:
  /// **'برنامجك جاهز! استفسر عن أي يوم بالتفصيل.'**
  String get chatItineraryReady;

  /// No description provided for @chatItineraryDefaultDestination.
  ///
  /// In ar, this message translates to:
  /// **'وجهتك'**
  String get chatItineraryDefaultDestination;

  /// No description provided for @chatItineraryDayFallback.
  ///
  /// In ar, this message translates to:
  /// **'اليوم {number}'**
  String chatItineraryDayFallback(Object number);

  /// No description provided for @chatItinerarySave.
  ///
  /// In ar, this message translates to:
  /// **'حفظ البرنامج'**
  String get chatItinerarySave;

  /// No description provided for @chatItinerarySavedSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ البرنامج في سجل المحادثة على هذا الجهاز'**
  String get chatItinerarySavedSuccess;

  /// No description provided for @chatItinerarySaveFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر حفظ البرنامج. حاول مرة أخرى.'**
  String get chatItinerarySaveFailed;

  /// No description provided for @chatItineraryFullRequest.
  ///
  /// In ar, this message translates to:
  /// **'أريد برنامج سفر كامل إلى {destination} لمدة 7 أيام'**
  String chatItineraryFullRequest(Object destination);

  /// No description provided for @flightSearching.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث...'**
  String get flightSearching;

  /// No description provided for @flightPassengersLabel.
  ///
  /// In ar, this message translates to:
  /// **'المسافرون'**
  String get flightPassengersLabel;

  /// No description provided for @flightPersonCount.
  ///
  /// In ar, this message translates to:
  /// **'{count} شخص'**
  String flightPersonCount(Object count);

  /// No description provided for @flightSelectDate.
  ///
  /// In ar, this message translates to:
  /// **'اختر تاريخ'**
  String get flightSelectDate;

  /// No description provided for @flightAirportPickerSoon.
  ///
  /// In ar, this message translates to:
  /// **'اختيار المطار سيتوفر قريباً'**
  String get flightAirportPickerSoon;

  /// No description provided for @flightClassLabel.
  ///
  /// In ar, this message translates to:
  /// **'الدرجة'**
  String get flightClassLabel;

  /// No description provided for @flightSelectThis.
  ///
  /// In ar, this message translates to:
  /// **'اختر هذه الرحلة'**
  String get flightSelectThis;

  /// No description provided for @flightNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد رحلات متاحة'**
  String get flightNoResults;

  /// No description provided for @flightProviderWarning.
  ///
  /// In ar, this message translates to:
  /// **'بعض مزودي الرحلات غير متاحين مؤقتًا. نعرض الرحلات المتوفرة.'**
  String get flightProviderWarning;

  /// No description provided for @flightFlexibleButton.
  ///
  /// In ar, this message translates to:
  /// **'تواريخ مرنة'**
  String get flightFlexibleButton;

  /// No description provided for @flightSelectDates.
  ///
  /// In ar, this message translates to:
  /// **'اختر التواريخ'**
  String get flightSelectDates;

  /// No description provided for @flightTripLength.
  ///
  /// In ar, this message translates to:
  /// **'كم مدة رحلتك؟'**
  String get flightTripLength;

  /// No description provided for @flightWeekend.
  ///
  /// In ar, this message translates to:
  /// **'عطلة نهاية الأسبوع'**
  String get flightWeekend;

  /// No description provided for @flightWeekendHint.
  ///
  /// In ar, this message translates to:
  /// **'المغادرة يوم الجمعة، والعودة يوم الأحد للرحلات ذهابًا وإيابًا.'**
  String get flightWeekendHint;

  /// No description provided for @flightWeek.
  ///
  /// In ar, this message translates to:
  /// **'أسبوع'**
  String get flightWeek;

  /// No description provided for @flightMonth.
  ///
  /// In ar, this message translates to:
  /// **'شهر'**
  String get flightMonth;

  /// No description provided for @flightOther.
  ///
  /// In ar, this message translates to:
  /// **'مدة أخرى'**
  String get flightOther;

  /// No description provided for @flightDuration.
  ///
  /// In ar, this message translates to:
  /// **'المدة'**
  String get flightDuration;

  /// No description provided for @flightDays.
  ///
  /// In ar, this message translates to:
  /// **'أيام'**
  String get flightDays;

  /// No description provided for @flightWhenToGo.
  ///
  /// In ar, this message translates to:
  /// **'متى تريد السفر؟'**
  String get flightWhenToGo;

  /// No description provided for @flightSelectUpToMonths.
  ///
  /// In ar, this message translates to:
  /// **'اختر حتى 3 أشهر'**
  String get flightSelectUpToMonths;

  /// No description provided for @flightFlexibleSearchLoading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث عن الرحلات خلال الأشهر المحددة…'**
  String get flightFlexibleSearchLoading;

  /// No description provided for @flightNoResultsForSearch.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد رحلات من {origin} إلى {destination} بتاريخ {date}.'**
  String flightNoResultsForSearch(
      Object origin, Object destination, Object date);

  /// No description provided for @flightSearchError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحميل الرحلات. تحقق من اتصالك وحاول مجدداً.'**
  String get flightSearchError;

  /// No description provided for @flightDirect.
  ///
  /// In ar, this message translates to:
  /// **'مباشرة'**
  String get flightDirect;

  /// No description provided for @flightStops.
  ///
  /// In ar, this message translates to:
  /// **'عدد التوقفات: {count}'**
  String flightStops(int count);

  /// No description provided for @flightExtraBaggage.
  ///
  /// In ar, this message translates to:
  /// **'أمتعة إضافية'**
  String get flightExtraBaggage;

  /// No description provided for @flightExtraBaggageDescription.
  ///
  /// In ar, this message translates to:
  /// **'إضافة حقيبة مسجلة واحدة (حتى 23 كجم)'**
  String get flightExtraBaggageDescription;

  /// No description provided for @flightFlexibleTicket.
  ///
  /// In ar, this message translates to:
  /// **'تذكرة مرنة'**
  String get flightFlexibleTicket;

  /// No description provided for @flightFlexibleTicketDescription.
  ///
  /// In ar, this message translates to:
  /// **'تغيير التاريخ مجاناً حتى 24 ساعة قبل المغادرة'**
  String get flightFlexibleTicketDescription;

  /// No description provided for @flightExtraOptions.
  ///
  /// In ar, this message translates to:
  /// **'خيارات إضافية'**
  String get flightExtraOptions;

  /// No description provided for @flightExitRow.
  ///
  /// In ar, this message translates to:
  /// **'صف مخرج الطوارئ'**
  String get flightExitRow;

  /// No description provided for @flightAircraft.
  ///
  /// In ar, this message translates to:
  /// **'الطائرة'**
  String get flightAircraft;

  /// No description provided for @flightBookingReferenceLabel.
  ///
  /// In ar, this message translates to:
  /// **'مرجع الحجز'**
  String get flightBookingReferenceLabel;

  /// No description provided for @flightSelectedSeats.
  ///
  /// In ar, this message translates to:
  /// **'المقاعد المختارة'**
  String get flightSelectedSeats;

  /// No description provided for @flightBookingConfirmed.
  ///
  /// In ar, this message translates to:
  /// **'تم تأكيد الحجز'**
  String get flightBookingConfirmed;

  /// No description provided for @flightConfirmationError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تأكيد الحجز. أعد المحاولة للتحقق من حالته بأمان.'**
  String get flightConfirmationError;

  /// No description provided for @flightBackToHome.
  ///
  /// In ar, this message translates to:
  /// **'العودة إلى الرئيسية'**
  String get flightBackToHome;

  /// No description provided for @partnerAircraft.
  ///
  /// In ar, this message translates to:
  /// **'طراز الطائرة'**
  String get partnerAircraft;

  /// No description provided for @partnerAircraftCapacity.
  ///
  /// In ar, this message translates to:
  /// **'{seats} مقعداً · {rows} صفاً · ترتيب {layout}'**
  String partnerAircraftCapacity(int seats, int rows, Object layout);

  /// No description provided for @partnerAircraftChangeHasBookings.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن تغيير الطائرة بعد حجز المقاعد.'**
  String get partnerAircraftChangeHasBookings;

  /// No description provided for @flightConfirmBookingTitle.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد الحجز'**
  String get flightConfirmBookingTitle;

  /// No description provided for @flightBookingSuccess.
  ///
  /// In ar, this message translates to:
  /// **'✅ تم حجز الرحلة بنجاح! رقم الحجز: {ref}'**
  String flightBookingSuccess(Object ref);

  /// No description provided for @flightBookingInProgress.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الحجز...'**
  String get flightBookingInProgress;

  /// No description provided for @flightConfirmComplete.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد وإتمام الحجز'**
  String get flightConfirmComplete;

  /// No description provided for @flightPassengerInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومات المسافر'**
  String get flightPassengerInfo;

  /// No description provided for @flightPriceDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل السعر'**
  String get flightPriceDetails;

  /// No description provided for @flightTicketPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر التذكرة'**
  String get flightTicketPrice;

  /// No description provided for @flightTaxesFees.
  ///
  /// In ar, this message translates to:
  /// **'الضرائب والرسوم'**
  String get flightTaxesFees;

  /// No description provided for @flightServiceFee.
  ///
  /// In ar, this message translates to:
  /// **'رسوم الخدمة'**
  String get flightServiceFee;

  /// No description provided for @flightTotal.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get flightTotal;

  /// No description provided for @flightDuffelOffer.
  ///
  /// In ar, this message translates to:
  /// **'عرض Duffel'**
  String get flightDuffelOffer;

  /// No description provided for @flightDuffelBookingUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'الحجز عبر Duffel غير متصل بعد'**
  String get flightDuffelBookingUnavailable;

  /// No description provided for @flightContinueToPayment.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة إلى الدفع'**
  String get flightContinueToPayment;

  /// No description provided for @flightSimulationBadge.
  ///
  /// In ar, this message translates to:
  /// **'محاكاة'**
  String get flightSimulationBadge;

  /// No description provided for @flightSimulatedSeatMapNotice.
  ///
  /// In ar, this message translates to:
  /// **'خريطة المقاعد تجريبية — أرقام المقاعد للعرض التوضيحي فقط.'**
  String get flightSimulatedSeatMapNotice;

  /// No description provided for @flightChooseSeatsAndContinue.
  ///
  /// In ar, this message translates to:
  /// **'اختر المقاعد وتابع'**
  String get flightChooseSeatsAndContinue;

  /// No description provided for @flightProviderUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'البحث المباشر عن الرحلات غير متاح مؤقتًا. حاول مرة أخرى.'**
  String get flightProviderUnavailable;

  /// No description provided for @flightDuffelTotal.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي Duffel لعدد {count} من المسافرين'**
  String flightDuffelTotal(int count);

  /// No description provided for @flightTermsNotice.
  ///
  /// In ar, this message translates to:
  /// **'بالنقر على تأكيد توافق على شروط الخدمة وسياسة الاسترداد'**
  String get flightTermsNotice;

  /// No description provided for @flightDemoUser.
  ///
  /// In ar, this message translates to:
  /// **'مستخدم تجريبي'**
  String get flightDemoUser;

  /// No description provided for @hotelSearching.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث...'**
  String get hotelSearching;

  /// No description provided for @hotelDestinationHint.
  ///
  /// In ar, this message translates to:
  /// **'المدينة أو الوجهة...'**
  String get hotelDestinationHint;

  /// No description provided for @hotelDestinationRequired.
  ///
  /// In ar, this message translates to:
  /// **'أدخل وجهة أو اسمح بالوصول إلى موقعك لتحديد مدينتك.'**
  String get hotelDestinationRequired;

  /// No description provided for @hotelSelectDestination.
  ///
  /// In ar, this message translates to:
  /// **'اختر وجهة من قائمة الاقتراحات.'**
  String get hotelSelectDestination;

  /// No description provided for @hotelLoadingDestinations.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ البحث عن الوجهات...'**
  String get hotelLoadingDestinations;

  /// No description provided for @hotelNoDestinationSuggestions.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم العثور على وجهات لهذا البحث.'**
  String get hotelNoDestinationSuggestions;

  /// No description provided for @hotelDestinationSuggestionsError.
  ///
  /// In ar, this message translates to:
  /// **'اقتراحات الوجهات غير متاحة مؤقتًا.'**
  String get hotelDestinationSuggestionsError;

  /// No description provided for @hotelSearchNearby.
  ///
  /// In ar, this message translates to:
  /// **'البحث بالقرب مني'**
  String get hotelSearchNearby;

  /// No description provided for @openLocationSettings.
  ///
  /// In ar, this message translates to:
  /// **'فتح الإعدادات'**
  String get openLocationSettings;

  /// No description provided for @hotelNearbyTitle.
  ///
  /// In ar, this message translates to:
  /// **'فنادق بالقرب مني'**
  String get hotelNearbyTitle;

  /// No description provided for @hotelNearbyUsingDemoLocation.
  ///
  /// In ar, this message translates to:
  /// **'الموقع غير متاح؛ نعرض فنادق تجريبية بالقرب من طرابلس.'**
  String get hotelNearbyUsingDemoLocation;

  /// No description provided for @hotelSortDistance.
  ///
  /// In ar, this message translates to:
  /// **'📍 المسافة'**
  String get hotelSortDistance;

  /// No description provided for @hotelDistanceKilometers.
  ///
  /// In ar, this message translates to:
  /// **'يبعد {distance} كم'**
  String hotelDistanceKilometers(Object distance);

  /// No description provided for @hotelRoomsLabel.
  ///
  /// In ar, this message translates to:
  /// **'غرف'**
  String get hotelRoomsLabel;

  /// No description provided for @hotelGuestsLabel.
  ///
  /// In ar, this message translates to:
  /// **'ضيوف'**
  String get hotelGuestsLabel;

  /// No description provided for @hotelStaySummary.
  ///
  /// In ar, this message translates to:
  /// **'{nights} ليال · {rooms} غرفة · {guests} ضيوف'**
  String hotelStaySummary(Object guests, Object nights, Object rooms);

  /// No description provided for @hotelNightsSummary.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{0 ليلة} one{{count} ليلة} two{ليلتان} few{{count} ليالٍ} many{{count} ليلة} other{{count} ليلة}}'**
  String hotelNightsSummary(int count);

  /// No description provided for @hotelRoomsSummary.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{0 غرفة} one{{count} غرفة} two{غرفتان} few{{count} غرف} many{{count} غرفة} other{{count} غرفة}}'**
  String hotelRoomsSummary(int count);

  /// No description provided for @hotelGuestsSummary.
  ///
  /// In ar, this message translates to:
  /// **'{count, plural, =0{0 ضيف} one{{count} ضيف} two{ضيفان} few{{count} ضيوف} many{{count} ضيف} other{{count} ضيف}}'**
  String hotelGuestsSummary(int count);

  /// No description provided for @hotelResultsTitle.
  ///
  /// In ar, this message translates to:
  /// **'فنادق {city} · {nights} ليال'**
  String hotelResultsTitle(Object city, Object nights);

  /// No description provided for @hotelNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد فنادق لهذه التواريخ.'**
  String get hotelNoResults;

  /// No description provided for @hotelSearchUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'البحث غير متاح مؤقتًا. حاول مرة أخرى.'**
  String get hotelSearchUnavailable;

  /// No description provided for @hotelFilterAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get hotelFilterAll;

  /// No description provided for @hotelFilterBudget.
  ///
  /// In ar, this message translates to:
  /// **'اقتصادي'**
  String get hotelFilterBudget;

  /// No description provided for @hotelFilterMidRange.
  ///
  /// In ar, this message translates to:
  /// **'متوسط'**
  String get hotelFilterMidRange;

  /// No description provided for @hotelFilterLuxury.
  ///
  /// In ar, this message translates to:
  /// **'فاخر'**
  String get hotelFilterLuxury;

  /// No description provided for @hotelSortRating.
  ///
  /// In ar, this message translates to:
  /// **'⭐ التقييم'**
  String get hotelSortRating;

  /// No description provided for @hotelSortPriceLow.
  ///
  /// In ar, this message translates to:
  /// **'↑ السعر'**
  String get hotelSortPriceLow;

  /// No description provided for @hotelSortPriceHigh.
  ///
  /// In ar, this message translates to:
  /// **'↓ السعر'**
  String get hotelSortPriceHigh;

  /// No description provided for @hotelFeatured.
  ///
  /// In ar, this message translates to:
  /// **'مميز'**
  String get hotelFeatured;

  /// No description provided for @hotelViewBtn.
  ///
  /// In ar, this message translates to:
  /// **'عرض'**
  String get hotelViewBtn;

  /// No description provided for @hotelTotalLabel.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get hotelTotalLabel;

  /// No description provided for @hotelNightsSuffix.
  ///
  /// In ar, this message translates to:
  /// **'({nights} ليال)'**
  String hotelNightsSuffix(Object nights);

  /// No description provided for @hotelBookingSuccess.
  ///
  /// In ar, this message translates to:
  /// **'✅ تم حجز الفندق بنجاح!'**
  String get hotelBookingSuccess;

  /// No description provided for @hotelBookingInProgress.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الحجز...'**
  String get hotelBookingInProgress;

  /// No description provided for @hotelBookNow.
  ///
  /// In ar, this message translates to:
  /// **'احجز الآن'**
  String get hotelBookNow;

  /// No description provided for @hotelDuffelBookingUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'حجز فنادق Duffel غير متاح بعد'**
  String get hotelDuffelBookingUnavailable;

  /// No description provided for @hotelExternalBookingUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'الحجز داخل التطبيق لهذا الفندق غير متاح حاليًا'**
  String get hotelExternalBookingUnavailable;

  /// No description provided for @hotelSoldOut.
  ///
  /// In ar, this message translates to:
  /// **'نفدت الغرف'**
  String get hotelSoldOut;

  /// No description provided for @hotelAbout.
  ///
  /// In ar, this message translates to:
  /// **'عن الفندق'**
  String get hotelAbout;

  /// No description provided for @hotelAmenities.
  ///
  /// In ar, this message translates to:
  /// **'المرافق'**
  String get hotelAmenities;

  /// No description provided for @hotelRoomRatesTitle.
  ///
  /// In ar, this message translates to:
  /// **'أسعار الغرف المتاحة'**
  String get hotelRoomRatesTitle;

  /// No description provided for @hotelRoomRatesLoading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ تحميل الأسعار الحالية…'**
  String get hotelRoomRatesLoading;

  /// No description provided for @hotelRoomRatesUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'أسعار الغرف غير متاحة مؤقتًا.'**
  String get hotelRoomRatesUnavailable;

  /// No description provided for @hotelDefaultDescription.
  ///
  /// In ar, this message translates to:
  /// **'فندق راقٍ يقع في قلب المدينة يوفر أجواءً مريحة ومرافق متكاملة للضيوف.'**
  String get hotelDefaultDescription;

  /// No description provided for @hotelNightPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر الليلة'**
  String get hotelNightPrice;

  /// No description provided for @hotelXoteloEstimateLabel.
  ///
  /// In ar, this message translates to:
  /// **'تقدير Xotelo (غير مؤكد)'**
  String get hotelXoteloEstimateLabel;

  /// No description provided for @hotelNightsCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد الليالي'**
  String get hotelNightsCount;

  /// No description provided for @hotelNightsValue.
  ///
  /// In ar, this message translates to:
  /// **'{nights} ليال'**
  String hotelNightsValue(Object nights);

  /// No description provided for @hotelTaxesFees.
  ///
  /// In ar, this message translates to:
  /// **'الضرائب والرسوم'**
  String get hotelTaxesFees;

  /// No description provided for @hotelSubtotal.
  ///
  /// In ar, this message translates to:
  /// **'المجموع الفرعي'**
  String get hotelSubtotal;

  /// No description provided for @hotelTotal.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي'**
  String get hotelTotal;

  /// No description provided for @partnerHotelLocation.
  ///
  /// In ar, this message translates to:
  /// **'موقع الفندق'**
  String get partnerHotelLocation;

  /// No description provided for @partnerHotelName.
  ///
  /// In ar, this message translates to:
  /// **'اسم الفندق'**
  String get partnerHotelName;

  /// No description provided for @partnerHotelLocationName.
  ///
  /// In ar, this message translates to:
  /// **'اسم موقع الفندق'**
  String get partnerHotelLocationName;

  /// No description provided for @partnerHotelGoogleMapsUrl.
  ///
  /// In ar, this message translates to:
  /// **'رابط خرائط Google أو معرّف المكان'**
  String get partnerHotelGoogleMapsUrl;

  /// No description provided for @partnerHotelGoogleRating.
  ///
  /// In ar, this message translates to:
  /// **'تقييم خرائط Google'**
  String get partnerHotelGoogleRating;

  /// No description provided for @partnerHotelGoogleReviewCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد تقييمات خرائط Google'**
  String get partnerHotelGoogleReviewCount;

  /// No description provided for @partnerHotelGoogleRatingReadOnly.
  ///
  /// In ar, this message translates to:
  /// **'تتم المزامنة من Google Places ولا يمكن تعديلها هنا.'**
  String get partnerHotelGoogleRatingReadOnly;

  /// No description provided for @partnerHotelGoogleRatingPending.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار بيانات Google Places. تحقق من مفتاح الواجهة الخلفية ومطابقة الفندق.'**
  String get partnerHotelGoogleRatingPending;

  /// No description provided for @hotelRatingUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'تقييم Google غير متاح'**
  String get hotelRatingUnavailable;

  /// No description provided for @partnerHotelTaxAndFeesPercentage.
  ///
  /// In ar, this message translates to:
  /// **'نسبة الضرائب والرسوم (%)'**
  String get partnerHotelTaxAndFeesPercentage;

  /// No description provided for @partnerHotelRoomTypes.
  ///
  /// In ar, this message translates to:
  /// **'أنواع الغرف'**
  String get partnerHotelRoomTypes;

  /// No description provided for @partnerHotelAvailableRooms.
  ///
  /// In ar, this message translates to:
  /// **'الغرف المتاحة'**
  String get partnerHotelAvailableRooms;

  /// No description provided for @partnerHotelAvailability.
  ///
  /// In ar, this message translates to:
  /// **'التوافر'**
  String get partnerHotelAvailability;

  /// No description provided for @partnerStructuredJsonHint.
  ///
  /// In ar, this message translates to:
  /// **'حرّر القيمة كمصفوفة JSON من الكائنات.'**
  String get partnerStructuredJsonHint;

  /// No description provided for @partnerHotelLocationHint.
  ///
  /// In ar, this message translates to:
  /// **'ألصق رابط خرائط Google أو أدخل الإحداثيات أو رمز Plus أو معرّف المكان.'**
  String get partnerHotelLocationHint;

  /// No description provided for @partnerHotelLocationInvalid.
  ///
  /// In ar, this message translates to:
  /// **'أدخل إحداثيات صحيحة أو رابط خرائط Google أو رمز Plus أو معرّف مكان صالحًا.'**
  String get partnerHotelLocationInvalid;

  /// No description provided for @partnerHotelRatingReadOnly.
  ///
  /// In ar, this message translates to:
  /// **'تتم المزامنة من Google Places ولا يمكن تعديلها هنا.'**
  String get partnerHotelRatingReadOnly;

  /// No description provided for @partnerDistrict.
  ///
  /// In ar, this message translates to:
  /// **'المنطقة'**
  String get partnerDistrict;

  /// No description provided for @partnerNeighborhood.
  ///
  /// In ar, this message translates to:
  /// **'الحي'**
  String get partnerNeighborhood;

  /// No description provided for @partnerLandmark.
  ///
  /// In ar, this message translates to:
  /// **'معلم قريب'**
  String get partnerLandmark;

  /// No description provided for @commonEnterSixDigitCode.
  ///
  /// In ar, this message translates to:
  /// **'أدخل الرمز المكوّن من 6 أرقام'**
  String get commonEnterSixDigitCode;

  /// No description provided for @commonWelcomeToZentrip.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك في زنتريب! 🎉'**
  String get commonWelcomeToZentrip;

  /// No description provided for @commonReadyToExplore.
  ///
  /// In ar, this message translates to:
  /// **'جاهز لاستكشاف العالم؟'**
  String get commonReadyToExplore;

  /// No description provided for @commonTakePhoto.
  ///
  /// In ar, this message translates to:
  /// **'التقاط صورة'**
  String get commonTakePhoto;

  /// No description provided for @commonChooseFromGallery.
  ///
  /// In ar, this message translates to:
  /// **'اختيار من المعرض'**
  String get commonChooseFromGallery;

  /// No description provided for @commonRemovePhoto.
  ///
  /// In ar, this message translates to:
  /// **'إزالة الصورة'**
  String get commonRemovePhoto;

  /// No description provided for @commonGreetingNamed.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً، {name} 👋'**
  String commonGreetingNamed(Object name);

  /// No description provided for @resendCodeIn.
  ///
  /// In ar, this message translates to:
  /// **'إعادة الإرسال خلال {seconds}ث'**
  String resendCodeIn(Object seconds);

  /// No description provided for @codeInvalidWithAttempts.
  ///
  /// In ar, this message translates to:
  /// **'الكود اللي دخلته غلط. متبقّي {count} محاولات'**
  String codeInvalidWithAttempts(Object count);

  /// No description provided for @tooManyAttempts.
  ///
  /// In ar, this message translates to:
  /// **'تجاوزت عدد المحاولات المسموح بها. من فضلك اطلب كود جديد.'**
  String get tooManyAttempts;

  /// No description provided for @tripsSuggestedFromPackage.
  ///
  /// In ar, this message translates to:
  /// **'مقترح من باقتك'**
  String get tripsSuggestedFromPackage;

  /// No description provided for @tripsRepeatLastSearch.
  ///
  /// In ar, this message translates to:
  /// **'كرر آخر بحث'**
  String get tripsRepeatLastSearch;

  /// No description provided for @tripsSearchFlightsTo.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن رحلات إلى {destination}'**
  String tripsSearchFlightsTo(Object destination);

  /// No description provided for @tripsSearchHotelsIn.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن فنادق في {destination}'**
  String tripsSearchHotelsIn(Object destination);

  /// No description provided for @tripsGoToFlightSearch.
  ///
  /// In ar, this message translates to:
  /// **'انتقال لصفحة البحث'**
  String get tripsGoToFlightSearch;

  /// No description provided for @tripsGoToHotelSearch.
  ///
  /// In ar, this message translates to:
  /// **'انتقال لصفحة الفنادق'**
  String get tripsGoToHotelSearch;

  /// No description provided for @tripsPricePerPerson.
  ///
  /// In ar, this message translates to:
  /// **'السعر للشخص'**
  String get tripsPricePerPerson;

  /// No description provided for @tripsAboutDestination.
  ///
  /// In ar, this message translates to:
  /// **'عن الوجهة'**
  String get tripsAboutDestination;

  /// No description provided for @tripsHighlights.
  ///
  /// In ar, this message translates to:
  /// **'أبرز المعالم'**
  String get tripsHighlights;

  /// No description provided for @tripsBookTrip.
  ///
  /// In ar, this message translates to:
  /// **'احجز الرحلة'**
  String get tripsBookTrip;

  /// No description provided for @packageTicketPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر التذكرة'**
  String get packageTicketPrice;

  /// No description provided for @packageHotelPricePerNight.
  ///
  /// In ar, this message translates to:
  /// **'سعر الفندق (لليلة)'**
  String get packageHotelPricePerNight;

  /// No description provided for @packageTotalPrice.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي للشخص'**
  String get packageTotalPrice;

  /// No description provided for @bookThisOffer.
  ///
  /// In ar, this message translates to:
  /// **'احجز العرض'**
  String get bookThisOffer;

  /// No description provided for @packageBookingSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم حجز عرضك إلى {destination}!'**
  String packageBookingSuccess(Object destination);

  /// No description provided for @tripsFlightInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومات الرحلة'**
  String get tripsFlightInfo;

  /// No description provided for @tripsAirline.
  ///
  /// In ar, this message translates to:
  /// **'الخط الجوي'**
  String get tripsAirline;

  /// No description provided for @tripsTripType.
  ///
  /// In ar, this message translates to:
  /// **'نوع الرحلة'**
  String get tripsTripType;

  /// No description provided for @tripsSchedule.
  ///
  /// In ar, this message translates to:
  /// **'المواعيد'**
  String get tripsSchedule;

  /// No description provided for @tripsBookingDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الحجز'**
  String get tripsBookingDetails;

  /// No description provided for @cancelTrip.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الرحلة'**
  String get cancelTrip;

  /// No description provided for @cancelBooking.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء الحجز'**
  String get cancelBooking;

  /// No description provided for @cancelBookingConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'هل تريد إلغاء هذا الحجز؟'**
  String get cancelBookingConfirmTitle;

  /// No description provided for @cancelBookingConfirmMessage.
  ///
  /// In ar, this message translates to:
  /// **'سيتم تغيير حالة هذا الحجز إلى ملغي.'**
  String get cancelBookingConfirmMessage;

  /// No description provided for @bookingCancelledSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء الحجز.'**
  String get bookingCancelledSuccess;

  /// No description provided for @cancelTripConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'تلغي الرحلة دي؟'**
  String get cancelTripConfirmTitle;

  /// No description provided for @cancelTripConfirmMessage.
  ///
  /// In ar, this message translates to:
  /// **'الإلغاء يخضع لشروط سعر شركة الطيران. ستتم مراجعة أي مبلغ مسترد مستحق وإعادته إلى وسيلة الدفع الأصلية.'**
  String get cancelTripConfirmMessage;

  /// No description provided for @cancelTripSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إلغاء رحلتك'**
  String get cancelTripSuccess;

  /// No description provided for @cancellingTrip.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ الإلغاء...'**
  String get cancellingTrip;

  /// No description provided for @flightRefundRequested.
  ///
  /// In ar, this message translates to:
  /// **'تم طلب الإلغاء. ستتم مراجعة أي مبلغ مسترد مستحق وإعادته إلى وسيلة الدفع الأصلية بعد مراجعة شركة الطيران.'**
  String get flightRefundRequested;

  /// No description provided for @flightRefundStatusTitle.
  ///
  /// In ar, this message translates to:
  /// **'حالة استرداد المبلغ'**
  String get flightRefundStatusTitle;

  /// No description provided for @flightRefundPendingLabel.
  ///
  /// In ar, this message translates to:
  /// **'المراجعة'**
  String get flightRefundPendingLabel;

  /// No description provided for @flightRefundPendingValue.
  ///
  /// In ar, this message translates to:
  /// **'بانتظار مراجعة شركة الطيران'**
  String get flightRefundPendingValue;

  /// No description provided for @flightRefundMethodLabel.
  ///
  /// In ar, this message translates to:
  /// **'طريقة الاسترداد'**
  String get flightRefundMethodLabel;

  /// No description provided for @flightRefundOriginalMethod.
  ///
  /// In ar, this message translates to:
  /// **'وسيلة الدفع الأصلية، إذا كان الحجز مستردًا'**
  String get flightRefundOriginalMethod;

  /// No description provided for @flightScheduleConflict.
  ///
  /// In ar, this message translates to:
  /// **'لديك رحلة أخرى محجوزة في هذا التاريخ بالفعل.'**
  String get flightScheduleConflict;

  /// No description provided for @transferScheduleConflict.
  ///
  /// In ar, this message translates to:
  /// **'لديك سيارة أجرة محجوزة بالفعل في هذا الوقت.'**
  String get transferScheduleConflict;

  /// No description provided for @tripsTotalPrice.
  ///
  /// In ar, this message translates to:
  /// **'السعر الإجمالي'**
  String get tripsTotalPrice;

  /// No description provided for @tripsDownloadTicket.
  ///
  /// In ar, this message translates to:
  /// **'تحميل التذكرة'**
  String get tripsDownloadTicket;

  /// No description provided for @tripsTicketDownloadStarted.
  ///
  /// In ar, this message translates to:
  /// **'بدأ تحميل التذكرة'**
  String get tripsTicketDownloadStarted;

  /// No description provided for @tripsShareTripInfo.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة تفاصيل الرحلة'**
  String get tripsShareTripInfo;

  /// No description provided for @tripsBookFirstTrip.
  ///
  /// In ar, this message translates to:
  /// **'احجز رحلتك الأولى'**
  String get tripsBookFirstTrip;

  /// No description provided for @profileSectionTripsChats.
  ///
  /// In ar, this message translates to:
  /// **'الرحلات والمحادثات'**
  String get profileSectionTripsChats;

  /// No description provided for @profileSectionPreferences.
  ///
  /// In ar, this message translates to:
  /// **'التفضيلات'**
  String get profileSectionPreferences;

  /// No description provided for @profileSectionAccountSecurity.
  ///
  /// In ar, this message translates to:
  /// **'الحساب والأمان'**
  String get profileSectionAccountSecurity;

  /// No description provided for @profileDefaultUserName.
  ///
  /// In ar, this message translates to:
  /// **'مستخدم زنتريب'**
  String get profileDefaultUserName;

  /// No description provided for @profileStatTrips.
  ///
  /// In ar, this message translates to:
  /// **'رحلة'**
  String get profileStatTrips;

  /// No description provided for @profileStatChats.
  ///
  /// In ar, this message translates to:
  /// **'محادثة'**
  String get profileStatChats;

  /// No description provided for @profileStatSaved.
  ///
  /// In ar, this message translates to:
  /// **'محفوظ'**
  String get profileStatSaved;

  /// No description provided for @nearbyLocationServiceDisabled.
  ///
  /// In ar, this message translates to:
  /// **'خدمة الموقع معطّلة'**
  String get nearbyLocationServiceDisabled;

  /// No description provided for @nearbyLocationPermissionDenied.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم منح إذن الموقع'**
  String get nearbyLocationPermissionDenied;

  /// No description provided for @nearbyLocationPermissionDeniedForever.
  ///
  /// In ar, this message translates to:
  /// **'تم رفض إذن الموقع نهائياً'**
  String get nearbyLocationPermissionDeniedForever;

  /// No description provided for @nearbyLocationUnableToDetermine.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تحديد الموقع'**
  String get nearbyLocationUnableToDetermine;

  /// No description provided for @cityCairo.
  ///
  /// In ar, this message translates to:
  /// **'القاهرة'**
  String get cityCairo;

  /// No description provided for @cityDubai.
  ///
  /// In ar, this message translates to:
  /// **'دبي'**
  String get cityDubai;

  /// No description provided for @attractionCatHistorical.
  ///
  /// In ar, this message translates to:
  /// **'تاريخية'**
  String get attractionCatHistorical;

  /// No description provided for @attractionCatNatural.
  ///
  /// In ar, this message translates to:
  /// **'طبيعية'**
  String get attractionCatNatural;

  /// No description provided for @attractionCatCultural.
  ///
  /// In ar, this message translates to:
  /// **'ثقافية'**
  String get attractionCatCultural;

  /// No description provided for @attractionCatArchitecture.
  ///
  /// In ar, this message translates to:
  /// **'معمارية'**
  String get attractionCatArchitecture;

  /// No description provided for @attractionCatCafe.
  ///
  /// In ar, this message translates to:
  /// **'مقاهي'**
  String get attractionCatCafe;

  /// No description provided for @packageCatCity.
  ///
  /// In ar, this message translates to:
  /// **'مدن'**
  String get packageCatCity;

  /// No description provided for @packageCatMountain.
  ///
  /// In ar, this message translates to:
  /// **'جبال'**
  String get packageCatMountain;

  /// No description provided for @packageCatDesert.
  ///
  /// In ar, this message translates to:
  /// **'صحراء'**
  String get packageCatDesert;

  /// No description provided for @homeMonuments.
  ///
  /// In ar, this message translates to:
  /// **'أماكن شهيرة في البلدان'**
  String get homeMonuments;

  /// No description provided for @carTypeElectric.
  ///
  /// In ar, this message translates to:
  /// **'كهربائية'**
  String get carTypeElectric;

  /// No description provided for @carFuelHybrid.
  ///
  /// In ar, this message translates to:
  /// **'هجينة'**
  String get carFuelHybrid;

  /// No description provided for @carFuelDiesel.
  ///
  /// In ar, this message translates to:
  /// **'ديزل'**
  String get carFuelDiesel;

  /// No description provided for @carPerDaySuffix.
  ///
  /// In ar, this message translates to:
  /// **'/ يوم'**
  String get carPerDaySuffix;

  /// No description provided for @tripsTabActive.
  ///
  /// In ar, this message translates to:
  /// **'جارية'**
  String get tripsTabActive;

  /// No description provided for @tripsFilterAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get tripsFilterAll;

  /// No description provided for @tripsFilterFlights.
  ///
  /// In ar, this message translates to:
  /// **'رحلات طيران'**
  String get tripsFilterFlights;

  /// No description provided for @tripsFilterHotels.
  ///
  /// In ar, this message translates to:
  /// **'فنادق'**
  String get tripsFilterHotels;

  /// No description provided for @tripsFilterCars.
  ///
  /// In ar, this message translates to:
  /// **'تأجير سيارات'**
  String get tripsFilterCars;

  /// No description provided for @tripsFilterTours.
  ///
  /// In ar, this message translates to:
  /// **'جولات ومعالم'**
  String get tripsFilterTours;

  /// No description provided for @tripsFilterTransfers.
  ///
  /// In ar, this message translates to:
  /// **'التوصيلات'**
  String get tripsFilterTransfers;

  /// No description provided for @tripsKindTransfer.
  ///
  /// In ar, this message translates to:
  /// **'توصيلة'**
  String get tripsKindTransfer;

  /// No description provided for @transferVehicleLabel.
  ///
  /// In ar, this message translates to:
  /// **'السيارة'**
  String get transferVehicleLabel;

  /// No description provided for @tripSeatsLabel.
  ///
  /// In ar, this message translates to:
  /// **'المقاعد'**
  String get tripSeatsLabel;

  /// No description provided for @tripExtrasLabel.
  ///
  /// In ar, this message translates to:
  /// **'الإضافات'**
  String get tripExtrasLabel;

  /// No description provided for @tripsKindFlight.
  ///
  /// In ar, this message translates to:
  /// **'طيران'**
  String get tripsKindFlight;

  /// No description provided for @tripsKindHotel.
  ///
  /// In ar, this message translates to:
  /// **'فندق'**
  String get tripsKindHotel;

  /// No description provided for @tripsKindCar.
  ///
  /// In ar, this message translates to:
  /// **'سيارة'**
  String get tripsKindCar;

  /// No description provided for @tripsKindTour.
  ///
  /// In ar, this message translates to:
  /// **'جولة'**
  String get tripsKindTour;

  /// No description provided for @tripsRefLabel.
  ///
  /// In ar, this message translates to:
  /// **'المرجع'**
  String get tripsRefLabel;

  /// No description provided for @emptyActiveTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا شيء جارٍ حالياً'**
  String get emptyActiveTitle;

  /// No description provided for @emptyActiveSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'الرحلات والحجوزات الجارية حالياً ستظهر هنا'**
  String get emptyActiveSubtitle;

  /// No description provided for @tripsNoFilterResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حجوزات في هذه الفئة'**
  String get tripsNoFilterResults;

  /// No description provided for @adminDashboard.
  ///
  /// In ar, this message translates to:
  /// **'لوحة تحكم الإدارة'**
  String get adminDashboard;

  /// No description provided for @adminWorkspaceLabel.
  ///
  /// In ar, this message translates to:
  /// **'إدارة زنتريب'**
  String get adminWorkspaceLabel;

  /// No description provided for @adminOverview.
  ///
  /// In ar, this message translates to:
  /// **'نظرة عامة'**
  String get adminOverview;

  /// No description provided for @adminPartners.
  ///
  /// In ar, this message translates to:
  /// **'الشركاء'**
  String get adminPartners;

  /// No description provided for @adminOffers.
  ///
  /// In ar, this message translates to:
  /// **'العروض'**
  String get adminOffers;

  /// No description provided for @adminCatalog.
  ///
  /// In ar, this message translates to:
  /// **'الكتالوج'**
  String get adminCatalog;

  /// No description provided for @adminPlaces.
  ///
  /// In ar, this message translates to:
  /// **'الأماكن'**
  String get adminPlaces;

  /// No description provided for @adminReservations.
  ///
  /// In ar, this message translates to:
  /// **'الحجوزات'**
  String get adminReservations;

  /// No description provided for @adminCustomers.
  ///
  /// In ar, this message translates to:
  /// **'العملاء'**
  String get adminCustomers;

  /// No description provided for @adminPopularity.
  ///
  /// In ar, this message translates to:
  /// **'الشعبية'**
  String get adminPopularity;

  /// No description provided for @adminCountryVisits.
  ///
  /// In ar, this message translates to:
  /// **'الزيارات حسب الدولة'**
  String get adminCountryVisits;

  /// No description provided for @adminPlaceVisits.
  ///
  /// In ar, this message translates to:
  /// **'الزيارات حسب المكان'**
  String get adminPlaceVisits;

  /// No description provided for @adminNoCountryVisits.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد إجماليات زيارات للدول بعد.'**
  String get adminNoCountryVisits;

  /// No description provided for @adminNoPlaceVisits.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد إجماليات زيارات للأماكن بعد.'**
  String get adminNoPlaceVisits;

  /// No description provided for @adminUnspecifiedCountry.
  ///
  /// In ar, this message translates to:
  /// **'دولة غير محددة'**
  String get adminUnspecifiedCountry;

  /// No description provided for @adminWelcome.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك'**
  String get adminWelcome;

  /// No description provided for @adminSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'نظرة سريعة على نشاط السفر.'**
  String get adminSubtitle;

  /// No description provided for @adminBackToApp.
  ///
  /// In ar, this message translates to:
  /// **'العودة إلى تطبيق السفر'**
  String get adminBackToApp;

  /// No description provided for @adminRefresh.
  ///
  /// In ar, this message translates to:
  /// **'تحديث'**
  String get adminRefresh;

  /// No description provided for @adminCustomerCount.
  ///
  /// In ar, this message translates to:
  /// **'العملاء'**
  String get adminCustomerCount;

  /// No description provided for @adminUserCount.
  ///
  /// In ar, this message translates to:
  /// **'المستخدمون'**
  String get adminUserCount;

  /// No description provided for @adminPartnerCount.
  ///
  /// In ar, this message translates to:
  /// **'الشركاء النشطون'**
  String get adminPartnerCount;

  /// No description provided for @adminPartnerListings.
  ///
  /// In ar, this message translates to:
  /// **'القوائم'**
  String get adminPartnerListings;

  /// No description provided for @adminActivePartnerListings.
  ///
  /// In ar, this message translates to:
  /// **'القوائم المتاحة'**
  String get adminActivePartnerListings;

  /// No description provided for @adminPartnerAccounts.
  ///
  /// In ar, this message translates to:
  /// **'حسابات الشركاء'**
  String get adminPartnerAccounts;

  /// No description provided for @adminAddPartner.
  ///
  /// In ar, this message translates to:
  /// **'إضافة شريك'**
  String get adminAddPartner;

  /// No description provided for @adminPartnerName.
  ///
  /// In ar, this message translates to:
  /// **'اسم الشريك أو الشركة'**
  String get adminPartnerName;

  /// No description provided for @adminPartnerEmail.
  ///
  /// In ar, this message translates to:
  /// **'بريد مستخدم مسجل'**
  String get adminPartnerEmail;

  /// No description provided for @adminPartnerService.
  ///
  /// In ar, this message translates to:
  /// **'خدمة الشريك'**
  String get adminPartnerService;

  /// No description provided for @adminPartnerExistingAccountHint.
  ///
  /// In ar, this message translates to:
  /// **'يجب أن يكون لدى الشريك حساب زنتريب مسبقاً. لن يتم إنشاء كلمة مرور أو تغييرها.'**
  String get adminPartnerExistingAccountHint;

  /// No description provided for @adminPartnerStatusActive.
  ///
  /// In ar, this message translates to:
  /// **'نشط'**
  String get adminPartnerStatusActive;

  /// No description provided for @adminPartnerStatusInactive.
  ///
  /// In ar, this message translates to:
  /// **'غير نشط'**
  String get adminPartnerStatusInactive;

  /// No description provided for @adminDisablePartner.
  ///
  /// In ar, this message translates to:
  /// **'تعطيل الشريك'**
  String get adminDisablePartner;

  /// No description provided for @adminRestorePartner.
  ///
  /// In ar, this message translates to:
  /// **'استعادة الشريك'**
  String get adminRestorePartner;

  /// No description provided for @adminPartnerRestored.
  ///
  /// In ar, this message translates to:
  /// **'تمت استعادة صلاحية الشريك.'**
  String get adminPartnerRestored;

  /// No description provided for @adminDisablePartnerConfirmation.
  ///
  /// In ar, this message translates to:
  /// **'سيتم إلغاء صلاحية الشريك مع الاحتفاظ بالشركة والقوائم وسجل الحجوزات.'**
  String get adminDisablePartnerConfirmation;

  /// No description provided for @adminPartnerDisabled.
  ///
  /// In ar, this message translates to:
  /// **'تم تعطيل صلاحية الشريك مع الحفاظ على السجلات.'**
  String get adminPartnerDisabled;

  /// No description provided for @adminPartnerAdded.
  ///
  /// In ar, this message translates to:
  /// **'تمت إضافة الشريك'**
  String get adminPartnerAdded;

  /// No description provided for @adminNoPartners.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم العثور على شركاء.'**
  String get adminNoPartners;

  /// No description provided for @adminLegacyAttractionReviewTitle.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة شركاء المعالم السابقين'**
  String get adminLegacyAttractionReviewTitle;

  /// No description provided for @adminLegacyAttractionReviewDescription.
  ///
  /// In ar, this message translates to:
  /// **'راجع الحساب والقوائم. لكل معلم، اختر مكاناً موجوداً أو أنشئ مكاناً منسقاً أو اتركه دون ربط. لن تُلغى صلاحية الشريك إلا بعد موافقتك.'**
  String get adminLegacyAttractionReviewDescription;

  /// No description provided for @adminLegacyAttractionReviewAction.
  ///
  /// In ar, this message translates to:
  /// **'مراجعة وإلغاء الوصول'**
  String get adminLegacyAttractionReviewAction;

  /// No description provided for @adminLegacyAttractionReviewed.
  ///
  /// In ar, this message translates to:
  /// **'تمت المراجعة وإلغاء الوصول'**
  String get adminLegacyAttractionReviewed;

  /// No description provided for @adminLegacyAttractionApproveRetire.
  ///
  /// In ar, this message translates to:
  /// **'الموافقة وإلغاء الوصول'**
  String get adminLegacyAttractionApproveRetire;

  /// No description provided for @adminLegacyAttractionConfirmTitle.
  ///
  /// In ar, this message translates to:
  /// **'هل توافق على إلغاء وصول الشريك؟'**
  String get adminLegacyAttractionConfirmTitle;

  /// No description provided for @adminLegacyAttractionConfirmBody.
  ///
  /// In ar, this message translates to:
  /// **'ستفقد حسابات الشريك صلاحية الشريك. ستبقى الشركة وسجل القوائم محفوظين، وستضاف الأماكن المحددة إلى الكتالوج المنسق.'**
  String get adminLegacyAttractionConfirmBody;

  /// No description provided for @adminLegacyAttractionReviewSaved.
  ///
  /// In ar, this message translates to:
  /// **'تمت الموافقة على المراجعة وإلغاء وصول الشريك.'**
  String get adminLegacyAttractionReviewSaved;

  /// No description provided for @adminLegacyAttractionCreatePlace.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء مكان منسق'**
  String get adminLegacyAttractionCreatePlace;

  /// No description provided for @adminLegacyAttractionOmit.
  ///
  /// In ar, this message translates to:
  /// **'اتركه دون ربط'**
  String get adminLegacyAttractionOmit;

  /// No description provided for @adminLegacyAttractionUseExisting.
  ///
  /// In ar, this message translates to:
  /// **'استخدم مكاناً موجوداً'**
  String get adminLegacyAttractionUseExisting;

  /// No description provided for @adminLegacyAttractionNonPlaceListing.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن إضافة هذا النوع إلى الأماكن. ستبقى القائمة محفوظة.'**
  String get adminLegacyAttractionNonPlaceListing;

  /// No description provided for @adminLegacyAttractionNoListings.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد قوائم مرتبطة بهذا الحساب.'**
  String get adminLegacyAttractionNoListings;

  /// No description provided for @adminLegacyAttractionReviewPlace.
  ///
  /// In ar, this message translates to:
  /// **'ربط المكان'**
  String get adminLegacyAttractionReviewPlace;

  /// No description provided for @adminLegacyAttractionAccountReviewedBy.
  ///
  /// In ar, this message translates to:
  /// **'تمت المراجعة بواسطة {name}'**
  String adminLegacyAttractionAccountReviewedBy(Object name);

  /// No description provided for @adminServiceAirline.
  ///
  /// In ar, this message translates to:
  /// **'شركة طيران'**
  String get adminServiceAirline;

  /// No description provided for @adminServiceHotel.
  ///
  /// In ar, this message translates to:
  /// **'فندق'**
  String get adminServiceHotel;

  /// No description provided for @adminServiceCar.
  ///
  /// In ar, this message translates to:
  /// **'تأجير سيارات'**
  String get adminServiceCar;

  /// No description provided for @adminServiceTransfer.
  ///
  /// In ar, this message translates to:
  /// **'توصيل'**
  String get adminServiceTransfer;

  /// No description provided for @adminServiceTravel.
  ///
  /// In ar, this message translates to:
  /// **'باقات سياحية'**
  String get adminServiceTravel;

  /// No description provided for @adminServiceAttraction.
  ///
  /// In ar, this message translates to:
  /// **'المعالم (حسابات سابقة)'**
  String get adminServiceAttraction;

  /// No description provided for @adminRequiredField.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل مطلوب.'**
  String get adminRequiredField;

  /// No description provided for @adminInvalidEmail.
  ///
  /// In ar, this message translates to:
  /// **'أدخل بريداً إلكترونياً صحيحاً.'**
  String get adminInvalidEmail;

  /// No description provided for @adminNewCustomers.
  ///
  /// In ar, this message translates to:
  /// **'عملاء جدد (آخر 30 يوماً)'**
  String get adminNewCustomers;

  /// No description provided for @adminReservationCount.
  ///
  /// In ar, this message translates to:
  /// **'الحجوزات'**
  String get adminReservationCount;

  /// No description provided for @adminFlights.
  ///
  /// In ar, this message translates to:
  /// **'الرحلات الجوية'**
  String get adminFlights;

  /// No description provided for @adminServices.
  ///
  /// In ar, this message translates to:
  /// **'حجوزات أخرى'**
  String get adminServices;

  /// No description provided for @adminTransfers.
  ///
  /// In ar, this message translates to:
  /// **'التوصيلات'**
  String get adminTransfers;

  /// No description provided for @adminBookedValue.
  ///
  /// In ar, this message translates to:
  /// **'قيمة الحجوزات'**
  String get adminBookedValue;

  /// No description provided for @adminRecentReservations.
  ///
  /// In ar, this message translates to:
  /// **'أحدث الحجوزات'**
  String get adminRecentReservations;

  /// No description provided for @adminReservationBreakdown.
  ///
  /// In ar, this message translates to:
  /// **'توزيع الحجوزات'**
  String get adminReservationBreakdown;

  /// No description provided for @adminNoReservations.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حجوزات لعرضها حالياً.'**
  String get adminNoReservations;

  /// No description provided for @adminNoCustomers.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد عملاء لعرضهم حالياً.'**
  String get adminNoCustomers;

  /// No description provided for @adminLoadFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحميل بيانات لوحة التحكم.'**
  String get adminLoadFailed;

  /// No description provided for @adminNoAccess.
  ///
  /// In ar, this message translates to:
  /// **'لا يملك هذا الحساب صلاحية وصول المسؤول.'**
  String get adminNoAccess;

  /// No description provided for @adminSearchCustomers.
  ///
  /// In ar, this message translates to:
  /// **'الاسم أو البريد الإلكتروني'**
  String get adminSearchCustomers;

  /// No description provided for @adminCustomerName.
  ///
  /// In ar, this message translates to:
  /// **'العميل'**
  String get adminCustomerName;

  /// No description provided for @adminReservationDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ السفر'**
  String get adminReservationDate;

  /// No description provided for @adminAmount.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get adminAmount;

  /// No description provided for @adminStatus.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get adminStatus;

  /// No description provided for @adminType.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get adminType;

  /// No description provided for @adminBookingCount.
  ///
  /// In ar, this message translates to:
  /// **'الحجوزات'**
  String get adminBookingCount;

  /// No description provided for @adminConfirmed.
  ///
  /// In ar, this message translates to:
  /// **'مؤكد'**
  String get adminConfirmed;

  /// No description provided for @adminUpcoming.
  ///
  /// In ar, this message translates to:
  /// **'قادم'**
  String get adminUpcoming;

  /// No description provided for @adminCatalogSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ العنصر في الكتالوج.'**
  String get adminCatalogSaved;

  /// No description provided for @adminCatalogDeleted.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف العنصر من الكتالوج.'**
  String get adminCatalogDeleted;

  /// No description provided for @adminDeleteCatalogEntry.
  ///
  /// In ar, this message translates to:
  /// **'حذف عنصر الكتالوج؟'**
  String get adminDeleteCatalogEntry;

  /// No description provided for @adminDeleteConfirmation.
  ///
  /// In ar, this message translates to:
  /// **'لا يمكن التراجع عن هذا الإجراء.'**
  String get adminDeleteConfirmation;

  /// No description provided for @adminDelete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get adminDelete;

  /// No description provided for @adminAddOffer.
  ///
  /// In ar, this message translates to:
  /// **'إضافة عرض'**
  String get adminAddOffer;

  /// No description provided for @adminAddMonument.
  ///
  /// In ar, this message translates to:
  /// **'إضافة مكان'**
  String get adminAddMonument;

  /// No description provided for @adminCatalogEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد عناصر في الكتالوج بعد.'**
  String get adminCatalogEmpty;

  /// No description provided for @adminWorkingHours.
  ///
  /// In ar, this message translates to:
  /// **'ساعات العمل'**
  String get adminWorkingHours;

  /// No description provided for @adminBestTime.
  ///
  /// In ar, this message translates to:
  /// **'أفضل وقت للزيارة'**
  String get adminBestTime;

  /// No description provided for @adminNights.
  ///
  /// In ar, this message translates to:
  /// **'ليالي'**
  String get adminNights;

  /// No description provided for @adminCalculatedOfferTotal.
  ///
  /// In ar, this message translates to:
  /// **'الإجمالي المحسوب للشخص'**
  String get adminCalculatedOfferTotal;

  /// No description provided for @adminTitle.
  ///
  /// In ar, this message translates to:
  /// **'العنوان'**
  String get adminTitle;

  /// No description provided for @adminLocation.
  ///
  /// In ar, this message translates to:
  /// **'الموقع'**
  String get adminLocation;

  /// No description provided for @adminCountry.
  ///
  /// In ar, this message translates to:
  /// **'الدولة'**
  String get adminCountry;

  /// No description provided for @adminDestinationCode.
  ///
  /// In ar, this message translates to:
  /// **'رمز الوجهة'**
  String get adminDestinationCode;

  /// No description provided for @adminDescription.
  ///
  /// In ar, this message translates to:
  /// **'الوصف'**
  String get adminDescription;

  /// No description provided for @adminImageUrl.
  ///
  /// In ar, this message translates to:
  /// **'رابط الصورة'**
  String get adminImageUrl;

  /// No description provided for @adminBadge.
  ///
  /// In ar, this message translates to:
  /// **'الشارة'**
  String get adminBadge;

  /// No description provided for @adminStartingPrice.
  ///
  /// In ar, this message translates to:
  /// **'السعر الابتدائي للشخص'**
  String get adminStartingPrice;

  /// No description provided for @adminFlightPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر الرحلة للشخص'**
  String get adminFlightPrice;

  /// No description provided for @adminHotelPriceNight.
  ///
  /// In ar, this message translates to:
  /// **'سعر الفندق للليلة'**
  String get adminHotelPriceNight;

  /// No description provided for @adminLinkedFlight.
  ///
  /// In ar, this message translates to:
  /// **'الرحلة المضمنة في هذا العرض'**
  String get adminLinkedFlight;

  /// No description provided for @adminSelectFlight.
  ///
  /// In ar, this message translates to:
  /// **'اختر رحلة موجودة'**
  String get adminSelectFlight;

  /// No description provided for @adminOfferFlightMissing.
  ///
  /// In ar, this message translates to:
  /// **'لم يتم ربط رحلة'**
  String get adminOfferFlightMissing;

  /// No description provided for @packageAirline.
  ///
  /// In ar, this message translates to:
  /// **'شركة الطيران'**
  String get packageAirline;

  /// No description provided for @packageStayTotal.
  ///
  /// In ar, this message translates to:
  /// **'الإقامة الفندقية'**
  String get packageStayTotal;

  /// No description provided for @adminRating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم (0–5)'**
  String get adminRating;

  /// No description provided for @adminReviewCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد المراجعات'**
  String get adminReviewCount;

  /// No description provided for @adminCategoryTag.
  ///
  /// In ar, this message translates to:
  /// **'تصنيف المعلم'**
  String get adminCategoryTag;

  /// No description provided for @adminEntryFee.
  ///
  /// In ar, this message translates to:
  /// **'رسوم الدخول'**
  String get adminEntryFee;

  /// No description provided for @adminEditOffer.
  ///
  /// In ar, this message translates to:
  /// **'تعديل العرض'**
  String get adminEditOffer;

  /// No description provided for @adminEditMonument.
  ///
  /// In ar, this message translates to:
  /// **'تعديل المكان'**
  String get adminEditMonument;

  /// No description provided for @adminCategory.
  ///
  /// In ar, this message translates to:
  /// **'الفئة'**
  String get adminCategory;

  /// No description provided for @adminFeaturedBadge.
  ///
  /// In ar, this message translates to:
  /// **'عرض مميز'**
  String get adminFeaturedBadge;

  /// No description provided for @adminHighlights.
  ///
  /// In ar, this message translates to:
  /// **'النقاط البارزة'**
  String get adminHighlights;

  /// No description provided for @adminTagsLandmarks.
  ///
  /// In ar, this message translates to:
  /// **'العلامات'**
  String get adminTagsLandmarks;

  /// No description provided for @partnerDashboard.
  ///
  /// In ar, this message translates to:
  /// **'بوابة الشركاء'**
  String get partnerDashboard;

  /// No description provided for @partnerWorkspaceLabel.
  ///
  /// In ar, this message translates to:
  /// **'مساحة الشريك'**
  String get partnerWorkspaceLabel;

  /// No description provided for @partnerOverview.
  ///
  /// In ar, this message translates to:
  /// **'نظرة عامة'**
  String get partnerOverview;

  /// No description provided for @partnerListings.
  ///
  /// In ar, this message translates to:
  /// **'القوائم'**
  String get partnerListings;

  /// No description provided for @partnerReservations.
  ///
  /// In ar, this message translates to:
  /// **'الحجوزات'**
  String get partnerReservations;

  /// No description provided for @partnerCustomers.
  ///
  /// In ar, this message translates to:
  /// **'العملاء'**
  String get partnerCustomers;

  /// No description provided for @partnerWelcome.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك'**
  String get partnerWelcome;

  /// No description provided for @partnerSubtitle.
  ///
  /// In ar, this message translates to:
  /// **'أدر نشاطك السياحي على زنتريب.'**
  String get partnerSubtitle;

  /// No description provided for @partnerListingCount.
  ///
  /// In ar, this message translates to:
  /// **'قوائمك'**
  String get partnerListingCount;

  /// No description provided for @partnerActiveListings.
  ///
  /// In ar, this message translates to:
  /// **'متاح الآن'**
  String get partnerActiveListings;

  /// No description provided for @partnerReservationCount.
  ///
  /// In ar, this message translates to:
  /// **'الحجوزات'**
  String get partnerReservationCount;

  /// No description provided for @partnerCustomerCount.
  ///
  /// In ar, this message translates to:
  /// **'العملاء'**
  String get partnerCustomerCount;

  /// No description provided for @partnerBookedValue.
  ///
  /// In ar, this message translates to:
  /// **'قيمة الحجوزات'**
  String get partnerBookedValue;

  /// No description provided for @partnerRecentReservations.
  ///
  /// In ar, this message translates to:
  /// **'أحدث الحجوزات'**
  String get partnerRecentReservations;

  /// No description provided for @partnerManageListings.
  ///
  /// In ar, this message translates to:
  /// **'العقارات والمخزون'**
  String get partnerManageListings;

  /// No description provided for @partnerAvailability.
  ///
  /// In ar, this message translates to:
  /// **'التوفر'**
  String get partnerAvailability;

  /// No description provided for @partnerPricing.
  ///
  /// In ar, this message translates to:
  /// **'الأسعار'**
  String get partnerPricing;

  /// No description provided for @partnerCreateListing.
  ///
  /// In ar, this message translates to:
  /// **'إضافة قائمة'**
  String get partnerCreateListing;

  /// No description provided for @partnerEditListing.
  ///
  /// In ar, this message translates to:
  /// **'تعديل القائمة'**
  String get partnerEditListing;

  /// No description provided for @partnerListingTitle.
  ///
  /// In ar, this message translates to:
  /// **'اسم القائمة'**
  String get partnerListingTitle;

  /// No description provided for @partnerCity.
  ///
  /// In ar, this message translates to:
  /// **'المدينة'**
  String get partnerCity;

  /// No description provided for @partnerCountry.
  ///
  /// In ar, this message translates to:
  /// **'الدولة'**
  String get partnerCountry;

  /// No description provided for @partnerDescription.
  ///
  /// In ar, this message translates to:
  /// **'الوصف'**
  String get partnerDescription;

  /// No description provided for @partnerImageUrl.
  ///
  /// In ar, this message translates to:
  /// **'رابط الصورة'**
  String get partnerImageUrl;

  /// No description provided for @partnerPrice.
  ///
  /// In ar, this message translates to:
  /// **'السعر'**
  String get partnerPrice;

  /// No description provided for @partnerAttributes.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الخدمة (JSON)'**
  String get partnerAttributes;

  /// No description provided for @partnerSave.
  ///
  /// In ar, this message translates to:
  /// **'حفظ التغييرات'**
  String get partnerSave;

  /// No description provided for @partnerCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get partnerCancel;

  /// No description provided for @partnerEmptyListings.
  ///
  /// In ar, this message translates to:
  /// **'أضف أول قائمة لك لبدء استقبال الحجوزات.'**
  String get partnerEmptyListings;

  /// No description provided for @partnerNoReservations.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حجوزات للشركة حتى الآن.'**
  String get partnerNoReservations;

  /// No description provided for @partnerNoCustomers.
  ///
  /// In ar, this message translates to:
  /// **'سيظهر هنا العملاء الذين لديهم حجوزات.'**
  String get partnerNoCustomers;

  /// No description provided for @partnerLoadFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحميل بيانات الشريك.'**
  String get partnerLoadFailed;

  /// No description provided for @partnerListingSaved.
  ///
  /// In ar, this message translates to:
  /// **'تم حفظ القائمة.'**
  String get partnerListingSaved;

  /// No description provided for @partnerListingSaveFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر حفظ هذه القائمة.'**
  String get partnerListingSaveFailed;

  /// No description provided for @partnerStatusActive.
  ///
  /// In ar, this message translates to:
  /// **'متاح'**
  String get partnerStatusActive;

  /// No description provided for @partnerStatusPaused.
  ///
  /// In ar, this message translates to:
  /// **'متوقف'**
  String get partnerStatusPaused;

  /// No description provided for @partnerCustomerDetails.
  ///
  /// In ar, this message translates to:
  /// **'تفاصيل الضيف'**
  String get partnerCustomerDetails;

  /// No description provided for @partnerBackToApp.
  ///
  /// In ar, this message translates to:
  /// **'العودة إلى تطبيق السفر'**
  String get partnerBackToApp;

  /// No description provided for @partnerTypeFlight.
  ///
  /// In ar, this message translates to:
  /// **'رحلة طيران'**
  String get partnerTypeFlight;

  /// No description provided for @partnerTypeHotel.
  ///
  /// In ar, this message translates to:
  /// **'إقامة'**
  String get partnerTypeHotel;

  /// No description provided for @partnerTypeCar.
  ///
  /// In ar, this message translates to:
  /// **'تأجير سيارة'**
  String get partnerTypeCar;

  /// No description provided for @partnerTypeTransfer.
  ///
  /// In ar, this message translates to:
  /// **'توصيل'**
  String get partnerTypeTransfer;

  /// No description provided for @partnerTypePackage.
  ///
  /// In ar, this message translates to:
  /// **'باقة سياحية'**
  String get partnerTypePackage;

  /// No description provided for @partnerAddListingHint.
  ///
  /// In ar, this message translates to:
  /// **'يمكنك إضافة عروض لنوع الخدمة الخاص بشركتك فقط. أدخل تفاصيل الخدمة أدناه، وسيتم تحديد الدولة تلقائياً من الموقع المختار.'**
  String get partnerAddListingHint;

  /// No description provided for @partnerServiceType.
  ///
  /// In ar, this message translates to:
  /// **'فئة الخدمة'**
  String get partnerServiceType;

  /// No description provided for @partnerInvalidPrice.
  ///
  /// In ar, this message translates to:
  /// **'أدخل سعراً صحيحاً غير سالب.'**
  String get partnerInvalidPrice;

  /// No description provided for @partnerInvalidAttributes.
  ///
  /// In ar, this message translates to:
  /// **'يجب أن تكون تفاصيل الخدمة كائن JSON صحيحاً.'**
  String get partnerInvalidAttributes;

  /// No description provided for @partnerRequiredField.
  ///
  /// In ar, this message translates to:
  /// **'هذا الحقل مطلوب.'**
  String get partnerRequiredField;

  /// No description provided for @partnerHotelPhotoRequired.
  ///
  /// In ar, this message translates to:
  /// **'أضف صورة رئيسية للفندق.'**
  String get partnerHotelPhotoRequired;

  /// No description provided for @partnerHotelMainPhoto.
  ///
  /// In ar, this message translates to:
  /// **'الصورة الرئيسية'**
  String get partnerHotelMainPhoto;

  /// No description provided for @partnerHotelGallery.
  ///
  /// In ar, this message translates to:
  /// **'صور إضافية'**
  String get partnerHotelGallery;

  /// No description provided for @partnerChooseMainPhoto.
  ///
  /// In ar, this message translates to:
  /// **'اختر الصورة الرئيسية'**
  String get partnerChooseMainPhoto;

  /// No description provided for @partnerAddHotelPhotos.
  ///
  /// In ar, this message translates to:
  /// **'أضف صوراً أخرى'**
  String get partnerAddHotelPhotos;

  /// No description provided for @partnerTicketPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر التذكرة'**
  String get partnerTicketPrice;

  /// No description provided for @partnerFlightRoute.
  ///
  /// In ar, this message translates to:
  /// **'مسار الرحلة'**
  String get partnerFlightRoute;

  /// No description provided for @partnerOriginCity.
  ///
  /// In ar, this message translates to:
  /// **'مدينة المغادرة'**
  String get partnerOriginCity;

  /// No description provided for @partnerOriginCode.
  ///
  /// In ar, this message translates to:
  /// **'رمز مطار المغادرة'**
  String get partnerOriginCode;

  /// No description provided for @partnerDestinationCity.
  ///
  /// In ar, this message translates to:
  /// **'مدينة الوصول'**
  String get partnerDestinationCity;

  /// No description provided for @partnerDestinationCode.
  ///
  /// In ar, this message translates to:
  /// **'رمز مطار الوصول'**
  String get partnerDestinationCode;

  /// No description provided for @partnerFlightNumber.
  ///
  /// In ar, this message translates to:
  /// **'رقم الرحلة'**
  String get partnerFlightNumber;

  /// No description provided for @partnerDepartureTime.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ ووقت المغادرة'**
  String get partnerDepartureTime;

  /// No description provided for @partnerArrivalTime.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ ووقت الوصول'**
  String get partnerArrivalTime;

  /// No description provided for @partnerAirportCodeHint.
  ///
  /// In ar, this message translates to:
  /// **'أدخل رمز المطار المكوّن من 3 أحرف، مثل MJI.'**
  String get partnerAirportCodeHint;

  /// No description provided for @partnerAirportSearch.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن مدينة أو مطار أو دولة أو رمز'**
  String get partnerAirportSearch;

  /// No description provided for @partnerGeneratedCode.
  ///
  /// In ar, this message translates to:
  /// **'المرجع'**
  String get partnerGeneratedCode;

  /// No description provided for @partnerInvalidAirportCode.
  ///
  /// In ar, this message translates to:
  /// **'يجب أن يتكون رمز المطار من 3 أحرف بالضبط.'**
  String get partnerInvalidAirportCode;

  /// No description provided for @partnerInvalidFlightTimes.
  ///
  /// In ar, this message translates to:
  /// **'اختر وقتاً صحيحاً، ويجب أن يكون الوصول بعد المغادرة.'**
  String get partnerInvalidFlightTimes;

  /// No description provided for @partnerSeatsAvailable.
  ///
  /// In ar, this message translates to:
  /// **'المقاعد المتاحة'**
  String get partnerSeatsAvailable;

  /// No description provided for @partnerSeatClass.
  ///
  /// In ar, this message translates to:
  /// **'درجة المقعد'**
  String get partnerSeatClass;

  /// No description provided for @partnerBusinessPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر درجة رجال الأعمال'**
  String get partnerBusinessPrice;

  /// No description provided for @partnerAddress.
  ///
  /// In ar, this message translates to:
  /// **'عنوان الشارع'**
  String get partnerAddress;

  /// No description provided for @partnerStars.
  ///
  /// In ar, this message translates to:
  /// **'تصنيف الفندق بالنجوم'**
  String get partnerStars;

  /// No description provided for @partnerRating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم'**
  String get partnerRating;

  /// No description provided for @partnerReviewCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد التقييمات'**
  String get partnerReviewCount;

  /// No description provided for @partnerAmenities.
  ///
  /// In ar, this message translates to:
  /// **'المرافق'**
  String get partnerAmenities;

  /// No description provided for @partnerAmenityInputHint.
  ///
  /// In ar, this message translates to:
  /// **'اكتب مرفقًا واضغط Enter أو الفاصلة'**
  String get partnerAmenityInputHint;

  /// No description provided for @partnerAmenityAdd.
  ///
  /// In ar, this message translates to:
  /// **'إضافة مرفق'**
  String get partnerAmenityAdd;

  /// No description provided for @partnerBrand.
  ///
  /// In ar, this message translates to:
  /// **'ماركة المركبة'**
  String get partnerBrand;

  /// No description provided for @partnerModel.
  ///
  /// In ar, this message translates to:
  /// **'طراز المركبة'**
  String get partnerModel;

  /// No description provided for @partnerCategory.
  ///
  /// In ar, this message translates to:
  /// **'الفئة'**
  String get partnerCategory;

  /// No description provided for @partnerYear.
  ///
  /// In ar, this message translates to:
  /// **'سنة الطراز'**
  String get partnerYear;

  /// No description provided for @partnerSeats.
  ///
  /// In ar, this message translates to:
  /// **'مقاعد الركاب'**
  String get partnerSeats;

  /// No description provided for @partnerTransmission.
  ///
  /// In ar, this message translates to:
  /// **'ناقل الحركة'**
  String get partnerTransmission;

  /// No description provided for @partnerFuelType.
  ///
  /// In ar, this message translates to:
  /// **'نوع الوقود'**
  String get partnerFuelType;

  /// No description provided for @partnerAvailableVehicles.
  ///
  /// In ar, this message translates to:
  /// **'المركبات المتاحة'**
  String get partnerAvailableVehicles;

  /// No description provided for @carSoldOut.
  ///
  /// In ar, this message translates to:
  /// **'نفدت السيارات'**
  String get carSoldOut;

  /// No description provided for @carSubtotal.
  ///
  /// In ar, this message translates to:
  /// **'المجموع الفرعي'**
  String get carSubtotal;

  /// No description provided for @partnerFeatures.
  ///
  /// In ar, this message translates to:
  /// **'الميزات'**
  String get partnerFeatures;

  /// No description provided for @partnerAirConditioning.
  ///
  /// In ar, this message translates to:
  /// **'تكييف الهواء'**
  String get partnerAirConditioning;

  /// No description provided for @partnerGps.
  ///
  /// In ar, this message translates to:
  /// **'نظام تحديد المواقع'**
  String get partnerGps;

  /// No description provided for @partnerOpeningHours.
  ///
  /// In ar, this message translates to:
  /// **'ساعات العمل'**
  String get partnerOpeningHours;

  /// No description provided for @partnerLatitude.
  ///
  /// In ar, this message translates to:
  /// **'خط العرض'**
  String get partnerLatitude;

  /// No description provided for @partnerLongitude.
  ///
  /// In ar, this message translates to:
  /// **'خط الطول'**
  String get partnerLongitude;

  /// No description provided for @partnerTags.
  ///
  /// In ar, this message translates to:
  /// **'الوسوم'**
  String get partnerTags;

  /// No description provided for @partnerVehicleType.
  ///
  /// In ar, this message translates to:
  /// **'نوع المركبة'**
  String get partnerVehicleType;

  /// No description provided for @partnerMaxPassengers.
  ///
  /// In ar, this message translates to:
  /// **'الحد الأقصى للركاب'**
  String get partnerMaxPassengers;

  /// No description provided for @partnerMaxLuggage.
  ///
  /// In ar, this message translates to:
  /// **'الحد الأقصى للأمتعة'**
  String get partnerMaxLuggage;

  /// No description provided for @partnerDurationMinutes.
  ///
  /// In ar, this message translates to:
  /// **'المدة بالدقائق'**
  String get partnerDurationMinutes;

  /// No description provided for @partnerIncludedServices.
  ///
  /// In ar, this message translates to:
  /// **'الخدمات المشمولة'**
  String get partnerIncludedServices;

  /// No description provided for @partnerDurationNights.
  ///
  /// In ar, this message translates to:
  /// **'المدة بالليالي'**
  String get partnerDurationNights;

  /// No description provided for @partnerHighlights.
  ///
  /// In ar, this message translates to:
  /// **'أبرز المميزات'**
  String get partnerHighlights;

  /// No description provided for @partnerCommaSeparatedHint.
  ///
  /// In ar, this message translates to:
  /// **'افصل بين القيم المتعددة بفواصل.'**
  String get partnerCommaSeparatedHint;

  /// No description provided for @partnerInvalidServiceField.
  ///
  /// In ar, this message translates to:
  /// **'أدخل قيمة صحيحة لهذا الحقل.'**
  String get partnerInvalidServiceField;

  /// No description provided for @airportMajorLabel.
  ///
  /// In ar, this message translates to:
  /// **'مطار رئيسي'**
  String get airportMajorLabel;

  /// No description provided for @airportMinorLabel.
  ///
  /// In ar, this message translates to:
  /// **'مطار إقليمي'**
  String get airportMinorLabel;

  /// No description provided for @airportNearestLabel.
  ///
  /// In ar, this message translates to:
  /// **'أقرب مطار'**
  String get airportNearestLabel;

  /// No description provided for @airportCategoryAddLocation.
  ///
  /// In ar, this message translates to:
  /// **'أضف مدينة أو مكاناً، مثل الطبيعة في بالي، إندونيسيا.'**
  String get airportCategoryAddLocation;

  /// No description provided for @compareIn.
  ///
  /// In ar, this message translates to:
  /// **'قارن بعملة'**
  String get compareIn;

  /// No description provided for @lydFixedRate.
  ///
  /// In ar, this message translates to:
  /// **'سعر مرجعي ثابت: 1 دولار أمريكي = 6.4 دينار ليبي'**
  String get lydFixedRate;

  /// No description provided for @refreshRates.
  ///
  /// In ar, this message translates to:
  /// **'تحديث الأسعار'**
  String get refreshRates;

  /// No description provided for @retryRates.
  ///
  /// In ar, this message translates to:
  /// **'إعادة محاولة الأسعار'**
  String get retryRates;

  /// No description provided for @frankfurterRatesUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'أسعار فرانكفورتر المرجعية اليومية · لا يتوفر تاريخ للأسعار'**
  String get frankfurterRatesUnavailable;

  /// No description provided for @frankfurterRatesDate.
  ///
  /// In ar, this message translates to:
  /// **'أسعار فرانكفورتر المرجعية اليومية · حتى {date}'**
  String frankfurterRatesDate(Object date);

  /// No description provided for @rateRefreshFailed.
  ///
  /// In ar, this message translates to:
  /// **'تعذر تحديث أسعار الصرف. قد لا تتوفر الأسعار المحوّلة.'**
  String get rateRefreshFailed;

  /// No description provided for @ratesMayBeStale.
  ///
  /// In ar, this message translates to:
  /// **'قد تكون الأسعار المرجعية قديمة. حدّث للتحقق من وجود تحديثات.'**
  String get ratesMayBeStale;

  /// No description provided for @unpricedOffers.
  ///
  /// In ar, this message translates to:
  /// **'{count} من العروض بلا سعر قابل للمقارنة، وتُستثنى من تصفية الأسعار.'**
  String unpricedOffers(int count);

  /// No description provided for @priceEstimateDisclaimer.
  ///
  /// In ar, this message translates to:
  /// **'المبالغ المحوّلة تقديرية وليست أسعار حجز. قد تختلف الرسوم وأسعار التسوية.'**
  String get priceEstimateDisclaimer;

  /// No description provided for @providerPrice.
  ///
  /// In ar, this message translates to:
  /// **'سعر المزوّد'**
  String get providerPrice;

  /// No description provided for @comparisonEstimate.
  ///
  /// In ar, this message translates to:
  /// **'تقدير للمقارنة'**
  String get comparisonEstimate;

  /// No description provided for @priceUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'غير متاح'**
  String get priceUnavailable;

  /// No description provided for @providerTotal.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي المزوّد'**
  String get providerTotal;

  /// No description provided for @providerPerPerson.
  ///
  /// In ar, this message translates to:
  /// **'للفرد'**
  String get providerPerPerson;

  /// No description provided for @flightAllTravelersEstimate.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي تقديري لجميع المسافرين'**
  String get flightAllTravelersEstimate;

  /// No description provided for @flightPartnerOutboundOnly.
  ///
  /// In ar, this message translates to:
  /// **'للذهاب فقط'**
  String get flightPartnerOutboundOnly;

  /// No description provided for @flightPartnerRoundTripWarning.
  ///
  /// In ar, this message translates to:
  /// **'تغطي أسعار الشركاء رحلة الذهاب فقط، ولا يمكن مقارنتها بإجمالي رحلات الذهاب والعودة.'**
  String get flightPartnerRoundTripWarning;

  /// No description provided for @flightMaxBudget.
  ///
  /// In ar, this message translates to:
  /// **'الحد الأقصى لإجمالي المسافرين'**
  String get flightMaxBudget;

  /// No description provided for @clearBudget.
  ///
  /// In ar, this message translates to:
  /// **'مسح الميزانية'**
  String get clearBudget;

  /// No description provided for @hotelPerRoomNight.
  ///
  /// In ar, this message translates to:
  /// **'سعر المزوّد للغرفة / الليلة'**
  String get hotelPerRoomNight;

  /// No description provided for @hotelEstimatePerRoomNight.
  ///
  /// In ar, this message translates to:
  /// **'تقدير للغرفة / الليلة'**
  String get hotelEstimatePerRoomNight;

  /// No description provided for @hotelBudgetThreshold.
  ///
  /// In ar, this message translates to:
  /// **'اقتصادي أقل من 100 {currency} / الليلة'**
  String hotelBudgetThreshold(Object currency);

  /// No description provided for @hotelMidThreshold.
  ///
  /// In ar, this message translates to:
  /// **'متوسط من 100 إلى أقل من 250 {currency} / الليلة'**
  String hotelMidThreshold(Object currency);

  /// No description provided for @hotelLuxuryThreshold.
  ///
  /// In ar, this message translates to:
  /// **'فاخر 250 {currency} أو أكثر / الليلة'**
  String hotelLuxuryThreshold(Object currency);

  /// No description provided for @offerSourcePartner.
  ///
  /// In ar, this message translates to:
  /// **'شريك'**
  String get offerSourcePartner;

  /// No description provided for @offerSourceDuffel.
  ///
  /// In ar, this message translates to:
  /// **'دافل'**
  String get offerSourceDuffel;

  /// No description provided for @tryAgain.
  ///
  /// In ar, this message translates to:
  /// **'حاول مرة أخرى'**
  String get tryAgain;

  /// No description provided for @invalidComparisonBudget.
  ///
  /// In ar, this message translates to:
  /// **'أدخل مبلغاً صحيحاً لا يقل عن صفر'**
  String get invalidComparisonBudget;

  /// No description provided for @referenceRatePolicy.
  ///
  /// In ar, this message translates to:
  /// **'تُميّز الأسعار الأقدم من 4 أيام؛ ولا تُستخدم أسعار الصرف الأقدم من 7 أيام.'**
  String get referenceRatePolicy;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
