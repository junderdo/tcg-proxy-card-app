import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../upload/card_uploader.dart';
import '../upload/panel_frame.dart';

/// Walks through one upload: preview, transfer, panel refresh and result.
class UploadDialog extends StatefulWidget {
  const UploadDialog({super.key, required this.upload});

  final CardUploadController upload;

  @override
  State<UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<UploadDialog> {
  CardUploadController get _upload => widget.upload;

  @override
  void initState() {
    super.initState();
    _upload.addListener(_onUploadChanged);
  }

  @override
  void dispose() {
    _upload.removeListener(_onUploadChanged);
    super.dispose();
  }

  void _onUploadChanged() {
    if (_upload.stage == UploadStage.cancelled) {
      Navigator.pop(context);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        scrollable: true,
        title: Text(_title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            if (_upload.image case final image?)
              _Preview(pngBytes: image.previewPng),
            ..._buildStatus(context),
          ],
        ),
        actions: _buildActions(),
      ),
    );
  }

  String get _title => switch (_upload.stage) {
    UploadStage.preparing => 'Preparing image',
    UploadStage.confirming => 'Send to ${_upload.device.displayName}?',
    UploadStage.transferring => 'Uploading',
    UploadStage.refreshing => 'Refreshing display',
    UploadStage.displayed => 'Uploaded',
    UploadStage.displayedNotSaved => 'Shown but not saved',
    UploadStage.failed => 'Upload failed',
    UploadStage.cancelled => 'Upload cancelled',
  };

  List<Widget> _buildStatus(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (_upload.stage) {
      UploadStage.preparing => const [
        Center(child: CircularProgressIndicator()),
        Text('Dithering the card art to the six panel colors…'),
      ],
      UploadStage.confirming => const [
        Text('This preview shows exactly what the card will display.'),
      ],
      UploadStage.transferring => [
        LinearProgressIndicator(value: _upload.progress),
        Text(
          'Sent ${_kilobytes(_upload.bytesSent)} of '
          '${_kilobytes(_upload.totalBytes)} KB',
        ),
      ],
      UploadStage.refreshing => const [
        LinearProgressIndicator(),
        Text(
          'The card received the image and is refreshing its display. '
          'This takes up to a minute.',
        ),
      ],
      UploadStage.displayed => [
        _StatusLine(
          icon: Icons.check_circle,
          color: colors.primary,
          text: 'The card is showing the new image.',
        ),
      ],
      UploadStage.displayedNotSaved => [
        _StatusLine(
          icon: Icons.warning_amber,
          color: colors.error,
          text:
              "The card is showing the new image, but couldn't save it, so "
              "it won't survive a reboot (error 0x0B STORAGE_FAILED).",
        ),
      ],
      UploadStage.failed => [
        _StatusLine(
          icon: Icons.error_outline,
          color: colors.error,
          text: _upload.errorMessage ?? 'The upload failed.',
        ),
      ],
      UploadStage.cancelled => const [],
    };
  }

  List<Widget> _buildActions() {
    if (_upload.canCancel) {
      return [
        TextButton(onPressed: _upload.cancel, child: const Text('Cancel')),
        if (_upload.stage == UploadStage.confirming)
          FilledButton(onPressed: _upload.send, child: const Text('Send')),
      ];
    }
    if (_upload.isFinished) {
      return [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ];
    }
    return const [];
  }

  static String _kilobytes(int bytes) => (bytes / 1000).toStringAsFixed(0);
}

class _Preview extends StatelessWidget {
  const _Preview({required this.pngBytes});

  final Uint8List pngBytes;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: AspectRatio(
          aspectRatio: PanelFrame.width / PanelFrame.height,
          child: Semantics(
            label: 'Preview of the image on the card',
            image: true,
            child: Image.memory(
              pngBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Icon(icon, color: color),
        Expanded(child: Text(text)),
      ],
    );
  }
}
