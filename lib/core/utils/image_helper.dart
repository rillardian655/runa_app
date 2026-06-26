import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class ImageHelper {
  static ImageProvider getImageProvider(String url) {
    if (url.startsWith('data:image')) {
      final base64String = url.split(',').last;
      return MemoryImage(base64Decode(base64String));
    } else if (url.startsWith('file://') || url.startsWith('/')) {
      return FileImage(File(url.replaceFirst('file://', '')));
    } else {
      return NetworkImage(url);
    }
  }

  static Widget getImageWidget(String url, {BoxFit fit = BoxFit.cover}) {
    if (url.startsWith('data:image')) {
      final base64String = url.split(',').last;
      return Image.memory(base64Decode(base64String), fit: fit);
    } else if (url.startsWith('file://') || url.startsWith('/')) {
      return Image.file(File(url.replaceFirst('file://', '')), fit: fit);
    } else {
      return Image.network(
        url,
        fit: fit,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image, color: Colors.grey),
      );
    }
  }
}
