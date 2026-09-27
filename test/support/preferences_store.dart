import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingPreferencesStore extends InMemorySharedPreferencesStore {
  FailingPreferencesStore() : super.empty();

  String? failKey;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == failKey) return false;
    return super.setValue(valueType, key, value);
  }
}
