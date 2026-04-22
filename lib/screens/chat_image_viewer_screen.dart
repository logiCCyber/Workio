import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ChatImageViewerScreen extends StatefulWidget {
  final String imageUrl;
  final String heroTag;

  const ChatImageViewerScreen({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  State<ChatImageViewerScreen> createState() => _ChatImageViewerScreenState();
}

class _ChatImageViewerScreenState extends State<ChatImageViewerScreen> {
  bool _downloading = false;

  String _safeFileName(String raw, {required String fallback}) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('Invalid image url');

    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed (${response.statusCode})');
    }

    return response.bodyBytes;
  }

  Future<File> _writeBytesToDevice(
      Uint8List bytes,
      String fileName,
      ) async {
    Directory baseDir;

    if (Platform.isAndroid) {
      baseDir =
          await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory();
    } else {
      baseDir =
          await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();
    }

    final folder = Directory(
      '${baseDir.path}${Platform.pathSeparator}Workio${Platform.pathSeparator}images',
    );

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final file = File(
      '${folder.path}${Platform.pathSeparator}${_safeFileName(fileName, fallback: "image.jpg")}',
    );

    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _saveImage() async {
    if (_downloading) return;

    try {
      setState(() => _downloading = true);

      final bytes = await _downloadBytes(widget.imageUrl);
      final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await _writeBytesToDevice(bytes, fileName);

      if (!mounted) return;
      _showStyledSnack(
        'Image saved: ${file.path.split(Platform.pathSeparator).last}',
        icon: Icons.download_done_rounded,
        accent: const Color(0xFF34D399),
      );
    } catch (e) {
      if (!mounted) return;
      _showStyledSnack(
        'Save image failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  void _showStyledSnack(
      String text, {
        IconData icon = Icons.check_circle_rounded,
        Color accent = const Color(0xFF34D399),
      }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        padding: EdgeInsets.zero,
        duration: const Duration(milliseconds: 2200),
        content: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2F3036),
                Color(0xFF24252B),
                Color(0xFF171A22),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withOpacity(0.18),
                  ),
                ),
                child: Icon(
                  icon,
                  color: accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.close_rounded,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _downloading ? null : _saveImage,
            icon: _downloading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Icon(
              Icons.download_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Center(
        child: Hero(
          tag: widget.heroTag,
          child: Image.network(
            widget.imageUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;

              return const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (_, __, ___) => const Center(
              child: Text(
                'IMAGE LOAD ERROR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}