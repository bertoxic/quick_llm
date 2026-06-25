import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_llm/models/chat_message.dart';
import 'package:quick_llm/widgets/message_bubble.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('renders Mermaid flowchart blocks with a visual preview',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownContentWidget(
            text: '''
```mermaid
flowchart TD
  A["Collect inputs"]
  B["Build preview"]
  A --> B
```
''',
            isUser: false,
            isDarkMode: false,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Collect inputs'), findsWidgets);
    expect(find.text('Build preview'), findsWidgets);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsWidgets);
  });

  testWidgets('shows side tool activity list and opens details',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            isDarkMode: false,
            message: ChatMessage(
              text: 'Simulation complete.',
              isUser: false,
              timestamp: DateTime(2026),
              details: {
                'tools': {
                  'activity': [
                    for (var i = 1; i <= 4; i++)
                      {
                        'id': 'simulation_tool_$i',
                        'title': 'Simulation tool $i',
                        'status': 'complete',
                        'summary': 'Ran Monte Carlo analysis.',
                        'ui_surface': 'Scenario lab',
                        'steps': [
                          'Parsed scenario inputs',
                          'Ran 1000 seeded Monte Carlo trials',
                        ],
                        'output': 'p50 period 3 = 124.5',
                      },
                  ],
                },
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Tool activity'), findsOneWidget);
    expect(find.text('Simulation tool 1'), findsWidgets);
    expect(find.textContaining('Show more'), findsOneWidget);

    await tester.tap(find.textContaining('Show more'));
    await tester.pumpAndSettle();

    expect(find.text('Simulation tool 4'), findsWidgets);
    expect(find.textContaining('Monte Carlo'), findsWidgets);
  });
}
