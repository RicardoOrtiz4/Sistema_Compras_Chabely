import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBytesToSelectedPathImpl(String path, Uint8List bytes) async {
  final fileName = path.split(RegExp(r'[\\/]')).last.trim();
  final blob = html.Blob(<Object>[bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName.isEmpty ? 'download.bin' : fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}

Future<String?> resolvePreferredSavePathImpl(
  String suggestedName,
  List<String> _,
) async {
  return suggestedName.trim().isEmpty ? null : suggestedName.trim();
}
