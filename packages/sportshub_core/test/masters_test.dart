import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sportshub_core/sportshub_core.dart';

/// Bumthang -> Chokhor, Chumey; Thimphu -> Thim Throm. Villages under each.
class FakeMasters extends Fake implements MasterRepository {
  @override
  Future<List<LocationItem>> dzongkhags() async => const [
        LocationItem(id: 1, level: LocationLevel.dzongkhag, name: 'Bumthang'),
        LocationItem(id: 14, level: LocationLevel.dzongkhag, name: 'Thimphu'),
      ];

  @override
  Future<List<LocationItem>> gewogs(int dzongkhagId) async => switch (dzongkhagId) {
        1 => const [
            LocationItem(id: 1, level: LocationLevel.gewog, name: 'Chokhor', parentId: 1),
            LocationItem(id: 2, level: LocationLevel.gewog, name: 'Chumey', parentId: 1),
          ],
        _ => const [LocationItem(id: 159, level: LocationLevel.gewog, name: 'Thim Throm', parentId: 14, kind: 'thromde')],
      };

  @override
  Future<List<LocationItem>> villages(int gewogId) async => switch (gewogId) {
        1 => const [LocationItem(id: 1, level: LocationLevel.village, name: 'Chakhar', parentId: 1)],
        2 => const [LocationItem(id: 74, level: LocationLevel.village, name: 'Benzabi', parentId: 2)],
        _ => const [LocationItem(id: 3554, level: LocationLevel.village, name: 'Changangkha', parentId: 159)],
      };
}

void main() {
  group('LocationSelection', () {
    const chakhar = LocationSelection(dzongkhagId: 1, gewogId: 1, villageId: 1);

    test('a new dzongkhag clears the gewog and village', () {
      expect(chakhar.withDzongkhag(14), const LocationSelection(dzongkhagId: 14));
      expect(chakhar.withDzongkhag(1), chakhar, reason: 'the same one keeps them');
    });

    test('a new gewog clears the village', () {
      expect(chakhar.withGewog(2), const LocationSelection(dzongkhagId: 1, gewogId: 2));
      expect(chakhar.isComplete, isTrue);
      expect(chakhar.withGewog(2).isComplete, isFalse);
    });
  });

  test('a village row says where it is', () {
    final v = LocationItem.village({
      'id': 3554,
      'name': 'Changangkha',
      'is_active': true,
      'gewog_id': 159,
      'code': '1410007',
      'gewog': {
        'name': 'Thim Throm',
        'dzongkhag_id': 14,
        'dzongkhag': {'name': 'Thimphu'},
      },
    });
    expect(v.place, 'Thim Throm, Thimphu');
    expect(v.grandparentId, 14);
    expect(v.code, '1410007');
    expect(LocationItem.dzongkhag({'id': 1, 'name': 'Bumthang'}).place, isNull);
  });

  testWidgets('dzongkhag, then gewog, then village; changing one clears those under it', (tester) async {
    var value = LocationSelection.empty;
    await tester.pumpWidget(ProviderScope(
      overrides: [masterRepositoryProvider.overrideWithValue(FakeMasters())],
      child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => LocationFields(
              value: value,
              required: true,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Choose the dzongkhag first'), findsOneWidget);

    Future<void> choose(String label, String option) async {
      await tester.tap(find.widgetWithText(SearchableDropdown<int>, label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    await choose('Dzongkhag *', 'Bumthang');
    await choose('Gewog or thromde *', 'Chumey');
    await choose('Village *', 'Benzabi');
    expect(value, const LocationSelection(dzongkhagId: 1, gewogId: 2, villageId: 74));

    await choose('Dzongkhag *', 'Thimphu');
    expect(value, const LocationSelection(dzongkhagId: 14));
    expect(find.text('Benzabi'), findsNothing);
    await choose('Gewog or thromde *', 'Thim Throm');
    await choose('Village *', 'Changangkha');
    expect(value.isComplete, isTrue);
  });

  testWidgets('every dropdown can be searched: type to narrow, Enter takes the first', (tester) async {
    String? chosen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SearchableDropdown<String>(
            value: chosen,
            decoration: const InputDecoration(labelText: 'Dzongkhag'),
            options: [for (final d in dzongkhags) DropdownOption(d, d)],
            onChanged: (v) => setState(() => chosen = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Dzongkhag'));
    await tester.pumpAndSettle();
    final menu = find.byKey(SearchableDropdown.menuKey);
    Finder inMenu(String text) => find.descendant(of: menu, matching: find.text(text));
    expect(inMenu('Bumthang'), findsOneWidget);

    // Names starting with it first, then those with a word starting with it.
    await tester.enterText(find.descendant(of: menu, matching: find.byType(TextField)), 'tr');
    await tester.pumpAndSettle();
    expect(inMenu('Bumthang'), findsNothing);
    expect(inMenu('Trashigang'), findsOneWidget);
    expect(inMenu('Trongsa'), findsOneWidget);

    await tester.enterText(find.descendant(of: menu, matching: find.byType(TextField)), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches for “zzz”'), findsOneWidget);

    await tester.enterText(find.descendant(of: menu, matching: find.byType(TextField)), 'phodrang');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
    expect(chosen, 'Wangdue Phodrang');
    expect(find.text('Wangdue Phodrang'), findsOneWidget);
  });
}
