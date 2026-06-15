import 'dart:convert';
import 'package:flutter/material.dart';

class ImageHelper {
  static ImageProvider getImageProvider(String url) {
    if (url.startsWith('data:image')) {
      final base64String = url.split(',').last;
      return MemoryImage(base64Decode(base64String));
    } else {
      return NetworkImage(url);
    }
  }

  static Widget getImageWidget(String url, {BoxFit fit = BoxFit.cover}) {
    if (url.startsWith('data:image')) {
      final base64String = url.split(',').last;
      return Image.memory(base64Decode(base64String), fit: fit);
    } else {
      return Image.network(url, fit: fit);
    }
  }
}
