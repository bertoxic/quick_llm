import 'dart:isolate';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

const _pdfMargin = 42.0;
const _svgTextFontFamily = 'QuickLlmPdfSvg';

/// Exports an assistant reply as a styled, paginated PDF.
///
/// The renderer intentionally handles the Markdown blocks emitted most often
/// by chat models: headings, paragraphs, lists, quotes, code blocks, rules,
/// and GitHub-style tables.
class MarkdownPdfService {
  static final PdfColor _ink = PdfColor(31, 41, 55);
  static final PdfColor _muted = PdfColor(100, 116, 139);
  static final PdfColor _teal = PdfColor(13, 148, 136);
  static final PdfColor _softTeal = PdfColor(236, 253, 245);
  static final PdfColor _softCode = PdfColor(15, 23, 42);
  static final PdfColor _line = PdfColor(203, 213, 225);
  List<int>? _regularFontData;
  List<int>? _boldFontData;
  List<int>? _codeFontData;
  List<int>? _svgTextFontData;
  Future<void>? _svgTextFontLoad;

  Future<File> download(
    String source, {
    String title = 'Quick LLM response',
    Directory? outputDirectory,
    void Function(String stage)? onStage,
  }) async {
    final markdownSource = source.trim();
    if (markdownSource.isEmpty) {
      throw const MarkdownPdfException('There is no response to export.');
    }

    final downloadsDirectory = outputDirectory ??
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    if (!await downloadsDirectory.exists()) {
      await downloadsDirectory.create(recursive: true);
    }

    onStage?.call('Preparing PDF');
    // Give the download button time to repaint its progress state before any
    // synchronous PDF work begins.
    await Future<void>.delayed(Duration.zero);

    final containsSvg = RegExp(
      r'<svg\b[\s\S]*?</svg>',
      caseSensitive: false,
    ).hasMatch(markdownSource);
    final List<int> bytes;
    if (containsSvg) {
      onStage?.call('Rendering diagrams');
      await _loadFonts();
      bytes = await _buildPdfBytes(markdownSource, title);
    } else {
      onStage?.call('Formatting response');
      bytes = await Isolate.run(
        () => _buildTextOnlyPdfInBackground(markdownSource, title),
      );
    }

    onStage?.call('Saving PDF');
    final destination = File(
      '${downloadsDirectory.path}${Platform.pathSeparator}'
      'quick_llm_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    return destination.writeAsBytes(bytes, flush: true);
  }

  Future<List<int>> _buildPdfBytes(String source, String title) async {
    final document = PdfDocument()
      ..pageSettings.margins = (PdfMargins()..all = _pdfMargin);
    try {
      _addFooter(document);
      final cursor = _PdfCursor(document, document.pages.add());
      _drawTitle(cursor, title);

      await _drawMarkdownAndSvg(cursor, source);

      return await document.save();
    } finally {
      document.dispose();
    }
  }

  void _addFooter(PdfDocument document) {
    final footer = PdfPageTemplateElement(const Rect.fromLTWH(0, 0, 510, 24));
    footer.graphics.drawLine(
      PdfPen(_line, width: 0.5),
      const Offset(_pdfMargin, 1),
      const Offset(510 - _pdfMargin, 1),
    );
    footer.graphics.drawString(
      'Quick LLM  |  Markdown export',
      _font(8),
      brush: PdfSolidBrush(_muted),
      bounds: const Rect.fromLTWH(_pdfMargin, 7, 220, 12),
    );
    document.template.bottom = footer;
  }

  void _drawTitle(_PdfCursor cursor, String title) {
    _drawText(
      cursor,
      title,
      font: _font(20, bold: true),
      color: _ink,
      bottomSpacing: 4,
    );
    _drawText(
      cursor,
      'Exported ${_formatDate(DateTime.now())}',
      font: _font(8.5),
      color: _muted,
      bottomSpacing: 16,
    );
  }

  /// Renders raw SVG blocks as images rather than letting the Markdown parser
  /// turn the XML markup into a paragraph of text.
  Future<void> _drawMarkdownAndSvg(_PdfCursor cursor, String source) async {
    final svgPattern = RegExp(r'<svg\b[\s\S]*?</svg>', caseSensitive: false);
    var offset = 0;
    for (final match in svgPattern.allMatches(source)) {
      _drawMarkdown(cursor, source.substring(offset, match.start));
      await _drawSvg(cursor, match.group(0)!);
      offset = match.end;
    }
    _drawMarkdown(cursor, source.substring(offset));
  }

  void _drawMarkdown(_PdfCursor cursor, String source) {
    if (source.trim().isEmpty) return;
    final nodes = markdown.Document(
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    ).parse(source);
    for (final node in nodes) {
      if (node is markdown.Element) {
        _drawBlock(cursor, node);
      } else if (node.textContent.trim().isNotEmpty) {
        _drawParagraph(cursor, node.textContent);
      }
    }
  }

  Future<void> _drawSvg(_PdfCursor cursor, String svg) async {
    PictureInfo? pictureInfo;
    Picture? scaledPicture;
    Image? image;
    try {
      try {
        await _loadSvgTextFont();
      } catch (_) {
        // The SVG still has a platform fallback if a local text font cannot
        // be registered on this device.
      }
      pictureInfo = await vg.loadPicture(
        SvgStringLoader(_svgForPdf(svg)),
        null,
      );
      final sourceSize = pictureInfo.size;
      final sourceWidth = sourceSize.width > 0 ? sourceSize.width : 4.0;
      final sourceHeight = sourceSize.height > 0 ? sourceSize.height : 3.0;
      final aspectRatio = sourceWidth / sourceHeight;

      var targetWidth = cursor.width;
      var targetHeight = targetWidth / aspectRatio;
      if (targetHeight > 340) {
        targetHeight = 340;
        targetWidth = targetHeight * aspectRatio;
      }
      if (targetHeight < 96) {
        targetHeight = 96;
        targetWidth = targetHeight * aspectRatio;
      }

      final pixelWidth = (targetWidth * 2).round().clamp(1, 2400).toInt();
      final pixelHeight = (targetHeight * 2).round().clamp(1, 2400).toInt();
      final recorder = PictureRecorder();
      Canvas(recorder)
        ..scale(pixelWidth / sourceWidth, pixelHeight / sourceHeight)
        ..drawPicture(pictureInfo.picture);
      scaledPicture = recorder.endRecording();
      image = await scaledPicture.toImage(pixelWidth, pixelHeight);
      final png = await image.toByteData(format: ImageByteFormat.png);
      if (png == null) throw StateError('The SVG could not be encoded.');

      cursor.ensureSpace(targetHeight + 12);
      cursor.page.graphics.drawImage(
        PdfBitmap(png.buffer.asUint8List()),
        Rect.fromLTWH(_pdfMargin, cursor.y, targetWidth, targetHeight),
      );
      cursor.y += targetHeight + 12;
    } catch (_) {
      _drawBoxedText(
        cursor,
        'SVG graphic could not be rendered.',
        background: PdfColor(255, 247, 237),
        textColor: _ink,
        font: _font(10),
        bottomSpacing: 10,
      );
    } finally {
      image?.dispose();
      scaledPicture?.dispose();
      pictureInfo?.picture.dispose();
    }
  }

  /// SVGs from model responses commonly request desktop fonts such as Arial.
  /// Those fonts are not guaranteed to be available to Flutter's SVG rasterizer
  /// on every desktop, which otherwise displays each label as a missing glyph.
  String _svgForPdf(String svg) {
    final withoutDesktopFont = svg.replaceAll(
      RegExp(r'''\sfont-family\s*=\s*(?:"[^"]*"|'[^']*')''',
          caseSensitive: false),
      '',
    );
    return withoutDesktopFont.replaceAllMapped(
      RegExp(r'<text\b([^>]*)>', caseSensitive: false),
      (match) => '<text${match.group(1)} font-family="$_svgTextFontFamily">',
    );
  }

  void _drawBlock(_PdfCursor cursor, markdown.Element element) {
    switch (element.tag) {
      case 'h1':
        _drawHeading(cursor, element.textContent, 18, 14);
      case 'h2':
        _drawHeading(cursor, element.textContent, 15, 12);
      case 'h3':
        _drawHeading(cursor, element.textContent, 13, 10);
      case 'h4':
      case 'h5':
      case 'h6':
        _drawHeading(cursor, element.textContent, 11, 8);
      case 'p':
        _drawParagraph(cursor, element.textContent);
      case 'ul':
        _drawList(cursor, element, ordered: false);
      case 'ol':
        _drawList(cursor, element, ordered: true);
      case 'blockquote':
        _drawQuote(cursor, element.textContent);
      case 'pre':
        _drawCode(cursor, element.textContent);
      case 'table':
        _drawTable(cursor, element);
      case 'hr':
        _drawRule(cursor);
      case 'img':
        _drawParagraph(
            cursor, '[Image: ${element.attributes['alt'] ?? 'image'}]');
      default:
        final text = element.textContent.trim();
        if (text.isNotEmpty) _drawParagraph(cursor, text);
    }
  }

  void _drawHeading(
    _PdfCursor cursor,
    String text,
    double size,
    double spacing,
  ) {
    _drawText(
      cursor,
      _cleanText(text),
      font: _font(size, bold: true),
      color: _teal,
      topSpacing: 4,
      bottomSpacing: spacing,
    );
  }

  void _drawParagraph(_PdfCursor cursor, String text) {
    final clean = _cleanText(text);
    if (clean.isEmpty) return;
    _drawText(
      cursor,
      clean,
      font: _font(10.5),
      color: _ink,
      bottomSpacing: 9,
    );
  }

  void _drawList(
    _PdfCursor cursor,
    markdown.Element list, {
    required bool ordered,
  }) {
    final items = (list.children ?? const <markdown.Node>[])
        .whereType<markdown.Element>()
        .where((item) => item.tag == 'li')
        .toList();
    for (var index = 0; index < items.length; index++) {
      final marker = ordered ? '${index + 1}.' : '-';
      _drawText(
        cursor,
        '$marker ${_cleanText(items[index].textContent)}',
        font: _font(10.5),
        color: _ink,
        leftInset: 12,
        bottomSpacing: 5,
      );
    }
    cursor.y += 4;
  }

  void _drawQuote(_PdfCursor cursor, String text) {
    _drawBoxedText(
      cursor,
      _cleanText(text),
      background: _softTeal,
      textColor: _ink,
      font: _font(10.5),
      bottomSpacing: 10,
    );
  }

  void _drawCode(_PdfCursor cursor, String text) {
    final chunks = _chunkCodeBlock(text.trimRight());
    for (var index = 0; index < chunks.length; index++) {
      _drawBoxedText(
        cursor,
        chunks[index],
        background: _softCode,
        textColor: PdfColor(226, 232, 240),
        font: _font(8.5, monospace: true),
        bottomSpacing: index == chunks.length - 1 ? 11 : 3,
        hardWrap: true,
      );
    }
  }

  /// Splits code into small, bounded layout units before handing it to
  /// [PdfGrid]. A single very long YAML value can otherwise make the PDF
  /// layout engine repeatedly measure one enormous table cell.
  List<String> _chunkCodeBlock(String source) {
    if (source.isEmpty) return const <String>[];

    const maxCharactersPerVisualLine = 100;
    const maxVisualLinesPerChunk = 28;
    final visualLines = <String>[];

    for (final line in source.split('\n')) {
      if (line.isEmpty) {
        visualLines.add('');
        continue;
      }

      var start = 0;
      while (start < line.length) {
        var end = math.min(start + maxCharactersPerVisualLine, line.length);
        // Do not split a Unicode surrogate pair while hard-wrapping a long
        // scalar value. YAML is usually ASCII, but generated data can contain
        // emoji and other supplementary characters.
        if (end < line.length &&
            end > start &&
            line.codeUnitAt(end) >= 0xDC00 &&
            line.codeUnitAt(end) <= 0xDFFF) {
          end--;
        }
        if (end == start) end = math.min(start + 2, line.length);
        visualLines.add(line.substring(start, end));
        start = end;
      }
    }

    return <String>[
      for (var start = 0;
          start < visualLines.length;
          start += maxVisualLinesPerChunk)
        visualLines
            .sublist(
              start,
              math.min(start + maxVisualLinesPerChunk, visualLines.length),
            )
            .join('\n'),
    ];
  }

  void _drawRule(_PdfCursor cursor) {
    cursor.ensureSpace(12);
    cursor.page.graphics.drawLine(
      PdfPen(_line, width: 0.7),
      Offset(_pdfMargin, cursor.y + 4),
      Offset(_pdfMargin + cursor.width, cursor.y + 4),
    );
    cursor.y += 12;
  }

  void _drawTable(_PdfCursor cursor, markdown.Element table) {
    final rows = _tableRows(table);
    if (rows.isEmpty) return;

    final columnCount = rows.first.length;
    if (columnCount == 0) return;

    final grid = PdfGrid()
      ..repeatHeader = true
      ..style = PdfGridStyle(
        cellPadding: PdfPaddings(left: 6, right: 6, top: 5, bottom: 5),
        font: _font(8.5),
      );
    grid.columns.add(count: columnCount);
    grid.headers.add(1);

    for (var column = 0; column < columnCount; column++) {
      final cell = grid.headers[0].cells[column];
      cell.value = _pdfSafeText(rows.first[column]);
      cell.style = PdfGridCellStyle(
        backgroundBrush: PdfSolidBrush(_teal),
        textBrush: PdfBrushes.white,
        font: _font(8.5, bold: true),
      );
    }

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = grid.rows.add();
      for (var column = 0; column < columnCount; column++) {
        final cell = row.cells[column];
        cell.value = _pdfSafeText(rows[rowIndex][column]);
        if (rowIndex.isEven) {
          cell.style = PdfGridCellStyle(
            backgroundBrush: PdfSolidBrush(PdfColor(248, 250, 252)),
          );
        }
      }
    }

    final result = grid.draw(
      page: cursor.page,
      bounds: Rect.fromLTWH(_pdfMargin, cursor.y, cursor.width, 0),
      format: cursor.layoutFormat,
    );
    if (result != null) cursor.updateFrom(result, bottomSpacing: 12);
  }

  List<List<String>> _tableRows(markdown.Element table) {
    final rows = <List<String>>[];
    void collect(markdown.Element element) {
      if (element.tag == 'tr') {
        rows.add(
          (element.children ?? const <markdown.Node>[])
              .whereType<markdown.Element>()
              .where((cell) => cell.tag == 'th' || cell.tag == 'td')
              .map((cell) => _cleanText(cell.textContent))
              .toList(),
        );
        return;
      }
      for (final child in element.children ?? const <markdown.Node>[]) {
        if (child is markdown.Element) collect(child);
      }
    }

    collect(table);
    return rows;
  }

  void _drawBoxedText(
    _PdfCursor cursor,
    String text, {
    required PdfColor background,
    required PdfColor textColor,
    required PdfFont font,
    required double bottomSpacing,
    bool hardWrap = false,
  }) {
    final grid = PdfGrid()
      ..columns.add(count: 1)
      ..style = PdfGridStyle(
        cellPadding: PdfPaddings(left: 9, right: 9, top: 8, bottom: 8),
      );
    final cell = grid.rows.add().cells[0];
    cell.value = _pdfSafeText(text);
    cell.style = PdfGridCellStyle(
      backgroundBrush: PdfSolidBrush(background),
      textBrush: PdfSolidBrush(textColor),
      font: font,
      format: hardWrap
          ? PdfStringFormat(wordWrap: PdfWordWrapType.character)
          : null,
    );
    final result = grid.draw(
      page: cursor.page,
      bounds: Rect.fromLTWH(_pdfMargin, cursor.y, cursor.width, 0),
      format: cursor.layoutFormat,
    );
    if (result != null) cursor.updateFrom(result, bottomSpacing: bottomSpacing);
  }

  void _drawText(
    _PdfCursor cursor,
    String text, {
    required PdfFont font,
    required PdfColor color,
    double topSpacing = 0,
    double bottomSpacing = 0,
    double leftInset = 0,
  }) {
    cursor.y += topSpacing;
    final element = PdfTextElement(
      text: _pdfSafeText(text),
      font: font,
      brush: PdfSolidBrush(color),
      format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
    );
    final result = element.draw(
      page: cursor.page,
      bounds: Rect.fromLTWH(
        _pdfMargin + leftInset,
        cursor.y,
        cursor.width - leftInset,
        0,
      ),
      format: cursor.layoutFormat,
    );
    if (result != null) cursor.updateFrom(result, bottomSpacing: bottomSpacing);
  }

  Future<void> _loadFonts() async {
    if (_regularFontData != null) return;

    _regularFontData = await _readFirstFont(const [
      r'C:\Windows\Fonts\seguiemj.ttf',
      r'C:\Windows\Fonts\segoeui.ttf',
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ]);
    _boldFontData = await _readFirstFont(const [
      r'C:\Windows\Fonts\seguiemj.ttf',
      r'C:\Windows\Fonts\segoeuib.ttf',
      '/System/Library/Fonts/Supplemental/Arial Bold.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    ]);
    _codeFontData = await _readFirstFont(const [
      r'C:\Windows\Fonts\consola.ttf',
      '/System/Library/Fonts/Menlo.ttc',
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
    ]);
    _svgTextFontData = await _readFirstFont(const [
      r'C:\Windows\Fonts\segoeui.ttf',
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ]);
  }

  Future<List<int>?> _readFirstFont(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) return file.readAsBytes();
    }
    return null;
  }

  Future<void> _loadSvgTextFont() {
    return _svgTextFontLoad ??= () async {
      final fontData = _svgTextFontData;
      if (fontData == null) return;
      await loadFontFromList(
        Uint8List.fromList(fontData),
        fontFamily: _svgTextFontFamily,
      );
    }();
  }

  PdfFont _font(
    double size, {
    bool bold = false,
    bool monospace = false,
  }) {
    final data = monospace
        ? _codeFontData
        : bold
            ? _boldFontData ?? _regularFontData
            : _regularFontData;
    if (data != null) return PdfTrueTypeFont(data, size);

    return PdfStandardFont(
      monospace ? PdfFontFamily.courier : PdfFontFamily.helvetica,
      size,
      style: bold ? PdfFontStyle.bold : PdfFontStyle.regular,
    );
  }

  String _pdfSafeText(String text) {
    final safe = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0xD800 && rune <= 0xDFFF) {
        // A standalone UTF-16 surrogate is malformed text. Preserve valid
        // emoji (which are supplementary-plane code points) and guard only
        // this invalid input so it cannot break PDF generation.
        safe.write('?');
      } else {
        safe.writeCharCode(rune);
      }
    }
    return safe.toString();
  }

  String _cleanText(String text) => text
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  String _formatDate(DateTime time) {
    final local = time.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Text-only documents use a worker isolate so a long assistant response does
/// not monopolize the Flutter UI thread while it is being laid out.
Future<List<int>> _buildTextOnlyPdfInBackground(
  String source,
  String title,
) async {
  final renderer = MarkdownPdfService();
  await renderer._loadFonts();
  return renderer._buildPdfBytes(source, title);
}

class _PdfCursor {
  _PdfCursor(this.document, this.page);

  final PdfDocument document;
  PdfPage page;
  double y = _pdfMargin;

  double get width => page.getClientSize().width - (_pdfMargin * 2);
  double get _bottom => page.getClientSize().height - _pdfMargin;

  PdfLayoutFormat get layoutFormat => PdfLayoutFormat(
        layoutType: PdfLayoutType.paginate,
        paginateBounds: Rect.fromLTWH(
          _pdfMargin,
          _pdfMargin,
          width,
          _bottom - _pdfMargin,
        ),
      );

  void ensureSpace(double amount) {
    if (y + amount <= _bottom) return;
    page = document.pages.add();
    y = _pdfMargin;
  }

  void updateFrom(PdfLayoutResult result, {required double bottomSpacing}) {
    page = result.page;
    y = result.bounds.bottom + bottomSpacing;
    ensureSpace(1);
  }
}

class MarkdownPdfException implements Exception {
  final String message;

  const MarkdownPdfException(this.message);

  @override
  String toString() => message;
}
