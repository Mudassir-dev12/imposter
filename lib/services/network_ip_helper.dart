import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

/// Pure data class for network interface testing and abstraction.
class NetworkInterfaceInfo {
  final String name;
  final List<String> addresses;

  const NetworkInterfaceInfo({
    required this.name,
    required this.addresses,
  });
}

class NetworkIpHelper {
  /// Checks whether [ip] is a standard RFC 1918 private IPv4 address:
  /// - 10.0.0.0 – 10.255.255.255 (10/8)
  /// - 172.16.0.0 – 172.31.255.255 (172.16/12)
  /// - 192.168.0.0 – 192.168.255.255 (192.168/16)
  static bool isPrivateIPv4(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;

    final nums = parts.map((p) => int.tryParse(p)).toList();
    if (nums.any((n) => n == null || n < 0 || n > 255)) return false;

    final o1 = nums[0]!;
    final o2 = nums[1]!;

    // 10.0.0.0 – 10.255.255.255
    if (o1 == 10) return true;

    // 172.16.0.0 – 172.31.255.255
    if (o1 == 172 && o2 >= 16 && o2 <= 31) return true;

    // 192.168.0.0 – 192.168.255.255
    if (o1 == 192 && o2 == 168) return true;

    return false;
  }

  /// Pure selection function that picks the best private IPv4 from interface list.
  /// Prefers interfaces with names matching Wi-Fi or Access Point / Hotspot keywords
  /// (e.g. wlan, ap, wifi, swlan, softap), falling back to other private IPv4 interfaces.
  /// Returns `null` if no private IPv4 address is found.
  static String? selectHostIp(List<NetworkInterfaceInfo> interfaces) {
    final preferredRegex = RegExp(r'(wlan|ap|wifi|swlan|softap)', caseSensitive: false);
    final ignoreRegex = RegExp(r'(dummy|rmnet|tun|p2p|docker|vbox)', caseSensitive: false);

    String? preferredIp;
    String? fallbackIp;

    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      final isPreferred = preferredRegex.hasMatch(name);
      final isIgnored = ignoreRegex.hasMatch(name);

      for (final rawAddr in iface.addresses) {
        final addr = rawAddr.trim();
        if (addr.isEmpty || addr.startsWith('127.') || addr.startsWith('169.254.')) {
          continue;
        }

        if (isPrivateIPv4(addr)) {
          if (isPreferred && preferredIp == null) {
            preferredIp = addr;
          } else if (!isIgnored && fallbackIp == null) {
            fallbackIp = addr;
          }
        }
      }
    }

    return preferredIp ?? fallbackIp;
  }

  /// Resolves the device's host IP for local multiplayer:
  /// 1. Tries [networkInfo.getWifiIP()].
  /// 2. If null, empty, or 0.0.0.0 (e.g. when device is acting as hotspot AP),
  ///    falls back to enumerating [NetworkInterface.list] and selecting private IPv4.
  static Future<String?> resolveHostIp({NetworkInfo? networkInfo}) async {
    final info = networkInfo ?? NetworkInfo();

    // 1. Try getWifiIP from network_info_plus
    try {
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && isPrivateIPv4(wifiIp)) {
        return wifiIp.trim();
      }
    } catch (_) {}

    // 2. Fallback: Enumerate network interfaces (works on hotspot host device)
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      final infos = interfaces.map((i) {
        return NetworkInterfaceInfo(
          name: i.name,
          addresses: i.addresses.map((a) => a.address).toList(),
        );
      }).toList();

      return selectHostIp(infos);
    } catch (_) {
      return null;
    }
  }
}
