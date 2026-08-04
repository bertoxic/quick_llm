import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_llm/utils/local_tools.dart';

void main() {
  group('LocalToolService.shouldRunLiveWebSearch', () {
    test('detects recent product announcement requests', () {
      expect(
        LocalToolService.shouldRunLiveWebSearch(
          "What is OpenAI's most recent product announcement?",
        ),
        isTrue,
      );
    });

    test('detects product launch and release wording', () {
      expect(
        LocalToolService.shouldRunLiveWebSearch(
          'What did Anthropic announce in its newest model launch?',
        ),
        isTrue,
      );
      expect(
        LocalToolService.shouldRunLiveWebSearch(
          'When was the latest stable Flutter release?',
        ),
        isTrue,
      );
    });

    test('does not run web search for ordinary offline prompts', () {
      expect(
        LocalToolService.shouldRunLiveWebSearch(
          'Explain why dependency injection helps testing.',
        ),
        isFalse,
      );
    });
  });

  group('LocalToolService native tool dispatch', () {
    test('publishes Ollama-compatible function schemas', () {
      final toolNames = LocalToolService.ollamaToolDefinitions()
          .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
          .toSet();

      expect(toolNames, contains('calculator'));
      expect(toolNames, contains('date_time'));
      expect(toolNames, contains('web_search'));
      expect(toolNames, contains('shell_command_runner'));
      expect(toolNames, contains('multi_step_planner'));
      expect(toolNames, contains('local_document_search'));
      expect(toolNames, contains('tool_router'));
      expect(toolNames, contains('mind_map_generator'));
      expect(toolNames, contains('mind_map_tool'));
      expect(toolNames, contains('simulation_tool'));
      expect(toolNames, contains('webpage_reader'));
      expect(toolNames, contains('document_generator'));
      expect(toolNames, contains('pdf_document_generator'));
      expect(toolNames, contains('chart_diagram_generator'));
      expect(toolNames, contains('ci_cli_runner'));
      expect(toolNames, contains('workflow_automation'));
    });

    test('publishes expanded CI/CLI actions', () {
      final tool = LocalToolService.ollamaToolDefinitions().firstWhere(
        (tool) =>
            (tool['function'] as Map<String, dynamic>)['name'] ==
            'ci_cli_runner',
      );
      final function = tool['function'] as Map<String, dynamic>;
      final parameters = function['parameters'] as Map<String, dynamic>;
      final properties = parameters['properties'] as Map<String, dynamic>;
      final action = properties['action'] as Map<String, dynamic>;
      final enumValues = action['enum'] as List<dynamic>;

      expect(enumValues, contains('flutter_test_target'));
      expect(enumValues, contains('flutter_pub_outdated'));
      expect(enumValues, contains('flutter_doctor'));
      expect(properties, contains('target'));
    });

    test('injects agentic quality instructions into system prompts', () {
      final prompt = LocalToolService.applySystemInstructions(
        'Be concise.',
      );

      expect(prompt, contains('intelligent local AI agent'));
      expect(prompt, contains('Before calling any tool, silently check'));
      expect(prompt, contains('Quality gate before presenting a tool result'));
    });

    test('publishes advanced tool schema guidance', () {
      final tools = {
        for (final tool in LocalToolService.ollamaToolDefinitions())
          (tool['function'] as Map<String, dynamic>)['name'] as String:
              tool['function'] as Map<String, dynamic>
      };

      final simulation = tools['simulation_tool']!;
      final simulationParams = simulation['parameters'] as Map<String, dynamic>;
      final simulationProperties =
          simulationParams['properties'] as Map<String, dynamic>;
      expect(
        simulationProperties['iterations']['description'],
        contains('10000'),
      );
      expect(simulationProperties, contains('percentiles'));

      final diagram = tools['chart_diagram_generator']!;
      final diagramParams = diagram['parameters'] as Map<String, dynamic>;
      final diagramProperties =
          diagramParams['properties'] as Map<String, dynamic>;
      expect(diagramProperties, contains('detail_level'));
      expect(diagramProperties, contains('must_include'));

      final document = tools['document_generator']!;
      final documentParams = document['parameters'] as Map<String, dynamic>;
      final documentProperties =
          documentParams['properties'] as Map<String, dynamic>;
      expect(documentProperties, contains('document_type'));
    });

    test('executes calculator tool calls and returns role tool messages',
        () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'type': 'function',
          'function': {
            'name': 'calculator',
            'arguments': {'expression': '(2 + 3) * 4'},
          },
        },
      ]);

      expect(batch.toolMessages, hasLength(1));
      expect(batch.toolMessages.single['role'], 'tool');
      expect(batch.toolMessages.single['tool_name'], 'calculator');
      expect(batch.toolMessages.single['content'], contains('20'));
      expect(batch.context.results.single, contains('20'));
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('reads the local date and time without asking the model to guess',
        () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'type': 'function',
          'function': {
            'name': 'date_time',
            'arguments': {'action': 'date'},
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'date_time');
      expect(batch.toolMessages.single['content'], contains('local_date='));
      expect(batch.toolMessages.single['content'], contains('weekday='));
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('preflights direct date requests with the device clock', () async {
      final context = await LocalToolService.contextForPrompt(
        "What's today's date?",
      );

      expect(context.results, anyElement(contains('date_time(date)')));
      expect(
        context.activities.map((activity) => activity.id),
        contains('date_time'),
      );
      expect(
        context.activities.map((activity) => activity.id),
        isNot(contains('web_search')),
      );
    });

    test('parses stringified Ollama tool arguments', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'calculator',
            'arguments': '{"expression":"10 / 4"}',
          },
        },
      ]);

      expect(batch.toolMessages.single['content'], contains('2.5'));
    });

    test('executes multi-step planner instead of reporting unavailable',
        () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'multi_step_planner',
            'arguments': {
              'task': 'Fix the local tool calling workflow',
              'step_count': 4,
            },
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'multi_step_planner');
      expect(batch.toolMessages.single['content'], contains('generated plan'));
      expect(batch.toolMessages.single['content'], contains('"strategy"'));
      expect(
        batch.toolMessages.single['content'],
        contains('"acceptance_check"'),
      );
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
      expect(batch.context.activities.single.output, contains('4 step'));
    });

    test('routes complex prompts to multiple native tools', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'tool_router',
            'arguments': {
              'request':
                  'Read https://example.com, then turn the findings into a chart.',
            },
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'tool_router');
      expect(batch.toolMessages.single['content'], contains('webpage_reader'));
      expect(
        batch.toolMessages.single['content'],
        contains('chart_diagram_generator'),
      );
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('preflight router exposes likely tools before model generation',
        () async {
      final context = await LocalToolService.contextForPrompt(
        'Create a launch plan, turn the milestones into a flowchart, and draft a report.',
      );

      expect(context.results, anyElement(contains('tool_router')));
      expect(context.results, anyElement(contains('multi_step_planner')));
      expect(
        context.activities.map((activity) => activity.id),
        containsAll([
          'tool_router',
          'multi_step_planner',
        ]),
      );
      expect(
        context.results,
        anyElement(contains('tool_quality_gate')),
      );
      expect(
        context.results,
        anyElement(contains('Chain selected tools')),
      );
    });

    test('public router preview identifies advanced visual document tools', () {
      final routes = LocalToolService.routeToolsForPrompt(
        'Create a report and visualize the findings as a diagram.',
      );
      final names = routes.map((route) => route['tool']).toSet();

      expect(names, contains('document_generator'));
      expect(names, contains('chart_diagram_generator'));
    });

    test('generates mind maps as structured nodes, Mermaid, and SVG', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'mind_map_generator',
            'arguments': {
              'topic': 'Launch plan',
              'ideas':
                  'Audience: founders, teams\nChannels: email, web\nRisks: timing, budget',
              'format': 'all',
            },
          },
        },
      ]);

      final content = batch.toolMessages.single['content'] as String;
      expect(batch.toolMessages.single['tool_name'], 'mind_map_generator');
      expect(content, contains('"children"'));
      expect(content, contains('mindmap'));
      expect(content, contains('<svg'));
      final artifact =
          batch.context.activities.single.toJson()['artifact'] as Map;
      expect(artifact['file_name'], 'launch_plan.svg');
      expect(
        artifact['type'],
        'svg',
      );
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('runs deterministic scenario forecasts', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'simulation_tool',
            'arguments': {
              'scenario': 'Forecast signups for the next two months.',
              'variables': {
                'base_value': 100,
                'growth_rate': 0.1,
              },
              'horizon': 2,
            },
          },
        },
      ]);

      final content = batch.toolMessages.single['content'] as String;
      expect(batch.toolMessages.single['tool_name'], 'simulation_tool');
      expect(content, contains('"baseline": 121'));
      expect(content, contains('"monte_carlo"'));
      expect(content, contains('"iterations": 10000'));
      expect(content, contains('"p5"'));
      expect(content, contains('"p95"'));
      expect(content, contains('"histogram"'));
      expect(content, contains('"sensitivity_analysis"'));
      expect(content, contains('Box-Muller'));
      expect(
        batch.context.activities.single.toJson()['artifact']['type'],
        'svg',
      );
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('generates chart and diagram outputs', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'chart_diagram_generator',
            'arguments': {
              'title': 'Quarterly usage',
              'chart_type': 'bar',
              'data': 'Q1=10, Q2=20, Q3=15',
              'format': 'all',
            },
          },
        },
      ]);

      final content = batch.toolMessages.single['content'] as String;
      expect(batch.toolMessages.single['tool_name'], 'chart_diagram_generator');
      expect(content, contains('xychart-beta'));
      expect(content, contains('<svg'));
      expect(
        batch.context.activities.single.toJson()['artifact']['type'],
        'svg',
      );
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('generates polished line charts from labels and values', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'chart_diagram_generator',
            'arguments': {
              'title': 'Latency trend',
              'subtitle': 'p95 by release',
              'chart_type': 'line',
              'labels': ['v1', 'v2', 'v3'],
              'values': [220, 180, 145],
              'x_label': 'Release',
              'y_label': 'Latency',
              'unit': 'ms',
              'format': 'all',
            },
          },
        },
      ]);

      final content = batch.toolMessages.single['content'] as String;
      final artifact =
          batch.context.activities.single.toJson()['artifact'] as Map;

      expect(content, contains('"entry_count": 3'));
      expect(content, contains('line [220, 180, 145]'));
      expect(artifact['content'], contains('<polyline'));
      expect(artifact['content'], contains('Latency'));
      expect(artifact['content'], contains('220 ms'));
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('generates pie charts with slices and legend labels', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'chart_diagram_generator',
            'arguments': {
              'title': 'Traffic mix',
              'chart_type': 'pie',
              'entries': [
                {'label': 'Organic', 'value': 55},
                {'label': 'Paid', 'value': 30},
                {'label': 'Referral', 'value': 15},
              ],
              'unit': 'visits',
              'format': 'all',
            },
          },
        },
      ]);

      final content = batch.toolMessages.single['content'] as String;
      final artifact =
          batch.context.activities.single.toJson()['artifact'] as Map;

      expect(content, contains('pie showData'));
      expect(artifact['content'], contains('<path d="M'));
      expect(artifact['content'], contains('Organic'));
      expect(artifact['content'], contains('55 visits'));
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('blocks charts without numeric data instead of inventing values',
        () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'chart_diagram_generator',
            'arguments': {
              'title': 'Vague chart',
              'chart_type': 'bar',
              'data': 'Alpha, Beta, Gamma',
            },
          },
        },
      ]);

      expect(batch.toolMessages.single['content'], contains('provide entries'));
      expect(
        batch.context.activities.single.status,
        LocalToolStatus.unavailable,
      );
    });

    test('generates document content without requiring a file write', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'document_generator',
            'arguments': {
              'title': 'Tool rollout',
              'content': 'Goals\n- Add advanced tools\n- Verify behavior',
              'format': 'markdown',
            },
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'document_generator');
      expect(batch.toolMessages.single['content'], contains('# Tool rollout'));
      final artifact =
          batch.context.activities.single.toJson()['artifact'] as Map;
      expect(artifact['type'], 'markdown');
      expect(artifact['file_name'], 'tool_rollout.md');
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('prepares PDF document artifacts as saveable base64 content',
        () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'document_generator',
            'arguments': {
              'title': 'Executive Summary',
              'content': 'A concise update for the team.',
              'format': 'pdf',
            },
          },
        },
      ]);

      final artifact =
          batch.context.activities.single.toJson()['artifact'] as Map;
      expect(batch.toolMessages.single['tool_name'], 'document_generator');
      expect(artifact['type'], 'pdf');
      expect(artifact['file_name'], 'executive_summary.pdf');
      expect(artifact['encoding'], 'base64');
      expect(artifact['content'], isNotEmpty);
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('writes PDFs through the dedicated PDF document tool alias', () async {
      final fixtureDir = Directory('build/local_tool_tests/pdf');
      await fixtureDir.create(recursive: true);
      final output = File('${fixtureDir.path}/tool-summary');
      if (await File('${output.path}.pdf').exists()) {
        await File('${output.path}.pdf').delete();
      }

      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'pdf_document_generator',
            'arguments': {
              'title': 'Tool Summary',
              'content':
                  'Tools can route, plan, run CLI checks, and save PDFs.',
              'output_path': output.path,
            },
          },
        },
      ]);

      final written = File('${output.path}.pdf');
      expect(batch.toolMessages.single['tool_name'], 'pdf_document_generator');
      expect(batch.toolMessages.single['content'], contains('.pdf'));
      expect(await written.exists(), isTrue);
      expect(await written.length(), greaterThan(100));
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('blocks unsupported CI/CLI actions with a clear result', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'ci_cli_runner',
            'arguments': {'action': 'rm_rf'},
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'ci_cli_runner');
      expect(batch.toolMessages.single['content'], contains('choose'));
      expect(
        batch.context.activities.single.status,
        LocalToolStatus.unavailable,
      );
    });

    test('searches local documents and returns matching snippets', () async {
      final fixtureDir = Directory('build/local_tool_tests');
      await fixtureDir.create(recursive: true);
      final fixture = File('${fixtureDir.path}/notes.txt');
      await fixture.writeAsString(
        'Alpha notes\nTool calling should continue after tool results.\n',
      );

      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'local_document_search',
            'arguments': {
              'query': 'tool results',
              'path': fixtureDir.path,
            },
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'local_document_search');
      expect(batch.toolMessages.single['content'], contains('notes.txt'));
      expect(batch.toolMessages.single['content'], contains('tool results'));
      expect(batch.context.activities.single.status, LocalToolStatus.complete);
    });

    test('blocks unsafe code execution with a clear tool result', () async {
      final batch = await LocalToolService.executeOllamaToolCalls([
        {
          'function': {
            'name': 'code_executor',
            'arguments': {
              'language': 'python',
              'code': 'import os\nprint(os.getcwd())',
            },
          },
        },
      ]);

      expect(batch.toolMessages.single['tool_name'], 'code_executor');
      expect(batch.toolMessages.single['content'], contains('blocked'));
      expect(
        batch.context.activities.single.status,
        LocalToolStatus.unavailable,
      );
    });
  });
}
