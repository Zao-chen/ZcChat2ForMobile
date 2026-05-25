abstract class WebPreviewStorage {
  String? read(String key);

  void write(String key, String value);

  void remove(String key);
}
