import 'dart:async';

import 'package:camera/camera.dart';

class CameraPpgSource {
  CameraPpgSource({this.frontFacing = false, this.flash = true})
    : _samples = null;

  CameraPpgSource.forTesting(Stream<double> samples)
    : _samples = samples,
      frontFacing = false,
      flash = false;

  final bool frontFacing;
  final bool flash;
  final Stream<double>? _samples;

  Stream<double> meanRedChannel() {
    final Stream<double>? injected = _samples;
    if (injected != null) {
      return injected;
    }
    // ignore: close_sinks
    late StreamController<double> controller;
    CameraController? cameraController;
    controller = StreamController<double>(
      onListen: () async {
        final List<CameraDescription> cameras = await availableCameras();
        final CameraLensDirection direction = frontFacing
            ? CameraLensDirection.front
            : CameraLensDirection.back;
        final CameraDescription camera = cameras.firstWhere(
          (CameraDescription c) => c.lensDirection == direction,
          orElse: () => cameras.first,
        );
        cameraController = CameraController(
          camera,
          ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await cameraController!.initialize();
        if (flash) {
          await cameraController!.setFlashMode(FlashMode.torch);
        }
        await cameraController!.startImageStream((CameraImage image) {
          if (!controller.isClosed && image.planes.isNotEmpty) {
            final List<int> bytes = image.planes.first.bytes;
            if (bytes.isEmpty) {
              return;
            }
            int sum = 0;
            for (final int b in bytes) {
              sum += b;
            }
            controller.add(sum / bytes.length);
          }
        });
      },
      onCancel: () async {
        final CameraController? current = cameraController;
        if (current != null) {
          if (current.value.isStreamingImages) {
            await current.stopImageStream();
          }
          await current.setFlashMode(FlashMode.off);
          await current.dispose();
        }
      },
    );
    return controller.stream;
  }
}
