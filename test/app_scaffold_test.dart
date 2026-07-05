import 'package:calarm/app.dart';
import 'package:calarm/core/bootstrap/app_bootstrap.dart';
import 'package:calarm/core/identity/app_identity.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the scaffold feature boundaries', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CalarmApp()));

    expect(find.text(AppIdentity.defaultDisplayName), findsOneWidget);
    expect(find.text('Wake plan'), findsOneWidget);
    expect(find.text('Week calendar'), findsOneWidget);
    expect(find.text('Alarm ringing'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  test('bootstrap exposes app identity and persistence config', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(appIdentityProvider).displayName,
      AppIdentity.defaultDisplayName,
    );
    expect(
      container.read(appIdentityProvider).applicationId,
      AppIdentity.defaultApplicationId,
    );
    expect(container.read(appDatabaseConfigProvider).name, 'calarm.sqlite');
  });
}
