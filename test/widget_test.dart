import 'package:flutter_test/flutter_test.dart';

import 'package:mt_vidros_app/main.dart';

void main() {
  testWidgets(
    'App abre direto na digitalização de molde, sem menu de medição',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MtVidrosApp());

      expect(find.text('Digitalizar molde'), findsOneWidget);
      expect(find.text('Do molde ao arquivo de corte'), findsOneWidget);
      expect(find.text('Fotografar molde'), findsOneWidget);
      expect(find.text('Nova medição'), findsNothing);
      expect(find.text('Histórico de medições'), findsNothing);
    },
  );
}
