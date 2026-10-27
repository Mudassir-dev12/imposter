import 'dart:convert';

/// Represents the data encoded in the host's QR code for guest players to join.
class QrPayload {
  final String host;
  final int port;
  final String code;

  const QrPayload({
    required this.host,
    required this.port,
    required this.code,
  });

  /// Host and port formatted as "host:port".
  String get address => '$host:$port';

  /// WebSocket URL formatted as "ws://host:port".
  String get wsUrl => 'ws://$host:$port';

  /// Encodes this payload into standard JSON:
  /// `{"host":"192.168.1.5","port":8765,"code":"ABCD"}`
  String encodeJson() {
    return jsonEncode({
      'host': host.trim(),
      'port': port,
      'code': code.trim().toUpperCase(),
    });
  }

  /// Encodes this payload into a URI:
  /// `impostor://join?host=192.168.1.5&port=8765&code=ABCD`
  String encodeUri() {
    final uri = Uri(
      scheme: 'impostor',
      host: 'join',
      queryParameters: {
        'host': host.trim(),
        'port': port.toString(),
        'code': code.trim().toUpperCase(),
      },
    );
    return uri.toString();
  }

  /// Attempts to decode a raw QR string (JSON or URI or formatted string).
  /// Returns `null` if the string cannot be parsed or fails validation.
  static QrPayload? tryDecode(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. Try parsing JSON
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) {
          final host = decoded['host']?.toString().trim();
          final portVal = decoded['port'];
          final code = decoded['code']?.toString().trim().toUpperCase();

          int? port;
          if (portVal is int) {
            port = portVal;
          } else if (portVal is String) {
            port = int.tryParse(portVal);
          }

          if (_isValid(host, port, code)) {
            return QrPayload(host: host!, port: port!, code: code!);
          }
        }
      } catch (_) {}
    }

    // 2. Try parsing URI (e.g. impostor://join?host=...&port=...&code=... or ws://...)
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.hasQuery) {
        final host = uri.queryParameters['host']?.trim() ??
            (uri.host.isNotEmpty ? uri.host : null);
        final portStr = uri.queryParameters['port'] ??
            (uri.hasPort ? uri.port.toString() : null);
        final port = portStr != null ? int.tryParse(portStr) : null;
        final code = uri.queryParameters['code']?.trim().toUpperCase();

        if (_isValid(host, port, code)) {
          return QrPayload(host: host!, port: port!, code: code!);
        }
      }
    } catch (_) {}

    // 3. Fallback: formatted string like "192.168.1.5:8765/ABCD" or "192.168.1.5:8765 ABCD"
    final slashParts = trimmed.split(RegExp(r'[/\s#]+'));
    if (slashParts.length == 2) {
      final addrPart = slashParts[0].trim();
      final codePart = slashParts[1].trim().toUpperCase();
      final colonIdx = addrPart.lastIndexOf(':');
      if (colonIdx > 0 && colonIdx < addrPart.length - 1) {
        final host = addrPart.substring(0, colonIdx).trim();
        final port = int.tryParse(addrPart.substring(colonIdx + 1).trim());
        if (_isValid(host, port, codePart)) {
          return QrPayload(host: host, port: port!, code: codePart);
        }
      }
    }

    return null;
  }

  static bool _isValid(String? host, int? port, String? code) {
    if (host == null || host.isEmpty) return false;
    if (port == null || port < 1 || port > 65535) return false;
    if (code == null || code.length != 4) return false;
    // Room code must be 4 alphanumeric characters (matches engine ALLOWED_ROOM_CODE_CHARS)
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(code)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QrPayload &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          code == other.code;

  @override
  int get hashCode => host.hashCode ^ port.hashCode ^ code.hashCode;

  @override
  String toString() => 'QrPayload(host: $host, port: $port, code: $code)';
}
