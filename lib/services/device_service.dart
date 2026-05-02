import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Provides a stable UUID device identifier that persists across app restarts.
/// Used to tag sync log entries so each device can skip its own changes on poll.
class DeviceService {
  static final DeviceService instance = DeviceService._();
  DeviceService._();

  static const _kKey = 'device_id';
  static const _uuid = Uuid();
  String? _id;

  Future<String> get id async {
    if (_id != null) return _id!;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kKey);
    if (stored != null) {
      _id = stored;
      return stored;
    }
    final newId = _uuid.v4();
    await prefs.setString(_kKey, newId);
    _id = newId;
    return newId;
  }
}
