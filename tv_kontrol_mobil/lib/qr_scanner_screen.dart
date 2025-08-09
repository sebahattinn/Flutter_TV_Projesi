import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool hasScanned = false;
  bool isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📱 Scan TV QR Code'),
        backgroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: Icon(
              isTorchOn ? Icons.flash_on : Icons.flash_off,
              color: isTorchOn ? Colors.yellow : Colors.grey,
            ),
            onPressed: () {
              setState(() {
                isTorchOn = !isTorchOn;
              });
              cameraController.toggleTorch();
            },
          ),
          IconButton(
            icon: const Icon(Icons.camera_front),
            onPressed: () => cameraController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                MobileScanner(
                  controller: cameraController,
                  onDetect: (capture) {
                    if (hasScanned) return;

                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final String? code = barcode.rawValue;
                      if (code != null && !hasScanned) {
                        _handleQRCode(code);
                      }
                    }
                  },
                ),
                // Custom overlay
                Center(
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue, width: 3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                // Corner indicators
                Center(
                  child: SizedBox(
                    width: 300,
                    height: 300,
                    child: Stack(
                      children: [
                        // Top-left corner
                        Positioned(
                          top: 0,
                          left: 0,
                          child: _buildCorner(true, true),
                        ),
                        // Top-right corner
                        Positioned(
                          top: 0,
                          right: 0,
                          child: _buildCorner(true, false),
                        ),
                        // Bottom-left corner
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: _buildCorner(false, true),
                        ),
                        // Bottom-right corner
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: _buildCorner(false, false),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            flex: 1,
            child: Center(
              child: Text(
                '📺 Point camera at TV QR code',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(bool isTop, bool isLeft) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border(
          top: isTop
              ? const BorderSide(color: Colors.blue, width: 4)
              : BorderSide.none,
          bottom: !isTop
              ? const BorderSide(color: Colors.blue, width: 4)
              : BorderSide.none,
          left: isLeft
              ? const BorderSide(color: Colors.blue, width: 4)
              : BorderSide.none,
          right: !isLeft
              ? const BorderSide(color: Colors.blue, width: 4)
              : BorderSide.none,
        ),
      ),
    );
  }

  void _handleQRCode(String code) {
    if (hasScanned) return;

    setState(() {
      hasScanned = true;
    });

    // Stop scanning
    cameraController.stop();

    try {
      // Parse the QR data
      final qrData = json.decode(code);
      debugPrint("✅ QR Code parsed successfully: $qrData");
      Navigator.pop(context, qrData);
    } catch (e) {
      debugPrint("❌ Invalid QR code format: $e");

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR code format'),
          backgroundColor: Colors.red,
        ),
      );

      // Allow rescanning after error
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            hasScanned = false;
          });
          cameraController.start();
        }
      });
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}
