import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LocalToolService {
  static const _browserHeaders = {
    'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'accept-language': 'en-US,en;q=0.9',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36',
  };

  static const _chartPalette = [
    '#FF5722',
    '#76ABAE',
    '#303841',
    '#0f766e',
    '#f59e0b',
    '#2563eb',
    '#be123c',
    '#7c3aed',
    '#0891b2',
    '#65a30d',
  ];

  static const systemInstructions = '''
You are an intelligent local AI agent with access to a powerful native tool suite. Tool use must be deliberate, multi-step when useful, and focused on producing outputs that are genuinely useful rather than generic placeholders. For every request I give you, first decide whether a tool is needed. Use tools whenever they would make the answer more accurate, current, structured, visual, calculated, saved, or executable.

Do not guess when a tool can provide a better answer. Do not fake tool results. If a tool is needed, call the native tool, wait for the result, then answer normally.

When native tool schemas are attached, invoke the provider's structured function-call mechanism. Never print or explain a pseudo-call such as `tool_code web_search(...)`, a JSON call, or a tool plan as if it had already run. A tool has only run after its result is returned to you.

You may use multiple tools in one turn. For complex requests, call `tool_router` first, call `multi_step_planner` when the work needs ordered steps, then call each needed tool in sequence. After tool results return, continue with the next useful tool instead of stopping early.

Before calling any tool, silently check: intent, best tool sequence, exact parameters, whether one result should feed another tool, and how the output will be validated. Never call a tool with vague placeholder parameters.

Use the tools like this:

1. Use `calculator` for arithmetic, financial estimates, percentages, totals, comparisons, and any calculation that should not be guessed.
2. Use `web_search` for live/current information, prices, news, recent facts, API changes, policies, documentation updates, market research, product research, or anything likely to have changed. Search with specific queries; compare returned sources instead of relying on one snippet. Use `deep_research` for a research brief that needs multiple queries, source-page reading, comparison, and citations.
3. Use `date_time` whenever I ask for today's date, current time, day of the week, local timezone, or date arithmetic. Never infer the current date from training data.
3. Use `web_scraper_reader`, `webpage_reader`, or URL-reading tools when I provide a specific link and ask you to read, summarize, extract, compare, or analyze its content.
4. Use `note_save` when I ask you to remember, store, save, or keep information.
5. Use `note_get` when I ask about something previously saved, remembered, or noted.
6. Use `file_reader_writer` only when I explicitly give a local file path and ask you to read, edit, create, or write a file.
7. Use `shell_command_runner` only when I explicitly ask for shell, terminal, command-line, or OS-level execution.
8. Use `multi_step_planner` when I ask for a plan, roadmap, task breakdown, strategy, development steps, learning path, launch plan, or project execution guide.
9. Use `tool_router` when my request is complex and you need to decide the best tool sequence before executing.
10. Use `mind_map_generator` or `mind_map_tool` when I ask for a mind map, concept map, idea map, brainstorm map, or structured visual thinking. Ask for at least three levels of structure and concrete branch labels when the topic is non-trivial.
11. Use `simulation_tool` for what-if analysis, projections, forecasting, scenario planning, sensitivity checks, cost modeling, growth modeling, risk analysis, or business estimates. Provide numeric assumptions, distributions or volatility, a horizon, target thresholds when relevant, and at least 10000 iterations for meaningful Monte Carlo percentiles.
12. Use `local_document_search` when I ask you to search local documents using a query and optional path.
13. Use `code_executor` only when I explicitly ask you to run Python or JavaScript code.
14. Use `document_generator` when I ask you to generate markdown, HTML, text documents, reports, templates, documentation, proposals, or formatted long-form output. Use `pdf_document_generator` or `document_generator` with `format: "pdf"` whenever I ask for PDF, save as PDF, export as PDF, or provide an output path ending in `.pdf`. Reports should include an executive summary, structured sections, conclusions/recommendations, and tables for numeric claims.
15. Use `chart_diagram_generator` when I ask for charts, diagrams, SVG, Mermaid, architecture diagrams, flowcharts, graphs, visual explanations, or structured visuals. For diagrams, infer the full system scope, include meaningful labels, grouped sections, error/edge paths where relevant, and edge labels for Mermaid flowcharts. Avoid trivial 3-node diagrams when the topic warrants deeper coverage.
16. Use `ci_cli_runner` when I explicitly ask you to run supported Flutter/Dart CI or project CLI checks such as analyze, tests, targeted tests, format checks, pub get, pub outdated, doctor, or dependency listing. Report command, exit code, key stdout/stderr, and any artifact or failure clearly.
17. Use `workflow_automation` when I ask for repeatable workflows, automation design, triggers, actions, checks, fallback steps, or failure handling.

Before answering complex requests, briefly think through:

* What information is needed?
* Which tool or tools can provide it?
* What order should the tools be used in?
* What should be verified instead of assumed?

For simple requests, answer directly unless a tool would clearly improve accuracy.

For complex requests, use this process:

1. Identify the goal.
2. Choose the correct tool or tool sequence.
3. Call the tools.
4. If another tool is useful after reading a result, call it before answering.
5. Combine the results.
6. Give a clear final answer with practical next steps.

Default tool chains:
* Research/report: `deep_research` -> synthesize cited evidence -> `document_generator` or `pdf_document_generator`.
* Architecture/visual explanation: `tool_router` -> `multi_step_planner` -> `chart_diagram_generator` and, when useful, `mind_map_generator`.
* Forecast/projection: `web_search` for base rates when current data matters -> `simulation_tool` -> `chart_diagram_generator` or `document_generator`.
* Run and document: `ci_cli_runner` -> parse results -> final answer or `document_generator`.

When using visual tools, return the visual in the correct format. If SVG is returned, place it inside a fenced `svg block. If Mermaid is returned, place it inside a fenced `mermaid block.

Quality gate before presenting a tool result: confirm the output answers the actual user intent, is more specific than a generic prose answer, contains sufficient detail for diagrams/documents/simulations, and can be directly used, saved, shared, or acted on. If a tool fails or returns weak output, disclose it plainly and retry once with better parameters when possible.

Always prefer accuracy over speed. Use tools when they are useful, but do not call tools unnecessarily.
''';

  static const List<LocalToolDefinition> tierOneTools = [
    LocalToolDefinition(
      id: 'shell_command_runner',
      title: 'Shell command runner',
      summary: 'Execute whitelisted read-only shell commands.',
      detail: 'Scoped to safe operations like ls, dir, cat, type, and grep.',
      uiSurface: 'Terminal sidebar',
    ),
    LocalToolDefinition(
      id: 'file_reader_writer',
      title: 'File reader/writer',
      summary: 'Read local text files or prepare file outputs.',
      detail: 'Pairs with executors for local agent workflows.',
      uiSurface: 'File activity rail',
    ),
    LocalToolDefinition(
      id: 'multi_step_planner',
      title: 'Multi-step planner',
      summary: 'Create a JSON task plan and advance steps in order.',
      detail: 'Foundation for longer agentic tasks.',
      uiSurface: 'Plan timeline',
    ),
    LocalToolDefinition(
      id: 'date_time',
      title: 'Date & time',
      summary: 'Read the device clock and perform simple date arithmetic.',
      detail:
          'Returns local date, weekday, time, UTC timestamp, and timezone offset.',
      uiSurface: 'Inline result',
    ),
    LocalToolDefinition(
      id: 'tool_router',
      title: 'Tool router',
      summary: 'Choose the best tool or tool sequence for a request.',
      detail: 'Ranks native tools and explains why each one should run.',
      uiSurface: 'Routing panel',
    ),
    LocalToolDefinition(
      id: 'mind_map_generator',
      title: 'Mind map generator',
      summary: 'Turn ideas into visual mind maps.',
      detail: 'Outputs structured nodes, Mermaid mindmap, SVG, or all formats.',
      uiSurface: 'Mind map canvas',
    ),
    LocalToolDefinition(
      id: 'simulation_tool',
      title: 'Simulation tool',
      summary: 'Run scenarios, forecasts, and what-if calculations.',
      detail: 'Builds conservative, baseline, and optimistic projections.',
      uiSurface: 'Scenario lab',
    ),
    LocalToolDefinition(
      id: 'web_search',
      title: 'Web search',
      summary: 'Fetch live search results or current market data.',
      detail: 'Uses public web endpoints and injects returned sources.',
      uiSurface: 'Search sidebar',
    ),
    LocalToolDefinition(
      id: 'deep_research',
      title: 'Deep research',
      summary:
          'Plan multi-query research, read source pages, and collect evidence.',
      detail:
          'Runs three focused searches, reads selected pages, and returns a citation-ready evidence pack.',
      uiSurface: 'Research sidebar',
    ),
    LocalToolDefinition(
      id: 'note_saver',
      title: 'Note saver',
      summary: 'Persist named notes across sessions.',
      detail: 'Supports note_save("key", "value") and note_get("key").',
      uiSurface: 'Memory drawer',
    ),
    LocalToolDefinition(
      id: 'web_scraper_reader',
      title: 'Web scraper/reader',
      summary: 'Fetch a URL and strip HTML to clean readable text.',
      detail: 'Turns pasted links into summary-ready context.',
      uiSurface: 'Reader sidebar',
    ),
    LocalToolDefinition(
      id: 'webpage_reader',
      title: 'Webpage reader',
      summary: 'Read a known webpage without doing search.',
      detail: 'Fetches supplied URLs and returns clean article-like text.',
      uiSurface: 'Reader sidebar',
    ),
    LocalToolDefinition(
      id: 'local_document_search',
      title: 'RAG / local document search',
      summary: 'Retrieve relevant chunks from embedded local files.',
      detail: 'Requires a connected local vector index.',
      uiSurface: 'Knowledge sidebar',
    ),
    LocalToolDefinition(
      id: 'code_executor',
      title: 'Code executor',
      summary: 'Run sandboxed Python or JavaScript snippets locally.',
      detail: 'Requires a connected sandbox executor.',
      uiSurface: 'Execution sidebar',
    ),
    LocalToolDefinition(
      id: 'document_generator',
      title: 'PDF/document generator',
      summary: 'Generate Markdown, HTML, text, or PDF-ready documents.',
      detail:
          'Can write generated document artifacts when an output path is supplied.',
      uiSurface: 'Document studio',
    ),
    LocalToolDefinition(
      id: 'pdf_document_generator',
      title: 'PDF document generator',
      summary: 'Create saveable PDF artifacts and write PDFs to local paths.',
      detail:
          'Dedicated alias for save/export/create PDF requests so models choose PDF more reliably.',
      uiSurface: 'Document studio',
    ),
    LocalToolDefinition(
      id: 'chart_diagram_generator',
      title: 'Chart/diagram generator',
      summary: 'Generate charts, diagrams, Mermaid, and SVG.',
      detail: 'Turns small data sets or process steps into visual outputs.',
      uiSurface: 'Diagram canvas',
    ),
    LocalToolDefinition(
      id: 'ci_cli_runner',
      title: 'CI/CLI execution tool',
      summary: 'Run supported local Flutter/Dart project commands.',
      detail:
          'Whitelisted actions include analyze, tests, targeted tests, format, pub get/outdated/deps, and doctor.',
      uiSurface: 'CI console',
    ),
    LocalToolDefinition(
      id: 'workflow_automation',
      title: 'Workflow automation',
      summary: 'Draft repeatable automated workflows.',
      detail:
          'Produces triggers, actions, checks, approvals, and fallback handling.',
      uiSurface: 'Automation board',
    ),
  ];

  static List<Map<String, dynamic>> ollamaToolDefinitions() {
    Map<String, dynamic> functionTool({
      required String name,
      required String description,
      required Map<String, dynamic> properties,
      List<String> required = const [],
    }) {
      return {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': {
            'type': 'object',
            'properties': properties,
            'required': required,
          },
        },
      };
    }

    return [
      functionTool(
        name: 'calculator',
        description: 'Evaluate a deterministic arithmetic expression.',
        required: const ['expression'],
        properties: {
          'expression': {
            'type': 'string',
            'description': 'Arithmetic expression, e.g. "(12 + 5) * 3".',
          },
        },
      ),
      functionTool(
        name: 'date_time',
        description:
            'Read the device clock for the current local date, time, weekday, timezone offset, or simple date arithmetic. Use this instead of guessing today\'s date.',
        properties: {
          'action': {
            'type': 'string',
            'enum': ['now', 'date', 'time', 'weekday', 'add_days'],
            'description':
                'Defaults to now, which returns all current clock fields.',
          },
          'days': {
            'type': 'integer',
            'description':
                'Required only for add_days. Positive values move forward and negative values move backward.',
          },
        },
      ),
      functionTool(
        name: 'web_search',
        description:
            'Fetch live web search results or current crypto market prices. Use targeted current-data queries and synthesize across returned sources.',
        required: const ['query'],
        properties: {
          'query': {
            'type': 'string',
            'description': 'The search query or current-data request.',
          },
        },
      ),
      functionTool(
        name: 'deep_research',
        description:
            'Run a multi-source research workflow: plan focused searches, read selected webpages, compare evidence, and return citation-ready context. Use for research reports or questions that need more than a quick search.',
        required: const ['topic'],
        properties: {
          'topic': {
            'type': 'string',
            'description': 'The research question or topic to investigate.',
          },
        },
      ),
      functionTool(
        name: 'web_scraper_reader',
        description: 'Fetch a specific URL and return readable page text.',
        required: const ['url'],
        properties: {
          'url': {
            'type': 'string',
            'description': 'The full http or https URL to fetch.',
          },
        },
      ),
      functionTool(
        name: 'webpage_reader',
        description:
            'Read a specific webpage URL and return clean page text. Use this when the user supplied a URL and wants the page read, not searched.',
        required: const ['url'],
        properties: {
          'url': {
            'type': 'string',
            'description': 'The full http or https URL to read.',
          },
        },
      ),
      functionTool(
        name: 'note_save',
        description: 'Persist a note under a short key on this device.',
        required: const ['key', 'value'],
        properties: {
          'key': {
            'type': 'string',
            'description': 'Stable note key.',
          },
          'value': {
            'type': 'string',
            'description': 'Note content to save.',
          },
        },
      ),
      functionTool(
        name: 'note_get',
        description: 'Retrieve a note saved on this device.',
        required: const ['key'],
        properties: {
          'key': {
            'type': 'string',
            'description': 'Stable note key.',
          },
        },
      ),
      functionTool(
        name: 'file_reader_writer',
        description:
            'Read, write, or append local text files from explicit paths.',
        required: const ['action', 'path'],
        properties: {
          'action': {
            'type': 'string',
            'enum': ['read', 'write', 'append'],
            'description':
                'Use read for inspection, write for new files or overwrites, and append to add to an existing file.',
          },
          'path': {
            'type': 'string',
            'description': 'Quoted local file path.',
          },
          'content': {
            'type': 'string',
            'description': 'Text content for write or append actions.',
          },
          'overwrite': {
            'type': 'boolean',
            'description':
                'For write, set true to replace an existing file. Defaults to false.',
          },
        },
      ),
      functionTool(
        name: 'shell_command_runner',
        description:
            'Execute a whitelisted read-only shell command: ls, dir, cat, type, or grep.',
        required: const ['command'],
        properties: {
          'command': {
            'type': 'string',
            'description':
                'Command to run. Only ls, dir, cat, type, and grep are allowed.',
          },
        },
      ),
      functionTool(
        name: 'multi_step_planner',
        description:
            'Create a structured task plan with ordered steps, tool handoffs, validation checks, and a next action.',
        required: const ['task'],
        properties: {
          'task': {
            'type': 'string',
            'description': 'Task to plan.',
          },
          'step_count': {
            'type': 'integer',
            'description': 'Optional desired number of steps from 3 to 8.',
          },
        },
      ),
      functionTool(
        name: 'tool_router',
        description:
            'Recommend the best available Quick LLM tool sequence for a request, including chaining, validation, and deliverable expectations.',
        required: const ['request'],
        properties: {
          'request': {
            'type': 'string',
            'description': 'The user request to route.',
          },
        },
      ),
      functionTool(
        name: 'mind_map_generator',
        description:
            'Generate a non-flat mind map from a topic or list of ideas. Can output structured nodes, Mermaid, SVG, or all formats.',
        required: const ['topic'],
        properties: {
          'topic': {
            'type': 'string',
            'description': 'Central topic or title for the mind map.',
          },
          'ideas': {
            'type': 'string',
            'description':
                'Optional bullet list, comma list, or notes to turn into branches.',
          },
          'format': {
            'type': 'string',
            'enum': ['nodes', 'mermaid', 'svg', 'all'],
            'description': 'Desired output format. Defaults to all.',
          },
          'depth': {
            'type': 'integer',
            'description':
                'Desired concept depth. Use 3 or more for non-trivial topics.',
          },
          'include_cross_links': {
            'type': 'boolean',
            'description':
                'Set true when related ideas should be called out across branches.',
          },
        },
      ),
      functionTool(
        name: 'mind_map_tool',
        description:
            'Turn ideas into a visual mind map. Alias of mind_map_generator.',
        required: const ['ideas'],
        properties: {
          'ideas': {
            'type': 'string',
            'description': 'Ideas, notes, or bullet points to map.',
          },
          'topic': {
            'type': 'string',
            'description': 'Optional central topic.',
          },
          'format': {
            'type': 'string',
            'enum': ['nodes', 'mermaid', 'svg', 'all'],
            'description': 'Desired output format. Defaults to all.',
          },
          'depth': {
            'type': 'integer',
            'description':
                'Desired concept depth. Use 3 or more for non-trivial topics.',
          },
          'include_cross_links': {
            'type': 'boolean',
            'description':
                'Set true when related ideas should be called out across branches.',
          },
        },
      ),
      functionTool(
        name: 'simulation_tool',
        description:
            'Run scenario, forecast, what-if, Monte Carlo, risk, and sensitivity simulations with deterministic repeatable outputs, percentiles, and histogram summaries.',
        required: const ['scenario'],
        properties: {
          'scenario': {
            'type': 'string',
            'description': 'Scenario or what-if question to analyze.',
          },
          'variables': {
            'type': 'object',
            'description':
                'Numeric inputs such as base_value, growth_rate, periods, change, cost, revenue, conversion_rate, churn_rate, or distribution-like assumptions.',
          },
          'horizon': {
            'type': 'integer',
            'description':
                'Optional number of periods to forecast. Defaults to 3.',
          },
          'iterations': {
            'type': 'integer',
            'description':
                'Optional Monte Carlo trial count from 100 to 50000. Use at least 10000 for meaningful P5/P50/P95 percentiles. Defaults to 10000.',
          },
          'volatility': {
            'type': 'number',
            'description':
                'Optional period volatility as decimal or percent. Defaults from sensitivity or growth rate.',
          },
          'target_value': {
            'type': 'number',
            'description':
                'Optional target threshold for probability-of-success estimates.',
          },
          'seed': {
            'type': 'integer',
            'description':
                'Optional deterministic simulation seed for reproducible runs.',
          },
          'scenarios': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Optional named scenario labels such as bear, base, and bull.',
          },
          'percentiles': {
            'type': 'array',
            'items': {'type': 'number'},
            'description':
                'Optional requested percentiles. The native result includes P5/P10/P25/P50/P75/P90/P95.',
          },
        },
      ),
      functionTool(
        name: 'local_document_search',
        description:
            'Search local text files or directories for relevant snippets.',
        required: const ['query'],
        properties: {
          'query': {
            'type': 'string',
            'description': 'Document search query.',
          },
          'path': {
            'type': 'string',
            'description':
                'Optional file or directory path. Defaults to the current app directory.',
          },
          'paths': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional list of files or directories to search.',
          },
        },
      ),
      functionTool(
        name: 'code_executor',
        description:
            'Run a short, guarded Python or JavaScript snippet and return stdout/stderr.',
        required: const ['code'],
        properties: {
          'language': {
            'type': 'string',
            'enum': ['python', 'javascript'],
            'description': 'Programming language.',
          },
          'code': {
            'type': 'string',
            'description': 'Code to execute.',
          },
        },
      ),
      functionTool(
        name: 'document_generator',
        description:
            'Generate a structured Markdown, HTML, text, or PDF-ready document and optionally write it to an output path. Use format="pdf" for PDF requests.',
        required: const ['title', 'content'],
        properties: {
          'title': {
            'type': 'string',
            'description': 'Document title.',
          },
          'content': {
            'type': 'string',
            'description':
                'Source content, notes, outline, findings, tables, and recommendations to turn into a professional document.',
          },
          'format': {
            'type': 'string',
            'enum': ['markdown', 'html', 'text', 'pdf'],
            'description':
                'Document format. Use pdf when the user asks to save, export, or create a PDF. Defaults from output_path extension or markdown.',
          },
          'output_path': {
            'type': 'string',
            'description':
                'Optional local path to write the generated artifact. Paths ending in .pdf automatically create a PDF.',
          },
          'overwrite': {
            'type': 'boolean',
            'description':
                'Set true to replace an existing output_path. Defaults to false.',
          },
          'save_as_pdf': {
            'type': 'boolean',
            'description':
                'Set true when the user asks for a PDF but did not specify format.',
          },
          'document_type': {
            'type': 'string',
            'enum': [
              'technical_report',
              'research_brief',
              'business_case',
              'reference_manual',
              'incident_report',
              'proposal',
              'memo'
            ],
            'description':
                'Optional template intent. Reports should include summary, body sections, recommendations, and appendix/methodology when relevant.',
          },
        },
      ),
      functionTool(
        name: 'pdf_document_generator',
        description:
            'Generate a structured PDF document and optionally write it to an output path. Prefer this for save/export/create PDF requests.',
        required: const ['title', 'content'],
        properties: {
          'title': {
            'type': 'string',
            'description': 'PDF document title.',
          },
          'content': {
            'type': 'string',
            'description':
                'Source content, notes, outline, findings, tables, and recommendations to turn into a PDF.',
          },
          'output_path': {
            'type': 'string',
            'description':
                'Optional local path to write the PDF. A .pdf extension is added if missing.',
          },
          'overwrite': {
            'type': 'boolean',
            'description':
                'Set true to replace an existing output_path. Defaults to false.',
          },
          'document_type': {
            'type': 'string',
            'enum': [
              'technical_report',
              'research_brief',
              'business_case',
              'reference_manual',
              'incident_report',
              'proposal',
              'memo'
            ],
            'description':
                'Optional template intent. Reports should include summary, body sections, recommendations, and appendix/methodology when relevant.',
          },
        },
      ),
      functionTool(
        name: 'chart_diagram_generator',
        description:
            'Generate polished charts or diagrams as structured data, Mermaid, SVG, or all formats. Prefer structured labels/values for charts and detailed, edge-labeled process data for diagrams.',
        required: const ['title'],
        properties: {
          'title': {
            'type': 'string',
            'description': 'Chart or diagram title.',
          },
          'subtitle': {
            'type': 'string',
            'description': 'Optional chart subtitle or context line.',
          },
          'chart_type': {
            'type': 'string',
            'enum': ['bar', 'line', 'pie', 'flowchart'],
            'description': 'Visual type. Defaults to bar.',
          },
          'data': {
            'type': 'string',
            'description':
                'Dataset or process steps, e.g. "Alpha=10, Beta=20" or a detailed edge-labeled flow such as "Client ->|submits token| API ->|validates| Auth".',
          },
          'labels': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Ordered labels for chart categories or x-axis points.',
          },
          'values': {
            'type': 'array',
            'items': {'type': 'number'},
            'description': 'Numeric values aligned with labels.',
          },
          'entries': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'label': {'type': 'string'},
                'value': {'type': 'number'},
              },
              'required': ['label', 'value'],
            },
            'description':
                'Structured chart entries. Prefer this or labels/values over prose data.',
          },
          'x_label': {
            'type': 'string',
            'description': 'Optional x-axis label for bar and line charts.',
          },
          'y_label': {
            'type': 'string',
            'description': 'Optional y-axis label for bar and line charts.',
          },
          'unit': {
            'type': 'string',
            'description': 'Optional unit suffix such as %, USD, users, or ms.',
          },
          'format': {
            'type': 'string',
            'enum': ['mermaid', 'svg', 'data', 'all'],
            'description': 'Desired output format. Defaults to all.',
          },
          'detail_level': {
            'type': 'string',
            'enum': ['simple', 'moderate', 'comprehensive'],
            'description':
                'Use moderate or comprehensive when diagrams need full scope, grouped components, edge cases, or 10+ meaningful nodes.',
          },
          'must_include': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'Important nodes, paths, edge cases, labels, or sections that the visual should include.',
          },
        },
      ),
      functionTool(
        name: 'ci_cli_runner',
        description:
            'Run a whitelisted local CI/CLI action such as Flutter tests, Dart tests, analyze, format check, or pub get.',
        required: const ['action'],
        properties: {
          'action': {
            'type': 'string',
            'enum': [
              'flutter_test',
              'flutter_test_target',
              'flutter_analyze',
              'dart_test',
              'dart_analyze',
              'dart_format_check',
              'dart_format',
              'flutter_pub_get',
              'dart_pub_get',
              'flutter_pub_outdated',
              'dart_pub_outdated',
              'flutter_doctor',
              'flutter_pub_deps',
              'dart_pub_deps'
            ],
            'description': 'Whitelisted CI/CLI action to run.',
          },
          'target': {
            'type': 'string',
            'description':
                'Optional test file, directory, or package target for supported actions.',
          },
          'working_directory': {
            'type': 'string',
            'description':
                'Optional working directory. Defaults to the current app directory.',
          },
        },
      ),
      functionTool(
        name: 'workflow_automation',
        description:
            'Draft an automation workflow with trigger, actions, checks, approvals, and failure handling.',
        required: const ['objective'],
        properties: {
          'objective': {
            'type': 'string',
            'description': 'Outcome the automation should accomplish.',
          },
          'trigger': {
            'type': 'string',
            'description':
                'Optional event or schedule that starts the workflow.',
          },
          'steps': {
            'type': 'string',
            'description':
                'Optional newline, comma, or arrow separated workflow steps.',
          },
        },
      ),
    ];
  }

  static String? applySystemInstructions(
    String? systemPrompt, {
    bool enableTools = true,
  }) {
    final existing = systemPrompt?.trim();
    if (!enableTools) {
      return existing == null || existing.isEmpty ? null : existing;
    }
    if (existing == null || existing.isEmpty) return systemInstructions.trim();
    return '$existing\n\n${systemInstructions.trim()}';
  }

  static List<Map<String, dynamic>> routeToolsForPrompt(String request) {
    return _routesForPrompt(request);
  }

  static Future<LocalToolCallBatch> executeOllamaToolCalls(
    List<Map<String, dynamic>> toolCalls,
  ) async {
    final toolMessages = <Map<String, dynamic>>[];
    final results = <String>[];
    final activities = <LocalToolActivity>[];

    for (var index = 0; index < toolCalls.length; index++) {
      final parsed = _ParsedToolCall.fromOllama(toolCalls[index], index);
      final toolName = parsed.name.trim().toLowerCase();
      final execution = await _executeNamedTool(toolName, parsed.arguments);
      final content = execution.results.isEmpty
          ? '$toolName completed with no output.'
          : execution.results.join('\n\n');

      results.addAll(execution.results);
      activities.addAll(execution.activities);
      toolMessages.add({
        'role': 'tool',
        'tool_name': toolName,
        'content': content,
      });
    }

    return LocalToolCallBatch(
      toolMessages: toolMessages,
      context: LocalToolContext(results, activities: activities),
    );
  }

  static Future<_ToolExecution> _executeNamedTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    switch (name) {
      case 'calculator':
        return _runCalculatorTool(_stringArg(arguments, const [
          'expression',
          'input',
          'query',
        ]));
      case 'date_time':
      case 'calendar':
        return _runDateTimeTool(arguments);
      case 'web_search':
        return _runWebSearch(_stringArg(arguments, const [
              'query',
              'search_query',
              'prompt',
            ]) ??
            '');
      case 'deep_research':
      case 'research':
        return _runDeepResearch(_stringArg(arguments, const [
              'topic',
              'query',
              'prompt',
              'question',
            ]) ??
            '');
      case 'web_scraper_reader':
        return _readUrlTool(
            _stringArg(arguments, const ['url', 'uri', 'link']));
      case 'webpage_reader':
      case 'webpage_reader_tool':
        return _readWebpageTool(
            _stringArg(arguments, const ['url', 'uri', 'link']));
      case 'note_save':
        return _saveNoteTool(
          key: _stringArg(arguments, const ['key', 'name']),
          value: _stringArg(arguments, const ['value', 'content', 'note']),
        );
      case 'note_get':
        return _getNoteTool(_stringArg(arguments, const ['key', 'name']));
      case 'file_reader_writer':
      case 'file_reader':
        return _fileReaderWriterTool(arguments);
      case 'shell_command_runner':
        return _executeShellCommandTool(
          _stringArg(arguments, const ['command', 'cmd']),
        );
      case 'multi_step_planner':
        return _runMultiStepPlannerTool(
          task: _stringArg(arguments, const ['task', 'objective', 'prompt']),
          requestedStepCount: _intArg(arguments, const ['step_count', 'steps']),
        );
      case 'tool_router':
        return _runToolRouterTool(_stringArg(arguments, const [
              'request',
              'prompt',
              'task',
              'input',
            ]) ??
            '');
      case 'mind_map_generator':
      case 'mind_map_tool':
      case 'mind_map':
        return _runMindMapGeneratorTool(
          toolId:
              name == 'mind_map_tool' ? 'mind_map_tool' : 'mind_map_generator',
          topic:
              _stringArg(arguments, const ['topic', 'title', 'central_topic']),
          ideas: _stringArg(arguments, const [
            'ideas',
            'content',
            'notes',
            'input',
            'prompt',
          ]),
          format: _stringArg(arguments, const ['format', 'output_format']),
        );
      case 'simulation_tool':
      case 'scenario_simulator':
        return _runSimulationTool(arguments);
      case 'local_document_search':
        return _runLocalDocumentSearchTool(
          query: _stringArg(arguments, const ['query', 'q', 'prompt']),
          paths: _pathsArg(arguments),
        );
      case 'code_executor':
        return _runCodeExecutorTool(
          language: _stringArg(arguments, const ['language', 'lang']),
          code: _stringArg(arguments, const ['code', 'source', 'snippet']),
        );
      case 'document_generator':
        return _runDocumentGeneratorTool(arguments);
      case 'pdf_document_generator':
      case 'save_pdf_document':
        return _runDocumentGeneratorTool({
          ...arguments,
          'format': 'pdf',
          'save_as_pdf': true,
        });
      case 'chart_diagram_generator':
      case 'chart_generator':
      case 'diagram_generator':
        return _runChartDiagramGeneratorTool(arguments);
      case 'ci_cli_runner':
      case 'ci_cl_execution_tool':
      case 'cli_execution_tool':
        return _runCiCliRunnerTool(arguments);
      case 'workflow_automation':
      case 'workflow_automation_tool':
        return _runWorkflowAutomationTool(arguments);
      default:
        return _ToolExecution.singleFailure(
          id: name,
          title: name,
          uiSurface: 'Tool runner',
          summary: 'Unknown tool requested.',
          error: 'Unknown tool: $name',
          result: '$name failed: unknown tool. Do not invent tool output.',
          status: LocalToolStatus.unavailable,
        );
    }
  }

  static _ToolExecution _runCalculatorTool(String? expression) {
    final trimmed = expression?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'calculator',
        title: 'Calculator',
        uiSurface: 'Inline result',
        summary: 'Calculator did not run.',
        error: 'Missing expression.',
        result:
            'calculator failed: missing expression. Do not invent the answer.',
      );
    }

    final value = _ExpressionEvaluator(trimmed).parse();
    if (value == null || !value.isFinite) {
      return _ToolExecution.singleFailure(
        id: 'calculator',
        title: 'Calculator',
        uiSurface: 'Inline result',
        summary: 'Calculator could not evaluate the expression.',
        error: 'Invalid expression: $trimmed',
        result:
            'calculator("$trimmed") failed: invalid expression. Do not invent the answer.',
      );
    }

    final formatted = _formatNumber(value);
    return _ToolExecution(
      results: ['calculator("$trimmed") = $formatted'],
      activities: [
        LocalToolActivity.complete(
          id: 'calculator',
          title: 'Calculator',
          summary: 'Computed arithmetic with a native tool call.',
          uiSurface: 'Inline result',
          steps: const [
            'Received native tool call',
            'Evaluated expression locally',
            'Returned numeric result',
          ],
          output: formatted,
        ),
      ],
    );
  }

  static _ToolExecution _runDateTimeTool(Map<String, dynamic> arguments) {
    final action =
        (_stringArg(arguments, const ['action', 'operation']) ?? 'now')
            .trim()
            .toLowerCase();
    const supportedActions = {'now', 'date', 'time', 'weekday', 'add_days'};
    if (!supportedActions.contains(action)) {
      return _ToolExecution.singleFailure(
        id: 'date_time',
        title: 'Date & time',
        uiSurface: 'Inline result',
        summary: 'Date/time request did not run.',
        error: 'Unsupported action: $action',
        result: 'date_time failed: use now, date, time, weekday, or add_days.',
        status: LocalToolStatus.unavailable,
      );
    }

    final localNow = DateTime.now();
    final target = action == 'add_days'
        ? localNow.add(Duration(
            days: _intArg(arguments, const ['days', 'offset_days']) ?? 0))
        : localNow;
    final date = _formatCalendarDate(target);
    final weekday = _weekdayName(target.weekday);
    final time = _formatClockTime(target);
    final timezone =
        '${target.timeZoneName} (${_formatUtcOffset(target.timeZoneOffset)})';
    final output = switch (action) {
      'date' => 'local_date=$date\nweekday=$weekday\ntimezone=$timezone',
      'time' =>
        'local_time=$time\ntimezone=$timezone\nutc=${localNow.toUtc().toIso8601String()}',
      'weekday' => 'weekday=$weekday\nlocal_date=$date\ntimezone=$timezone',
      'add_days' =>
        'base_local_date=${_formatCalendarDate(localNow)}\ndays=${_intArg(arguments, const [
                  'days',
                  'offset_days'
                ]) ?? 0}\ntarget_local_date=$date\nweekday=$weekday\ntimezone=$timezone',
      _ =>
        'local_date=$date\nweekday=$weekday\nlocal_time=$time\ntimezone=$timezone\nutc=${localNow.toUtc().toIso8601String()}',
    };

    return _ToolExecution(
      results: ['date_time($action)\n$output'],
      activities: [
        LocalToolActivity.complete(
          id: 'date_time',
          title: 'Date & time',
          summary: 'Read the device clock locally.',
          uiSurface: 'Inline result',
          steps: [
            'Read the local device clock',
            if (action == 'add_days') 'Applied requested day offset',
            'Returned date/time with timezone offset',
          ],
          output: action == 'time' ? time : date,
        ),
      ],
    );
  }

  static String _formatCalendarDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _formatClockTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static String _formatUtcOffset(Duration offset) {
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes < 0 ? '-' : '+';
    final absoluteMinutes = totalMinutes.abs();
    final hours = (absoluteMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absoluteMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }

  static String _weekdayName(int weekday) {
    const names = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return names[weekday - 1];
  }

  static Future<_ToolExecution> _readUrlTool(String? urlText) async {
    final trimmed = urlText?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'web_scraper_reader',
        title: 'Web scraper/reader',
        uiSurface: 'Reader sidebar',
        summary: 'URL reader did not run.',
        error: 'Missing URL.',
        result:
            'web_scraper_reader failed: missing URL. Do not invent page contents.',
      );
    }

    return _readRequestedUrls(trimmed);
  }

  static Future<_ToolExecution> _readWebpageTool(String? urlText) async {
    final trimmed = urlText?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'webpage_reader',
        title: 'Webpage reader',
        uiSurface: 'Reader sidebar',
        summary: 'Webpage reader did not run.',
        error: 'Missing URL.',
        result:
            'webpage_reader failed: missing URL. Do not invent page contents.',
      );
    }

    return _readRequestedUrls(
      trimmed,
      id: 'webpage_reader',
      title: 'Webpage reader',
      resultName: 'webpage_reader',
    );
  }

  static Future<_ToolExecution> _saveNoteTool({
    required String? key,
    required String? value,
  }) async {
    final trimmedKey = key?.trim();
    final trimmedValue = value?.trim();
    if (trimmedKey == null ||
        trimmedKey.isEmpty ||
        trimmedValue == null ||
        trimmedValue.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'note_saver',
        title: 'Note saver',
        uiSurface: 'Memory drawer',
        summary: 'Note was not saved.',
        error: 'Missing key or value.',
        result: 'note_save failed: missing key or value.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteStorageKey(trimmedKey), trimmedValue);
    return _ToolExecution(
      results: ['note_save("$trimmedKey") completed.'],
      activities: [
        LocalToolActivity.complete(
          id: 'note_saver',
          title: 'Note saver',
          summary: 'Saved note across sessions.',
          uiSurface: 'Memory drawer',
          steps: ['Stored key "$trimmedKey" in local preferences'],
          output: trimmedKey,
        ),
      ],
    );
  }

  static Future<_ToolExecution> _getNoteTool(String? key) async {
    final trimmedKey = key?.trim();
    if (trimmedKey == null || trimmedKey.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'note_saver',
        title: 'Note saver',
        uiSurface: 'Memory drawer',
        summary: 'Note lookup did not run.',
        error: 'Missing key.',
        result: 'note_get failed: missing key.',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_noteStorageKey(trimmedKey));
    return _ToolExecution(
      results: [
        value == null
            ? 'note_get("$trimmedKey") returned no saved note.'
            : 'note_get("$trimmedKey") = $value',
      ],
      activities: [
        LocalToolActivity.complete(
          id: 'note_saver',
          title: 'Note saver',
          summary: value == null ? 'No note found.' : 'Retrieved saved note.',
          uiSurface: 'Memory drawer',
          steps: ['Looked up key "$trimmedKey" in local preferences'],
          output: value == null ? 'No note found' : trimmedKey,
        ),
      ],
    );
  }

  static Future<_ToolExecution> _readFileTool(String? path) async {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File tool did not run.',
        error: 'Missing file path.',
        result:
            'file_reader_writer failed: missing local file path. Do not invent file contents.',
        status: LocalToolStatus.unavailable,
      );
    }

    return _readFileAtPath(trimmed);
  }

  static Future<_ToolExecution> _executeShellCommandTool(
    String? command,
  ) async {
    final trimmed = command?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'shell_command_runner',
        title: 'Shell command runner',
        uiSurface: 'Terminal sidebar',
        summary: 'Shell tool did not run.',
        error: 'Missing command.',
        result:
            'shell_command_runner failed: missing command. Do not invent stdout.',
        status: LocalToolStatus.unavailable,
      );
    }

    return _executeSafeShellCommand(trimmed);
  }

  static Future<_ToolExecution> _fileReaderWriterTool(
    Map<String, dynamic> arguments,
  ) async {
    final action =
        (_stringArg(arguments, const ['action', 'operation']) ?? 'read')
            .trim()
            .toLowerCase();
    final path = _stringArg(arguments, const ['path', 'file']);

    if (action == 'read') {
      return _readFileTool(path);
    }

    if (action != 'write' && action != 'append') {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File tool did not run.',
        error: 'Unsupported action: $action',
        result:
            'file_reader_writer failed: unsupported action "$action". Use read, write, or append.',
        status: LocalToolStatus.unavailable,
      );
    }

    final trimmedPath = path?.trim();
    final content = _stringArg(arguments, const ['content', 'text', 'value']);
    if (trimmedPath == null || trimmedPath.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File write did not run.',
        error: 'Missing file path.',
        result:
            'file_reader_writer failed: missing local file path. Do not invent file output.',
        status: LocalToolStatus.unavailable,
      );
    }

    if (content == null) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File write did not run.',
        error: 'Missing content.',
        result:
            'file_reader_writer("$trimmedPath") failed: missing content for $action.',
      );
    }

    final file = File(trimmedPath);
    final overwrite = _boolArg(arguments, const ['overwrite', 'replace']);
    if (action == 'write' && await file.exists() && !overwrite) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File write blocked.',
        error: 'File already exists and overwrite was not true.',
        result:
            'file_reader_writer("$trimmedPath") blocked: file already exists. Set overwrite=true to replace it.',
        status: LocalToolStatus.unavailable,
      );
    }

    try {
      await file.parent.create(recursive: true);
      if (action == 'append') {
        await file.writeAsString(content, mode: FileMode.append);
      } else {
        await file.writeAsString(content);
      }

      final verb = action == 'append' ? 'appended' : 'wrote';
      return _ToolExecution(
        results: [
          'file_reader_writer("$trimmedPath") $verb ${content.length} characters.',
        ],
        activities: [
          LocalToolActivity.complete(
            id: 'file_reader_writer',
            title: 'File reader/writer',
            summary: action == 'append'
                ? 'Appended text to local file.'
                : 'Wrote local text file.',
            uiSurface: 'File activity rail',
            steps: [
              'Validated $action request',
              'Opened $trimmedPath',
              '${verb[0].toUpperCase()}${verb.substring(1)} ${content.length} characters',
            ],
            output: '$trimmedPath (${content.length} chars)',
          ),
        ],
      );
    } catch (error) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File write failed.',
        error: '$error',
        result:
            'file_reader_writer("$trimmedPath") failed: $error. Do not invent file output.',
      );
    }
  }

  static _ToolExecution _runMultiStepPlannerTool({
    required String? task,
    required int? requestedStepCount,
  }) {
    final trimmedTask = task?.trim();
    if (trimmedTask == null || trimmedTask.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'multi_step_planner',
        title: 'Multi-step planner',
        uiSurface: 'Plan timeline',
        summary: 'Planner did not run.',
        error: 'Missing task.',
        result: 'multi_step_planner failed: missing task.',
      );
    }

    final stepCount = (requestedStepCount ?? 6).clamp(3, 8).toInt();
    final routes = _routesForPrompt(trimmedTask);
    final steps = _buildPlannerSteps(trimmedTask, stepCount, routes);

    final plan = {
      'task': trimmedTask,
      'strategy': {
        'complexity': _planComplexity(trimmedTask, routes),
        'detected_tools': routes.map((route) => route['tool']).toList(),
        'deliverable': _planDeliverable(trimmedTask),
      },
      'steps': steps,
      'verification': _plannerVerification(trimmedTask, routes),
      'next_step': steps.first['title'],
    };
    final prettyPlan = const JsonEncoder.withIndent('  ').convert(plan);

    return _ToolExecution(
      results: [
        'multi_step_planner("$trimmedTask") generated plan:\n$prettyPlan',
      ],
      activities: [
        LocalToolActivity.complete(
          id: 'multi_step_planner',
          title: 'Multi-step planner',
          summary: 'Created a structured local plan.',
          uiSurface: 'Plan timeline',
          steps: steps
              .map((step) => '${step['id']}. ${step['title']} '
                  '(${step['status']})')
              .toList(),
          output: '$stepCount step plan',
        ),
      ],
    );
  }

  static _ToolExecution _runToolRouterTool(String request) {
    final trimmed = request.trim();
    if (trimmed.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'tool_router',
        title: 'Tool router',
        uiSurface: 'Routing panel',
        summary: 'Tool router did not run.',
        error: 'Missing request.',
        result: 'tool_router failed: missing request.',
      );
    }

    final routes = _routesForPrompt(trimmed);
    final route = {
      'request': trimmed,
      'recommended_tools': routes,
      'chain_strategy': _toolChainStrategy(routes),
      'quality_gates': _qualityGatesForRoutes(trimmed, routes),
      'next_action': routes.isEmpty
          ? 'answer_directly'
          : 'call ${routes.first['tool']} first',
    };
    final prettyRoute = const JsonEncoder.withIndent('  ').convert(route);

    return _ToolExecution(
      results: ['tool_router recommended route:\n$prettyRoute'],
      activities: [
        LocalToolActivity.complete(
          id: 'tool_router',
          title: 'Tool router',
          summary: routes.isEmpty
              ? 'No specialized tool was needed.'
              : 'Recommended a tool sequence.',
          uiSurface: 'Routing panel',
          steps: [
            'Scanned the request for tool intents',
            'Matched ${routes.length} tool candidate(s)',
            routes.isEmpty
                ? 'Recommended a direct response'
                : 'Top tool: ${routes.first['tool']}',
          ],
          output: routes.isEmpty
              ? 'direct response'
              : routes.map((route) => route['tool']).join(' -> '),
        ),
      ],
    );
  }

  static _ToolExecution _runMindMapGeneratorTool({
    required String toolId,
    required String? topic,
    required String? ideas,
    required String? format,
  }) {
    final trimmedTopic = topic?.trim();
    final trimmedIdeas = ideas?.trim();
    final rootLabel = (trimmedTopic != null && trimmedTopic.isNotEmpty)
        ? trimmedTopic
        : _firstIdeaTitle(trimmedIdeas);
    if (rootLabel == null || rootLabel.isEmpty) {
      return _ToolExecution.singleFailure(
        id: toolId,
        title: _toolTitle(toolId),
        uiSurface: 'Mind map canvas',
        summary: 'Mind map did not run.',
        error: 'Missing topic or ideas.',
        result: '$toolId failed: missing topic or ideas.',
      );
    }

    final tree =
        _buildMindMapTree(rootLabel, trimmedIdeas ?? trimmedTopic ?? '');
    final outputFormats = _visualOutputFormats(format);
    final mermaid = _mindMapMermaid(tree);
    final svg = _mindMapSvg(tree);
    final payload = <String, dynamic>{'topic': rootLabel};
    if (outputFormats.contains('nodes')) payload['nodes'] = tree;
    if (outputFormats.contains('mermaid')) payload['mermaid'] = mermaid;
    if (outputFormats.contains('svg')) payload['svg'] = svg;

    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    final childCount = (tree['children'] as List).length;

    return _ToolExecution(
      results: ['$toolId("$rootLabel") generated mind map:\n$pretty'],
      activities: [
        LocalToolActivity.complete(
          id: toolId,
          title: _toolTitle(toolId),
          summary: 'Generated a visual mind map.',
          uiSurface: 'Mind map canvas',
          steps: [
            'Parsed central topic "$rootLabel"',
            'Created $childCount branch node(s)',
            'Returned ${outputFormats.join(', ')} output',
          ],
          output: '$childCount branches',
          artifactType: 'svg',
          artifactContent: svg,
          artifactLabel: 'Mind map preview',
          artifactFileName: _suggestedArtifactFileName(rootLabel, 'svg'),
        ),
      ],
    );
  }

  static _ToolExecution _runSimulationTool(Map<String, dynamic> arguments) {
    final scenario =
        _stringArg(arguments, const ['scenario', 'question', 'prompt', 'task'])
            ?.trim();
    if (scenario == null || scenario.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'simulation_tool',
        title: 'Simulation tool',
        uiSurface: 'Scenario lab',
        summary: 'Simulation did not run.',
        error: 'Missing scenario.',
        result: 'simulation_tool failed: missing scenario.',
      );
    }

    final variables = _numericVariables(arguments);
    final scenarioNumbers = _numbersFromText(scenario);
    final baseValue = _simulationBaseValue(variables, scenarioNumbers);
    final growthRate = _simulationGrowthRate(variables, scenario);
    final perPeriodChange = _firstNumericValue(variables, const [
          'change',
          'delta',
          'monthly_change',
          'period_change',
        ]) ??
        0;
    final horizon = (_intArg(arguments, const ['horizon', 'periods']) ??
            variables['periods']?.round() ??
            variables['months']?.round() ??
            variables['years']?.round() ??
            3)
        .clamp(1, 24)
        .toInt();
    final sensitivity = _simulationSensitivity(variables, growthRate);
    final volatility =
        (_parseNumericValue(arguments['volatility'], 'volatility') ??
                _firstNumericValue(variables, const [
                  'volatility',
                  'stddev',
                  'standard_deviation',
                  'variance',
                ]) ??
                math.max(sensitivity, growthRate.abs() * 0.65))
            .abs()
            .clamp(0.0, 2.0)
            .toDouble();
    final iterations = (_intArg(arguments, const ['iterations', 'trials']) ??
            variables['iterations']?.round() ??
            variables['trials']?.round() ??
            10000)
        .clamp(100, 50000)
        .toInt();
    final targetValue =
        _parseNumericValue(arguments['target_value'], 'target') ??
            _firstNumericValue(variables, const [
              'target_value',
              'target',
              'goal',
              'break_even',
            ]);
    final seed = _intArg(arguments, const ['seed']) ??
        _simulationSeed(scenario, variables, horizon, iterations);

    final projections = _scenarioProjections(
      baseValue: baseValue,
      growthRate: growthRate,
      perPeriodChange: perPeriodChange,
      horizon: horizon,
      sensitivity: sensitivity,
    );
    final monteCarlo = _runMonteCarloSimulation(
      baseValue: baseValue,
      growthRate: growthRate,
      perPeriodChange: perPeriodChange,
      horizon: horizon,
      volatility: volatility,
      iterations: iterations,
      seed: seed,
      targetValue: targetValue,
    );
    final sensitivityAnalysis = _simulationSensitivityAnalysis(
      baseValue: baseValue,
      growthRate: growthRate,
      perPeriodChange: perPeriodChange,
      horizon: horizon,
      sensitivity: sensitivity,
    );
    final riskFlags = _simulationRiskFlags(
      monteCarlo: monteCarlo,
      baseValue: baseValue,
      targetValue: targetValue,
    );
    final finalSummary = monteCarlo['final_period'] as Map<String, dynamic>;
    final fanChartSvg = _simulationFanChartSvg(
      title: scenario,
      periodSummaries:
          (monteCarlo['period_summaries'] as List).cast<Map<String, dynamic>>(),
    );
    final payload = {
      'scenario': scenario,
      'algorithm':
          'Deterministic compound-growth scenarios plus seeded Monte Carlo using LCG random numbers and Box-Muller normal shocks.',
      'assumptions': {
        'base_value': baseValue,
        'growth_rate': growthRate,
        'per_period_change': perPeriodChange,
        'horizon': horizon,
        'sensitivity': sensitivity,
        'volatility': volatility,
        'iterations': iterations,
        'seed': seed,
        if (targetValue != null) 'target_value': targetValue,
        if (variables.isEmpty)
          'note':
              'No numeric variables were supplied; using a normalized index.',
      },
      'deterministic_scenarios': projections,
      'monte_carlo': monteCarlo,
      'sensitivity_analysis': sensitivityAnalysis,
      'risk_flags': riskFlags,
    };
    final pretty = const JsonEncoder.withIndent('  ').convert(payload);

    return _ToolExecution(
      results: ['simulation_tool("$scenario") result:\n$pretty'],
      activities: [
        LocalToolActivity.complete(
          id: 'simulation_tool',
          title: 'Simulation tool',
          summary:
              'Ran deterministic scenarios, Monte Carlo, and sensitivity analysis.',
          uiSurface: 'Scenario lab',
          steps: [
            'Parsed scenario inputs',
            'Projected $horizon period(s) across deterministic bands',
            'Ran $iterations seeded Monte Carlo trial(s)',
            'Computed percentile bands, target probability, and sensitivity cases',
          ],
          output: 'p50 period $horizon = ${_formatNumber(
            (finalSummary['p50'] as num).toDouble(),
          )}',
          artifactType: 'svg',
          artifactContent: fanChartSvg,
          artifactLabel: 'Simulation fan chart',
          artifactFileName: _suggestedArtifactFileName(scenario, 'svg'),
        ),
      ],
    );
  }

  static Future<_ToolExecution> _runDocumentGeneratorTool(
    Map<String, dynamic> arguments,
  ) async {
    final title = _stringArg(arguments, const ['title', 'name'])?.trim();
    final content =
        _stringArg(arguments, const ['content', 'body', 'notes', 'outline'])
            ?.trim();
    if (title == null || title.isEmpty || content == null || content.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'document_generator',
        title: 'PDF/document generator',
        uiSurface: 'Document studio',
        summary: 'Document generator did not run.',
        error: 'Missing title or content.',
        result: 'document_generator failed: missing title or content.',
      );
    }

    final outputPath = _stringArg(arguments, const ['output_path', 'path']);
    final wantsPdf = _boolArg(arguments, const [
          'pdf',
          'as_pdf',
          'save_as_pdf',
          'export_as_pdf',
          'make_pdf',
        ]) ||
        _stringArg(arguments, const ['tool_name', 'name']) ==
            'pdf_document_generator';
    final format = wantsPdf
        ? 'pdf'
        : _documentFormat(
            _stringArg(arguments, const ['format', 'output_format']),
            outputPath,
          );
    final overwrite = _boolArg(arguments, const ['overwrite', 'replace']);
    final generatedText = _documentText(title, content, format);
    final isPdf = format == 'pdf';
    final pdfBytes = isPdf ? _minimalPdfBytes(title, content) : null;
    final artifactContent = isPdf ? base64Encode(pdfBytes!) : generatedText;
    final artifactEncoding = isPdf ? 'base64' : null;
    final artifactFileName =
        _suggestedArtifactFileName(title, _documentExtension(format));

    if (outputPath != null && outputPath.trim().isNotEmpty) {
      final path = _normalizedDocumentOutputPath(outputPath.trim(), format);
      final file = File(path);
      if (await file.exists() && !overwrite) {
        return _ToolExecution.singleFailure(
          id: 'document_generator',
          title: 'PDF/document generator',
          uiSurface: 'Document studio',
          summary: 'Document write blocked.',
          error: 'File already exists and overwrite was not true.',
          result:
              'document_generator("$title") blocked: file already exists. Set overwrite=true to replace it.',
          status: LocalToolStatus.unavailable,
        );
      }

      try {
        await file.parent.create(recursive: true);
        if (isPdf) {
          await file.writeAsBytes(pdfBytes!);
        } else {
          await file.writeAsString(generatedText);
        }
        final size = await file.length();
        return _ToolExecution(
          results: [
            'document_generator("$title") wrote $format document to $path ($size bytes).',
          ],
          activities: [
            LocalToolActivity.complete(
              id: 'document_generator',
              title: 'PDF/document generator',
              summary: 'Generated and wrote a document artifact.',
              uiSurface: 'Document studio',
              steps: [
                'Built $format document content',
                'Created parent directory if needed',
                'Wrote $size bytes to $path',
              ],
              output: '$path ($format)',
              artifactType: format,
              artifactContent: artifactContent,
              artifactLabel: '$format document',
              artifactFileName: artifactFileName,
              artifactEncoding: artifactEncoding,
            ),
          ],
        );
      } catch (error) {
        return _ToolExecution.singleFailure(
          id: 'document_generator',
          title: 'PDF/document generator',
          uiSurface: 'Document studio',
          summary: 'Document write failed.',
          error: '$error',
          result: 'document_generator("$title") failed: $error',
        );
      }
    }

    final preview = isPdf
        ? 'PDF document prepared. Use the save button on the tool artifact to choose where to write it.\n\n${_documentText(title, content, 'markdown')}'
        : generatedText;
    return _ToolExecution(
      results: [
        'document_generator("$title") generated $format document:\n${_clip(preview, 8000)}',
      ],
      activities: [
        LocalToolActivity.complete(
          id: 'document_generator',
          title: 'PDF/document generator',
          summary: 'Generated document content.',
          uiSurface: 'Document studio',
          steps: [
            'Built $format document content',
            outputPath == null
                ? 'Returned content inline'
                : 'Output path was empty, returned content inline',
          ],
          output: '$format document',
          artifactType: format,
          artifactContent: artifactContent,
          artifactLabel: '$format document',
          artifactFileName: artifactFileName,
          artifactEncoding: artifactEncoding,
        ),
      ],
    );
  }

  static _ToolExecution _runChartDiagramGeneratorTool(
    Map<String, dynamic> arguments,
  ) {
    final title = _stringArg(arguments, const ['title', 'name'])?.trim();
    if (title == null || title.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'chart_diagram_generator',
        title: 'Chart/diagram generator',
        uiSurface: 'Diagram canvas',
        summary: 'Chart generator did not run.',
        error: 'Missing title.',
        result: 'chart_diagram_generator failed: missing title.',
      );
    }

    final chartType = _normalizeChartType(
        _stringArg(arguments, const ['chart_type', 'type']));
    final outputFormats = _visualOutputFormats(
      _stringArg(arguments, const ['format', 'output_format']),
    );
    final payload = <String, dynamic>{
      'title': title,
      'chart_type': chartType,
    };
    late final String svg;

    if (chartType == 'flowchart') {
      final dataText =
          _stringArg(arguments, const ['data', 'dataset', 'steps', 'content'])
              ?.trim();
      if (dataText == null || dataText.isEmpty) {
        return _ToolExecution.singleFailure(
          id: 'chart_diagram_generator',
          title: 'Chart/diagram generator',
          uiSurface: 'Diagram canvas',
          summary: 'Flowchart generator did not run.',
          error: 'Missing process steps.',
          result:
              'chart_diagram_generator failed: flowcharts need steps or process data.',
        );
      }
      final steps = _flowSteps(dataText);
      svg = _flowchartSvg(title, steps);
      payload['data'] = steps;
      if (outputFormats.contains('mermaid')) {
        payload['mermaid'] = _flowchartMermaid(title, steps);
      }
      if (outputFormats.contains('svg')) payload['svg'] = svg;
    } else {
      final spec = _chartSpecFromArguments(
        title: title,
        chartType: chartType,
        arguments: arguments,
      );
      if (spec.entries.isEmpty) {
        return _ToolExecution.singleFailure(
          id: 'chart_diagram_generator',
          title: 'Chart/diagram generator',
          uiSurface: 'Diagram canvas',
          summary: 'Chart generator did not run.',
          error: 'Missing numeric chart data.',
          result:
              'chart_diagram_generator failed: provide entries, labels+values, or data like "Q1=10, Q2=20".',
          status: LocalToolStatus.unavailable,
        );
      }
      svg = _chartSvg(spec);
      payload.addAll(spec.toJson());
      payload['data'] = spec.entries
          .map((entry) => {'label': entry.label, 'value': entry.value})
          .toList();
      if (outputFormats.contains('mermaid')) {
        payload['mermaid'] = _chartMermaid(spec);
      }
      if (outputFormats.contains('svg')) payload['svg'] = svg;
    }

    final pretty = const JsonEncoder.withIndent('  ').convert(payload);
    return _ToolExecution(
      results: ['chart_diagram_generator("$title") generated:\n$pretty'],
      activities: [
        LocalToolActivity.complete(
          id: 'chart_diagram_generator',
          title: 'Chart/diagram generator',
          summary: 'Generated chart or diagram output.',
          uiSurface: 'Diagram canvas',
          steps: [
            'Parsed $chartType input data',
            'Generated ${outputFormats.join(', ')} output',
          ],
          output: '$chartType ${outputFormats.join('/')}',
          artifactType: 'svg',
          artifactContent: svg,
          artifactLabel: '$chartType preview',
          artifactFileName: _suggestedArtifactFileName(title, 'svg'),
        ),
      ],
    );
  }

  static Future<_ToolExecution> _runCiCliRunnerTool(
    Map<String, dynamic> arguments,
  ) async {
    final action = _stringArg(arguments, const ['action', 'command'])?.trim();
    final spec = _ciCliActionSpec(action);
    if (spec == null) {
      return _ToolExecution.singleFailure(
        id: 'ci_cli_runner',
        title: 'CI/CLI execution tool',
        uiSurface: 'CI console',
        summary: 'CI/CLI action did not run.',
        error: 'Unsupported action: ${action ?? 'missing'}',
        result:
            'ci_cli_runner failed: choose flutter_test, flutter_test_target, flutter_analyze, dart_test, dart_analyze, dart_format_check, dart_format, flutter_pub_get, dart_pub_get, flutter_pub_outdated, dart_pub_outdated, flutter_doctor, flutter_pub_deps, or dart_pub_deps.',
        status: LocalToolStatus.unavailable,
      );
    }

    final workingDirectory =
        _stringArg(arguments, const ['working_directory', 'cwd', 'path'])
                ?.trim() ??
            Directory.current.path;
    if (!await Directory(workingDirectory).exists()) {
      return _ToolExecution.singleFailure(
        id: 'ci_cli_runner',
        title: 'CI/CLI execution tool',
        uiSurface: 'CI console',
        summary: 'CI/CLI action did not run.',
        error: 'Working directory not found: $workingDirectory',
        result:
            'ci_cli_runner("${spec.action}") failed: working directory not found.',
        status: LocalToolStatus.unavailable,
      );
    }

    final target =
        _stringArg(arguments, const ['target', 'file', 'test_path'])?.trim();
    final targetArgs =
        spec.supportsTarget && target != null && target.isNotEmpty
            ? [target]
            : const <String>[];
    final args = [...spec.args, ...targetArgs];
    final displayCommand = [spec.displayCommand, ...targetArgs].join(' ');

    try {
      final capture = await _runProcessCandidates(
        spec.candidates,
        args,
        workingDirectory: workingDirectory,
        timeout: const Duration(minutes: 3),
      );
      final stdoutText = _clip(capture.stdout.trim(), 8000);
      final stderrText = _clip(capture.stderr.trim(), 4000);
      final result = [
        'ci_cli_runner("${spec.action}") exit_code=${capture.exitCode}${capture.timedOut ? ' timed_out=true' : ''}',
        'command: $displayCommand',
        'cwd: $workingDirectory',
        'stdout:',
        stdoutText.isEmpty ? '[empty]' : stdoutText,
        'stderr:',
        stderrText.isEmpty ? '[empty]' : stderrText,
      ].join('\n');

      if (capture.exitCode != 0 || capture.timedOut) {
        return _ToolExecution.singleFailure(
          id: 'ci_cli_runner',
          title: 'CI/CLI execution tool',
          uiSurface: 'CI console',
          summary: capture.timedOut
              ? 'CI/CLI action timed out.'
              : 'CI/CLI action failed.',
          error: capture.timedOut
              ? 'Execution exceeded 3 minutes.'
              : 'Exit code ${capture.exitCode}.',
          result: result,
        );
      }

      return _ToolExecution(
        results: [result],
        activities: [
          LocalToolActivity.complete(
            id: 'ci_cli_runner',
            title: 'CI/CLI execution tool',
            summary: 'Ran whitelisted local verification.',
            uiSurface: 'CI console',
            steps: [
              'Validated action ${spec.action}',
              'Ran $displayCommand',
              'Captured stdout and stderr',
            ],
            output: 'exit 0',
          ),
        ],
      );
    } on ProcessException catch (error) {
      return _ToolExecution.singleFailure(
        id: 'ci_cli_runner',
        title: 'CI/CLI execution tool',
        uiSurface: 'CI console',
        summary: 'CI/CLI runtime was not found.',
        error: error.message,
        result:
            'ci_cli_runner("${spec.action}") failed: runtime was not found for ${spec.displayCommand}.',
        status: LocalToolStatus.unavailable,
      );
    } catch (error) {
      return _ToolExecution.singleFailure(
        id: 'ci_cli_runner',
        title: 'CI/CLI execution tool',
        uiSurface: 'CI console',
        summary: 'CI/CLI action failed.',
        error: '$error',
        result: 'ci_cli_runner("${spec.action}") failed: $error',
      );
    }
  }

  static _ToolExecution _runWorkflowAutomationTool(
    Map<String, dynamic> arguments,
  ) {
    final objective =
        _stringArg(arguments, const ['objective', 'task', 'goal', 'prompt'])
            ?.trim();
    if (objective == null || objective.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'workflow_automation',
        title: 'Workflow automation',
        uiSurface: 'Automation board',
        summary: 'Workflow automation did not run.',
        error: 'Missing objective.',
        result: 'workflow_automation failed: missing objective.',
      );
    }

    final trigger =
        _stringArg(arguments, const ['trigger', 'schedule', 'event'])?.trim();
    final stepText = _stringArg(arguments, const ['steps', 'actions', 'plan']);
    final actions = _workflowActions(objective, stepText);
    final workflow = {
      'objective': objective,
      'trigger': trigger == null || trigger.isEmpty
          ? 'manual or user-defined trigger'
          : trigger,
      'actions': actions,
      'checks': [
        'Confirm inputs are present before each run',
        'Record outputs, errors, and timestamps',
        'Stop safely when a required tool is unavailable',
      ],
      'approval_points': [
        'Before writing files',
        'Before sending external requests',
        'Before running CI/CLI commands',
      ],
      'failure_handling': {
        'retry': 'retry transient network or tool failures once',
        'fallback': 'return a clear blocked or unavailable result',
        'notification': 'summarize what completed and what needs attention',
      },
    };
    final pretty = const JsonEncoder.withIndent('  ').convert(workflow);

    return _ToolExecution(
      results: ['workflow_automation("$objective") draft:\n$pretty'],
      activities: [
        LocalToolActivity.complete(
          id: 'workflow_automation',
          title: 'Workflow automation',
          summary: 'Drafted a repeatable workflow.',
          uiSurface: 'Automation board',
          steps: [
            'Defined trigger',
            'Created ${actions.length} ordered action(s)',
            'Added checks and failure handling',
          ],
          output: '${actions.length} actions',
        ),
      ],
    );
  }

  static Future<_ToolExecution> _runLocalDocumentSearchTool({
    required String? query,
    required List<String> paths,
  }) async {
    final trimmedQuery = query?.trim();
    if (trimmedQuery == null || trimmedQuery.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'local_document_search',
        title: 'RAG / local document search',
        uiSurface: 'Knowledge sidebar',
        summary: 'Document search did not run.',
        error: 'Missing query.',
        result: 'local_document_search failed: missing query.',
      );
    }

    final roots = paths.isEmpty ? [Directory.current.path] : paths;
    final terms = _queryTerms(trimmedQuery);
    if (terms.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'local_document_search',
        title: 'RAG / local document search',
        uiSurface: 'Knowledge sidebar',
        summary: 'Document search did not run.',
        error: 'Query has no searchable terms.',
        result:
            'local_document_search("$trimmedQuery") failed: query has no searchable terms.',
      );
    }

    final files = await _collectSearchFiles(roots, limit: 260);
    final hits = <_DocumentSearchHit>[];

    for (final file in files) {
      if (hits.length >= 80) break;
      try {
        final size = await file.length();
        if (size > 1024 * 1024) continue;

        final lines = await file.readAsLines();
        var hitsForFile = 0;
        for (var i = 0; i < lines.length && hitsForFile < 3; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          final normalizedLine = line.toLowerCase();
          final score =
              terms.where((term) => normalizedLine.contains(term)).length;
          if (score == 0) continue;

          hits.add(
            _DocumentSearchHit(
              path: file.path,
              lineNumber: i + 1,
              snippet: _clip(line, 240),
              score: score,
            ),
          );
          hitsForFile++;
        }
      } catch (_) {
        continue;
      }
    }

    hits.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      return a.path.compareTo(b.path);
    });

    final topHits = hits.take(8).toList();
    if (topHits.isEmpty) {
      return _ToolExecution(
        results: [
          'local_document_search("$trimmedQuery") searched ${files.length} file(s) under ${roots.join(', ')} and found no matching snippets.',
        ],
        activities: [
          LocalToolActivity.complete(
            id: 'local_document_search',
            title: 'RAG / local document search',
            summary: 'Searched local text files; no matches found.',
            uiSurface: 'Knowledge sidebar',
            steps: [
              'Searched ${files.length} text-like file(s)',
              'Query terms: ${terms.join(', ')}',
              'No matching snippets found',
            ],
            output: '0 matches',
          ),
        ],
      );
    }

    final lines = <String>[
      'local_document_search("$trimmedQuery") searched ${files.length} file(s) under ${roots.join(', ')}:',
    ];
    for (var i = 0; i < topHits.length; i++) {
      final hit = topHits[i];
      lines.add(
        '${i + 1}. ${hit.path}:${hit.lineNumber} - ${hit.snippet}',
      );
    }

    return _ToolExecution(
      results: [lines.join('\n')],
      activities: [
        LocalToolActivity.complete(
          id: 'local_document_search',
          title: 'RAG / local document search',
          summary: 'Searched local text files and returned snippets.',
          uiSurface: 'Knowledge sidebar',
          steps: [
            'Collected ${files.length} searchable file(s)',
            'Matched query terms: ${terms.join(', ')}',
            'Returned ${topHits.length} snippet(s)',
          ],
          output: '${topHits.length} match(es)',
        ),
      ],
    );
  }

  static Future<_ToolExecution> _runCodeExecutorTool({
    required String? language,
    required String? code,
  }) async {
    final trimmedCode = code?.trim();
    if (trimmedCode == null || trimmedCode.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'code_executor',
        title: 'Code executor',
        uiSurface: 'Execution sidebar',
        summary: 'Code execution did not run.',
        error: 'Missing code.',
        result: 'code_executor failed: missing code.',
      );
    }

    final normalizedLanguage = _normalizeCodeLanguage(language, trimmedCode);
    if (normalizedLanguage == null) {
      return _ToolExecution.singleFailure(
        id: 'code_executor',
        title: 'Code executor',
        uiSurface: 'Execution sidebar',
        summary: 'Code execution did not run.',
        error: 'Unsupported or missing language.',
        result:
            'code_executor failed: specify language "python" or "javascript".',
        status: LocalToolStatus.unavailable,
      );
    }

    final safetyIssue = _codeSafetyIssue(normalizedLanguage, trimmedCode);
    if (safetyIssue != null) {
      return _ToolExecution.singleFailure(
        id: 'code_executor',
        title: 'Code executor',
        uiSurface: 'Execution sidebar',
        summary: 'Code execution blocked by safety guard.',
        error: safetyIssue,
        result: 'code_executor("$normalizedLanguage") blocked: $safetyIssue',
        status: LocalToolStatus.unavailable,
      );
    }

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('quick_llm_code_');
      final capture = normalizedLanguage == 'python'
          ? await _runProcessCandidates(
              const [
                _ProcessCandidate('python'),
                _ProcessCandidate('python3'),
                _ProcessCandidate('py', ['-3']),
              ],
              ['-c', trimmedCode],
              workingDirectory: tempDir.path,
              timeout: const Duration(seconds: 5),
            )
          : await _runProcessCandidates(
              const [_ProcessCandidate('node')],
              ['-e', trimmedCode],
              workingDirectory: tempDir.path,
              timeout: const Duration(seconds: 5),
            );

      final stdoutText = _clip(capture.stdout.trim(), 8000);
      final stderrText = _clip(capture.stderr.trim(), 4000);
      final result = [
        'code_executor("$normalizedLanguage") exit_code=${capture.exitCode}${capture.timedOut ? ' timed_out=true' : ''}',
        'stdout:',
        stdoutText.isEmpty ? '[empty]' : stdoutText,
        'stderr:',
        stderrText.isEmpty ? '[empty]' : stderrText,
      ].join('\n');

      if (capture.exitCode != 0 || capture.timedOut) {
        return _ToolExecution.singleFailure(
          id: 'code_executor',
          title: 'Code executor',
          uiSurface: 'Execution sidebar',
          summary:
              capture.timedOut ? 'Code execution timed out.' : 'Code failed.',
          error: capture.timedOut
              ? 'Execution exceeded 5 seconds.'
              : 'Exit code ${capture.exitCode}.',
          result: result,
        );
      }

      return _ToolExecution(
        results: [result],
        activities: [
          LocalToolActivity.complete(
            id: 'code_executor',
            title: 'Code executor',
            summary: 'Executed guarded local code.',
            uiSurface: 'Execution sidebar',
            steps: [
              'Validated $normalizedLanguage snippet',
              'Ran with a 5 second timeout in a temporary directory',
              'Captured stdout and stderr',
            ],
            output: stdoutText.isEmpty ? 'No stdout' : stdoutText,
          ),
        ],
      );
    } on ProcessException catch (error) {
      return _ToolExecution.singleFailure(
        id: 'code_executor',
        title: 'Code executor',
        uiSurface: 'Execution sidebar',
        summary: 'Runtime was not found.',
        error: error.message,
        result:
            'code_executor("$normalizedLanguage") failed: runtime was not found. Install ${normalizedLanguage == 'python' ? 'Python' : 'Node.js'} or choose another tool.',
        status: LocalToolStatus.unavailable,
      );
    } catch (error) {
      return _ToolExecution.singleFailure(
        id: 'code_executor',
        title: 'Code executor',
        uiSurface: 'Execution sidebar',
        summary: 'Code execution failed.',
        error: '$error',
        result: 'code_executor("$normalizedLanguage") failed: $error',
      );
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // Temporary cleanup failure should not hide the tool result.
        }
      }
    }
  }

  static Future<LocalToolContext> contextForPrompt(
    String prompt, {
    String? forcedAction,
  }) async {
    final results = <String>[];
    final activities = <LocalToolActivity>[];
    final routes = _routesForPrompt(prompt);
    final action = forcedAction?.trim().toLowerCase();
    var hasForcedWebPipeline = false;
    var hasForcedShell = false;
    var hasForcedFile = false;

    if (routes.isNotEmpty) {
      final routeSummary = routes
          .map((route) =>
              '${route['tool']} (${route['confidence']}): ${route['reason']}')
          .join('\n');
      results.add('tool_router recommended native tools:\n$routeSummary');
      results.add(_toolQualityBrief(prompt, routes));
      activities.add(
        LocalToolActivity.complete(
          id: 'tool_router',
          title: 'Tool router',
          summary: 'Selected likely native tools before model generation.',
          uiSurface: 'Routing panel',
          steps: const [
            'Scanned the prompt for tool-triggering intent',
            'Matched the request against the available native tool catalog',
            'Ranked the most useful tools for this turn',
          ],
          output: routeSummary,
        ),
      );
    }

    if (_shouldAutoPlan(prompt, routes)) {
      final planner = _runMultiStepPlannerTool(
        task: prompt,
        requestedStepCount: routes.length >= 3 ? 6 : 4,
      );
      results.addAll(planner.results);
      activities.addAll(planner.activities);
    }

    if (action != null && action.isNotEmpty) {
      switch (action) {
        case 'brainstorm':
          results.add(
            'BRAINSTORM_MODE: Generate a diverse, non-obvious set of ideas for the user request. Group them into themes, include practical next actions, and avoid researching unless the user explicitly asks for evidence.',
          );
          activities.add(
            LocalToolActivity.complete(
              id: 'brainstorm',
              title: 'Brainstorm',
              summary: 'Applied the focused ideation workflow.',
              uiSurface: 'Quick action',
              steps: const [
                'Activated divergent ideation mode',
                'Requested grouped, actionable ideas',
              ],
            ),
          );
        case 'web_search':
          final execution = await _runWebSearch(prompt);
          results.addAll(execution.results);
          activities.addAll(execution.activities);
          hasForcedWebPipeline = true;
        case 'deep_research':
          final execution = await _runDeepResearch(prompt);
          results.addAll(execution.results);
          activities.addAll(execution.activities);
          hasForcedWebPipeline = true;
        case 'shell_command_runner':
          final execution = await _executeSafeShellCommand(prompt.trim());
          results.addAll(execution.results);
          activities.addAll(execution.activities);
          hasForcedShell = true;
        case 'file_reader_writer':
          final execution = await _runFileReadTool(prompt);
          results.addAll(execution.results);
          activities.addAll(execution.activities);
          hasForcedFile = true;
        case 'multi_step_planner':
          final execution = _runMultiStepPlannerTool(
            task: prompt,
            requestedStepCount: 6,
          );
          results.addAll(execution.results);
          activities.addAll(execution.activities);
        case 'webpage_reader':
          final execution = await _readRequestedUrls(
            prompt,
            id: 'webpage_reader',
            title: 'Webpage reader',
            resultName: 'webpage_reader',
          );
          results.addAll(execution.results);
          activities.addAll(execution.activities);
          hasForcedWebPipeline = true;
        case 'local_document_search':
          final execution = await _runLocalDocumentSearchTool(
            query: prompt,
            paths: const [],
          );
          results.addAll(execution.results);
          activities.addAll(execution.activities);
        case 'hint':
          results.add(
            'HINT_MODE: Give one concise, specific, immediately useful hint for the user request. Explain why it is useful in one sentence.',
          );
        // Notes and code require structured arguments. Keep the mode visible
        // to the model instead of guessing a key, language, or unsafe command.
        case 'note':
        case 'code_executor':
          results.add(
            'QUICK_ACTION_MODE=$action. Use the matching native tool with concrete arguments from the user request. Do not invent a note key, programming language, or code snippet.',
          );
        default:
          break;
      }
    }

    final expression = _extractExpression(prompt);
    if (expression != null) {
      final value = _ExpressionEvaluator(expression).parse();
      if (value != null && value.isFinite) {
        final formatted = _formatNumber(value);
        results.add('calculator("$expression") = $formatted');
        activities.add(
          LocalToolActivity.complete(
            id: 'calculator',
            title: 'Calculator',
            summary: 'Computed arithmetic before model generation.',
            uiSurface: 'Inline result',
            steps: const [
              'Extracted expression',
              'Evaluated locally',
              'Injected numeric result',
            ],
            output: formatted,
          ),
        );
      }
    }

    if (!hasForcedWebPipeline) {
      if (_looksLikeWebReaderRequest(prompt)) {
        final execution = await _readRequestedUrls(prompt);
        results.addAll(execution.results);
        activities.addAll(execution.activities);
      }

      if (_looksLikeDateTimeRequest(prompt)) {
        final dayOffset = _dateOffsetForPrompt(prompt);
        final execution = _runDateTimeTool({
          'action': _dateTimeActionForPrompt(prompt),
          if (dayOffset != null) 'days': dayOffset,
        });
        results.addAll(execution.results);
        activities.addAll(execution.activities);
      } else if (shouldRunLiveWebSearch(prompt)) {
        final execution = await _runWebSearch(prompt);
        results.addAll(execution.results);
        activities.addAll(execution.activities);
      }
    }

    if (_looksLikeNoteRequest(prompt)) {
      final execution = await _runNoteTool(prompt);
      results.addAll(execution.results);
      activities.addAll(execution.activities);
    }

    if (!hasForcedFile && _looksLikeFileReadRequest(prompt)) {
      final execution = await _runFileReadTool(prompt);
      results.addAll(execution.results);
      activities.addAll(execution.activities);
    }

    if (!hasForcedShell && _looksLikeShellRequest(prompt)) {
      final execution = await _runShellTool(prompt);
      results.addAll(execution.results);
      activities.addAll(execution.activities);
    }

    activities.addAll(_unavailableToolWarnings(prompt));

    if (_looksLikeSketchRequest(prompt)) {
      results.add(
        'svg_sketch is available for this explicit drawing request. Return a fenced ```svg block with a complete <svg> element.',
      );
      activities.add(
        LocalToolActivity.ready(
          id: 'svg_sketch',
          title: 'SVG sketch',
          summary: 'SVG preview is enabled for this drawing request.',
          uiSurface: 'Inline preview',
          steps: const [
            'Detected explicit visual request',
            'Will render fenced SVG blocks',
          ],
        ),
      );
    }

    return LocalToolContext(results, activities: activities);
  }

  static String composePrompt(String prompt, LocalToolContext context) {
    if (!context.hasResults) return prompt;

    return [
      'Local tool results:',
      ...context.results.map((result) => '- $result'),
      '',
      'Rules for these results:',
      '- Treat supplied live prices/search results as the only current-data source.',
      '- If a requested tool reports unavailable or failed, say that plainly and do not fabricate output.',
      '- Use the route-specific quality guidance above to make tool calls detailed, chained, and validated.',
      '- Do not use svg_sketch unless the user explicitly asked for a drawing/diagram/SVG.',
      '',
      'User message:',
      prompt,
    ].join('\n');
  }

  static Future<_ToolExecution> _runWebSearch(String prompt) async {
    final search = await _fetchDuckDuckGoSearch(_searchQueryForPrompt(prompt));
    if (search.hasCompletedActivity) return search;

    final cryptoSymbols = _cryptoSymbolsForPrompt(prompt);
    if (cryptoSymbols.isNotEmpty) {
      final market = await _fetchCryptoPrices(cryptoSymbols);
      if (market != null) return market;
    }

    return search;
  }

  /// Builds a citation-ready evidence pack instead of relying on a single
  /// search snippet. Kept native so it works even with models that do not
  /// reliably chain function calls themselves.
  static Future<_ToolExecution> _runDeepResearch(String topic) async {
    final subject = topic.trim();
    if (subject.isEmpty) {
      return _ToolExecution.singleFailure(
        id: 'deep_research',
        title: 'Deep research',
        uiSurface: 'Research sidebar',
        summary: 'Research did not run.',
        error: 'Missing research topic.',
        result: 'deep_research failed: missing topic. Do not invent research.',
      );
    }

    final queries = deepResearchQueryPlan(subject);
    final results = <String>[
      'DEEP_RESEARCH_EVIDENCE_PACK for "$subject".',
      'Final-answer requirements: provide a concise answer first; cite factual claims inline with source title and URL; separate sourced facts, reasonable inferences, and unresolved or conflicting evidence; do not cite a source that is not present below.',
      'Research plan: ${queries.asMap().entries.map((entry) => '${entry.key + 1}. ${entry.value}').join(' | ')}',
    ];
    final activities = <LocalToolActivity>[];
    final searches = <_ToolExecution>[];

    // Sequential requests are friendlier to public search endpoints and give
    // us a stable activity order in the research sidebar.
    for (final query in queries) {
      final execution = await _fetchDuckDuckGoSearch(query);
      searches.add(execution);
      results.addAll(execution.results);
      activities.addAll(execution.activities);
    }

    final sources = <LocalToolSource>[];
    for (final execution in searches) {
      for (final activity in execution.activities) {
        sources.addAll(activity.sources);
      }
    }
    final selectedUrls = _selectResearchSourceUrls(sources, maxCount: 3);
    final pages = <_ToolExecution>[];
    for (final url in selectedUrls) {
      final page = await _readRequestedUrls(
        url,
        id: 'deep_research_reader',
        title: 'Research source reader',
        resultName: 'deep_research_reader',
      );
      pages.add(page);
      results.addAll(page.results);
      activities.addAll(page.activities);
    }

    final citedSources = <LocalToolSource>[];
    final seenSources = <String>{};
    for (final source in sources) {
      if (seenSources.add(source.url)) citedSources.add(source);
    }
    for (final page in pages) {
      for (final activity in page.activities) {
        for (final source in activity.sources) {
          if (seenSources.add(source.url)) citedSources.add(source);
        }
      }
    }

    final successfulSearches =
        searches.where((execution) => execution.hasCompletedActivity).length;
    final successfulPages =
        pages.where((execution) => execution.hasCompletedActivity).length;
    activities.insert(
      0,
      LocalToolActivity.complete(
        id: 'deep_research',
        title: 'Deep research',
        summary: 'Built a multi-query, multi-source evidence pack.',
        uiSurface: 'Research sidebar',
        steps: [
          'Planned ${queries.length} focused search queries',
          'Completed $successfulSearches/${queries.length} search passes',
          'Selected ${selectedUrls.length} distinct source page(s)',
          'Read $successfulPages/${selectedUrls.length} source page(s)',
          'Attached citation and evidence requirements for synthesis',
        ],
        output:
            '${queries.length} queries, $successfulSearches searches, $successfulPages pages, ${citedSources.length} sources',
        sources: citedSources.take(12).toList(),
      ),
    );

    if (citedSources.isEmpty) {
      results.add(
        'Deep research could not retrieve a usable source. State that live research was unavailable instead of presenting unsupported claims.',
      );
    } else {
      results.add(
        'Citation catalog:\n${citedSources.take(12).map((source) => '- ${source.title}: ${source.url}').join('\n')}',
      );
    }

    return _ToolExecution(results: results, activities: activities);
  }

  /// The stable query plan used by native and model-invoked Deep Research.
  static List<String> deepResearchQueryPlan(String topic) {
    final base = _searchQueryForPrompt(topic).trim();
    final query = base.isEmpty ? topic : base;
    final candidates = [
      query,
      '$query primary sources official documentation',
      '$query independent analysis evidence perspectives',
    ];
    final unique = <String>[];
    final normalized = <String>{};
    for (final candidate in candidates) {
      final compact = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.isEmpty || !normalized.add(compact.toLowerCase())) continue;
      unique.add(compact.length > 240 ? compact.substring(0, 240) : compact);
    }
    return unique;
  }

  static List<String> _selectResearchSourceUrls(
    List<LocalToolSource> sources, {
    required int maxCount,
  }) {
    final selected = <String>[];
    final seenUrls = <String>{};
    final seenHosts = <String>{};

    void select(LocalToolSource source, {required bool requireNewHost}) {
      final uri = Uri.tryParse(source.url);
      if (uri == null ||
          !(uri.scheme == 'https' || uri.scheme == 'http') ||
          uri.host.isEmpty ||
          selected.length >= maxCount ||
          seenUrls.contains(source.url) ||
          (requireNewHost && seenHosts.contains(uri.host.toLowerCase()))) {
        return;
      }
      seenUrls.add(source.url);
      seenHosts.add(uri.host.toLowerCase());
      selected.add(source.url);
    }

    for (final source in sources) {
      select(source, requireNewHost: true);
    }
    for (final source in sources) {
      select(source, requireNewHost: false);
    }
    return selected;
  }

  static Future<_ToolExecution?> _fetchCryptoPrices(
    List<_CryptoAsset> assets,
  ) async {
    final ids = assets.map((asset) => asset.coingeckoId).toSet().join(',');
    final url = Uri.https('api.coingecko.com', '/api/v3/simple/price', {
      'ids': ids,
      'vs_currencies': 'usd',
      'include_24hr_change': 'true',
      'include_last_updated_at': 'true',
    });

    try {
      final response = await http.get(url, headers: const {
        'accept': 'application/json'
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final fallback = await _fetchCoinbaseSpotPrices(
          assets,
          'CoinGecko returned HTTP ${response.statusCode}.',
        );
        if (fallback != null) return fallback;

        return _ToolExecution.singleFailure(
          id: 'web_search',
          title: 'Web search',
          uiSurface: 'Search sidebar',
          summary: 'Live crypto price request failed.',
          error: 'CoinGecko returned HTTP ${response.statusCode}.',
          result:
              'web_search failed for crypto price: CoinGecko returned HTTP ${response.statusCode}. Do not invent a price.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final fetchedAt = DateTime.now().toUtc();
      final lines = <String>[
        'web_search live market result from CoinGecko (${url.toString()}) fetched_at=${fetchedAt.toIso8601String()}',
      ];
      final steps = <String>[
        'Requested CoinGecko simple price API',
        'Parsed USD price and 24h change',
      ];
      final outputParts = <String>[];

      for (final asset in assets) {
        final value = decoded[asset.coingeckoId];
        if (value is! Map<String, dynamic>) continue;
        final usd = _asDouble(value['usd']);
        final change = _asDouble(value['usd_24h_change']);
        final updatedAt = _asInt(value['last_updated_at']);
        if (usd == null) continue;

        final updatedText = updatedAt == null
            ? 'unknown update time'
            : DateTime.fromMillisecondsSinceEpoch(updatedAt * 1000, isUtc: true)
                .toIso8601String();
        final changeText = change == null
            ? '24h change unavailable'
            : '${change.toStringAsFixed(2)}% 24h';
        final priceText = '\$${_formatCurrency(usd)}';
        lines.add(
          '${asset.symbol}/USD = $priceText; $changeText; last_updated=$updatedText; source=CoinGecko',
        );
        outputParts.add('${asset.symbol}: $priceText');
      }

      if (outputParts.isEmpty) return null;
      steps.add('Injected ${outputParts.join(', ')} into prompt');

      return _ToolExecution(
        results: [lines.join('\n')],
        activities: [
          LocalToolActivity.complete(
            id: 'web_search',
            title: 'Web search',
            summary: 'Fetched live crypto market data.',
            uiSurface: 'Search sidebar',
            steps: steps,
            output: outputParts.join(', '),
            sources: [
              LocalToolSource(
                title: 'CoinGecko simple price API',
                url: url.toString(),
              ),
            ],
          ),
        ],
      );
    } on TimeoutException {
      final fallback = await _fetchCoinbaseSpotPrices(
        assets,
        'CoinGecko request timed out.',
      );
      if (fallback != null) return fallback;

      return _ToolExecution.singleFailure(
        id: 'web_search',
        title: 'Web search',
        uiSurface: 'Search sidebar',
        summary: 'Live crypto price request timed out.',
        error: 'CoinGecko request timed out.',
        result:
            'web_search failed for crypto price: request timed out. Do not invent a price.',
      );
    } catch (error) {
      final fallback = await _fetchCoinbaseSpotPrices(
        assets,
        'CoinGecko failed: $error',
      );
      if (fallback != null) return fallback;

      return _ToolExecution.singleFailure(
        id: 'web_search',
        title: 'Web search',
        uiSurface: 'Search sidebar',
        summary: 'Live crypto price request failed.',
        error: '$error',
        result:
            'web_search failed for crypto price: $error. Do not invent a price.',
      );
    }
  }

  static Future<_ToolExecution?> _fetchCoinbaseSpotPrices(
    List<_CryptoAsset> assets,
    String fallbackReason,
  ) async {
    final fetchedAt = DateTime.now().toUtc();
    final lines = <String>[
      'web_search live market fallback from Coinbase fetched_at=${fetchedAt.toIso8601String()} fallback_reason=$fallbackReason',
    ];
    final outputParts = <String>[];
    final sources = <LocalToolSource>[];

    for (final asset in assets) {
      final url = Uri.https(
        'api.coinbase.com',
        '/v2/prices/${asset.symbol}-USD/spot',
      );

      try {
        final response = await http.get(url, headers: const {
          'accept': 'application/json'
        }).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) continue;

        final data = decoded['data'];
        if (data is! Map<String, dynamic>) continue;

        final amount = _asDouble(data['amount']);
        if (amount == null) continue;

        final priceText = '\$${_formatCurrency(amount)}';
        lines.add(
          '${asset.symbol}/USD = $priceText; last_updated=fetched_at; source=Coinbase spot price',
        );
        outputParts.add('${asset.symbol}: $priceText');
        sources.add(
          LocalToolSource(
            title: 'Coinbase ${asset.symbol}-USD spot price',
            url: url.toString(),
          ),
        );
      } catch (_) {
        continue;
      }
    }

    if (outputParts.isEmpty) return null;

    return _ToolExecution(
      results: [lines.join('\n')],
      activities: [
        LocalToolActivity.complete(
          id: 'web_search',
          title: 'Web search',
          summary: 'Fetched live crypto market data from fallback source.',
          uiSurface: 'Search sidebar',
          steps: [
            fallbackReason,
            'Queried Coinbase spot price API',
            'Injected ${outputParts.join(', ')} into prompt',
          ],
          output: outputParts.join(', '),
          sources: sources,
        ),
      ],
    );
  }

  static Future<_ToolExecution> _fetchDuckDuckGoSearch(String query) async {
    final safeQuery = query.trim().isEmpty ? 'current news' : query.trim();
    final attempts = <String>[];
    final providerFetches = [
      _SearchProviderFetch(
        name: 'DuckDuckGo Lite',
        url: Uri.https('lite.duckduckgo.com', '/lite/', {'q': safeQuery}),
        parser: _parseDuckDuckGoHtmlResults,
      ),
      _SearchProviderFetch(
        name: 'DuckDuckGo HTML',
        url: Uri.https('duckduckgo.com', '/html/', {'q': safeQuery}),
        parser: _parseDuckDuckGoHtmlResults,
      ),
      _SearchProviderFetch(
        name: 'Bing',
        url: Uri.https('www.bing.com', '/search', {'q': safeQuery}),
        parser: _parseBingHtmlResults,
      ),
    ];

    for (final provider in providerFetches) {
      try {
        final response = await http
            .get(provider.url, headers: _browserHeaders)
            .timeout(const Duration(seconds: 12));
        attempts.add('${provider.name}: HTTP ${response.statusCode}');

        if (response.statusCode != 200) continue;

        final results = provider.parser(response.body).take(6).toList();
        attempts[attempts.length - 1] =
            '${provider.name}: HTTP ${response.statusCode}, ${results.length} parsed result(s)';
        if (results.isEmpty) continue;

        final fetchedAt = DateTime.now().toUtc().toIso8601String();
        final lines = <String>[
          'web_search("$safeQuery") live search results from ${provider.name} fetched_at=$fetchedAt',
        ];
        for (var i = 0; i < results.length; i++) {
          final result = results[i];
          lines.add(
            '${i + 1}. ${result.title} - ${result.snippet} (${result.url})',
          );
        }

        return _ToolExecution(
          results: [lines.join('\n')],
          activities: [
            LocalToolActivity.complete(
              id: 'web_search',
              title: 'Web search',
              summary: 'Fetched live web search results.',
              uiSurface: 'Search sidebar',
              steps: [
                'Queried ${provider.name} for "$safeQuery"',
                'Parsed ${results.length} organic result snippets',
                'Injected source URLs into prompt',
              ],
              output: '${results.length} result(s)',
              sources: results
                  .map((result) => LocalToolSource(
                        title: result.title,
                        url: result.url,
                      ))
                  .toList(),
            ),
          ],
        );
      } on TimeoutException {
        attempts.add('${provider.name}: timed out');
      } catch (error) {
        attempts.add('${provider.name}: $error');
      }
    }

    final attemptText =
        attempts.isEmpty ? 'no providers attempted' : attempts.join('; ');
    return _ToolExecution.singleFailure(
      id: 'web_search',
      title: 'Web search',
      uiSurface: 'Search sidebar',
      summary: 'Search providers returned no parsed results.',
      error: attemptText,
      result:
          'web_search("$safeQuery") failed: no usable organic search results were parsed. Provider attempts: $attemptText. Do not invent search results.',
    );
  }

  static Future<_ToolExecution> _readRequestedUrls(
    String prompt, {
    String id = 'web_scraper_reader',
    String title = 'Web scraper/reader',
    String resultName = 'web_scraper_reader',
  }) async {
    final urls = _urlsForPrompt(prompt).take(2).toList();
    if (urls.isEmpty) return const _ToolExecution();

    final results = <String>[];
    final activities = <LocalToolActivity>[];

    for (final urlText in urls) {
      final uri = Uri.tryParse(urlText);
      if (uri == null || !uri.hasScheme) continue;

      try {
        final response =
            await http.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          results.add(
            '$resultName("$urlText") failed: HTTP ${response.statusCode}. Do not invent page contents.',
          );
          activities.add(
            LocalToolActivity.failed(
              id: id,
              title: title,
              summary: 'URL fetch failed.',
              uiSurface: 'Reader sidebar',
              error: 'HTTP ${response.statusCode}',
              steps: [
                'Fetched $urlText',
                'Server returned HTTP ${response.statusCode}'
              ],
            ),
          );
          continue;
        }

        final text = _stripHtml(response.body);
        final clipped = _clip(text, 6000);
        results.add(
          '$resultName("$urlText") fetched ${text.length} text characters:\n$clipped',
        );
        activities.add(
          LocalToolActivity.complete(
            id: id,
            title: title,
            summary: 'Fetched and cleaned URL text.',
            uiSurface: 'Reader sidebar',
            steps: [
              'Fetched $urlText',
              'Removed scripts, styles, and HTML tags',
              'Injected ${clipped.length} characters',
            ],
            output: '${text.length} characters',
            sources: [LocalToolSource(title: urlText, url: urlText)],
          ),
        );
      } catch (error) {
        results.add(
          '$resultName("$urlText") failed: $error. Do not invent page contents.',
        );
        activities.add(
          LocalToolActivity.failed(
            id: id,
            title: title,
            summary: 'URL fetch failed.',
            uiSurface: 'Reader sidebar',
            error: '$error',
            steps: ['Tried to fetch $urlText'],
          ),
        );
      }
    }

    return _ToolExecution(results: results, activities: activities);
  }

  static Future<_ToolExecution> _runNoteTool(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    final saveMatch = RegExp(
      r"""note_save\(\s*["']([^"']+)["']\s*,\s*["']([\s\S]*?)["']\s*\)""",
      caseSensitive: false,
    ).firstMatch(prompt);
    final getMatch = RegExp(
      r"""note_get\(\s*["']([^"']+)["']\s*\)""",
      caseSensitive: false,
    ).firstMatch(prompt);

    if (saveMatch != null) {
      final key = saveMatch.group(1)!.trim();
      final value = saveMatch.group(2)!.trim();
      await prefs.setString(_noteStorageKey(key), value);
      return _ToolExecution(
        results: ['note_save("$key") completed.'],
        activities: [
          LocalToolActivity.complete(
            id: 'note_saver',
            title: 'Note saver',
            summary: 'Saved note across sessions.',
            uiSurface: 'Memory drawer',
            steps: ['Stored key "$key" in local preferences'],
            output: key,
          ),
        ],
      );
    }

    if (getMatch != null) {
      final key = getMatch.group(1)!.trim();
      final value = prefs.getString(_noteStorageKey(key));
      return _ToolExecution(
        results: [
          value == null
              ? 'note_get("$key") returned no saved note.'
              : 'note_get("$key") = $value',
        ],
        activities: [
          LocalToolActivity.complete(
            id: 'note_saver',
            title: 'Note saver',
            summary: value == null ? 'No note found.' : 'Retrieved saved note.',
            uiSurface: 'Memory drawer',
            steps: ['Looked up key "$key" in local preferences'],
            output: value == null ? 'No note found' : key,
          ),
        ],
      );
    }

    return const _ToolExecution();
  }

  static Future<_ToolExecution> _runFileReadTool(String prompt) async {
    final path = _quotedPathForPrompt(prompt);
    if (path == null) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File tool did not run.',
        error: 'No quoted local path was found.',
        result:
            'file_reader_writer did not run: provide a quoted local file path or attach the file. Do not invent file contents.',
        status: LocalToolStatus.unavailable,
      );
    }

    return _readFileAtPath(path);
  }

  static Future<_ToolExecution> _readFileAtPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File was not found.',
        error: 'File not found: $path',
        result:
            'file_reader_writer("$path") failed: file not found. Do not invent file contents.',
      );
    }

    try {
      final content = await file.readAsString();
      final clipped = _clip(content, 10000);
      return _ToolExecution(
        results: [
          'file_reader_writer("$path") read ${content.length} characters:\n$clipped',
        ],
        activities: [
          LocalToolActivity.complete(
            id: 'file_reader_writer',
            title: 'File reader/writer',
            summary: 'Read local text file.',
            uiSurface: 'File activity rail',
            steps: [
              'Opened $path',
              'Read ${content.length} characters',
              'Injected ${clipped.length} characters',
            ],
            output: '${content.length} characters',
          ),
        ],
      );
    } catch (error) {
      return _ToolExecution.singleFailure(
        id: 'file_reader_writer',
        title: 'File reader/writer',
        uiSurface: 'File activity rail',
        summary: 'File read failed.',
        error: '$error',
        result:
            'file_reader_writer("$path") failed: $error. Do not invent file contents.',
      );
    }
  }

  static Future<_ToolExecution> _runShellTool(String prompt) async {
    final command = _shellCommandForPrompt(prompt);
    if (command == null) {
      return _ToolExecution.singleFailure(
        id: 'shell_command_runner',
        title: 'Shell command runner',
        uiSurface: 'Terminal sidebar',
        summary: 'Shell tool did not run.',
        error: 'No explicit shell command found.',
        result:
            'shell_command_runner did not run: provide an explicit command after "shell:" or "run command:". Do not invent stdout.',
        status: LocalToolStatus.unavailable,
      );
    }

    return _executeSafeShellCommand(command);
  }

  static Future<_ToolExecution> _executeSafeShellCommand(String command) async {
    final parts = _splitCommand(command);
    if (parts.isEmpty) return const _ToolExecution();
    final op = parts.first.toLowerCase();
    if (!const ['ls', 'dir', 'cat', 'type', 'grep'].contains(op)) {
      return _ToolExecution.singleFailure(
        id: 'shell_command_runner',
        title: 'Shell command runner',
        uiSurface: 'Terminal sidebar',
        summary: 'Command blocked by whitelist.',
        error: 'Blocked command: $op',
        result:
            'shell_command_runner("$command") blocked: only ls, dir, cat, type, and grep are allowed. Do not invent stdout.',
        status: LocalToolStatus.unavailable,
      );
    }

    try {
      final output = await _runSafeCommand(parts);
      return _ToolExecution(
        results: ['shell_command_runner("$command") stdout:\n$output'],
        activities: [
          LocalToolActivity.complete(
            id: 'shell_command_runner',
            title: 'Shell command runner',
            summary: 'Executed whitelisted local command.',
            uiSurface: 'Terminal sidebar',
            steps: [
              'Validated command "$op"',
              'Executed without a shell',
              'Captured stdout',
            ],
            output: _clip(output, 500),
          ),
        ],
      );
    } catch (error) {
      return _ToolExecution.singleFailure(
        id: 'shell_command_runner',
        title: 'Shell command runner',
        uiSurface: 'Terminal sidebar',
        summary: 'Command failed.',
        error: '$error',
        result:
            'shell_command_runner("$command") failed: $error. Do not invent stdout.',
      );
    }
  }

  static Future<String> _runSafeCommand(List<String> parts) async {
    final op = parts.first.toLowerCase();
    if (op == 'ls' || op == 'dir') {
      final path = parts.length > 1 ? parts[1] : Directory.current.path;
      final dir = Directory(path);
      final entries = await dir
          .list(followLinks: false)
          .take(120)
          .map((entity) => entity.path)
          .toList();
      return entries.join('\n');
    }

    if (op == 'cat' || op == 'type') {
      if (parts.length < 2) throw const FormatException('Missing file path');
      return _clip(await File(parts[1]).readAsString(), 12000);
    }

    if (op == 'grep') {
      if (parts.length < 3) {
        throw const FormatException('Usage: grep pattern file');
      }
      final pattern = parts[1].toLowerCase();
      final lines = await File(parts[2]).readAsLines();
      return lines
          .asMap()
          .entries
          .where((entry) => entry.value.toLowerCase().contains(pattern))
          .take(80)
          .map((entry) => '${entry.key + 1}: ${entry.value}')
          .join('\n');
    }

    throw FormatException('Unsupported command: $op');
  }

  static String _toolTitle(String id) {
    switch (id) {
      case 'mind_map_tool':
        return 'Mind map tool';
      case 'mind_map_generator':
        return 'Mind map generator';
      default:
        return id
            .split('_')
            .map((part) => part.isEmpty
                ? part
                : '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
    }
  }

  static List<Map<String, dynamic>> _routesForPrompt(String request) {
    final normalized = request.toLowerCase();
    final routes = <Map<String, dynamic>>[];

    void add(String tool, String reason, double confidence) {
      if (routes.any((route) => route['tool'] == tool)) return;
      routes.add({
        'tool': tool,
        'reason': reason,
        'confidence': double.parse(confidence.toStringAsFixed(2)),
      });
    }

    if (_urlsForPrompt(request).isNotEmpty &&
        RegExp(r'\b(read|summarize|analyze|scrape|fetch|article|page|url|link)\b')
            .hasMatch(normalized)) {
      add('webpage_reader', 'A specific URL should be read directly.', 0.95);
    }
    if (_looksLikeDateTimeRequest(request)) {
      add('date_time', 'The request needs the local device clock.', 0.98);
    }
    if (shouldRunLiveWebSearch(request) && _urlsForPrompt(request).isEmpty) {
      add('web_search', 'The request needs current or live web information.',
          0.92);
    }
    if (_extractExpression(request) != null) {
      add('calculator', 'The request contains deterministic arithmetic.', 0.9);
    }
    if (RegExp(
            r'\b(simulat|scenario|forecast|projection|what[- ]if|sensitivity)\b')
        .hasMatch(normalized)) {
      add('simulation_tool',
          'The request asks for scenarios, forecasts, or what-if math.', 0.9);
    }
    if (RegExp(r'\b(mind ?map|brainstorm map|idea map|map these ideas)\b')
        .hasMatch(normalized)) {
      add('mind_map_generator',
          'The request asks to organize ideas as a mind map.', 0.88);
    }
    if (RegExp(r'\b(chart|graph|diagram|flowchart|mermaid|svg|visuali[sz]e)\b')
        .hasMatch(normalized)) {
      add(
          'chart_diagram_generator',
          'The request asks for a chart, diagram, SVG, or Mermaid output.',
          0.86);
    }
    if (RegExp(r'\b(save as pdf|export as pdf|create pdf|make pdf|\.pdf)\b')
        .hasMatch(normalized)) {
      add('pdf_document_generator',
          'The request asks to create, save, or export a PDF artifact.', 0.91);
    }
    if (RegExp(
            r'\b(pdf|document|report|brief|proposal|memo|write[- ]?up|template|documentation)\b')
        .hasMatch(normalized)) {
      add('document_generator',
          'The request asks to generate a reusable document artifact.', 0.84);
    }
    if (RegExp(
            r'\b(ci|cli|test|tests|analy[sz]e|format check|format|pub get|pub outdated|pub deps|doctor|flutter test|dart test|flutter analyze|dart analyze)\b')
        .hasMatch(normalized)) {
      add(
          'ci_cli_runner',
          'The request asks to run a supported local verification command.',
          0.82);
    }
    if (RegExp(
            r'\b(automation|workflow|recurring|trigger|pipeline|repeatable)\b')
        .hasMatch(normalized)) {
      add('workflow_automation',
          'The request asks to create a repeatable workflow.', 0.8);
    }
    if (RegExp(
            r'\b(search my local documents|local document|rag|find in files)\b')
        .hasMatch(normalized)) {
      add('local_document_search',
          'The request asks for local text or document lookup.', 0.78);
    }
    if (_looksLikeFileReadRequest(request)) {
      add('file_reader_writer',
          'The request explicitly references a local file operation.', 0.76);
    }
    if (_looksLikeShellRequest(request)) {
      add('shell_command_runner',
          'The request explicitly asks for a shell command.', 0.74);
    }
    if (RegExp(r'\b(run code|execute code|python|javascript|js snippet)\b')
        .hasMatch(normalized)) {
      add('code_executor',
          'The request asks to execute a short guarded code snippet.', 0.72);
    }

    routes.sort((a, b) =>
        (b['confidence'] as double).compareTo(a['confidence'] as double));
    return routes.take(5).toList();
  }

  static String _toolQualityBrief(
    String request,
    List<Map<String, dynamic>> routes,
  ) {
    final gates = _qualityGatesForRoutes(request, routes);
    if (gates.isEmpty) {
      return 'tool_quality_gate: answer directly unless a native tool can materially improve accuracy, structure, calculation, currentness, or artifact quality.';
    }

    return [
      'tool_quality_gate:',
      ...gates.map((gate) => '- $gate'),
    ].join('\n');
  }

  static List<String> _toolChainStrategy(List<Map<String, dynamic>> routes) {
    final tools = routes.map((route) => route['tool'].toString()).toList();
    if (tools.isEmpty) return const ['answer_directly'];

    final strategy = <String>[];
    if (tools.length > 1) {
      strategy.add('call tool_router first to confirm the execution order');
    }
    if (tools.length > 2 || tools.contains('document_generator')) {
      strategy.add('call multi_step_planner before producing artifacts');
    }
    strategy.addAll(tools.map((tool) => 'run $tool with specific parameters'));
    strategy.add('validate the result before the final answer');
    return strategy;
  }

  static List<String> _qualityGatesForRoutes(
    String request,
    List<Map<String, dynamic>> routes,
  ) {
    final tools = routes.map((route) => route['tool']).toSet();
    final gates = <String>[];
    if (tools.length > 1) {
      gates.add(
          'Chain selected tools so each output feeds the next step; do not stop after the first partial result.');
    }
    if (tools.contains('web_search')) {
      gates.add(
          'Use targeted current-data searches and synthesize across returned source snippets with URLs.');
    }
    if (tools.contains('webpage_reader')) {
      gates.add(
          'Ground webpage claims in fetched page text and preserve the source URL.');
    }
    if (tools.contains('simulation_tool')) {
      gates.add(
          'Pass numeric assumptions, horizon, volatility or sensitivity, target threshold when relevant, and at least 10000 iterations.');
    }
    if (tools.contains('chart_diagram_generator')) {
      gates.add(
          'For diagrams, include full scope, meaningful node labels, typed edges, and grouped/error paths when relevant.');
    }
    if (tools.contains('mind_map_generator')) {
      gates.add(
          'For mind maps, request at least three levels of depth with concrete branch and leaf labels.');
    }
    if (tools.contains('document_generator') ||
        tools.contains('pdf_document_generator')) {
      gates.add(
          'Documents should have an executive summary, organized sections, recommendations, and tables for numeric claims.');
    }
    if (tools.contains('ci_cli_runner')) {
      gates.add(
          'CLI results must report command, exit code, key stdout/stderr, and any remaining risk.');
    }
    if (tools.contains('workflow_automation')) {
      gates.add(
          'Automation plans need trigger, ordered actions, checks, approvals, retry/failure paths, and clear stop conditions.');
    }
    if (request.toLowerCase().contains('advanced') ||
        request.toLowerCase().contains('complex')) {
      gates.add(
          'The user explicitly asked for advanced/complex tool use, so prefer richer parameters and validation over minimal examples.');
    }
    return gates;
  }

  static bool _shouldAutoPlan(
    String request,
    List<Map<String, dynamic>> routes,
  ) {
    final normalized = request.toLowerCase();
    if (RegExp(
      r'\b(plan|roadmap|strategy|break ?down|step[- ]by[- ]step|workflow|execute|project)\b',
    ).hasMatch(normalized)) {
      return true;
    }
    if (routes.length >= 3) return true;
    if (routes.length >= 2 &&
        RegExp(r'\b(then|and then|combine|turn .* into|after that)\b')
            .hasMatch(normalized)) {
      return true;
    }
    return false;
  }

  static List<Map<String, dynamic>> _buildPlannerSteps(
    String task,
    int stepCount,
    List<Map<String, dynamic>> routes,
  ) {
    final subject = _planSubject(task);
    final routeTools = routes.map((route) => route['tool'].toString()).toList();
    final candidates = <Map<String, dynamic>>[
      {
        'title': 'Pin down the $subject outcome',
        'description':
            'Translate "$task" into a concrete deliverable, explicit constraints, and a definition of done.',
        'tool_hints': const ['tool_router'],
        'dependencies': const [],
        'deliverable': _planDeliverable(task),
        'acceptance_check':
            'The final output format, audience, and success criteria are unambiguous.',
      },
      {
        'title': routeTools.isEmpty
            ? 'Choose the response path'
            : 'Route work through ${routeTools.take(3).join(', ')}',
        'description': routeTools.isEmpty
            ? 'Decide whether this should be answered directly or broken into smaller subtasks.'
            : 'Sequence the needed tools so each result feeds the next step instead of producing disconnected outputs.',
        'tool_hints': routeTools.isEmpty ? const ['tool_router'] : routeTools,
        'dependencies': const [1],
        'deliverable': 'Ordered execution route',
        'acceptance_check':
            'Every selected tool has a reason and a clear handoff into the next action.',
      },
    ];

    for (final route in routes) {
      candidates.add(_plannerStepForTool(
        route['tool'].toString(),
        task,
        candidates.length + 1,
      ));
    }

    candidates.addAll([
      {
        'title': 'Integrate intermediate results',
        'description':
            'Merge tool outputs into one coherent answer, resolving conflicts and preserving source or artifact context.',
        'tool_hints': routeTools.isEmpty ? const [] : routeTools,
        'dependencies': [
          for (var i = 1; i <= math.max(2, candidates.length); i++) i,
        ],
        'deliverable': 'Unified working answer',
        'acceptance_check':
            'No tool result is ignored, duplicated, or contradicted without explanation.',
      },
      {
        'title': 'Verify the $subject result',
        'description':
            'Check the output against the original request, run available validation, and inspect visual artifacts when present.',
        'tool_hints': routeTools.contains('ci_cli_runner')
            ? const ['ci_cli_runner']
            : const [],
        'dependencies': [candidates.length],
        'deliverable': 'Verification notes',
        'acceptance_check':
            'The answer is accurate, complete, and any unavailable tool or remaining risk is called out plainly.',
      },
      {
        'title': 'Deliver the final response',
        'description':
            'Present the result in the requested format with concise context, previews or file paths when generated, and next actions only if useful.',
        'tool_hints': const [],
        'dependencies': [candidates.length + 1],
        'deliverable': 'Final user-facing response',
        'acceptance_check':
            'The response can be acted on immediately without reading raw tool logs.',
      },
    ]);

    final selected = candidates.take(stepCount).toList();
    return selected.asMap().entries.map((entry) {
      final index = entry.key + 1;
      return {
        'id': index,
        'status': index == 1 ? 'in_progress' : 'pending',
        ...entry.value,
      };
    }).toList();
  }

  static Map<String, dynamic> _plannerStepForTool(
    String tool,
    String task,
    int candidateIndex,
  ) {
    switch (tool) {
      case 'webpage_reader':
        return {
          'title': 'Read the supplied webpage',
          'description':
              'Fetch the URL, strip noise, and extract the page facts needed for "$task".',
          'tool_hints': const ['webpage_reader'],
          'dependencies': const [2],
          'deliverable': 'Clean webpage context',
          'acceptance_check':
              'The page content is quoted or summarized only from the fetched URL.',
        };
      case 'web_search':
        return {
          'title': 'Collect current external context',
          'description':
              'Search live sources for current facts, compare result snippets, and keep source URLs attached.',
          'tool_hints': const ['web_search'],
          'dependencies': const [2],
          'deliverable': 'Current sourced findings',
          'acceptance_check':
              'Recent or live claims are tied to returned search results.',
        };
      case 'mind_map_generator':
        return {
          'title': 'Generate the mind map artifact',
          'description':
              'Turn the core ideas into structured nodes plus a rendered SVG preview with clear branches and arrows.',
          'tool_hints': const ['mind_map_generator'],
          'dependencies': const [2],
          'deliverable': 'Renderable mind map',
          'acceptance_check':
              'The preview shows the central idea, branch labels, and visible connectors.',
        };
      case 'chart_diagram_generator':
        return {
          'title': 'Build the visual diagram',
          'description':
              'Parse the data or process steps and generate a previewable SVG or Mermaid diagram.',
          'tool_hints': const ['chart_diagram_generator'],
          'dependencies': const [2],
          'deliverable': 'Chart or diagram preview',
          'acceptance_check':
              'Labels, values, and arrows match the supplied data or workflow.',
        };
      case 'simulation_tool':
        return {
          'title': 'Run scenario calculations',
          'description':
              'Normalize assumptions, forecast conservative/baseline/optimistic cases, and expose sensitivity.',
          'tool_hints': const ['simulation_tool'],
          'dependencies': const [2],
          'deliverable': 'Scenario projection table',
          'acceptance_check':
              'Every numeric output follows from stated assumptions.',
        };
      case 'document_generator':
        return {
          'title': 'Produce the document artifact',
          'description':
              'Convert the approved content into the requested document format and write it only when a path is supplied.',
          'tool_hints': const ['document_generator'],
          'dependencies': [candidateIndex - 1],
          'deliverable': 'Generated document',
          'acceptance_check':
              'The document has a title, organized sections, and the requested format.',
        };
      case 'pdf_document_generator':
        return {
          'title': 'Produce the PDF artifact',
          'description':
              'Convert the approved content into a PDF artifact and write it when an output path is supplied.',
          'tool_hints': const ['pdf_document_generator'],
          'dependencies': [candidateIndex - 1],
          'deliverable': 'Generated PDF',
          'acceptance_check':
              'The PDF artifact has a title, organized content, and a saved path or saveable preview.',
        };
      case 'ci_cli_runner':
        return {
          'title': 'Run local verification',
          'description':
              'Execute only the supported CI/CLI command needed for the task and capture stdout/stderr.',
          'tool_hints': const ['ci_cli_runner'],
          'dependencies': [candidateIndex - 1],
          'deliverable': 'CI/CLI result',
          'acceptance_check':
              'The exit code and important output are included in the final report.',
        };
      case 'workflow_automation':
        return {
          'title': 'Design the automation flow',
          'description':
              'Define triggers, ordered actions, checks, approvals, and failure handling for repeatable execution.',
          'tool_hints': const ['workflow_automation'],
          'dependencies': const [2],
          'deliverable': 'Automation blueprint',
          'acceptance_check':
              'The workflow states what starts it, what runs, what is checked, and how failures stop.',
        };
      default:
        return {
          'title': 'Use $tool for task-specific context',
          'description':
              'Run $tool where it adds evidence, execution, or structure for "$task".',
          'tool_hints': [tool],
          'dependencies': const [2],
          'deliverable': '$tool output',
          'acceptance_check':
              'The tool output is used directly in the final answer.',
        };
    }
  }

  static String _planSubject(String task) {
    final terms = _queryTerms(task).take(4).map(_titleCase).toList();
    if (terms.isEmpty) return 'task';
    return terms.join(' ').toLowerCase();
  }

  static String _planDeliverable(String task) {
    final normalized = task.toLowerCase();
    if (normalized.contains('mind map')) return 'Mind map with preview';
    if (normalized.contains('chart') || normalized.contains('diagram')) {
      return 'Visual chart or diagram';
    }
    if (normalized.contains('pdf') || normalized.contains('document')) {
      return 'Generated document';
    }
    if (normalized.contains('workflow') || normalized.contains('automation')) {
      return 'Automation blueprint';
    }
    if (normalized.contains('forecast') || normalized.contains('what-if')) {
      return 'Scenario forecast';
    }
    return 'Completed answer or artifact';
  }

  static String _planComplexity(
    String task,
    List<Map<String, dynamic>> routes,
  ) {
    final signals = routes.length +
        RegExp(r'\b(and|then|after|before|multiple|complex|advanced)\b')
            .allMatches(task.toLowerCase())
            .length;
    if (signals >= 4) return 'high';
    if (signals >= 2) return 'medium';
    return 'low';
  }

  static List<String> _plannerVerification(
    String task,
    List<Map<String, dynamic>> routes,
  ) {
    final checks = <String>[
      'Confirm the final output directly satisfies: "$task".',
    ];
    final tools = routes.map((route) => route['tool']).toSet();
    if (tools.contains('web_search') || tools.contains('webpage_reader')) {
      checks
          .add('Ensure sourced claims only use fetched/search-returned text.');
    }
    if (tools.contains('mind_map_generator') ||
        tools.contains('chart_diagram_generator')) {
      checks.add('Inspect the rendered visual preview, not just the code.');
    }
    if (tools.contains('simulation_tool')) {
      checks
          .add('Check assumptions and recompute at least one projected value.');
    }
    if (tools.contains('ci_cli_runner')) {
      checks.add('Report command, exit code, and key output lines.');
    }
    return checks;
  }

  static List<String> _visualOutputFormats(String? format) {
    final normalized = format?.trim().toLowerCase();
    switch (normalized) {
      case 'nodes':
        return const ['nodes'];
      case 'data':
        return const ['data'];
      case 'mermaid':
        return const ['mermaid'];
      case 'svg':
        return const ['svg'];
      case 'all':
      case null:
      case '':
        return const ['nodes', 'mermaid', 'svg'];
      default:
        return const ['nodes', 'mermaid', 'svg'];
    }
  }

  static String? _firstIdeaTitle(String? ideas) {
    final lines = _splitIdeaText(ideas ?? '');
    if (lines.isEmpty) return null;
    return _clipOneLine(lines.first, 70);
  }

  static Map<String, dynamic> _buildMindMapTree(
      String rootLabel, String ideas) {
    final branches = _mindMapBranches(rootLabel, ideas);
    return {
      'id': 'root',
      'label': rootLabel,
      'children': branches.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final branch = entry.value;
        final children = (branch['children'] as List<String>)
            .asMap()
            .entries
            .map((childEntry) => {
                  'id': 'node_${index}_${childEntry.key + 1}',
                  'label': childEntry.value,
                })
            .toList();
        return {
          'id': 'node_$index',
          'label': branch['label'],
          'children': children,
        };
      }).toList(),
    };
  }

  static List<Map<String, dynamic>> _mindMapBranches(
    String rootLabel,
    String ideas,
  ) {
    final lines = _splitIdeaText(ideas)
        .where((line) => line.toLowerCase() != rootLabel.toLowerCase())
        .toList();
    final branches = <Map<String, dynamic>>[];

    for (final line in lines) {
      if (branches.length >= 8) break;
      final arrowParts = line.split(RegExp(r'\s*->\s*'));
      final colonParts = line.split(RegExp(r'\s*:\s*'));
      if (arrowParts.length > 1) {
        branches.add({
          'label': _clipOneLine(arrowParts.first, 48),
          'children': arrowParts
              .skip(1)
              .map(_cleanIdeaText)
              .where(
                (part) {
                  return part.isNotEmpty;
                },
              )
              .take(5)
              .toList(),
        });
      } else if (colonParts.length > 1) {
        branches.add({
          'label': _clipOneLine(colonParts.first, 48),
          'children':
              _splitIdeaText(colonParts.skip(1).join(':')).take(5).toList(),
        });
      } else {
        branches.add({
          'label': _clipOneLine(line, 48),
          'children': const <String>[],
        });
      }
    }

    if (branches.isEmpty) {
      final terms = _queryTerms('$rootLabel $ideas')
          .where((term) => !rootLabel.toLowerCase().contains(term))
          .take(6)
          .toList();
      final fallback = terms.isEmpty
          ? const ['Context', 'Goals', 'Options', 'Risks', 'Next steps']
          : terms.map(_titleCase).toList();
      for (final label in fallback) {
        branches.add({'label': label, 'children': const <String>[]});
      }
    }

    return branches;
  }

  static List<String> _splitIdeaText(String text) {
    final normalized = text
        .split(RegExp(r'[\n\r]+'))
        .map(_cleanIdeaText)
        .where((line) => line.isNotEmpty)
        .toList();
    if (normalized.length > 1) return normalized;

    final split = text
        .split(RegExp(r'[;,]+'))
        .map(_cleanIdeaText)
        .where((line) => line.isNotEmpty)
        .toList();
    return split.isEmpty ? normalized : split;
  }

  static String _cleanIdeaText(String text) {
    return text
        .replaceFirst(RegExp(r'^\s*(?:[-*+]|\d+[.)])\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _mindMapMermaid(Map<String, dynamic> tree) {
    final buffer = StringBuffer()
      ..writeln('mindmap')
      ..writeln('  root((${_mermaidMindMapLabel(tree['label'].toString())}))');
    final children = tree['children'];
    if (children is List) {
      for (final child in children) {
        if (child is! Map) continue;
        buffer.writeln(
            '    ${_mermaidMindMapLabel((child['label'] ?? '').toString())}');
        final grandchildren = child['children'];
        if (grandchildren is List) {
          for (final grandchild in grandchildren) {
            if (grandchild is! Map) continue;
            buffer.writeln(
                '      ${_mermaidMindMapLabel((grandchild['label'] ?? '').toString())}');
          }
        }
      }
    }
    return buffer.toString().trimRight();
  }

  static String _mindMapSvg(Map<String, dynamic> tree) {
    final children = (tree['children'] as List).whereType<Map>().toList();
    final branchCount = math.max(children.length, 1);
    const width = 900.0;
    const height = 620.0;
    const centerX = width / 2;
    const centerY = height / 2;
    const radius = 220.0;
    final buffer = StringBuffer()
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="900" height="620" viewBox="0 0 900 620">')
      ..writeln(
          '<defs><marker id="mindArrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="#64748b"/></marker></defs>')
      ..writeln('<rect width="900" height="620" fill="#f8fafc"/>')
      ..writeln('<circle cx="$centerX" cy="$centerY" r="72" fill="#2563eb"/>')
      ..writeln(
          '<text x="$centerX" y="$centerY" text-anchor="middle" dominant-baseline="middle" fill="white" font-family="Arial" font-size="18" font-weight="700">${_xmlEscape(_clipOneLine(tree['label'].toString(), 28))}</text>');

    for (var i = 0; i < children.length; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / branchCount);
      final x = centerX + math.cos(angle) * radius;
      final y = centerY + math.sin(angle) * radius;
      final label = (children[i]['label'] ?? '').toString();
      final lineStartX = centerX + math.cos(angle) * 72;
      final lineStartY = centerY + math.sin(angle) * 72;
      final lineEndX = centerX + math.cos(angle) * (radius - 92);
      final lineEndY = centerY + math.sin(angle) * (radius - 32);
      buffer
        ..writeln(
            '<line x1="$lineStartX" y1="$lineStartY" x2="$lineEndX" y2="$lineEndY" stroke="#64748b" stroke-width="3" marker-end="url(#mindArrow)"/>')
        ..writeln(
            '<rect x="${x - 88}" y="${y - 28}" width="176" height="56" rx="8" fill="#ffffff" stroke="#2563eb" stroke-width="2"/>')
        ..writeln(
            '<text x="$x" y="$y" text-anchor="middle" dominant-baseline="middle" fill="#0f172a" font-family="Arial" font-size="14" font-weight="700">${_xmlEscape(_clipOneLine(label, 24))}</text>');

      final grandchildren = children[i]['children'];
      if (grandchildren is List && grandchildren.isNotEmpty) {
        for (var j = 0; j < grandchildren.length && j < 3; j++) {
          final grandchild = grandchildren[j];
          if (grandchild is! Map) continue;
          final childY = y + 48 + (j * 30);
          buffer
            ..writeln(
                '<line x1="$x" y1="${y + 28}" x2="$x" y2="$childY" stroke="#cbd5e1" stroke-width="2"/>')
            ..writeln(
                '<text x="$x" y="$childY" text-anchor="middle" fill="#475569" font-family="Arial" font-size="12">${_xmlEscape(_clipOneLine((grandchild['label'] ?? '').toString(), 28))}</text>');
        }
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static Map<String, double> _numericVariables(
    Map<String, dynamic> arguments,
  ) {
    final values = <String, double>{};

    void add(String key, dynamic value) {
      final parsed = _parseNumericValue(value, key);
      if (parsed != null) values[key.toLowerCase()] = parsed;
    }

    const directKeys = [
      'base',
      'base_value',
      'baseline',
      'starting_value',
      'current_value',
      'revenue',
      'cost',
      'users',
      'conversion_rate',
      'growth',
      'growth_rate',
      'rate',
      'periods',
      'months',
      'years',
      'change',
      'delta',
      'sensitivity',
      'shock',
    ];
    for (final key in directKeys) {
      if (arguments.containsKey(key)) add(key, arguments[key]);
    }

    final raw = arguments['variables'] ?? arguments['inputs'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        add(entry.key.toString(), entry.value);
      }
    } else if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final name = item['name'] ?? item['key'] ?? item['label'];
          final value = item['value'] ?? item['amount'];
          if (name != null) add(name.toString(), value);
        } else {
          _parseKeyValueNumbers(item.toString()).forEach(add);
        }
      }
    } else if (raw is String) {
      _parseKeyValueNumbers(raw).forEach(add);
    }

    return values;
  }

  static Map<String, String> _parseKeyValueNumbers(String text) {
    final pairs = <String, String>{};
    final regex = RegExp(
      r'([A-Za-z][A-Za-z0-9 _-]{0,40})\s*[:=]\s*([-+]?\$?\d[\d,]*(?:\.\d+)?%?)',
    );
    for (final match in regex.allMatches(text)) {
      pairs[match.group(1)!.trim()] = match.group(2)!.trim();
    }
    return pairs;
  }

  static double? _parseNumericValue(dynamic value, String key) {
    if (value is num) {
      return _rateLikeKey(key) && value.abs() > 1
          ? value.toDouble() / 100
          : value.toDouble();
    }
    if (value is! String) return null;
    final trimmed = value.trim();
    final isPercent = trimmed.contains('%');
    final numeric = double.tryParse(
      trimmed.replaceAll(RegExp(r'[$,%\s]'), ''),
    );
    if (numeric == null) return null;
    if (isPercent || (_rateLikeKey(key) && numeric.abs() > 1)) {
      return numeric / 100;
    }
    return numeric;
  }

  static bool _rateLikeKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('rate') ||
        normalized.contains('growth') ||
        normalized.contains('percent') ||
        normalized.contains('conversion') ||
        normalized.contains('margin') ||
        normalized.contains('sensitivity') ||
        normalized.contains('shock');
  }

  static List<double> _numbersFromText(String text) {
    return RegExp(r'[-+]?\d[\d,]*(?:\.\d+)?%?')
        .allMatches(text)
        .map((match) =>
            double.tryParse(match.group(0)!.replaceAll(RegExp(r'[,%]'), '')))
        .whereType<double>()
        .toList();
  }

  static double _simulationBaseValue(
    Map<String, double> variables,
    List<double> scenarioNumbers,
  ) {
    final revenue = variables['revenue'];
    final cost = variables['cost'];
    if (revenue != null && cost != null) return revenue - cost;
    return _firstNumericValue(variables, const [
          'base_value',
          'baseline',
          'base',
          'starting_value',
          'current_value',
          'users',
          'revenue',
        ]) ??
        (scenarioNumbers.isNotEmpty ? scenarioNumbers.first : 100);
  }

  static double _simulationGrowthRate(
    Map<String, double> variables,
    String scenario,
  ) {
    final fromVariables = _firstNumericValue(variables, const [
      'growth_rate',
      'growth',
      'rate',
      'monthly_growth',
      'annual_growth',
      'conversion_rate',
    ]);
    if (fromVariables != null) return fromVariables;
    final percentMatch =
        RegExp(r'([-+]?\d+(?:\.\d+)?)\s*%').firstMatch(scenario);
    if (percentMatch != null) {
      return double.parse(percentMatch.group(1)!) / 100;
    }
    return 0;
  }

  static double? _firstNumericValue(
    Map<String, double> variables,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = variables[key];
      if (value != null) return value;
    }
    return null;
  }

  static double _simulationSensitivity(
    Map<String, double> variables,
    double growthRate,
  ) {
    final explicit = _firstNumericValue(
      variables,
      const ['sensitivity', 'shock', 'variance'],
    );
    if (explicit != null) return explicit.abs();
    return math.max(growthRate.abs() * 0.5, 0.05);
  }

  static List<Map<String, dynamic>> _scenarioProjections({
    required double baseValue,
    required double growthRate,
    required double perPeriodChange,
    required int horizon,
    required double sensitivity,
  }) {
    final projections = <Map<String, dynamic>>[];
    for (var period = 0; period <= horizon; period++) {
      projections.add({
        'period': period,
        'conservative': _roundDouble(_projectValue(
          baseValue,
          growthRate - sensitivity,
          perPeriodChange,
          period,
        )),
        'baseline': _roundDouble(_projectValue(
          baseValue,
          growthRate,
          perPeriodChange,
          period,
        )),
        'optimistic': _roundDouble(_projectValue(
          baseValue,
          growthRate + sensitivity,
          perPeriodChange,
          period,
        )),
      });
    }
    return projections;
  }

  static double _projectValue(
    double baseValue,
    double growthRate,
    double perPeriodChange,
    int period,
  ) {
    return baseValue * math.pow(1 + growthRate, period) +
        perPeriodChange * period;
  }

  static Map<String, dynamic> _runMonteCarloSimulation({
    required double baseValue,
    required double growthRate,
    required double perPeriodChange,
    required int horizon,
    required double volatility,
    required int iterations,
    required int seed,
    required double? targetValue,
  }) {
    final random = _DeterministicRandom(seed);
    final valuesByPeriod = List.generate(horizon + 1, (_) => <double>[]);
    final samplePaths = <List<double>>[];
    var targetHits = 0;
    var negativeFinals = 0;

    for (var trial = 0; trial < iterations; trial++) {
      var value = baseValue;
      final path = <double>[_roundDouble(value)];
      valuesByPeriod[0].add(value);

      for (var period = 1; period <= horizon; period++) {
        final shock = random.nextStandardNormal() * volatility;
        final periodGrowth = (growthRate + shock).clamp(-0.95, 3.0).toDouble();
        value = value * (1 + periodGrowth) + perPeriodChange;
        valuesByPeriod[period].add(value);
        path.add(_roundDouble(value));
      }

      final finalValue = path.last;
      if (targetValue != null && finalValue >= targetValue) targetHits++;
      if (finalValue < 0) negativeFinals++;
      if (samplePaths.length < 5) samplePaths.add(path);
    }

    final periodSummaries = valuesByPeriod
        .asMap()
        .entries
        .map((entry) => _distributionSummary(entry.key, entry.value))
        .toList();
    final finalPeriod = periodSummaries.last;

    return {
      'iterations': iterations,
      'volatility': volatility,
      'seed': seed,
      'period_summaries': periodSummaries,
      'final_period': finalPeriod,
      if (targetValue != null)
        'target_probability': _roundDouble(targetHits / iterations),
      'probability_below_zero': _roundDouble(negativeFinals / iterations),
      'sample_paths': samplePaths,
    };
  }

  static Map<String, dynamic> _distributionSummary(
    int period,
    List<double> values,
  ) {
    final sorted = [...values]..sort();
    final mean = values.fold<double>(0, (sum, value) => sum + value) /
        math.max(values.length, 1);
    final variance = values.fold<double>(
          0,
          (sum, value) => sum + math.pow(value - mean, 2).toDouble(),
        ) /
        math.max(values.length, 1);

    return {
      'period': period,
      'p5': _roundDouble(_percentile(sorted, 0.05)),
      'p10': _roundDouble(_percentile(sorted, 0.10)),
      'p25': _roundDouble(_percentile(sorted, 0.25)),
      'p50': _roundDouble(_percentile(sorted, 0.50)),
      'p75': _roundDouble(_percentile(sorted, 0.75)),
      'p90': _roundDouble(_percentile(sorted, 0.90)),
      'p95': _roundDouble(_percentile(sorted, 0.95)),
      'mean': _roundDouble(mean),
      'stddev': _roundDouble(math.sqrt(variance)),
      'min': _roundDouble(sorted.isEmpty ? 0 : sorted.first),
      'max': _roundDouble(sorted.isEmpty ? 0 : sorted.last),
      'histogram': _histogramBuckets(sorted, 8),
    };
  }

  static List<Map<String, dynamic>> _histogramBuckets(
    List<double> sortedValues,
    int bucketCount,
  ) {
    if (sortedValues.isEmpty) return const [];
    final min = sortedValues.first;
    final max = sortedValues.last;
    final buckets = math.max(bucketCount, 1);
    if ((max - min).abs() < 0.0000001) {
      return [
        {
          'min': _roundDouble(min),
          'max': _roundDouble(max),
          'count': sortedValues.length,
        },
      ];
    }

    final span = max - min;
    final counts = List<int>.filled(buckets, 0);
    for (final value in sortedValues) {
      final index =
          (((value - min) / span) * buckets).floor().clamp(0, buckets - 1);
      counts[index]++;
    }

    return counts.asMap().entries.map((entry) {
      final index = entry.key;
      final start = min + span * (index / buckets);
      final end = min + span * ((index + 1) / buckets);
      return {
        'min': _roundDouble(start),
        'max': _roundDouble(end),
        'count': entry.value,
      };
    }).toList();
  }

  static double _percentile(List<double> sortedValues, double percentile) {
    if (sortedValues.isEmpty) return 0;
    final index = (sortedValues.length - 1) * percentile.clamp(0, 1);
    final lower = index.floor();
    final upper = index.ceil();
    if (lower == upper) return sortedValues[lower];
    final weight = index - lower;
    return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
  }

  static List<Map<String, dynamic>> _simulationSensitivityAnalysis({
    required double baseValue,
    required double growthRate,
    required double perPeriodChange,
    required int horizon,
    required double sensitivity,
  }) {
    final baseFinal = _projectValue(
      baseValue,
      growthRate,
      perPeriodChange,
      horizon,
    );
    final cases = <({String name, double base, double rate, double change})>[
      (
        name: 'growth_rate - sensitivity',
        base: baseValue,
        rate: growthRate - sensitivity,
        change: perPeriodChange,
      ),
      (
        name: 'growth_rate + sensitivity',
        base: baseValue,
        rate: growthRate + sensitivity,
        change: perPeriodChange,
      ),
      (
        name: 'base_value - 10%',
        base: baseValue * 0.90,
        rate: growthRate,
        change: perPeriodChange,
      ),
      (
        name: 'base_value + 10%',
        base: baseValue * 1.10,
        rate: growthRate,
        change: perPeriodChange,
      ),
      (
        name: 'per_period_change - 10%',
        base: baseValue,
        rate: growthRate,
        change: perPeriodChange * 0.90,
      ),
      (
        name: 'per_period_change + 10%',
        base: baseValue,
        rate: growthRate,
        change: perPeriodChange * 1.10,
      ),
    ];

    return cases.map((scenarioCase) {
      final finalValue = _projectValue(
        scenarioCase.base,
        scenarioCase.rate,
        scenarioCase.change,
        horizon,
      );
      return {
        'case': scenarioCase.name,
        'final_value': _roundDouble(finalValue),
        'delta_from_baseline': _roundDouble(finalValue - baseFinal),
      };
    }).toList();
  }

  static List<String> _simulationRiskFlags({
    required Map<String, dynamic> monteCarlo,
    required double baseValue,
    required double? targetValue,
  }) {
    final finalPeriod = monteCarlo['final_period'] as Map<String, dynamic>;
    final p10 = (finalPeriod['p10'] as num).toDouble();
    final p90 = (finalPeriod['p90'] as num).toDouble();
    final p50 = (finalPeriod['p50'] as num).toDouble();
    final targetProbability = monteCarlo['target_probability'];
    final belowZero = (monteCarlo['probability_below_zero'] as num).toDouble();
    final flags = <String>[];

    if (belowZero > 0.05) {
      flags.add('${_formatNumber(belowZero * 100)}% of trials end below zero.');
    }
    if ((p90 - p10).abs() > baseValue.abs() * 0.75) {
      flags.add('Outcome spread is wide relative to the starting value.');
    }
    if (targetValue != null && targetProbability is num) {
      final probability = targetProbability.toDouble();
      if (probability < 0.5) {
        flags.add(
            'Target probability is below 50%; base assumptions may be too weak.');
      } else {
        flags.add(
            'Target is reached in ${_formatNumber(probability * 100)}% of trials.');
      }
    }
    if (p50 < baseValue) {
      flags.add('Median final value is below the starting value.');
    }

    return flags.isEmpty
        ? ['No major downside flags under the supplied assumptions.']
        : flags;
  }

  static String _simulationFanChartSvg({
    required String title,
    required List<Map<String, dynamic>> periodSummaries,
  }) {
    const width = 760.0;
    const height = 360.0;
    const left = 58.0;
    const right = 24.0;
    const top = 58.0;
    const bottom = 48.0;
    const chartWidth = width - left - right;
    const chartHeight = height - top - bottom;
    final values = periodSummaries
        .expand((summary) => [summary['p10'], summary['p50'], summary['p90']])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    final minValue = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxValue = values.isEmpty ? 1.0 : values.reduce(math.max);
    final span =
        (maxValue - minValue).abs() < 0.0001 ? 1.0 : maxValue - minValue;

    String pointFor(Map<String, dynamic> summary, String key) {
      final period = (summary['period'] as num).toDouble();
      final maxPeriod =
          math.max((periodSummaries.last['period'] as num).toDouble(), 1);
      final value = (summary[key] as num).toDouble();
      final x = left + chartWidth * (period / maxPeriod);
      final y = top + chartHeight * (1 - ((value - minValue) / span));
      return '${_formatNumber(x)},${_formatNumber(y)}';
    }

    final p10 = periodSummaries.map((summary) => pointFor(summary, 'p10'));
    final p50 = periodSummaries.map((summary) => pointFor(summary, 'p50'));
    final p90 = periodSummaries.map((summary) => pointFor(summary, 'p90'));
    final band = [...p10, ...p90.toList().reversed].join(' ');

    return [
      '<svg xmlns="http://www.w3.org/2000/svg" width="760" height="360" viewBox="0 0 760 360">',
      '<rect width="760" height="360" fill="#f8fafc"/>',
      '<text x="24" y="32" fill="#0f172a" font-family="Arial" font-size="18" font-weight="700">${_xmlEscape(_clipOneLine(title, 74))}</text>',
      '<line x1="$left" y1="${height - bottom}" x2="${width - right}" y2="${height - bottom}" stroke="#334155" stroke-width="2"/>',
      '<line x1="$left" y1="$top" x2="$left" y2="${height - bottom}" stroke="#334155" stroke-width="2"/>',
      '<polygon points="$band" fill="#76ABAE" opacity="0.24"/>',
      '<polyline points="${p10.join(' ')}" fill="none" stroke="#76ABAE" stroke-width="2" stroke-dasharray="5 5"/>',
      '<polyline points="${p90.join(' ')}" fill="none" stroke="#76ABAE" stroke-width="2" stroke-dasharray="5 5"/>',
      '<polyline points="${p50.join(' ')}" fill="none" stroke="#FF5722" stroke-width="4"/>',
      '<text x="${width - right - 120}" y="${top + 18}" fill="#475569" font-family="Arial" font-size="12">p10-p90 band</text>',
      '<text x="${width - right - 120}" y="${top + 38}" fill="#FF5722" font-family="Arial" font-size="12" font-weight="700">p50 median</text>',
      '<text x="20" y="${top + 8}" fill="#475569" font-family="Arial" font-size="11">${_xmlEscape(_formatNumber(maxValue))}</text>',
      '<text x="20" y="${height - bottom}" fill="#475569" font-family="Arial" font-size="11">${_xmlEscape(_formatNumber(minValue))}</text>',
      '</svg>',
    ].join('\n');
  }

  static int _simulationSeed(
    String scenario,
    Map<String, double> variables,
    int horizon,
    int iterations,
  ) {
    var hash = 2166136261;
    final material = [
      scenario,
      horizon.toString(),
      iterations.toString(),
      ...variables.entries.map((entry) => '${entry.key}=${entry.value}'),
    ].join('|');
    for (final codeUnit in material.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static double _roundDouble(double value) {
    return double.parse(value.toStringAsFixed(4));
  }

  static String _documentFormat(String? requestedFormat, String? outputPath) {
    final normalized = requestedFormat?.trim().toLowerCase();
    if (const ['markdown', 'md'].contains(normalized)) return 'markdown';
    if (normalized == 'html') return 'html';
    if (normalized == 'text' || normalized == 'txt') return 'text';
    if (normalized == 'pdf') return 'pdf';

    final extension = outputPath == null ? '' : _extension(outputPath);
    switch (extension) {
      case '.html':
      case '.htm':
        return 'html';
      case '.txt':
        return 'text';
      case '.pdf':
        return 'pdf';
      case '.md':
      case '.markdown':
      default:
        return 'markdown';
    }
  }

  static String _documentExtension(String format) {
    switch (format) {
      case 'html':
        return 'html';
      case 'text':
        return 'txt';
      case 'pdf':
        return 'pdf';
      case 'markdown':
      default:
        return 'md';
    }
  }

  static String _normalizedDocumentOutputPath(String path, String format) {
    if (_extension(path).isNotEmpty) return path;
    return '$path.${_documentExtension(format)}';
  }

  static String _suggestedArtifactFileName(String title, String extension) {
    final stem = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeStem = stem.isEmpty ? 'quick_llm_artifact' : stem;
    final safeExtension = extension.replaceAll(RegExp(r'^\.+'), '');
    return '$safeStem.$safeExtension';
  }

  static String _documentText(String title, String content, String format) {
    final lines = content
        .split(RegExp(r'[\n\r]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    switch (format) {
      case 'html':
        final body = lines.map((line) {
          final clean = _xmlEscape(line.replaceFirst(
            RegExp(r'^\s*(?:[-*+]|\d+[.)])\s*'),
            '',
          ));
          return '<p>$clean</p>';
        }).join('\n');
        return [
          '<!doctype html>',
          '<html>',
          '<head><meta charset="utf-8"><title>${_xmlEscape(title)}</title></head>',
          '<body>',
          '<h1>${_xmlEscape(title)}</h1>',
          body,
          '</body>',
          '</html>',
        ].join('\n');
      case 'text':
        return [
          title,
          ''.padLeft(title.length, '='),
          '',
          lines.join('\n'),
        ].join('\n');
      case 'pdf':
      case 'markdown':
      default:
        return [
          '# $title',
          '',
          ...lines.map((line) => line.startsWith('#') ? line : line),
          '',
        ].join('\n');
    }
  }

  static List<int> _minimalPdfBytes(String title, String content) {
    final lines = <String>[
      title,
      '',
      ...content
          .split(RegExp(r'[\n\r]+'))
          .expand((line) => _wrapText(line, 86)),
    ].take(42).toList();
    final stream = StringBuffer()
      ..writeln('BT')
      ..writeln('/F1 12 Tf')
      ..writeln('50 760 Td');
    for (final line in lines) {
      stream
        ..writeln('(${_pdfEscape(line)}) Tj')
        ..writeln('0 -16 Td');
    }
    stream.writeln('ET');
    final streamText = stream.toString();
    final streamLength = ascii.encode(streamText).length;
    final objects = [
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n',
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n',
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n',
      '4 0 obj\n<< /Length $streamLength >>\nstream\n${streamText}endstream\nendobj\n',
      '5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n',
    ];
    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];
    for (final object in objects) {
      offsets.add(buffer.length);
      buffer.write(object);
    }
    final xrefOffset = buffer.length;
    buffer
      ..writeln('xref')
      ..writeln('0 ${objects.length + 1}')
      ..writeln('0000000000 65535 f ');
    for (final offset in offsets) {
      buffer.writeln('${offset.toString().padLeft(10, '0')} 00000 n ');
    }
    buffer
      ..writeln('trailer')
      ..writeln('<< /Size ${objects.length + 1} /Root 1 0 R >>')
      ..writeln('startxref')
      ..writeln('$xrefOffset')
      ..writeln('%%EOF');
    return ascii.encode(buffer.toString());
  }

  static List<String> _wrapText(String text, int width) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return [''];
    final words = clean.split(' ');
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ('$current $word'.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  static String _pdfEscape(String text) {
    return text
        .replaceAll(RegExp(r'[^\x09\x0A\x0D\x20-\x7E]'), '?')
        .replaceAll('\\', '\\\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
  }

  static String _normalizeChartType(String? chartType) {
    final normalized = chartType?.trim().toLowerCase() ?? '';
    if (normalized.contains('flow') || normalized.contains('process')) {
      return 'flowchart';
    }
    if (normalized.contains('line')) return 'line';
    if (normalized.contains('pie')) return 'pie';
    return 'bar';
  }

  static List<String> _flowSteps(String dataText) {
    final separator =
        dataText.contains('->') ? RegExp(r'\s*->\s*') : RegExp(r'[\n\r;,]+');
    final steps = dataText
        .split(separator)
        .map(_cleanIdeaText)
        .where((step) => step.isNotEmpty)
        .take(12)
        .toList();
    return steps.length >= 2 ? steps : [dataText.trim(), 'Review output'];
  }

  static String _flowchartMermaid(String title, List<String> steps) {
    final buffer = StringBuffer()
      ..writeln('flowchart TD')
      ..writeln('  title["${_mermaidQuote(title)}"]');
    for (var i = 0; i < steps.length; i++) {
      buffer.writeln('  N$i["${_mermaidQuote(steps[i])}"]');
      if (i > 0) buffer.writeln('  N${i - 1} --> N$i');
    }
    return buffer.toString().trimRight();
  }

  static String _flowchartSvg(String title, List<String> steps) {
    final width = math.max(720, steps.length * 170).toInt();
    const height = 220;
    final buffer = StringBuffer()
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">')
      ..writeln('<rect width="$width" height="$height" fill="#f8fafc"/>')
      ..writeln(
          '<text x="24" y="34" fill="#0f172a" font-family="Arial" font-size="20" font-weight="700">${_xmlEscape(title)}</text>');
    for (var i = 0; i < steps.length; i++) {
      final x = 30 + i * 160;
      buffer
        ..writeln(
            '<rect x="$x" y="80" width="130" height="62" rx="8" fill="#ffffff" stroke="#0f766e" stroke-width="2"/>')
        ..writeln(
            '<text x="${x + 65}" y="112" text-anchor="middle" dominant-baseline="middle" fill="#0f172a" font-family="Arial" font-size="13">${_xmlEscape(_clipOneLine(steps[i], 18))}</text>');
      if (i < steps.length - 1) {
        buffer
          ..writeln(
              '<line x1="${x + 130}" y1="111" x2="${x + 158}" y2="111" stroke="#64748b" stroke-width="2"/>')
          ..writeln(
              '<polygon points="${x + 158},111 ${x + 150},106 ${x + 150},116" fill="#64748b"/>');
      }
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static List<_ChartEntry> _chartEntries(String dataText) {
    final entries = <_ChartEntry>[];
    final pairRegex = RegExp(
      r'([^=,:;\n]+?)\s*[:=]\s*(-?\d[\d,]*(?:\.\d+)?)',
    );
    for (final match in pairRegex.allMatches(dataText)) {
      final value = double.tryParse(match.group(2)!.replaceAll(',', ''));
      if (value == null) continue;
      entries.add(_ChartEntry(_clipOneLine(match.group(1)!.trim(), 32), value));
    }
    if (entries.isNotEmpty) return entries.take(12).toList();

    final labelNumberRegex = RegExp(
      r'([A-Za-z][A-Za-z0-9 _-]{0,32})\s+(-?\d[\d,]*(?:\.\d+)?)',
    );
    for (final match in labelNumberRegex.allMatches(dataText)) {
      final value = double.tryParse(match.group(2)!.replaceAll(',', ''));
      if (value == null) continue;
      entries.add(_ChartEntry(_clipOneLine(match.group(1)!.trim(), 32), value));
    }
    if (entries.isNotEmpty) return entries.take(12).toList();

    return entries;
  }

  static _ChartSpec _chartSpecFromArguments({
    required String title,
    required String chartType,
    required Map<String, dynamic> arguments,
  }) {
    final entries = <_ChartEntry>[];
    final rawEntries = arguments['entries'];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map) {
          final label =
              '${item['label'] ?? item['name'] ?? item['x'] ?? ''}'.trim();
          final value = _asDouble(item['value'] ?? item['y']);
          if (label.isNotEmpty && value != null) {
            entries.add(_ChartEntry(_clipOneLine(label, 36), value));
          }
        }
      }
    }

    if (entries.isEmpty) {
      final labels = _stringListArg(arguments, const ['labels', 'x_values']);
      final values = _numberListArg(arguments, const ['values', 'y_values']);
      for (var i = 0; i < labels.length && i < values.length; i++) {
        entries.add(_ChartEntry(_clipOneLine(labels[i], 36), values[i]));
      }
    }

    if (entries.isEmpty) {
      final dataText =
          _stringArg(arguments, const ['data', 'dataset', 'content'])?.trim();
      if (dataText != null && dataText.isNotEmpty) {
        entries.addAll(_chartEntries(dataText));
      }
    }

    return _ChartSpec(
      title: title,
      subtitle:
          _stringArg(arguments, const ['subtitle', 'description'])?.trim(),
      chartType: chartType,
      entries: entries.take(16).toList(),
      xLabel:
          _stringArg(arguments, const ['x_label', 'xlabel', 'xAxis'])?.trim(),
      yLabel:
          _stringArg(arguments, const ['y_label', 'ylabel', 'yAxis'])?.trim(),
      unit: _stringArg(arguments, const ['unit', 'units', 'suffix'])?.trim(),
    );
  }

  static String _chartSvg(_ChartSpec spec) {
    switch (spec.chartType) {
      case 'line':
        return _lineChartSvg(spec);
      case 'pie':
        return _pieChartSvg(spec);
      case 'bar':
      default:
        return _barChartSvg(spec);
    }
  }

  static String _chartMermaid(_ChartSpec spec) {
    if (spec.chartType == 'pie') {
      final buffer = StringBuffer()
        ..writeln('pie showData')
        ..writeln('  title ${_mermaidQuote(spec.title)}');
      for (final entry in spec.entries) {
        buffer.writeln(
            '  "${_mermaidQuote(entry.label)}" : ${_formatNumber(entry.value)}');
      }
      return buffer.toString().trimRight();
    }

    final extent = _chartExtent(spec.entries);
    final labels = spec.entries
        .map((entry) => '"${_mermaidQuote(entry.label)}"')
        .join(', ');
    final values =
        spec.entries.map((entry) => _formatNumber(entry.value)).join(', ');
    final series = spec.chartType == 'line' ? 'line' : 'bar';
    final yLabel = spec.yLabel?.isNotEmpty == true ? spec.yLabel! : 'Value';
    return [
      'xychart-beta',
      '  title "${_mermaidQuote(spec.title)}"',
      '  x-axis [$labels]',
      '  y-axis "${_mermaidQuote(yLabel)}" ${_formatNumber(extent.min)} --> ${_formatNumber(extent.max)}',
      '  $series [$values]',
    ].join('\n');
  }

  static String _barChartSvg(_ChartSpec spec) {
    const width = 820.0;
    const height = 460.0;
    const left = 82.0;
    const right = 36.0;
    const top = 76.0;
    const bottom = 82.0;
    const chartWidth = width - left - right;
    const chartHeight = height - top - bottom;
    final extent = _chartExtent(spec.entries);
    double yFor(double value) =>
        top + chartHeight * (1 - ((value - extent.min) / extent.span));
    final baseline = yFor(0.clamp(extent.min, extent.max).toDouble());
    final slotWidth = chartWidth / spec.entries.length;
    final barWidth = math.max(16.0, math.min(52.0, slotWidth * 0.58));
    final buffer = StringBuffer()
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="${width.toInt()}" height="${height.toInt()}" viewBox="0 0 ${width.toInt()} ${height.toInt()}">')
      ..writeln(
          '<rect width="${width.toInt()}" height="${height.toInt()}" fill="#f8fafc"/>')
      ..write(_chartTitleSvg(spec, width))
      ..write(
          _cartesianGridSvg(spec, left, top, chartWidth, chartHeight, extent));
    for (var i = 0; i < spec.entries.length; i++) {
      final entry = spec.entries[i];
      final x = left + i * slotWidth + (slotWidth - barWidth) / 2;
      final valueY = yFor(entry.value);
      final rectY = math.min(valueY, baseline);
      final rectHeight = math.max(2.0, (baseline - valueY).abs());
      final color = _chartPalette[i % _chartPalette.length];
      buffer
        ..writeln(
            '<rect x="${_formatNumber(x)}" y="${_formatNumber(rectY)}" width="${_formatNumber(barWidth)}" height="${_formatNumber(rectHeight)}" rx="5" fill="$color"/>')
        ..writeln(
            '<text x="${_formatNumber(x + barWidth / 2)}" y="${_formatNumber(rectY - 8)}" text-anchor="middle" fill="#334155" font-family="Arial" font-size="11" font-weight="700">${_xmlEscape(_formatChartValue(entry.value, spec.unit))}</text>')
        ..writeln(
            '<text x="${_formatNumber(left + i * slotWidth + slotWidth / 2)}" y="${_formatNumber(top + chartHeight + 28)}" text-anchor="middle" fill="#475569" font-family="Arial" font-size="11">${_xmlEscape(_clipOneLine(entry.label, 14))}</text>');
    }
    buffer.write(_axisLabelsSvg(
        spec, width, height, left, top, chartWidth, chartHeight));
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static String _lineChartSvg(_ChartSpec spec) {
    const width = 820.0;
    const height = 460.0;
    const left = 82.0;
    const right = 36.0;
    const top = 76.0;
    const bottom = 82.0;
    const chartWidth = width - left - right;
    const chartHeight = height - top - bottom;
    final extent = _chartExtent(spec.entries);
    final pointCount = math.max(1, spec.entries.length - 1);
    double xFor(int index) => left + chartWidth * (index / pointCount);
    double yFor(double value) =>
        top + chartHeight * (1 - ((value - extent.min) / extent.span));
    final points = [
      for (var i = 0; i < spec.entries.length; i++)
        '${_formatNumber(xFor(i))},${_formatNumber(yFor(spec.entries[i].value))}'
    ];
    final buffer = StringBuffer()
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="${width.toInt()}" height="${height.toInt()}" viewBox="0 0 ${width.toInt()} ${height.toInt()}">')
      ..writeln(
          '<rect width="${width.toInt()}" height="${height.toInt()}" fill="#f8fafc"/>')
      ..write(_chartTitleSvg(spec, width))
      ..write(
          _cartesianGridSvg(spec, left, top, chartWidth, chartHeight, extent))
      ..writeln(
          '<polyline points="${points.join(' ')}" fill="none" stroke="#FF5722" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>');
    for (var i = 0; i < spec.entries.length; i++) {
      final entry = spec.entries[i];
      final x = xFor(i);
      final y = yFor(entry.value);
      buffer
        ..writeln(
            '<circle cx="${_formatNumber(x)}" cy="${_formatNumber(y)}" r="5" fill="#ffffff" stroke="#FF5722" stroke-width="3"/>')
        ..writeln(
            '<text x="${_formatNumber(x)}" y="${_formatNumber(y - 12)}" text-anchor="middle" fill="#334155" font-family="Arial" font-size="11" font-weight="700">${_xmlEscape(_formatChartValue(entry.value, spec.unit))}</text>')
        ..writeln(
            '<text x="${_formatNumber(x)}" y="${_formatNumber(top + chartHeight + 28)}" text-anchor="middle" fill="#475569" font-family="Arial" font-size="11">${_xmlEscape(_clipOneLine(entry.label, 14))}</text>');
    }
    buffer
      ..write(_axisLabelsSvg(
          spec, width, height, left, top, chartWidth, chartHeight))
      ..writeln('</svg>');
    return buffer.toString();
  }

  static String _pieChartSvg(_ChartSpec spec) {
    const width = 820.0;
    const height = 460.0;
    const cx = 250.0;
    const cy = 248.0;
    const radius = 138.0;
    final positiveEntries =
        spec.entries.where((entry) => entry.value > 0).take(10).toList();
    final entries = positiveEntries.isEmpty
        ? spec.entries
            .map((entry) => _ChartEntry(entry.label, entry.value.abs()))
            .where((entry) => entry.value > 0)
            .take(10)
            .toList()
        : positiveEntries;
    final total = entries.fold<double>(0, (sum, entry) => sum + entry.value);
    final buffer = StringBuffer()
      ..writeln(
          '<svg xmlns="http://www.w3.org/2000/svg" width="${width.toInt()}" height="${height.toInt()}" viewBox="0 0 ${width.toInt()} ${height.toInt()}">')
      ..writeln(
          '<rect width="${width.toInt()}" height="${height.toInt()}" fill="#f8fafc"/>')
      ..write(_chartTitleSvg(spec, width));
    var angle = -math.pi / 2;
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final sweep = total == 0 ? 0.0 : (entry.value / total) * math.pi * 2;
      final endAngle = angle + sweep;
      final largeArc = sweep > math.pi ? 1 : 0;
      final x1 = cx + radius * math.cos(angle);
      final y1 = cy + radius * math.sin(angle);
      final x2 = cx + radius * math.cos(endAngle);
      final y2 = cy + radius * math.sin(endAngle);
      final color = _chartPalette[i % _chartPalette.length];
      buffer.writeln(
        '<path d="M ${_formatNumber(cx)} ${_formatNumber(cy)} L ${_formatNumber(x1)} ${_formatNumber(y1)} A ${_formatNumber(radius)} ${_formatNumber(radius)} 0 $largeArc 1 ${_formatNumber(x2)} ${_formatNumber(y2)} Z" fill="$color" stroke="#f8fafc" stroke-width="3"/>',
      );
      final mid = angle + sweep / 2;
      const labelRadius = radius * 0.66;
      final percent = total == 0 ? 0.0 : entry.value / total * 100;
      if (percent >= 7) {
        buffer.writeln(
          '<text x="${_formatNumber(cx + labelRadius * math.cos(mid))}" y="${_formatNumber(cy + labelRadius * math.sin(mid))}" text-anchor="middle" dominant-baseline="middle" fill="#ffffff" font-family="Arial" font-size="12" font-weight="700">${_xmlEscape('${_formatNumber(percent)}%')}</text>',
        );
      }
      angle = endAngle;
    }
    buffer.writeln('<circle cx="$cx" cy="$cy" r="62" fill="#f8fafc"/>');
    buffer.writeln(
        '<text x="$cx" y="${cy - 4}" text-anchor="middle" fill="#0f172a" font-family="Arial" font-size="18" font-weight="700">${_xmlEscape(_formatChartValue(total, spec.unit))}</text>');
    buffer.writeln(
        '<text x="$cx" y="${cy + 18}" text-anchor="middle" fill="#64748b" font-family="Arial" font-size="11">total</text>');
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final y = 132 + i * 30;
      final percent = total == 0 ? 0.0 : entry.value / total * 100;
      buffer
        ..writeln(
            '<rect x="520" y="$y" width="14" height="14" rx="3" fill="${_chartPalette[i % _chartPalette.length]}"/>')
        ..writeln(
            '<text x="544" y="${y + 12}" fill="#334155" font-family="Arial" font-size="13" font-weight="700">${_xmlEscape(_clipOneLine(entry.label, 24))}</text>')
        ..writeln(
            '<text x="728" y="${y + 12}" text-anchor="end" fill="#64748b" font-family="Arial" font-size="12">${_xmlEscape('${_formatChartValue(entry.value, spec.unit)} (${_formatNumber(percent)}%)')}</text>');
    }
    buffer.writeln('</svg>');
    return buffer.toString();
  }

  static _ChartExtent _chartExtent(List<_ChartEntry> entries) {
    final values = entries.map((entry) => entry.value).toList();
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if (minValue > 0) minValue = 0;
    if (maxValue < 0) maxValue = 0;
    if ((maxValue - minValue).abs() < 0.0001) {
      maxValue += 1;
      minValue -= 1;
    }
    final padding = (maxValue - minValue) * 0.08;
    return _ChartExtent(minValue - padding, maxValue + padding);
  }

  static String _chartTitleSvg(_ChartSpec spec, double width) {
    final buffer = StringBuffer()
      ..writeln(
          '<text x="36" y="38" fill="#0f172a" font-family="Arial" font-size="22" font-weight="700">${_xmlEscape(_clipOneLine(spec.title, 64))}</text>');
    if (spec.subtitle != null && spec.subtitle!.isNotEmpty) {
      buffer.writeln(
          '<text x="36" y="58" fill="#64748b" font-family="Arial" font-size="12">${_xmlEscape(_clipOneLine(spec.subtitle!, 100))}</text>');
    }
    buffer.writeln(
        '<line x1="36" y1="66" x2="${_formatNumber(width - 36)}" y2="66" stroke="#e2e8f0" stroke-width="1"/>');
    return buffer.toString();
  }

  static String _cartesianGridSvg(
    _ChartSpec spec,
    double left,
    double top,
    double chartWidth,
    double chartHeight,
    _ChartExtent extent,
  ) {
    final buffer = StringBuffer();
    for (var i = 0; i <= 5; i++) {
      final value = extent.max - extent.span * (i / 5);
      final y = top + chartHeight * (i / 5);
      buffer
        ..writeln(
            '<line x1="${_formatNumber(left)}" y1="${_formatNumber(y)}" x2="${_formatNumber(left + chartWidth)}" y2="${_formatNumber(y)}" stroke="#e2e8f0" stroke-width="1"/>')
        ..writeln(
            '<text x="${_formatNumber(left - 10)}" y="${_formatNumber(y + 4)}" text-anchor="end" fill="#64748b" font-family="Arial" font-size="11">${_xmlEscape(_formatChartValue(value, spec.unit))}</text>');
    }
    final zero = 0.clamp(extent.min, extent.max).toDouble();
    final baseline =
        top + chartHeight * (1 - ((zero - extent.min) / extent.span));
    buffer
      ..writeln(
          '<line x1="${_formatNumber(left)}" y1="${_formatNumber(baseline)}" x2="${_formatNumber(left + chartWidth)}" y2="${_formatNumber(baseline)}" stroke="#334155" stroke-width="2"/>')
      ..writeln(
          '<line x1="${_formatNumber(left)}" y1="${_formatNumber(top)}" x2="${_formatNumber(left)}" y2="${_formatNumber(top + chartHeight)}" stroke="#334155" stroke-width="2"/>');
    return buffer.toString();
  }

  static String _axisLabelsSvg(
    _ChartSpec spec,
    double width,
    double height,
    double left,
    double top,
    double chartWidth,
    double chartHeight,
  ) {
    final buffer = StringBuffer();
    if (spec.xLabel != null && spec.xLabel!.isNotEmpty) {
      buffer.writeln(
          '<text x="${_formatNumber(left + chartWidth / 2)}" y="${_formatNumber(height - 22)}" text-anchor="middle" fill="#475569" font-family="Arial" font-size="12" font-weight="700">${_xmlEscape(spec.xLabel!)}</text>');
    }
    if (spec.yLabel != null && spec.yLabel!.isNotEmpty) {
      buffer.writeln(
          '<text x="22" y="${_formatNumber(top + chartHeight / 2)}" text-anchor="middle" transform="rotate(-90 22 ${_formatNumber(top + chartHeight / 2)})" fill="#475569" font-family="Arial" font-size="12" font-weight="700">${_xmlEscape(spec.yLabel!)}</text>');
    }
    return buffer.toString();
  }

  static String _formatChartValue(double value, String? unit) {
    final number = _formatNumber(value);
    final suffix = unit?.trim();
    if (suffix == null || suffix.isEmpty) return number;
    if (suffix == '%') return '$number%';
    if (suffix == '\$' || suffix.toLowerCase() == 'usd') return '\$$number';
    return '$number $suffix';
  }

  static List<String> _stringListArg(
    Map<String, dynamic> arguments,
    List<String> names,
  ) {
    for (final name in names) {
      final value = arguments[name];
      if (value is List) {
        return value
            .map((item) => '$item'.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      if (value is String && value.trim().isNotEmpty) {
        return value
            .split(RegExp(r'[\n\r,;]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  static List<double> _numberListArg(
    Map<String, dynamic> arguments,
    List<String> names,
  ) {
    for (final name in names) {
      final value = arguments[name];
      if (value is List) {
        return value.map(_asDouble).whereType<double>().toList();
      }
      if (value is String && value.trim().isNotEmpty) {
        return RegExp(r'-?\d[\d,]*(?:\.\d+)?')
            .allMatches(value)
            .map(
                (match) => double.tryParse(match.group(0)!.replaceAll(',', '')))
            .whereType<double>()
            .toList();
      }
    }
    return const [];
  }

  static _CiCliActionSpec? _ciCliActionSpec(String? action) {
    final normalized =
        action?.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    switch (normalized) {
      case 'test':
      case 'tests':
      case 'flutter_test':
        return const _CiCliActionSpec(
          action: 'flutter_test',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['test'],
          displayCommand: 'flutter test',
          supportsTarget: true,
        );
      case 'flutter_test_target':
      case 'flutter_test_file':
      case 'targeted_flutter_test':
        return const _CiCliActionSpec(
          action: 'flutter_test_target',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['test'],
          displayCommand: 'flutter test',
          supportsTarget: true,
        );
      case 'analyze':
      case 'analysis':
      case 'flutter_analyze':
        return const _CiCliActionSpec(
          action: 'flutter_analyze',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['analyze'],
          displayCommand: 'flutter analyze',
        );
      case 'dart_test_all':
      case 'dart_test':
        return const _CiCliActionSpec(
          action: 'dart_test',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['test'],
          displayCommand: 'dart test',
          supportsTarget: true,
        );
      case 'dart_analyze':
        return const _CiCliActionSpec(
          action: 'dart_analyze',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['analyze'],
          displayCommand: 'dart analyze',
        );
      case 'format_check':
      case 'format':
      case 'dart_format_check':
        return const _CiCliActionSpec(
          action: 'dart_format_check',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['format', '--set-exit-if-changed', '.'],
          displayCommand: 'dart format --set-exit-if-changed .',
        );
      case 'dart_format':
      case 'format_write':
        return const _CiCliActionSpec(
          action: 'dart_format',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['format', '.'],
          displayCommand: 'dart format .',
        );
      case 'pub_get':
      case 'flutter_pub_get':
        return const _CiCliActionSpec(
          action: 'flutter_pub_get',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['pub', 'get'],
          displayCommand: 'flutter pub get',
        );
      case 'dart_pub_get':
        return const _CiCliActionSpec(
          action: 'dart_pub_get',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['pub', 'get'],
          displayCommand: 'dart pub get',
        );
      case 'outdated':
      case 'pub_outdated':
      case 'flutter_pub_outdated':
        return const _CiCliActionSpec(
          action: 'flutter_pub_outdated',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['pub', 'outdated'],
          displayCommand: 'flutter pub outdated',
        );
      case 'dart_pub_outdated':
        return const _CiCliActionSpec(
          action: 'dart_pub_outdated',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['pub', 'outdated'],
          displayCommand: 'dart pub outdated',
        );
      case 'doctor':
      case 'flutter_doctor':
        return const _CiCliActionSpec(
          action: 'flutter_doctor',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['doctor', '-v'],
          displayCommand: 'flutter doctor -v',
        );
      case 'deps':
      case 'pub_deps':
      case 'flutter_pub_deps':
        return const _CiCliActionSpec(
          action: 'flutter_pub_deps',
          candidates: [
            _ProcessCandidate('flutter'),
            _ProcessCandidate('flutter.bat'),
          ],
          args: ['pub', 'deps'],
          displayCommand: 'flutter pub deps',
        );
      case 'dart_pub_deps':
        return const _CiCliActionSpec(
          action: 'dart_pub_deps',
          candidates: [
            _ProcessCandidate('dart'),
            _ProcessCandidate('dart.exe'),
          ],
          args: ['pub', 'deps'],
          displayCommand: 'dart pub deps',
        );
      default:
        return null;
    }
  }

  static List<Map<String, dynamic>> _workflowActions(
    String objective,
    String? stepText,
  ) {
    final rawSteps = stepText == null || stepText.trim().isEmpty
        ? const [
            'Collect required inputs',
            'Route to the right tools',
            'Run each tool and capture results',
            'Validate outputs against the objective',
            'Summarize completion and next actions',
          ]
        : stepText
            .split(stepText.contains('->')
                ? RegExp(r'\s*->\s*')
                : RegExp(r'[\n\r;,]+'))
            .map(_cleanIdeaText)
            .where((step) => step.isNotEmpty)
            .toList();
    final steps = rawSteps.isEmpty ? ['Complete $objective'] : rawSteps;
    return steps.asMap().entries.map((entry) {
      final routes = _routesForPrompt(entry.value);
      return {
        'id': entry.key + 1,
        'action': entry.value,
        'tool_hint': routes.isEmpty ? 'direct_response' : routes.first['tool'],
        'status': entry.key == 0 ? 'ready' : 'pending',
      };
    }).toList();
  }

  static String _titleCase(String text) {
    return text
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _clipOneLine(String text, int maxLength) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= maxLength) return oneLine;
    return oneLine.substring(0, maxLength - 1).trimRight();
  }

  static String _mermaidMindMapLabel(String text) {
    final clean = text
        .replaceAll(RegExp(r'[:\n\r{}\[\]()]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.isEmpty ? 'Item' : clean;
  }

  static String _mermaidQuote(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll(RegExp(r'[\n\r]+'), ' ')
        .trim();
  }

  static String _xmlEscape(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static List<LocalToolActivity> _unavailableToolWarnings(String _) {
    return const [];
  }

  static String? _stringArg(
    Map<String, dynamic> arguments,
    List<String> names,
  ) {
    for (final name in names) {
      final value = arguments[name];
      if (value == null) continue;
      if (value is String) return value;
      if (value is num || value is bool) return value.toString();
    }
    return null;
  }

  static int? _intArg(Map<String, dynamic> arguments, List<String> names) {
    for (final name in names) {
      final value = arguments[name];
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value);
    }
    return null;
  }

  static bool _boolArg(Map<String, dynamic> arguments, List<String> names) {
    for (final name in names) {
      final value = arguments[name];
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == 'yes' || normalized == '1') {
          return true;
        }
      }
    }
    return false;
  }

  static List<String> _pathsArg(Map<String, dynamic> arguments) {
    final paths = <String>[];

    void addPath(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        paths.add(value.trim());
      }
    }

    addPath(arguments['path']);
    final rawPaths = arguments['paths'];
    if (rawPaths is List) {
      for (final value in rawPaths) {
        addPath(value);
      }
    } else {
      addPath(rawPaths);
    }

    return paths.toSet().toList();
  }

  static List<String> _queryTerms(String query) {
    const stopWords = {
      'the',
      'and',
      'for',
      'with',
      'from',
      'that',
      'this',
      'what',
      'when',
      'where',
      'which',
      'about',
      'into',
      'your',
      'you',
      'are',
      'was',
      'were',
      'has',
      'have',
    };

    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9_]+'))
        .where((term) => term.length >= 2 && !stopWords.contains(term))
        .toSet()
        .take(12)
        .toList();
  }

  static Future<List<File>> _collectSearchFiles(
    List<String> roots, {
    required int limit,
  }) async {
    final files = <File>[];

    for (final root in roots) {
      if (files.length >= limit) break;
      await _addSearchPath(root, files, limit);
    }

    return files;
  }

  static Future<void> _addSearchPath(
    String path,
    List<File> files,
    int limit,
  ) async {
    if (files.length >= limit || _shouldSkipSearchPath(path)) return;

    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      final file = File(path);
      if (_isSearchableFile(file.path)) files.add(file);
      return;
    }

    if (type != FileSystemEntityType.directory) return;

    try {
      await for (final entity
          in Directory(path).list(recursive: true, followLinks: false)) {
        if (files.length >= limit) break;
        if (_shouldSkipSearchPath(entity.path)) continue;
        if (entity is File && _isSearchableFile(entity.path)) {
          files.add(entity);
        }
      }
    } catch (_) {
      return;
    }
  }

  static bool _isSearchableFile(String path) {
    const extensions = {
      '.txt',
      '.md',
      '.markdown',
      '.csv',
      '.tsv',
      '.json',
      '.yaml',
      '.yml',
      '.xml',
      '.html',
      '.htm',
      '.log',
      '.rtf',
      '.dart',
      '.js',
      '.ts',
      '.jsx',
      '.tsx',
      '.py',
      '.java',
      '.kt',
      '.swift',
      '.c',
      '.cc',
      '.cpp',
      '.h',
      '.hpp',
      '.cs',
      '.go',
      '.rs',
      '.php',
      '.rb',
      '.sh',
      '.ps1',
      '.gradle',
      '.properties',
    };

    return extensions.contains(_extension(path));
  }

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot).toLowerCase();
  }

  static bool _shouldSkipSearchPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/.git/') ||
        normalized.contains('/.dart_tool/') ||
        normalized.contains('/build/') ||
        normalized.contains('/node_modules/') ||
        normalized.contains('/.idea/') ||
        normalized.endsWith('/.git') ||
        normalized.endsWith('/.dart_tool') ||
        normalized.endsWith('/build') ||
        normalized.endsWith('/node_modules');
  }

  static String? _normalizeCodeLanguage(String? language, String code) {
    final normalized = language?.trim().toLowerCase();
    if (normalized == 'python' || normalized == 'py') return 'python';
    if (normalized == 'javascript' ||
        normalized == 'js' ||
        normalized == 'node') {
      return 'javascript';
    }

    final lowerCode = code.toLowerCase();
    if (RegExp(r'\b(console\.log|const |let |var |=>|function )')
        .hasMatch(lowerCode)) {
      return 'javascript';
    }
    if (RegExp(r'\b(print\(|def |import |for .+ in )').hasMatch(lowerCode)) {
      return 'python';
    }
    return null;
  }

  static String? _codeSafetyIssue(String language, String code) {
    if (code.length > 6000) {
      return 'snippet is too long for the guarded local executor.';
    }

    final blocked = language == 'python'
        ? <RegExp>[
            RegExp(
                r'(^|\n)\s*(from|import)\s+(os|sys|subprocess|socket|shutil|pathlib|glob|requests|urllib|http|ftplib|pickle|ctypes|multiprocessing|threading|importlib)\b',
                caseSensitive: false),
            RegExp(r'\b(open|eval|exec|compile|input|__import__)\s*\(',
                caseSensitive: false),
            RegExp(r'__\w+__'),
          ]
        : <RegExp>[
            RegExp(
                r'\b(require|import|eval|Function|fetch|XMLHttpRequest|WebSocket)\b',
                caseSensitive: false),
            RegExp(r'\b(process|global|Deno|Bun)\b'),
            RegExp(r'\b(fs|child_process|net|http|https|dgram)\b',
                caseSensitive: false),
          ];

    for (final pattern in blocked) {
      if (pattern.hasMatch(code)) {
        return 'blocked pattern matched: ${pattern.pattern}';
      }
    }
    return null;
  }

  static Future<_ProcessCapture> _runProcessCandidates(
    List<_ProcessCandidate> candidates,
    List<String> args, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    ProcessException? lastProcessException;

    for (final candidate in candidates) {
      try {
        return await _runProcess(
          candidate.executable,
          [...candidate.prefixArgs, ...args],
          workingDirectory: workingDirectory,
          timeout: timeout,
        );
      } on ProcessException catch (error) {
        lastProcessException = error;
      }
    }

    throw lastProcessException ??
        const ProcessException('', [], 'No runtime candidates were supplied.');
  }

  static Future<_ProcessCapture> _runProcess(
    String executable,
    List<String> args, {
    required String workingDirectory,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return _ProcessCapture(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      timedOut: timedOut,
    );
  }

  static bool shouldRunLiveWebSearch(String prompt) {
    final normalized = prompt.toLowerCase();
    if (_looksLikeDateTimeRequest(prompt)) return false;
    return _cryptoSymbolsForPrompt(prompt).isNotEmpty ||
        RegExp(r'\b(web search|search web|google|duckduckgo|brave|serper|latest|recent|newest|current|currently|today|tonight|yesterday|tomorrow|news|look up|lookup|online|price now|right now|up[- ]to[- ]date|as of|this week|this month|this year|breaking|trending|announced?|announcements?|released?|release date|launch(?:ed|es|ing)?|product updates?|new model|new product)\b')
            .hasMatch(normalized);
  }

  static bool _looksLikeDateTimeRequest(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(
      r"\b(today'?s date|date today|current date|what(?:'s| is) (?:the )?(?:date|time|day)|what day is it|day of (?:the )?week|current time|time is it|local time|time now|time zone|timezone|calendar date|date in [-+]?\d+ days|\d+ days (?:from|after|before) (?:today|now))\b",
    ).hasMatch(normalized);
  }

  static String _dateTimeActionForPrompt(String prompt) {
    final normalized = prompt.toLowerCase();
    if (_dateOffsetForPrompt(prompt) != null) return 'add_days';
    if (RegExp(r'\b(time|timezone|time zone)\b').hasMatch(normalized)) {
      return 'time';
    }
    if (RegExp(r'\b(weekday|what day|day of (?:the )?week)\b')
        .hasMatch(normalized)) {
      return 'weekday';
    }
    if (RegExp(r'\b(date|today)\b').hasMatch(normalized)) return 'date';
    return 'now';
  }

  static int? _dateOffsetForPrompt(String prompt) {
    final inMatch =
        RegExp(r'\b(?:date in |in )([-+]?\d+) days?\b', caseSensitive: false)
            .firstMatch(prompt);
    if (inMatch != null) return int.tryParse(inMatch.group(1)!);

    final beforeMatch =
        RegExp(r'\b(\d+) days? before (?:today|now)\b', caseSensitive: false)
            .firstMatch(prompt);
    if (beforeMatch != null) return -int.parse(beforeMatch.group(1)!);

    final afterMatch = RegExp(r'\b(\d+) days? (?:from|after) (?:today|now)\b',
            caseSensitive: false)
        .firstMatch(prompt);
    return afterMatch == null ? null : int.parse(afterMatch.group(1)!);
  }

  static bool _looksLikeWebReaderRequest(String prompt) {
    final normalized = prompt.toLowerCase();
    return _urlsForPrompt(prompt).isNotEmpty &&
        RegExp(r'\b(read|scrape|summarize|analyze|fetch|url|link|article|page)\b')
            .hasMatch(normalized);
  }

  static bool _looksLikeNoteRequest(String prompt) {
    return RegExp(r'\b(note_save|note_get)\s*\(', caseSensitive: false)
        .hasMatch(prompt);
  }

  static bool _looksLikeFileReadRequest(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(r'\b(read file|open file|cat file|file_reader|local file)\b')
        .hasMatch(normalized);
  }

  static bool _looksLikeShellRequest(String prompt) {
    final normalized = prompt.toLowerCase();
    return RegExp(r'\b(shell:|run command:|terminal:|command:)\b')
        .hasMatch(normalized);
  }

  static bool _looksLikeSketchRequest(String prompt) {
    final normalized = prompt.toLowerCase();
    if (shouldRunLiveWebSearch(prompt)) return false;
    return RegExp(r'\b(draw|sketch|diagram|flowchart|svg|wireframe)\b')
        .hasMatch(normalized);
  }

  static String? _extractExpression(String prompt) {
    final normalized = prompt.toLowerCase();
    final mathIntentRegex = RegExp(
      r'\b(calculate|compute|solve|what is|whats|evaluate)\b',
    );
    final mathIntent = mathIntentRegex.hasMatch(normalized);
    if (!mathIntent) return null;

    final matches = RegExp(r'[-+*/%^().\d\s]+').allMatches(prompt);
    var best = '';
    for (final match in matches) {
      final candidate = match.group(0)?.trim() ?? '';
      final digitCount = RegExp(r'\d').allMatches(candidate).length;
      final operatorCount = RegExp(r'[-+*/%^]').allMatches(candidate).length;
      if (digitCount >= 2 &&
          operatorCount >= 1 &&
          candidate.length > best.length) {
        best = candidate;
      }
    }

    return best.isEmpty ? null : best;
  }

  static List<_CryptoAsset> _cryptoSymbolsForPrompt(String prompt) {
    final normalized = prompt.toLowerCase();
    final wantsPrice =
        RegExp(r'\b(price|market|quote|worth|usd|current|now|today)\b')
            .hasMatch(normalized);
    if (!wantsPrice) return const [];

    const assets = [
      _CryptoAsset(
          symbol: 'BTC', coingeckoId: 'bitcoin', names: ['btc', 'bitcoin']),
      _CryptoAsset(
          symbol: 'ETH', coingeckoId: 'ethereum', names: ['eth', 'ethereum']),
      _CryptoAsset(
          symbol: 'SOL', coingeckoId: 'solana', names: ['sol', 'solana']),
      _CryptoAsset(
          symbol: 'DOGE', coingeckoId: 'dogecoin', names: ['doge', 'dogecoin']),
    ];

    return assets
        .where(
          (asset) => asset.names.any(
            (name) =>
                RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(normalized),
          ),
        )
        .toList();
  }

  static String _searchQueryForPrompt(String prompt) {
    var query = prompt.trim();
    final prefixes = [
      RegExp(r'^web search\s*:\s*', caseSensitive: false),
      RegExp(r'^search web\s*(for)?\s*', caseSensitive: false),
      RegExp(r'^look up\s*', caseSensitive: false),
    ];
    for (final prefix in prefixes) {
      query = query.replaceFirst(prefix, '').trim();
    }
    return query;
  }

  static List<String> _urlsForPrompt(String prompt) {
    return RegExp(r"""https?://[^\s<>)"']+""", caseSensitive: false)
        .allMatches(prompt)
        .map((match) => match.group(0)!)
        .toList();
  }

  static List<_SearchResult> _parseDuckDuckGoHtmlResults(String html) {
    final results = <_SearchResult>[];
    final anchorRegex = RegExp(
      r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );

    for (final match in anchorRegex.allMatches(html)) {
      final rawHref = match.group(1) ?? '';
      final url = _normalizeSearchUrl(rawHref);
      final title = _cleanHtmlText(match.group(2) ?? '');
      if (!_isUsableSearchResult(title, url)) continue;

      final snippet = _snippetAfter(html, match.end, title);
      results.add(_SearchResult(title: title, url: url, snippet: snippet));
      if (results.length >= 10) break;
    }

    return _dedupeSearchResults(results);
  }

  static List<_SearchResult> _parseBingHtmlResults(String html) {
    final results = <_SearchResult>[];
    final blockRegex = RegExp(
      r'''<li\b[^>]*class=["'][^"']*\bb_algo\b[^"']*["'][^>]*>([\s\S]*?)</li>''',
      caseSensitive: false,
    );
    final anchorRegex = RegExp(
      r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
      caseSensitive: false,
    );
    final paragraphRegex = RegExp(
      r'''<p\b[^>]*>([\s\S]*?)</p>''',
      caseSensitive: false,
    );

    for (final blockMatch in blockRegex.allMatches(html)) {
      final block = blockMatch.group(1) ?? '';
      final anchor = anchorRegex.firstMatch(block);
      if (anchor == null) continue;

      final url = _normalizeSearchUrl(anchor.group(1) ?? '');
      final title = _cleanHtmlText(anchor.group(2) ?? '');
      if (!_isUsableSearchResult(title, url)) continue;

      final paragraph = paragraphRegex.firstMatch(block)?.group(1) ?? '';
      final snippet = _cleanHtmlText(paragraph).isEmpty
          ? _snippetAfter(block, anchor.end, title)
          : _cleanHtmlText(paragraph);
      results.add(_SearchResult(title: title, url: url, snippet: snippet));
      if (results.length >= 10) break;
    }

    return _dedupeSearchResults(results);
  }

  static List<_SearchResult> _dedupeSearchResults(List<_SearchResult> results) {
    final seen = <String>{};
    final deduped = <_SearchResult>[];
    for (final result in results) {
      final key = result.url.toLowerCase();
      if (seen.add(key)) deduped.add(result);
    }
    return deduped;
  }

  static String _snippetAfter(String html, int start, String title) {
    final end = math.min(start + 900, html.length);
    if (start >= end) return 'No snippet returned.';

    var snippet = _cleanHtmlText(html.substring(start, end));
    if (snippet.startsWith(title)) {
      snippet = snippet.substring(title.length).trim();
    }
    snippet = snippet
        .replaceFirst(
            RegExp(r'^(cached|similar|more)\b', caseSensitive: false), '')
        .trim();
    return snippet.isEmpty ? 'No snippet returned.' : _clip(snippet, 280);
  }

  static bool _isUsableSearchResult(String title, String url) {
    if (title.length < 2 || !url.startsWith('http')) return false;
    final normalizedTitle = title.toLowerCase();
    if (normalizedTitle == 'next' ||
        normalizedTitle == 'previous' ||
        normalizedTitle == 'feedback' ||
        normalizedTitle.contains('duckduckgo')) {
      return false;
    }

    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';
    if (host.isEmpty) return false;
    if (host.endsWith('duckduckgo.com') ||
        (host.endsWith('bing.com') && uri?.path == '/search')) {
      return false;
    }
    return true;
  }

  static String _normalizeSearchUrl(String rawHref) {
    var href = _htmlDecode(rawHref.trim());
    if (href.startsWith('//')) href = 'https:$href';

    final uri = Uri.tryParse(href);
    if (uri != null) {
      final uddg = uri.queryParameters['uddg'];
      if (uddg != null && uddg.isNotEmpty) return uddg;
      final url = uri.queryParameters['url'];
      if (url != null && url.startsWith('http')) return url;
    }

    final uddgMatch = RegExp(r'[?&]uddg=([^&]+)').firstMatch(href);
    if (uddgMatch != null) {
      return Uri.decodeComponent(uddgMatch.group(1)!);
    }

    if (href.startsWith('/l/?')) {
      final absolute = Uri.tryParse('https://duckduckgo.com$href');
      final uddg = absolute?.queryParameters['uddg'];
      if (uddg != null && uddg.isNotEmpty) return uddg;
    }

    return href;
  }

  static String _cleanHtmlText(String html) {
    return _htmlDecode(
      html
          .replaceAll(
              RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
          .replaceAll(
              RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  static String _htmlDecode(String text) {
    var decoded = text;
    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&nbsp;': ' ',
    };
    for (final entry in entities.entries) {
      decoded = decoded.replaceAll(entry.key, entry.value);
    }

    decoded = decoded.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) {
        final codePoint = int.tryParse(match.group(1)!);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      },
    );
    decoded = decoded.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) {
        final codePoint = int.tryParse(match.group(1)!, radix: 16);
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      },
    );
    return decoded;
  }

  static String? _quotedPathForPrompt(String prompt) {
    final match = RegExp(r"""["']([^"']+)["']""").firstMatch(prompt);
    return match?.group(1);
  }

  static String? _shellCommandForPrompt(String prompt) {
    final match = RegExp(
      r'(?:shell|run command|terminal|command)\s*:\s*([^\n\r]+)',
      caseSensitive: false,
    ).firstMatch(prompt);
    return match?.group(1)?.trim();
  }

  static List<String> _splitCommand(String command) {
    final matches =
        RegExp(r'''"([^"]*)"|'([^']*)'|(\S+)''').allMatches(command);
    return matches
        .map(
            (match) => match.group(1) ?? match.group(2) ?? match.group(3) ?? '')
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static String _stripHtml(String html) {
    var text = html
        .replaceAll(
            RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    const entities = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&nbsp;': ' ',
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }

  static String _noteStorageKey(String key) => 'quick_llm_note_$key';

  static String _clip(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}\n[... clipped ${text.length - maxLength} characters ...]';
  }

  static num? _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value);
    return null;
  }

  static double? _asDouble(dynamic value) => _asNum(value)?.toDouble();

  static int? _asInt(dynamic value) => _asNum(value)?.toInt();

  static String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatCurrency(double value) {
    if (value >= 1000) {
      final fixed = value.toStringAsFixed(2);
      final parts = fixed.split('.');
      final whole = parts.first.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
      return '$whole.${parts.last}';
    }
    return value.toStringAsFixed(value >= 1 ? 2 : 6);
  }
}

class LocalToolContext {
  final List<String> results;
  final List<LocalToolActivity> activities;

  const LocalToolContext(
    this.results, {
    this.activities = const [],
  });

  bool get hasResults => results.isNotEmpty;
  bool get hasActivities => activities.isNotEmpty;

  LocalToolContext merge(LocalToolContext other) {
    return LocalToolContext(
      [...results, ...other.results],
      activities: [...activities, ...other.activities],
    );
  }

  Map<String, dynamic> toDetails() {
    return {
      'tier': 'Tier 1 - Core Power User Tools',
      'activity_count': activities.length,
      'activity': activities.map((activity) => activity.toJson()).toList(),
      'catalog': LocalToolService.tierOneTools
          .map((definition) => definition.toJson())
          .toList(),
    };
  }
}

class LocalToolCallBatch {
  final List<Map<String, dynamic>> toolMessages;
  final LocalToolContext context;

  const LocalToolCallBatch({
    required this.toolMessages,
    required this.context,
  });
}

class LocalToolDefinition {
  final String id;
  final String title;
  final String summary;
  final String detail;
  final String uiSurface;

  const LocalToolDefinition({
    required this.id,
    required this.title,
    required this.summary,
    required this.detail,
    required this.uiSurface,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'detail': detail,
      'ui_surface': uiSurface,
    };
  }
}

enum LocalToolStatus { queued, ready, complete, failed, unavailable }

class LocalToolActivity {
  final String id;
  final String title;
  final LocalToolStatus status;
  final String summary;
  final String uiSurface;
  final List<String> steps;
  final String? output;
  final String? error;
  final List<LocalToolSource> sources;
  final String? artifactType;
  final String? artifactContent;
  final String? artifactLabel;
  final String? artifactFileName;
  final String? artifactEncoding;

  const LocalToolActivity({
    required this.id,
    required this.title,
    required this.status,
    required this.summary,
    required this.uiSurface,
    required this.steps,
    this.output,
    this.error,
    this.sources = const [],
    this.artifactType,
    this.artifactContent,
    this.artifactLabel,
    this.artifactFileName,
    this.artifactEncoding,
  });

  factory LocalToolActivity.complete({
    required String id,
    required String title,
    required String summary,
    required String uiSurface,
    required List<String> steps,
    String? output,
    List<LocalToolSource> sources = const [],
    String? artifactType,
    String? artifactContent,
    String? artifactLabel,
    String? artifactFileName,
    String? artifactEncoding,
  }) {
    return LocalToolActivity(
      id: id,
      title: title,
      status: LocalToolStatus.complete,
      summary: summary,
      uiSurface: uiSurface,
      steps: steps,
      output: output,
      sources: sources,
      artifactType: artifactType,
      artifactContent: artifactContent,
      artifactLabel: artifactLabel,
      artifactFileName: artifactFileName,
      artifactEncoding: artifactEncoding,
    );
  }

  factory LocalToolActivity.ready({
    required String id,
    required String title,
    required String summary,
    required String uiSurface,
    required List<String> steps,
  }) {
    return LocalToolActivity(
      id: id,
      title: title,
      status: LocalToolStatus.ready,
      summary: summary,
      uiSurface: uiSurface,
      steps: steps,
    );
  }

  factory LocalToolActivity.failed({
    required String id,
    required String title,
    required String summary,
    required String uiSurface,
    required String error,
    required List<String> steps,
  }) {
    return LocalToolActivity(
      id: id,
      title: title,
      status: LocalToolStatus.failed,
      summary: summary,
      uiSurface: uiSurface,
      steps: steps,
      error: error,
    );
  }

  factory LocalToolActivity.unavailable({
    required String id,
    required String title,
    required String summary,
    required String uiSurface,
    required List<String> steps,
  }) {
    return LocalToolActivity(
      id: id,
      title: title,
      status: LocalToolStatus.unavailable,
      summary: summary,
      uiSurface: uiSurface,
      steps: steps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'status': status.name,
      'summary': summary,
      'ui_surface': uiSurface,
      'steps': steps,
      if (output != null) 'output': output,
      if (error != null) 'error': error,
      if (sources.isNotEmpty)
        'sources': sources.map((source) => source.toJson()).toList(),
      if (artifactType != null && artifactContent != null)
        'artifact': {
          'type': artifactType,
          'content': artifactContent,
          if (artifactLabel != null) 'label': artifactLabel,
          if (artifactFileName != null) 'file_name': artifactFileName,
          if (artifactEncoding != null) 'encoding': artifactEncoding,
        },
    };
  }
}

class LocalToolSource {
  final String title;
  final String url;

  const LocalToolSource({
    required this.title,
    required this.url,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
    };
  }
}

class _ToolExecution {
  final List<String> results;
  final List<LocalToolActivity> activities;

  const _ToolExecution({
    this.results = const [],
    this.activities = const [],
  });

  bool get hasCompletedActivity => activities.any(
        (activity) => activity.status == LocalToolStatus.complete,
      );

  factory _ToolExecution.singleFailure({
    required String id,
    required String title,
    required String uiSurface,
    required String summary,
    required String error,
    required String result,
    LocalToolStatus status = LocalToolStatus.failed,
  }) {
    final activity = status == LocalToolStatus.unavailable
        ? LocalToolActivity.unavailable(
            id: id,
            title: title,
            summary: summary,
            uiSurface: uiSurface,
            steps: [error],
          )
        : LocalToolActivity.failed(
            id: id,
            title: title,
            summary: summary,
            uiSurface: uiSurface,
            error: error,
            steps: [error],
          );
    return _ToolExecution(results: [result], activities: [activity]);
  }
}

class _ParsedToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const _ParsedToolCall({
    required this.name,
    required this.arguments,
  });

  factory _ParsedToolCall.fromOllama(
    Map<String, dynamic> raw,
    int fallbackIndex,
  ) {
    final function = raw['function'];
    if (function is Map) {
      return _ParsedToolCall(
        name: (function['name'] ?? raw['name'] ?? 'unknown_tool').toString(),
        arguments: _parseArguments(function['arguments']),
      );
    }

    return _ParsedToolCall(
      name: (raw['name'] ?? 'unknown_tool_$fallbackIndex').toString(),
      arguments: _parseArguments(raw['arguments'] ?? raw['input']),
    );
  }

  static Map<String, dynamic> _parseArguments(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return {'input': value};
      }
    }
    return const {};
  }
}

class _CryptoAsset {
  final String symbol;
  final String coingeckoId;
  final List<String> names;

  const _CryptoAsset({
    required this.symbol,
    required this.coingeckoId,
    required this.names,
  });
}

class _SearchProviderFetch {
  final String name;
  final Uri url;
  final List<_SearchResult> Function(String html) parser;

  const _SearchProviderFetch({
    required this.name,
    required this.url,
    required this.parser,
  });
}

class _SearchResult {
  final String title;
  final String url;
  final String snippet;

  const _SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

class _DocumentSearchHit {
  final String path;
  final int lineNumber;
  final String snippet;
  final int score;

  const _DocumentSearchHit({
    required this.path,
    required this.lineNumber,
    required this.snippet,
    required this.score,
  });
}

class _DeterministicRandom {
  int _state;
  double? _spareNormal;

  _DeterministicRandom(int seed) : _state = seed & 0x7fffffff {
    if (_state == 0) _state = 1;
  }

  double nextDouble() {
    _state = (1103515245 * _state + 12345) & 0x7fffffff;
    return _state / 0x7fffffff;
  }

  double nextStandardNormal() {
    final spare = _spareNormal;
    if (spare != null) {
      _spareNormal = null;
      return spare;
    }

    final u1 = math.max(nextDouble(), 1e-12);
    final u2 = nextDouble();
    final radius = math.sqrt(-2 * math.log(u1));
    final theta = 2 * math.pi * u2;
    _spareNormal = radius * math.sin(theta);
    return radius * math.cos(theta);
  }
}

class _ChartEntry {
  final String label;
  final double value;

  const _ChartEntry(this.label, this.value);
}

class _ChartSpec {
  final String title;
  final String? subtitle;
  final String chartType;
  final List<_ChartEntry> entries;
  final String? xLabel;
  final String? yLabel;
  final String? unit;

  const _ChartSpec({
    required this.title,
    required this.subtitle,
    required this.chartType,
    required this.entries,
    required this.xLabel,
    required this.yLabel,
    required this.unit,
  });

  Map<String, dynamic> toJson() {
    return {
      if (subtitle != null && subtitle!.isNotEmpty) 'subtitle': subtitle,
      if (xLabel != null && xLabel!.isNotEmpty) 'x_label': xLabel,
      if (yLabel != null && yLabel!.isNotEmpty) 'y_label': yLabel,
      if (unit != null && unit!.isNotEmpty) 'unit': unit,
      'entry_count': entries.length,
    };
  }
}

class _ChartExtent {
  final double min;
  final double max;

  const _ChartExtent(this.min, this.max);

  double get span => max - min;
}

class _CiCliActionSpec {
  final String action;
  final List<_ProcessCandidate> candidates;
  final List<String> args;
  final String displayCommand;
  final bool supportsTarget;

  const _CiCliActionSpec({
    required this.action,
    required this.candidates,
    required this.args,
    required this.displayCommand,
    this.supportsTarget = false,
  });
}

class _ProcessCandidate {
  final String executable;
  final List<String> prefixArgs;

  const _ProcessCandidate(
    this.executable, [
    this.prefixArgs = const [],
  ]);
}

class _ProcessCapture {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  const _ProcessCapture({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });
}

class _ExpressionEvaluator {
  _ExpressionEvaluator(this.source);

  final String source;
  int _index = 0;

  double? parse() {
    try {
      final result = _parseExpression();
      _skipWhitespace();
      return _index == source.length ? result : null;
    } catch (_) {
      return null;
    }
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipWhitespace();
      if (_consume('+')) {
        value += _parseTerm();
      } else if (_consume('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parsePower();
    while (true) {
      _skipWhitespace();
      if (_consume('*')) {
        value *= _parsePower();
      } else if (_consume('/')) {
        value /= _parsePower();
      } else if (_consume('%')) {
        value %= _parsePower();
      } else {
        return value;
      }
    }
  }

  double _parsePower() {
    var value = _parseFactor();
    _skipWhitespace();
    if (_consume('^')) {
      value = math.pow(value, _parsePower()).toDouble();
    }
    return value;
  }

  double _parseFactor() {
    _skipWhitespace();
    if (_consume('+')) return _parseFactor();
    if (_consume('-')) return -_parseFactor();

    if (_consume('(')) {
      final value = _parseExpression();
      if (!_consume(')')) throw const FormatException('Missing )');
      return value;
    }

    return _parseNumber();
  }

  double _parseNumber() {
    _skipWhitespace();
    final start = _index;
    while (
        _index < source.length && RegExp(r'[\d.]').hasMatch(source[_index])) {
      _index++;
    }

    if (start == _index) throw const FormatException('Expected number');
    return double.parse(source.substring(start, _index));
  }

  bool _consume(String char) {
    _skipWhitespace();
    if (_index < source.length && source[_index] == char) {
      _index++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_index < source.length && source[_index].trim().isEmpty) {
      _index++;
    }
  }
}
