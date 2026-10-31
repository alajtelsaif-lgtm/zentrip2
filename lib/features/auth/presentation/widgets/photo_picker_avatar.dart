import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../l10n/app_localizations.dart';

class PhotoPickerAvatar extends StatefulWidget {
  final XFile? initialFile;
  final void Function(XFile?) onChanged;
  final double size;

  const PhotoPickerAvatar({
    super.key,
    this.initialFile,
    required this.onChanged,
    this.size = 88,
  });

  @override
  State<PhotoPickerAvatar> createState() => _PhotoPickerAvatarState();
}

class _PhotoPickerAvatarState extends State<PhotoPickerAvatar> {
  static const _maxPhotoBytes = 5 * 1024 * 1024;

  XFile? _file;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    if (_file != null) unawaited(_loadPreview(_file!));
  }

  @override
  void didUpdateWidget(covariant PhotoPickerAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFile == widget.initialFile ||
        _file == widget.initialFile) {
      return;
    }
    _file = widget.initialFile;
    _previewBytes = null;
    if (_file != null) unawaited(_loadPreview(_file!));
  }

  Future<void> _loadPreview(XFile file) async {
    try {
      final length = await file.length();
      if (length == 0 || length > _maxPhotoBytes) return;
      final bytes = await file.readAsBytes();
      if (!mounted || _file != file) return;
      setState(() => _previewBytes = bytes);
    } catch (_) {
      // An unreadable optional preview should not prevent registration.
    }
  }

  Future<void> _pick() async {
    final l10n = AppLocalizations.of(context);
    final picker = ImagePicker();
    final result = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primary),
              title: Text(l10n.commonTakePhoto),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: Text(l10n.commonChooseFromGallery),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_file != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.accentRed),
                title: Text(l10n.commonRemovePhoto,
                    style: const TextStyle(color: AppColors.accentRed)),
                onTap: () {
                  setState(() {
                    _file = null;
                    _previewBytes = null;
                  });
                  widget.onChanged(null);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || result == null) return;
    try {
      final picked = await picker.pickImage(
        source: result,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (!mounted || picked == null) return;

      final length = await picked.length();
      if (length == 0 || length > _maxPhotoBytes) {
        _showPhotoError('Choose an image smaller than 5 MB.');
        return;
      }

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _file = picked;
        _previewBytes = bytes;
      });
      widget.onChanged(picked);
    } catch (_) {
      if (mounted) {
        _showPhotoError('Could not read this image. Please try another.');
      }
    }
  }

  void _showPhotoError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _pick,
      child: Stack(
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primarySurface,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: _previewBytes != null
                ? Image.memory(
                    _previewBytes!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _file != null
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : _placeholder(),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Icon(
        Icons.person_rounded,
        size: widget.size * 0.5,
        color: AppColors.primary,
      );
}
