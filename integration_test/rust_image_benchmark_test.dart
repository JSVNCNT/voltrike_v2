import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:integration_test/integration_test.dart';
import 'package:voltrike_v2/core/native/registration_image_bridge.dart';
import 'package:voltrike_v2/features/auth/services/registration_image_preparer.dart';

const _sourceWidth = 3264;
const _sourceHeight = 2448;
const _sourcePixels = _sourceWidth * _sourceHeight;
const _targetAspectRatio = 1.586;
const _targetWidth = 1600;
const _warmupCount = 2;
const _sampleCount = 6;
const _rssSamplingInterval = Duration(milliseconds: 10);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'benchmarks the real Dart isolate and Rust file-path image pipelines',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'Run this benchmark on an Android physical device.',
      );
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      expect(
        androidInfo.isPhysicalDevice,
        isTrue,
        reason: 'Emulators do not provide representative image timings.',
      );

      final benchmarkDirectory = await Directory.systemTemp.createTemp(
        'voltrike_image_benchmark_',
      );
      final sourceFile = File(
        '${benchmarkDirectory.path}${Platform.pathSeparator}'
        'source_${_sourceWidth}x$_sourceHeight.jpg',
      );
      final dartOutput = File('${sourceFile.path}.voltrike.jpg');
      final rustOutput = File('${sourceFile.path}.voltrike.rust.jpg');

      try {
        // Fixture decoding, scaling, and JPEG encoding are setup work. They are
        // deliberately complete before either timed implementation runs.
        final fixtureBytes = await _createFixture(sourceFile);
        expect(_sourcePixels, lessThanOrEqualTo(8 * 1000 * 1000));

        const dartPreparer = RegistrationImagePreparer(engine: 'dart');
        final rustBridge = createNativeRegistrationImageBridge();
        expect(rustBridge.isSupported, isTrue);

        for (var index = 0; index < _warmupCount; index++) {
          if (index.isEven) {
            await _runDart(
              preparer: dartPreparer,
              sourceFile: sourceFile,
              outputFile: dartOutput,
            );
            await _runRust(
              bridge: rustBridge,
              sourceFile: sourceFile,
              outputFile: rustOutput,
            );
          } else {
            await _runRust(
              bridge: rustBridge,
              sourceFile: sourceFile,
              outputFile: rustOutput,
            );
            await _runDart(
              preparer: dartPreparer,
              sourceFile: sourceFile,
              outputFile: dartOutput,
            );
          }
        }

        final dartSamples = <_BenchmarkSample>[];
        final rustSamples = <_BenchmarkSample>[];
        for (var index = 0; index < _sampleCount; index++) {
          if (index.isEven) {
            dartSamples.add(
              await _runDart(
                preparer: dartPreparer,
                sourceFile: sourceFile,
                outputFile: dartOutput,
              ),
            );
            rustSamples.add(
              await _runRust(
                bridge: rustBridge,
                sourceFile: sourceFile,
                outputFile: rustOutput,
              ),
            );
          } else {
            rustSamples.add(
              await _runRust(
                bridge: rustBridge,
                sourceFile: sourceFile,
                outputFile: rustOutput,
              ),
            );
            dartSamples.add(
              await _runDart(
                preparer: dartPreparer,
                sourceFile: sourceFile,
                outputFile: dartOutput,
              ),
            );
          }
        }

        // Decode only the final outputs, after all timing and RSS samples.
        final dartImage = await _inspectOutput(dartOutput);
        final rustImage = await _inspectOutput(rustOutput);
        final expectedDimensions = _expectedOutputDimensions();
        expect(
          (dartImage.width, dartImage.height),
          expectedDimensions,
          reason: 'Dart output dimensions changed from production semantics.',
        );
        expect(
          (rustImage.width, rustImage.height),
          expectedDimensions,
          reason: 'Rust output dimensions must match the current Dart path.',
        );
        expect(dartImage.bytes, lessThanOrEqualTo(registrationImageMaxBytes));
        expect(rustImage.bytes, lessThanOrEqualTo(registrationImageMaxBytes));

        final dartLatency = dartSamples
            .map((sample) => sample.elapsedMicros)
            .toList(growable: false);
        final rustLatency = rustSamples
            .map((sample) => sample.elapsedMicros)
            .toList(growable: false);
        final dartMedianMicros = _percentile(dartLatency, 0.5);
        final rustMedianMicros = _percentile(rustLatency, 0.5);
        final report = <String, Object?>{
          'schemaVersion': 1,
          'device': <String, Object>{
            'model': androidInfo.model,
            'manufacturer': androidInfo.manufacturer,
            'androidRelease': androidInfo.version.release,
            'sdkInt': androidInfo.version.sdkInt,
            'supportedAbis': androidInfo.supportedAbis,
            'isPhysicalDevice': androidInfo.isPhysicalDevice,
          },
          'buildMode': kReleaseMode
              ? 'release'
              : kProfileMode
              ? 'profile'
              : 'debug',
          'fixture': <String, Object>{
            'format': 'jpeg',
            'width': _sourceWidth,
            'height': _sourceHeight,
            'pixels': _sourcePixels,
            'bytes': fixtureBytes,
            'generationExcluded': true,
          },
          'target': <String, Object>{
            'aspectRatio': _targetAspectRatio,
            'width': _targetWidth,
            'expectedHeight': expectedDimensions.$2,
          },
          'warmupsPerImplementation': _warmupCount,
          'samplesPerImplementation': _sampleCount,
          'executionOrder': 'alternating',
          'rssSamplingIntervalMs': _rssSamplingInterval.inMilliseconds,
          'rssScope': 'whole_process_current_rss',
          'dart': _summarize(dartSamples, dartImage),
          'rust': _summarize(rustSamples, rustImage),
          'dartToRustMedianRatio': dartMedianMicros / rustMedianMicros,
          'outputsHaveEqualDimensions':
              dartImage.width == rustImage.width &&
              dartImage.height == rustImage.height,
        };

        debugPrintSynchronously(
          'RUST_IMAGE_BENCHMARK ${jsonEncode(report)}',
          wrapWidth: null,
        );
        binding.reportData = <String, Object?>{'rustImageBenchmark': report};
      } finally {
        await _deleteIfPresent(dartOutput);
        await _deleteIfPresent(rustOutput);
        await _deleteIfPresent(sourceFile);
        if (await benchmarkDirectory.exists()) {
          await benchmarkDirectory.delete();
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<int> _createFixture(File destination) async {
  final logoData = await rootBundle.load('assets/images/logo.png');
  final logoBytes = logoData.buffer.asUint8List(
    logoData.offsetInBytes,
    logoData.lengthInBytes,
  );
  final logo = image_lib.decodeImage(logoBytes);
  expect(logo, isNotNull, reason: 'The bundled logo fixture must decode.');

  final fixture = image_lib.copyResize(
    logo!,
    width: _sourceWidth,
    height: _sourceHeight,
  );
  final encoded = image_lib.encodeJpg(fixture, quality: 92);
  await destination.writeAsBytes(encoded, flush: true);

  final decodedFixture = image_lib.decodeJpg(encoded);
  expect(decodedFixture, isNotNull);
  expect(
    (decodedFixture!.width, decodedFixture.height),
    (_sourceWidth, _sourceHeight),
  );
  expect(encoded, isNotEmpty);
  expect(encoded.length, lessThanOrEqualTo(32 * 1024 * 1024));
  return encoded.length;
}

Future<_BenchmarkSample> _runDart({
  required RegistrationImagePreparer preparer,
  required File sourceFile,
  required File outputFile,
}) async {
  await _deleteIfPresent(outputFile);
  final measured = await _measureWithRss(
    () => preparer.prepare(
      sourcePath: sourceFile.path,
      outputPath: outputFile.path,
      targetAspectRatio: _targetAspectRatio,
      targetWidth: _targetWidth,
    ),
  );
  expect(measured.value.path, outputFile.path);
  final outputBytes = await measured.value.length();
  _expectValidOutputSize(outputBytes);
  return _BenchmarkSample.fromMeasurement(measured, outputBytes: outputBytes);
}

Future<_BenchmarkSample> _runRust({
  required NativeRegistrationImageBridge bridge,
  required File sourceFile,
  required File outputFile,
}) async {
  await _deleteIfPresent(outputFile);
  final measured = await _measureWithRss(
    () => bridge.prepare(
      NativeRegistrationImageRequest(
        sourcePath: sourceFile.path,
        outputPath: outputFile.path,
        targetAspectRatio: _targetAspectRatio,
        targetWidth: _targetWidth,
      ),
    ),
  );
  final result = measured.value;
  expect(
    result.status,
    NativeRegistrationImageStatus.ok,
    reason: result.diagnostic,
  );
  expect(result.outputPath, outputFile.path);
  expect(
    (result.sourceWidth, result.sourceHeight),
    (_sourceWidth, _sourceHeight),
  );
  expect((
    result.outputWidth,
    result.outputHeight,
  ), _expectedOutputDimensions());
  expect(result.orientationApplied, isFalse);
  expect(result.usedSizeRetry, isFalse);

  final outputBytes = await outputFile.length();
  _expectValidOutputSize(outputBytes);
  expect(result.outputBytes, outputBytes);
  return _BenchmarkSample.fromMeasurement(
    measured,
    outputBytes: outputBytes,
    nativeResult: result,
  );
}

Future<_Measured<T>> _measureWithRss<T>(Future<T> Function() operation) async {
  final rssBefore = _tryReadCurrentRss();
  var rssPeak = rssBefore;
  final timer = Timer.periodic(_rssSamplingInterval, (_) {
    final sample = _tryReadCurrentRss();
    if (sample != null && (rssPeak == null || sample > rssPeak!)) {
      rssPeak = sample;
    }
  });
  final stopwatch = Stopwatch()..start();
  try {
    final value = await operation();
    stopwatch.stop();
    final rssAfter = _tryReadCurrentRss();
    if (rssAfter != null && (rssPeak == null || rssAfter > rssPeak!)) {
      rssPeak = rssAfter;
    }
    return _Measured<T>(
      value: value,
      elapsedMicros: stopwatch.elapsedMicroseconds,
      rssBeforeBytes: rssBefore,
      rssAfterBytes: rssAfter,
      rssPeakBytes: rssPeak,
    );
  } finally {
    if (stopwatch.isRunning) {
      stopwatch.stop();
    }
    timer.cancel();
  }
}

int? _tryReadCurrentRss() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return null;
  }
}

Future<_ImageOutput> _inspectOutput(File file) async {
  expect(await file.exists(), isTrue);
  final bytes = await file.readAsBytes();
  final decoded = image_lib.decodeJpg(bytes);
  expect(decoded, isNotNull, reason: '${file.path} must contain a JPEG.');
  return _ImageOutput(
    width: decoded!.width,
    height: decoded.height,
    bytes: bytes.length,
  );
}

(int, int) _expectedOutputDimensions() {
  final cropHeight = (_sourceWidth / _targetAspectRatio).round().clamp(
    1,
    _sourceHeight,
  );
  final outputHeight = (cropHeight * _targetWidth / _sourceWidth).round();
  return (_targetWidth, outputHeight);
}

void _expectValidOutputSize(int bytes) {
  expect(bytes, greaterThan(0));
  expect(bytes, lessThanOrEqualTo(registrationImageMaxBytes));
}

Map<String, Object?> _summarize(
  List<_BenchmarkSample> samples,
  _ImageOutput output,
) {
  final latency = samples
      .map((sample) => sample.elapsedMicros)
      .toList(growable: false);
  final peakRssDeltas = samples
      .map((sample) => sample.peakRssDeltaBytes)
      .whereType<int>()
      .toList(growable: false);
  final nativeDecode = samples
      .map((sample) => sample.nativeDecodeMicros)
      .whereType<int>()
      .toList(growable: false);
  final nativeTransform = samples
      .map((sample) => sample.nativeTransformMicros)
      .whereType<int>()
      .toList(growable: false);
  final nativeEncode = samples
      .map((sample) => sample.nativeEncodeMicros)
      .whereType<int>()
      .toList(growable: false);
  final nativeTotal = samples
      .map((sample) => sample.nativeTotalMicros)
      .whereType<int>()
      .toList(growable: false);

  return <String, Object?>{
    'medianUs': _percentile(latency, 0.5),
    'p95Us': _percentile(latency, 0.95),
    'minUs': latency.reduce((a, b) => a < b ? a : b),
    'maxUs': latency.reduce((a, b) => a > b ? a : b),
    'medianPeakRssDeltaBytes': peakRssDeltas.isEmpty
        ? null
        : _percentile(peakRssDeltas, 0.5),
    'maxPeakRssDeltaBytes': peakRssDeltas.isEmpty
        ? null
        : peakRssDeltas.reduce((a, b) => a > b ? a : b),
    'nativeMedianDecodeUs': nativeDecode.isEmpty
        ? null
        : _percentile(nativeDecode, 0.5),
    'nativeMedianTransformUs': nativeTransform.isEmpty
        ? null
        : _percentile(nativeTransform, 0.5),
    'nativeMedianEncodeUs': nativeEncode.isEmpty
        ? null
        : _percentile(nativeEncode, 0.5),
    'nativeMedianTotalUs': nativeTotal.isEmpty
        ? null
        : _percentile(nativeTotal, 0.5),
    'output': <String, int>{
      'width': output.width,
      'height': output.height,
      'bytes': output.bytes,
    },
    'samples': samples.map((sample) => sample.toJson()).toList(growable: false),
  };
}

int _percentile(List<int> samples, double percentile) {
  final sorted = samples.toList(growable: false)..sort();
  final index = (sorted.length * percentile).ceil().clamp(1, sorted.length) - 1;
  return sorted[index];
}

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

class _Measured<T> {
  const _Measured({
    required this.value,
    required this.elapsedMicros,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
    required this.rssPeakBytes,
  });

  final T value;
  final int elapsedMicros;
  final int? rssBeforeBytes;
  final int? rssAfterBytes;
  final int? rssPeakBytes;
}

class _BenchmarkSample {
  const _BenchmarkSample({
    required this.elapsedMicros,
    required this.outputBytes,
    required this.rssBeforeBytes,
    required this.rssAfterBytes,
    required this.rssPeakBytes,
    this.nativeDecodeMicros,
    this.nativeTransformMicros,
    this.nativeEncodeMicros,
    this.nativeTotalMicros,
  });

  factory _BenchmarkSample.fromMeasurement(
    _Measured<Object> measurement, {
    required int outputBytes,
    NativeRegistrationImageResult? nativeResult,
  }) {
    return _BenchmarkSample(
      elapsedMicros: measurement.elapsedMicros,
      outputBytes: outputBytes,
      rssBeforeBytes: measurement.rssBeforeBytes,
      rssAfterBytes: measurement.rssAfterBytes,
      rssPeakBytes: measurement.rssPeakBytes,
      nativeDecodeMicros: nativeResult?.decodeMicros,
      nativeTransformMicros: nativeResult?.transformMicros,
      nativeEncodeMicros: nativeResult?.encodeMicros,
      nativeTotalMicros: nativeResult?.totalMicros,
    );
  }

  final int elapsedMicros;
  final int outputBytes;
  final int? rssBeforeBytes;
  final int? rssAfterBytes;
  final int? rssPeakBytes;
  final int? nativeDecodeMicros;
  final int? nativeTransformMicros;
  final int? nativeEncodeMicros;
  final int? nativeTotalMicros;

  int? get peakRssDeltaBytes {
    final before = rssBeforeBytes;
    final peak = rssPeakBytes;
    return before == null || peak == null ? null : peak - before;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'elapsedUs': elapsedMicros,
    'outputBytes': outputBytes,
    'rssBeforeBytes': rssBeforeBytes,
    'rssAfterBytes': rssAfterBytes,
    'rssPeakBytes': rssPeakBytes,
    'peakRssDeltaBytes': peakRssDeltaBytes,
    'nativeDecodeUs': nativeDecodeMicros,
    'nativeTransformUs': nativeTransformMicros,
    'nativeEncodeUs': nativeEncodeMicros,
    'nativeTotalUs': nativeTotalMicros,
  };
}

class _ImageOutput {
  const _ImageOutput({
    required this.width,
    required this.height,
    required this.bytes,
  });

  final int width;
  final int height;
  final int bytes;
}
