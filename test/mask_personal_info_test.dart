import 'package:flutter/material.dart';
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/data/auth/ecard_bind_code_client.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/settings_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'TechPie',
    packageName: 'club.geekpie.techpie',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  group('StorageService - maskPersonalInfo', () {
    test('defaults to true and persists updates', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      expect(storage.maskPersonalInfo, isTrue);

      await storage.setMaskPersonalInfo(false);
      expect(storage.maskPersonalInfo, isFalse);

      await storage.setMaskPersonalInfo(true);
      expect(storage.maskPersonalInfo, isTrue);
    });
  });

  group('SettingsPage - personal info masking', () {
    late StorageService storage;
    late AuthService auth;
    late ThemeService theme;
    late DebugLogger logger;
    late ScheduleService schedule;
    late AssignmentService assignments;
    late ThirdPartyAuthService tpAuth;
    late OaGymService oaGym;
    late EgateAppService egateApp;
    late UniAuthService uniAuth;
    late SyncService sync;
    late CampusCardService campusCard;
    late EcardBindService ecardBind;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storage = StorageService(prefs);
      logger = DebugLogger();
      final http = LoggingHttpClient(logger);
      uniAuth = UniAuthService(logger: logger);
      auth = AuthService(storage, http, uniAuth, logger: logger);
      theme = ThemeService(storage);
      tpAuth = ThirdPartyAuthService(storage, http);
      schedule = ScheduleService(storage, http, auth, tpAuth);
      assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
      oaGym = OaGymService(auth, storage, tpAuth);
      egateApp = EgateAppService(auth, storage, tpAuth);

      final secureStore = InMemorySecureCredentialStore();
      campusCard = CampusCardService.withStore(secureStore);
      sync = SyncService(auth, tpAuth, storage, ecard: campusCard);
      ecardBind = EcardBindService(
        hijack: null,
        client: EcardBindCodeClient(
          send: (_, __, ___, ____) async => (200, '{"ok": true}'),
        ),
      );
    });

    tearDown(() {
      campusCard.dispose();
    });

    Widget createTestWidget() {
      return ServiceProvider(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: theme,
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: oaGym,
        egateAppService: egateApp,
        uniAuthService: uniAuth,
        syncService: sync,
        updateService: UpdateService(),
        campusCardService: campusCard,
        ecardBindService: ecardBind,
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      );
    }

    testWidgets('blurs personal info by default and toggles on tap', (tester) async {
      tester.view.physicalSize = const Size(780, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Simulate logged in user
      await storage.saveSession(
        UserSession(
          userId: '2023533123',
          userName: '测试用户',
          schoolName: '上海科技大学',
          createdAt: DateTime.now(),
        ),
      );
      await auth.loadSession();

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Initial state: blurred by default
      expect(find.text('测试用户'), findsOneWidget);
      expect(find.byTooltip('显示个人信息'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);

      // Tap on personal info row to reveal
      await tester.tap(find.text('测试用户'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('隐藏个人信息'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // Tap again to blur
      await tester.tap(find.text('测试用户'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('显示个人信息'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsWidgets);
    });

    testWidgets('switch updates storage and blurred state', (tester) async {
      tester.view.physicalSize = const Size(780, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await storage.saveSession(
        UserSession(
          userId: '2023533123',
          userName: '测试用户',
          schoolName: '上海科技大学',
          createdAt: DateTime.now(),
        ),
      );
      await auth.loadSession();

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.widgetWithText(ListTile, '默认隐藏个人信息');
      expect(switchFinder, findsOneWidget);

      // Toggle switch to off
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(storage.maskPersonalInfo, isFalse);
      expect(find.byTooltip('隐藏个人信息'), findsOneWidget);
    });
  });
}
