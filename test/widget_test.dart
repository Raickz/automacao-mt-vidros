import 'package:flutter_test/flutter_test.dart';

import 'package:mt_vidros_app/main.dart';

void main() {
  testWidgets('App abre na tela inicial com opção de nova medição', (WidgetTester tester) async {
    await tester.pumpWidget(const MtVidrosApp());

    expect(find.text('Nova medição'), findsOneWidget);
    expect(find.text('Histórico de medições'), findsOneWidget);
  });
}
