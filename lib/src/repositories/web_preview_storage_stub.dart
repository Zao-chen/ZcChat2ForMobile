import 'web_preview_storage_base.dart';

WebPreviewStorage createWebPreviewStorage() {
  return MemoryWebPreviewStorage();
}

class MemoryWebPreviewStorage implements WebPreviewStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  String? read(String key) {
    return _values[key];
  }

  @override
  void write(String key, String value) {
    _values[key] = value;
  }

  @override
  void remove(String key) {
    _values.remove(key);
  }
}
