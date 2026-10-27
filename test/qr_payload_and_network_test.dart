import 'package:flutter_test/flutter_test.dart';
import 'package:impostor_app/models/qr_payload.dart';
import 'package:impostor_app/services/network_ip_helper.dart';

void main() {
  group('QrPayload Tests', () {
    test('encodeJson produces valid JSON payload', () {
      const payload = QrPayload(
        host: '192.168.43.1',
        port: 8765,
        code: 'TEST',
      );

      final jsonStr = payload.encodeJson();
      expect(jsonStr, contains('"host":"192.168.43.1"'));
      expect(jsonStr, contains('"port":8765'));
      expect(jsonStr, contains('"code":"TEST"'));

      final decoded = QrPayload.tryDecode(jsonStr);
      expect(decoded, isNotNull);
      expect(decoded!.host, '192.168.43.1');
      expect(decoded.port, 8765);
      expect(decoded.code, 'TEST');
      expect(decoded.address, '192.168.43.1:8765');
      expect(decoded.wsUrl, 'ws://192.168.43.1:8765');
    });

    test('encodeUri produces valid URI payload and tryDecode parses it', () {
      const payload = QrPayload(
        host: '10.0.0.12',
        port: 8765,
        code: 'ABCD',
      );

      final uriStr = payload.encodeUri();
      expect(uriStr, startsWith('impostor://join?'));
      expect(uriStr, contains('host=10.0.0.12'));
      expect(uriStr, contains('port=8765'));
      expect(uriStr, contains('code=ABCD'));

      final decoded = QrPayload.tryDecode(uriStr);
      expect(decoded, isNotNull);
      expect(decoded!.host, '10.0.0.12');
      expect(decoded.port, 8765);
      expect(decoded.code, 'ABCD');
    });

    test('tryDecode parses formatted string (host:port/code)', () {
      final decoded = QrPayload.tryDecode('192.168.1.15:8765/ZXCV');
      expect(decoded, isNotNull);
      expect(decoded!.host, '192.168.1.15');
      expect(decoded.port, 8765);
      expect(decoded.code, 'ZXCV');

      final decodedWithSpace = QrPayload.tryDecode('192.168.1.15:8765 ZXCV');
      expect(decodedWithSpace, isNotNull);
      expect(decodedWithSpace!.code, 'ZXCV');
    });

    test('tryDecode handles port as string in JSON', () {
      const raw = '{"host":"172.20.10.1","port":"8765","code":"PQRS"}';
      final decoded = QrPayload.tryDecode(raw);
      expect(decoded, isNotNull);
      expect(decoded!.host, '172.20.10.1');
      expect(decoded.port, 8765);
      expect(decoded.code, 'PQRS');
    });

    test('tryDecode rejects invalid inputs', () {
      expect(QrPayload.tryDecode(null), isNull);
      expect(QrPayload.tryDecode(''), isNull);
      expect(QrPayload.tryDecode('   '), isNull);
      expect(QrPayload.tryDecode('not valid at all'), isNull);

      // Invalid port numbers
      expect(
        QrPayload.tryDecode('{"host":"192.168.1.1","port":0,"code":"ABCD"}'),
        isNull,
      );
      expect(
        QrPayload.tryDecode('{"host":"192.168.1.1","port":70000,"code":"ABCD"}'),
        isNull,
      );

      // Alphanumeric room code (engine generates letters + numbers)
      final alphanumeric = QrPayload.tryDecode(
        '{"host":"192.168.1.1","port":8765,"code":"A7X9"}',
      );
      expect(alphanumeric, isNotNull);
      expect(alphanumeric!.code, 'A7X9');

      // Invalid room code (not 4 alphanumeric chars)
      expect(
        QrPayload.tryDecode('{"host":"192.168.1.1","port":8765,"code":"ABC"}'),
        isNull,
      );
      expect(
        QrPayload.tryDecode('{"host":"192.168.1.1","port":8765,"code":"AB!#"}'),
        isNull,
      );
      expect(
        QrPayload.tryDecode('{"host":"192.168.1.1","port":8765,"code":"TOOLONG"}'),
        isNull,
      );

      // Missing host
      expect(
        QrPayload.tryDecode('{"port":8765,"code":"ABCD"}'),
        isNull,
      );
    });
  });

  group('NetworkIpHelper Tests', () {
    test('isPrivateIPv4 validates RFC 1918 ranges correctly', () {
      // 10.0.0.0/8
      expect(NetworkIpHelper.isPrivateIPv4('10.0.0.1'), isTrue);
      expect(NetworkIpHelper.isPrivateIPv4('10.254.100.5'), isTrue);
      expect(NetworkIpHelper.isPrivateIPv4('10.255.255.255'), isTrue);

      // 172.16.0.0/12
      expect(NetworkIpHelper.isPrivateIPv4('172.16.0.1'), isTrue);
      expect(NetworkIpHelper.isPrivateIPv4('172.20.10.1'), isTrue); // Common iOS/Android hotspot IP
      expect(NetworkIpHelper.isPrivateIPv4('172.31.255.254'), isTrue);
      expect(NetworkIpHelper.isPrivateIPv4('172.15.0.1'), isFalse); // Below range
      expect(NetworkIpHelper.isPrivateIPv4('172.32.0.1'), isFalse); // Above range

      // 192.168.0.0/16
      expect(NetworkIpHelper.isPrivateIPv4('192.168.1.1'), isTrue);
      expect(NetworkIpHelper.isPrivateIPv4('192.168.43.1'), isTrue); // Standard Android hotspot IP
      expect(NetworkIpHelper.isPrivateIPv4('192.168.254.254'), isTrue);
      expect(NetworkIpHelper.isPrivateIPv4('192.169.1.1'), isFalse);

      // Non-private addresses
      expect(NetworkIpHelper.isPrivateIPv4('127.0.0.1'), isFalse); // Loopback
      expect(NetworkIpHelper.isPrivateIPv4('169.254.1.1'), isFalse); // Link-local
      expect(NetworkIpHelper.isPrivateIPv4('8.8.8.8'), isFalse); // Public DNS
      expect(NetworkIpHelper.isPrivateIPv4('1.1.1.1'), isFalse); // Public
      expect(NetworkIpHelper.isPrivateIPv4('100.64.0.1'), isFalse); // Carrier Grade NAT

      // Malformed strings
      expect(NetworkIpHelper.isPrivateIPv4(''), isFalse);
      expect(NetworkIpHelper.isPrivateIPv4('abc'), isFalse);
      expect(NetworkIpHelper.isPrivateIPv4('192.168.1'), isFalse);
      expect(NetworkIpHelper.isPrivateIPv4('192.168.1.1.1'), isFalse);
      expect(NetworkIpHelper.isPrivateIPv4('256.1.1.1'), isFalse);
      expect(NetworkIpHelper.isPrivateIPv4('-1.0.0.1'), isFalse);
    });

    test('selectHostIp selects hotspot IP on AP device (ap0 / wlan)', () {
      // Scenario: Phone is hotspot, network_info_plus would return null,
      // ap0 interface has 192.168.43.1
      final fakeInterfaces = [
        const NetworkInterfaceInfo(
          name: 'lo',
          addresses: ['127.0.0.1'],
        ),
        const NetworkInterfaceInfo(
          name: 'rmnet_data0',
          addresses: ['100.75.12.34'], // Cellular data
        ),
        const NetworkInterfaceInfo(
          name: 'ap0',
          addresses: ['192.168.43.1'], // Android hotspot AP interface
        ),
      ];

      final selected = NetworkIpHelper.selectHostIp(fakeInterfaces);
      expect(selected, '192.168.43.1');
    });

    test('selectHostIp selects Wi-Fi IP on connected device (wlan0)', () {
      final fakeInterfaces = [
        const NetworkInterfaceInfo(
          name: 'lo',
          addresses: ['127.0.0.1'],
        ),
        const NetworkInterfaceInfo(
          name: 'wlan0',
          addresses: ['192.168.1.105'],
        ),
      ];

      final selected = NetworkIpHelper.selectHostIp(fakeInterfaces);
      expect(selected, '192.168.1.105');
    });

    test('selectHostIp prefers wlan/ap over secondary interfaces (e.g. eth0)', () {
      final fakeInterfaces = [
        const NetworkInterfaceInfo(
          name: 'eth0',
          addresses: ['10.0.0.50'],
        ),
        const NetworkInterfaceInfo(
          name: 'wlan0',
          addresses: ['192.168.1.20'],
        ),
      ];

      final selected = NetworkIpHelper.selectHostIp(fakeInterfaces);
      expect(selected, '192.168.1.20');
    });

    test('selectHostIp falls back to private IPv4 if no wlan/ap interface exists', () {
      final fakeInterfaces = [
        const NetworkInterfaceInfo(
          name: 'lo',
          addresses: ['127.0.0.1'],
        ),
        const NetworkInterfaceInfo(
          name: 'en0',
          addresses: ['172.16.5.10'],
        ),
      ];

      final selected = NetworkIpHelper.selectHostIp(fakeInterfaces);
      expect(selected, '172.16.5.10');
    });

    test('selectHostIp returns null when no private IPv4 exists', () {
      final fakeInterfaces = [
        const NetworkInterfaceInfo(
          name: 'lo',
          addresses: ['127.0.0.1'],
        ),
        const NetworkInterfaceInfo(
          name: 'rmnet0',
          addresses: ['100.64.1.2', '8.8.8.8'],
        ),
      ];

      expect(NetworkIpHelper.selectHostIp(fakeInterfaces), isNull);
      expect(NetworkIpHelper.selectHostIp([]), isNull);
    });
  });
}
