/// Application-wide constants and storage keys.
class AppConstants {
  static const String defaultHost =
      '10.0.2.2'; // Android emulator localhost alias
  static const int defaultPort = 8765;
  static const String defaultServerAddress = '10.0.2.2:8765';

  // SharedPreferences Keys
  static const String prefPlayerName = 'impostor_player_name';
  static const String prefServerAddress = 'impostor_server_address';
  static const String prefLastRoomCode = 'impostor_last_room_code';
  static const String prefLastPlayerId = 'impostor_last_player_id';
  static const String prefLastToken = 'impostor_last_token';
}
