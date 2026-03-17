import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ispace_timeline/models/mail_models.dart';
import 'package:ispace_timeline/pages/mail_page.dart';
import 'package:ispace_timeline/services/mail_service.dart';

// ─── Mock MailService ──────────────────────────────────────────────────────────

class _MockMailService implements MailService {
  final List<MailMessageSummary> _inbox;
  final List<MailMessageSummary> _drafts;
  final List<int> deletedUids = [];
  int? savedDraftUid;
  MailComposeData? sentData;

  // Capture last searchFolder call for assertions
  String? lastSearchQuery;
  MailSearchScope? lastSearchScope;

  _MockMailService({
    List<MailMessageSummary>? inbox,
    List<MailMessageSummary>? drafts,
  })  : _inbox = inbox ?? [],
        _drafts = drafts ?? [];

  static MailFolderSnapshot _snapshot(
    MailFolder folder,
    List<MailMessageSummary> msgs,
  ) =>
      MailFolderSnapshot(
        emailAddress: 'test@mail.bnbu.edu.cn',
        incomingServer: 'imap.example.com',
        outgoingServer: 'smtp.example.com',
        messages: msgs,
        fetchedAt: DateTime.now(),
        folder: folder,
        totalMessages: msgs.length,
        currentPage: 1,
        pageSize: 25,
      );

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
  }) async {
    final msgs = folder == MailFolder.drafts ? _drafts : _inbox;
    return _snapshot(folder, msgs);
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required int uid,
  }) async {
    final all = [..._inbox, ..._drafts];
    final summary = all.firstWhere((m) => m.uid == uid);
    return MailMessageDetail(
      uid: summary.uid,
      subject: summary.subject,
      sender: summary.sender,
      recipients: 'test@mail.bnbu.edu.cn',
      cc: null,
      date: summary.date,
      body: 'Draft body content',
      htmlBody: null,
      isSeen: summary.isSeen,
    );
  }

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) async {
    lastSearchQuery = query;
    lastSearchScope = searchScope;
    return [];
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {
    sentData = composeData;
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required int uid,
    required String partId,
  }) async =>
      [];

  @override
  Future<int?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
  }) async {
    savedDraftUid = (existingDraftUid ?? 0) + 1;
    return savedDraftUid;
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
  }) async {
    deletedUids.addAll(uids);
  }

  @override
  Future<void> close() async {}
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _wrapInApp(Widget child) => MaterialApp(home: child);

MailMessageSummary _makeSummary({
  required int uid,
  String subject = 'Test Subject',
  String sender = 'Sender <sender@example.com>',
  bool isSeen = true,
}) =>
    MailMessageSummary(
      uid: uid,
      subject: subject,
      sender: sender,
      preview: 'Preview',
      hasHtmlBody: false,
      date: DateTime(2026, 3, 17),
      isSeen: isSeen,
    );

MailAccessCredentials _creds() => MailAccessCredentials(
      userId: 'testuser',
      emailAddress: 'testuser@mail.bnbu.edu.cn',
      password: 'password',
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  // ── Test 1: Toolbar equal-width sections ──────────────────────────────────

  group('Toolbar layout', () {
    testWidgets('toolbar has 3 equally-divided sections', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      // Find the toolbar row (height 44) - it should contain 3 Expanded children
      // Each section (folder selector, 未读, 多选) should be wrapped in Expanded
      final expanded = tester.widgetList<Expanded>(find.byType(Expanded));
      // At least the 3 toolbar sections should be Expanded
      final toolbarExpanded = expanded
          .where((e) {
            final child = e.child;
            return child is InkWell || child is PopupMenuButton || child is Center;
          })
          .toList();
      expect(toolbarExpanded.length, greaterThanOrEqualTo(3),
          reason: 'Toolbar should have 3 Expanded sections');
    });

    testWidgets('toolbar sections have equal flex', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      final expandedWidgets =
          tester.widgetList<Expanded>(find.byType(Expanded)).toList();
      // All toolbar Expanded widgets should have flex = 1
      for (final e in expandedWidgets) {
        expect(e.flex, equals(1),
            reason: 'All Expanded sections should have flex=1');
      }
    });
  });

  // ── Test 2: ComposeMailPage has From field ─────────────────────────────────

  group('ComposeMailPage fields', () {
    testWidgets('shows 发件人 (From) field with user email', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
          ),
        ),
      );
      await tester.pump();

      // Should show "发件人：" label
      expect(find.text('发件人：'), findsOneWidget,
          reason: 'ComposeMailPage must show a 发件人 (From) field');
      // Should show the user's email in the From field
      expect(find.textContaining('testuser@mail.bnbu.edu.cn'), findsWidgets,
          reason: 'From field should display the sender email');
    });

    testWidgets('shows 收件人 (To) editable field', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('收件人：'), findsOneWidget);
      // Can type into the To field
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              (w.controller?.text ?? '').isEmpty,
          description: 'empty TextField for To',
        ).first,
        'recipient@example.com',
      );
      expect(find.text('recipient@example.com'), findsOneWidget);
    });

    testWidgets('pre-fills fields when draftDetail provided', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();
      const draftDetail = MailMessageDetail(
        uid: 42,
        subject: 'My Draft Subject',
        sender: 'testuser@mail.bnbu.edu.cn',
        recipients: 'somebody@example.com',
        cc: 'cc@example.com',
        date: null,
        body: 'Draft body text',
        htmlBody: null,
        isSeen: true,
      );
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            draftDetail: draftDetail,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('somebody@example.com'), findsWidgets,
          reason: 'To field should be pre-filled from draftDetail.recipients');
      expect(find.textContaining('My Draft Subject'), findsWidgets,
          reason: 'Subject field should be pre-filled');
      expect(find.textContaining('Draft body text'), findsWidgets,
          reason: 'Body should be pre-filled');
    });
  });

  // ── Test 3: Draft folder opens compose, not detail ─────────────────────────

  group('Draft folder behavior', () {
    testWidgets('tapping draft message opens ComposeMailPage not detail',
        (tester) async {
      final draft = _makeSummary(uid: 99, subject: 'My Draft', isSeen: true);
      final svc = _MockMailService(drafts: [draft]);

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump(); // initState triggers fetchFolder(inbox)

      // Switch to drafts folder via the folder selector
      await tester.tap(find.byType(PopupMenuButton<MailFolder>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('草稿箱'));
      await tester.pumpAndSettle();
      await tester.pump(); // fetchFolder(drafts) completes

      // Tap the draft message
      await tester.tap(find.text('My Draft'));
      await tester.pumpAndSettle();

      // Should show ComposeMailPage (has "发件人" label), not "邮件详情"
      expect(find.text('邮件详情'), findsNothing,
          reason: 'Draft taps should NOT open detail page');
      expect(find.text('发件人：'), findsOneWidget,
          reason: 'Draft taps SHOULD open compose page');
    });
  });

  // ── Test 4: Search scope behavior ─────────────────────────────────────────

  group('Search scope behavior', () {
    testWidgets('scope chips hidden when search bar is empty', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('仅主题'), findsNothing);
      expect(find.text('按发件人'), findsNothing);
      expect(find.text('按收件人'), findsNothing);
    });

    testWidgets('scope chips appear when search bar has text', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      // Find the search TextField (first one in the widget tree)
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '搜索',
        ),
        'hello',
      );
      await tester.pump();

      expect(find.text('仅主题'), findsOneWidget);
      expect(find.text('按发件人'), findsOneWidget);
      expect(find.text('按收件人'), findsOneWidget);
    });

    testWidgets('default scope uses allText (no secondary input visible)',
        (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '搜索',
        ),
        'hello',
      );
      await tester.pump();

      // No secondary "发件人邮箱：" or "收件人邮箱：" input should appear
      expect(find.text('发件人邮箱：'), findsNothing);
      expect(find.text('收件人邮箱：'), findsNothing);
    });

    testWidgets('按发件人 chip shows secondary sender input field',
        (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      // Open search
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '搜索',
        ),
        'hello',
      );
      await tester.pump();

      // Tap 按发件人
      await tester.tap(find.text('按发件人'));
      await tester.pump();

      // Secondary sender input should appear
      expect(find.text('发件人邮箱：'), findsOneWidget,
          reason: '按发件人 chip must show a secondary sender input');
      expect(find.text('收件人邮箱：'), findsNothing);
    });

    testWidgets('按收件人 chip shows secondary recipient input field',
        (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '搜索',
        ),
        'hello',
      );
      await tester.pump();

      await tester.tap(find.text('按收件人'));
      await tester.pump();

      expect(find.text('收件人邮箱：'), findsOneWidget,
          reason: '按收件人 chip must show a secondary recipient input');
      expect(find.text('发件人邮箱：'), findsNothing);
    });

    testWidgets(
        '按发件人 chip stays visible even when main search bar is cleared',
        (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '搜索',
      );

      await tester.enterText(searchField, 'hello');
      await tester.pump();
      await tester.tap(find.text('按发件人'));
      await tester.pump();

      // Clear the main search bar
      await tester.enterText(searchField, '');
      await tester.pump();

      // Scope chips and sender input should still be visible
      expect(find.text('发件人邮箱：'), findsOneWidget,
          reason: 'Sender input must remain visible when 按发件人 is active');
    });

    testWidgets('default search triggers with allText scope', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '搜索',
        ),
        'hello',
      );
      // Advance past debounce
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(svc.lastSearchScope, equals(MailSearchScope.allText),
          reason: 'Default search must use allText scope');
      expect(svc.lastSearchQuery, equals('hello'));
    });

    testWidgets('仅主题 chip triggers subject-scoped search', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '搜索',
      );
      await tester.enterText(searchField, 'test query');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Now tap 仅主题
      await tester.tap(find.text('仅主题'));
      await tester.pumpAndSettle();

      expect(svc.lastSearchScope, equals(MailSearchScope.subject),
          reason: '仅主题 chip must switch scope to subject');
    });
  });
}
