import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';
import '../models/qr_payload.dart';

/// Screen for scanning host room QR codes using mobile_scanner.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _hasDetected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasDetected) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        final payload = QrPayload.tryDecode(raw);
        if (payload != null) {
          _hasDetected = true;
          Navigator.of(context).pop(payload);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Room QR Code'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                final isTorchOn = state.torchState == TorchState.on;
                return Icon(
                  isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: isTorchOn ? AppTheme.accent : Colors.white,
                );
              },
            ),
            tooltip: 'Toggle Flashlight',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
            errorBuilder: (context, error) {
              final isPermissionDenied =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPermissionDenied
                              ? Icons.no_photography_rounded
                              : Icons.error_outline_rounded,
                          size: 54,
                          color: isPermissionDenied
                              ? AppTheme.accent
                              : AppTheme.impostorColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isPermissionDenied
                              ? 'Camera Permission Required'
                              : 'Scanner Error',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isPermissionDenied
                              ? 'Camera access was denied. You can still join by typing the room code and server address manually.'
                              : (error.errorDetails?.message ?? error.errorCode.message),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.keyboard_rounded),
                          label: const Text('Enter Code Manually'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Scanner frame overlay
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.primaryLight,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          // Subtitle helper
          Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(180),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                'Point camera at the QR code displayed on the host\'s screen',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
