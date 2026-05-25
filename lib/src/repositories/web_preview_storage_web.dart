// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'web_preview_storage_base.dart';

WebPreviewStorage createWebPreviewStorage() {
  return const BrowserWebPreviewStorage();
}

class BrowserWebPreviewStorage implements WebPreviewStorage {
  const BrowserWebPreviewStorage();

  @override
  String? read(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      html.window.localStorage[key] = value;
    } catch (_) {
      // Ignore browser storage failures and keep the app usable for the session.
    }
  }

  @override
  void remove(String key) {
    try {
      html.window.localStorage.remove(key);
    } catch (_) {
      // Ignore browser storage failures and keep the app usable for the session.
    }
  }
}
