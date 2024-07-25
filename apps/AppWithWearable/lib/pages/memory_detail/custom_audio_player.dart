import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_waveform/just_waveform.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';

enum PlayerLoadingState {
  loading,
  loaded,
  error,
}

enum FileType {
  NETWORK,
  LOCAL,
  ASSET,
}

///An example widget, it is not part of the CustomAudipPlayer UI.
class AudioPlayerTestPage extends StatefulWidget {
  const AudioPlayerTestPage({super.key});

  @override
  State<AudioPlayerTestPage> createState() => _AudioPlayerTestPageState();
}

class _AudioPlayerTestPageState extends State<AudioPlayerTestPage> {
  final files = [
    'assets/audios/BabyElephantWalk60.wav',
    'assets/audios/ImperialMarch60.wav',
    'assets/audios/PinkPanther30.wav',
    'assets/audios/Player.mp3',
    'https://file-examples.com/storage/fed61f387f6686cd19d49b1/2017/11/file_example_MP3_700KB.mp3',
    'result_waveform2.wav'
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Player Test'),
      ),
      body: ListView.separated(
        itemCount: files.length,
        padding: const EdgeInsets.all(16),
        separatorBuilder: (ctx, index) => const SizedBox(height: 16),
        itemBuilder: (ctx, index) {
          return ListTile(
            tileColor: Colors.white,
            title: Text(
              files[index],
              style: const TextStyle(color: Colors.black),
            ),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => CustomAudioPlayer(
                    audioFilePath: files[index],
                    type: files[index].contains('http')
                        ? FileType.NETWORK
                        : files[index].contains('assets')
                            ? FileType.ASSET
                            : FileType.LOCAL,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Custom [class] for [AudioPlayer]
///
/// This [class] is used to play the audio file with waveform
/// The constructor requires two values:
/// 1. [audioFilePath] - The path of the audio file
/// 2. [type] - The type of the file [NETWORK], [LOCAL], [ASSET]
class CustomAudioPlayer extends StatefulWidget {
  /// Constructor for [CustomAudioPlayer] for initializing the [audioFilePath] and [FileType]
  const CustomAudioPlayer({super.key, required this.audioFilePath, this.type = FileType.ASSET});

  /// The url/path of the audio file
  final String audioFilePath;

  /// [Boolean] value to check if the [AudioFile] is from [Network] or [Asset] or [File]
  /// Default value is [ASSET]
  final FileType type;

  @override
  State<CustomAudioPlayer> createState() => _CustomAudioPlayerState();
}

class _CustomAudioPlayerState extends State<CustomAudioPlayer> with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final progressStream = BehaviorSubject<WaveformProgress>();
  var _playerLoadingState = PlayerLoadingState.loading;
  final navigatorKey = GlobalKey<NavigatorState>();
  String errorMessage = '';
  @override
  void initState() {
    super.initState();
    ambiguate(WidgetsBinding.instance)!.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
    ));
    _init();
  }

  Future<void> _init() async {
    debugPrint('Audio File Path: ${widget.audioFilePath}');
    debugPrint('FileType: ${widget.type}');
    debugPrint('FilePath: ${p.join((await getApplicationDocumentsDirectory()).path, widget.audioFilePath)}');
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _player.playbackEventStream.listen((event) {}, onError: (Object e, StackTrace stackTrace) {
      debugPrint('A stream error occurred: $e');
    });

    try {
      await _player.setAudioSource(
        widget.type == FileType.NETWORK
            ? AudioSource.uri(Uri.parse(widget.audioFilePath))
            : widget.type == FileType.LOCAL
                ? AudioSource.file(p.join((await getApplicationDocumentsDirectory()).path, widget.audioFilePath))
                : AudioSource.asset(widget.audioFilePath),
      );
    } on PlayerException catch (e) {
      debugPrint('Audio Player Error: $e');
      setState(() {
        _playerLoadingState = PlayerLoadingState.error;
      });
      errorMessage = "Audio Player Error: $e";
      ScaffoldMessenger.of(navigatorKey.currentContext ?? context).showSnackBar(SnackBar(content: Text(errorMessage)));

      return;
    } catch (e) {
      debugPrint('Error loading audio source: $e');
      setState(() {
        _playerLoadingState = PlayerLoadingState.error;
      });
      errorMessage = "Audio Source Error: $e";
      ScaffoldMessenger.of(navigatorKey.currentContext ?? context).showSnackBar(SnackBar(content: Text(errorMessage)));

      return;
    }

    ///read audio file from assets
    final audioFile =
        File(p.join((await getApplicationDocumentsDirectory()).path, widget.audioFilePath.split('/').last));
    try {
      Future<ByteData> tempFile = widget.type == FileType.NETWORK
          ? NetworkAssetBundle(Uri.parse(widget.audioFilePath)).load(widget.audioFilePath)
          : widget.type == FileType.LOCAL
              ? File(p.join((await getApplicationDocumentsDirectory()).path, widget.audioFilePath))
                  .readAsBytes()
                  .then((value) => ByteData.view(value.buffer))
              : rootBundle.load(widget.audioFilePath);
      await audioFile.writeAsBytes((await tempFile).buffer.asUint8List());
      final waveFile = File(p.join((await getApplicationDocumentsDirectory()).path, 'result_waveform.wav'));
      JustWaveform.extract(audioInFile: audioFile, waveOutFile: waveFile)
          .listen(progressStream.add, onError: progressStream.addError);
    } catch (e) {
      setState(() {
        _playerLoadingState = PlayerLoadingState.error;
      });
      errorMessage = "Audio File Reading Error: $e";
      ScaffoldMessenger.of(navigatorKey.currentContext ?? context).showSnackBar(SnackBar(content: Text(errorMessage)));

      progressStream.addError(e);
      return;
    }
    setState(() {
      _playerLoadingState = PlayerLoadingState.loaded;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.stop();
    }
  }

  @override
  void dispose() {
    ambiguate(WidgetsBinding.instance)!.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  Stream<PositionData> get _positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
      _player.positionStream,
      _player.bufferedPositionStream,
      _player.durationStream,
      (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero));

  @override
  Widget build(BuildContext context) {
    return Material(
      key: navigatorKey,
      color: Theme.of(context).canvasColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: _showProperView(context),
    );
  }

  Widget _showProperView(BuildContext context) {
    if (PlayerLoadingState.loading == _playerLoadingState) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    } else if (PlayerLoadingState.error == _playerLoadingState) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          Container(
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Container(
              height: 150.0,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(4.0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    offset: Offset(0.0, 2.0),
                    blurRadius: 2.0,
                  ),
                ],
              ),
              width: double.maxFinite,
              child: StreamBuilder<WaveformProgress>(
                stream: progressStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final progress = snapshot.data?.progress ?? 0.0;
                  final waveform = snapshot.data?.waveform;
                  if (waveform == null) {
                    return Center(
                      child: Text(
                        '${(100 * progress).toInt()}%',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    );
                  }
                  return AudioWaveformWidget(
                    waveform: waveform,
                    start: Duration.zero,
                    duration: waveform.duration,
                    positionDataStream: _positionDataStream,
                    player: _player,
                  );
                },
              ),
            ),
          ),
          StreamBuilder(
            stream: _positionDataStream,
            builder: (context, AsyncSnapshot snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
                                .firstMatch("${const Duration(seconds: 0)}")
                                ?.group(1) ??
                            "${_player.position}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              } else if (snapshot.connectionState == ConnectionState.waiting) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
                                .firstMatch("${const Duration(seconds: 0)}")
                                ?.group(1) ??
                            "${_player.position}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$').firstMatch("${_player.position}")?.group(1) ??
                          "${Duration.zero}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      RegExp(r'((^0*[1-9]\d*:)?\d{2}:\d{2})\.\d+$')
                              .firstMatch("${_player.bufferedPosition - _player.position}")
                              ?.group(1) ??
                          "${(Duration.zero)}",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              );
            },
          ),
          ControlButtons(_player),
        ],
      ),
    );
  }
}

/// Displays the play/pause button and volume/speed sliders.
class ControlButtons extends StatefulWidget {
  final AudioPlayer player;

  const ControlButtons(this.player, {super.key});

  @override
  State<ControlButtons> createState() => _ControlButtonsState();
}

class _ControlButtonsState extends State<ControlButtons> {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Opens volume slider dialog
        IconButton(
          icon: SvgPicture.asset(
            'assets/images/replay_15.svg',
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          iconSize: 32.0,
          onPressed: () => widget.player.seek(
            Duration(
              seconds: widget.player.position.inSeconds <= 15 ? 0 : widget.player.position.inSeconds - 15,
            ),
          ),
        ),

        StreamBuilder<PlayerState>(
          stream: widget.player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final processingState = playerState?.processingState;
            final playing = playerState?.playing;
            if (playing != true) {
              return IconButton(
                icon: const Icon(Icons.play_arrow),
                iconSize: 40.0,
                onPressed: widget.player.play,
              );
            } else if (processingState != ProcessingState.completed) {
              return IconButton(
                icon: const Icon(Icons.pause),
                iconSize: 40.0,
                onPressed: widget.player.pause,
              );
            } else {
              return IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 40.0,
                onPressed: () => widget.player.seek(Duration.zero),
              );
            }
          },
        ),
        IconButton(
          icon: SvgPicture.asset(
            'assets/images/forward_15.svg',
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          iconSize: 32.0,
          onPressed: () => widget.player.seek(
            Duration(
              seconds: widget.player.position.inSeconds >= widget.player.duration!.inSeconds - 15
                  ? widget.player.bufferedPosition.inSeconds
                  : widget.player.position.inSeconds + 15,
            ),
          ),
        ),
        //speed controling button
        IconButton(
          icon: Text(
            '${widget.player.speed}x',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18),
          ),
          iconSize: 40.0,
          onPressed: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
              ),
              builder: (context) => PlaybackSpeedBottomSheet(
                onSpeedChange: (speed) async {
                  await widget.player.setSpeed(speed);
                  setState(() {});
                },
                currentValue: widget.player.speed,
              ),
            );
          },
        ),
      ],
    );
  }
}

class PlaybackSpeedBottomSheet extends StatefulWidget {
  const PlaybackSpeedBottomSheet({
    super.key,
    required this.onSpeedChange,
    required this.currentValue,
  });
  final Future<void> Function(double) onSpeedChange;
  final double currentValue;

  @override
  State<PlaybackSpeedBottomSheet> createState() => _PlaybackSpeedBottomSheetState();
}

class _PlaybackSpeedBottomSheetState extends State<PlaybackSpeedBottomSheet> {
  double dragValue = 0.5;

  @override
  void initState() {
    super.initState();
    dragValue = widget.currentValue;
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheet(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Options',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  CircleAvatar(
                    backgroundColor: Colors.black26,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      color: Colors.white,
                      icon: const Icon(Icons.close),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 32),
              Text(
                'Playback Speed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Container(
                margin: const EdgeInsets.only(top: 16.0),
                padding: const EdgeInsets.only(top: 16.0, bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    SliderTheme(
                      data: const SliderThemeData(
                        activeTrackColor: Colors.grey,
                        activeTickMarkColor: Colors.transparent,
                        inactiveTrackColor: Colors.grey,
                        inactiveTickMarkColor: Colors.grey,
                      ),
                      child: Slider(
                        value: dragValue,
                        min: 0.5,
                        max: 2,
                        divisions: 3,
                        label: '${dragValue}x',
                        onChanged: (val) {
                          dragValue = val;
                          widget.onSpeedChange.call(dragValue);
                          setState(() {});
                        },
                        onChangeEnd: (val) {
                          dragValue = val;
                          widget.onSpeedChange.call(dragValue);
                          setState(() {});
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          4,
                          (index) => Text('${(index + 1) * 0.5}x'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      onClosing: () {},
    );
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

T? ambiguate<T>(T? value) => value;

class AudioWaveformWidget extends StatefulWidget {
  final Color waveColor;
  final double scale;
  final double strokeWidth;
  final double pixelsPerStep;
  final Waveform waveform;
  final Duration start;
  final Duration duration;
  final Stream<PositionData> positionDataStream;
  final AudioPlayer player;

  const AudioWaveformWidget({
    super.key,
    required this.waveform,
    required this.start,
    required this.duration,
    this.waveColor = Colors.black,
    this.scale = 0.8,
    this.strokeWidth = 1.0,
    this.pixelsPerStep = 3.0,
    required this.positionDataStream,
    required this.player,
  });

  @override
  _AudioWaveformState createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveformWidget> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: widget.positionDataStream,
      builder: (context, snapshot) {
        final positionData = snapshot.data;
        final position = positionData?.position ?? Duration.zero;
        final duration = positionData?.duration ?? Duration.zero;

        final startCalculate = (position.inMilliseconds < 10);
        final endCalculate = (position.inMilliseconds > duration.inMilliseconds - 10);
        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: CustomPaint(
                painter: AudioWaveformPainter(
                  waveColor: widget.waveColor,
                  waveform: widget.waveform,
                  start: widget.start,
                  duration: widget.duration,
                  scale: widget.scale,
                  strokeWidth: widget.strokeWidth,
                  pixelsPerStep: widget.pixelsPerStep,
                  currentPoint: position,
                ),
              ),
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: Colors.red,
                thumbShape: VerticalSliderForAudio(
                    height: position.inMilliseconds < 10 ? 144 : 150, width: position.inMilliseconds < 10 ? 2 : 4),
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                overlayColor: Colors.red.shade200,
                overlayShape: SquareThumbShape(
                  width: startCalculate || endCalculate ? 0 : 8,
                  height: 150,
                ),
              ),
              child: Slider(
                min: 0.0,
                max: duration.inMilliseconds.toDouble(),
                value: min(position.inMilliseconds.toDouble(), duration.inMilliseconds.toDouble()),
                onChanged: (value) {
                  widget.player.seek(Duration(milliseconds: value.toInt()));
                  setState(() {});
                },
                onChangeEnd: (value) => widget.player.seek,
              ),
            ),
          ],
        );
      },
    );
  }
}

class SquareThumbShape extends SliderComponentShape {
  final double width;
  final double height;

  SquareThumbShape({this.width = 12.0, this.height = 8.0});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final Paint paint = Paint()
      ..color = Colors.red.shade100
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromCenter(center: center, width: width, height: height), paint);
  }
}

class VerticalSliderForAudio extends SliderComponentShape {
  final double height;
  final double width;
  VerticalSliderForAudio({required this.height, this.width = 4});
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.zero;

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final paint = Paint()..color = Colors.red;
    canvas.drawRect(
      Rect.fromCenter(center: center, width: width, height: height),
      paint,
    );
  }
}

class AudioWaveformPainter extends CustomPainter {
  final double scale;
  final double strokeWidth;
  final double pixelsPerStep;
  final Paint wavePaint;
  final Waveform waveform;
  final Duration start;
  final Duration duration;
  final Duration currentPoint;

  AudioWaveformPainter({
    required this.waveform,
    required this.start,
    required this.duration,
    Color waveColor = Colors.black,
    required this.scale,
    required this.strokeWidth,
    required this.pixelsPerStep,
    required this.currentPoint,
  }) : wavePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = waveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (duration == Duration.zero) return;

    double width = size.width;
    double height = size.height;

    final waveformPixelsPerWindow = waveform.positionToPixel(duration).toInt();
    final waveformPixelsPerDevicePixel = waveformPixelsPerWindow / width;
    final waveformPixelsPerStep = waveformPixelsPerDevicePixel * pixelsPerStep;
    final sampleOffset = waveform.positionToPixel(start);
    final sampleStart = -sampleOffset % waveformPixelsPerStep;
    for (var i = sampleStart.toDouble(); i <= waveformPixelsPerWindow + 1.0; i += waveformPixelsPerStep) {
      wavePaint.color = i < currentPoint.inSeconds * 100 ? Colors.red : Colors.black;
      final sampleIdx = (sampleOffset + i).toInt();
      final x = i / waveformPixelsPerDevicePixel;
      final minY = normalise(waveform.getPixelMin(sampleIdx), height);
      final maxY = normalise(waveform.getPixelMax(sampleIdx), height);
      canvas.drawLine(
        Offset(x + strokeWidth / 2, max(strokeWidth * 0.75, minY)),
        Offset(x + strokeWidth / 2, min(height - strokeWidth * 0.75, maxY)),
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) {
    return false;
  }

  double normalise(int s, double height) {
    if (waveform.flags == 0) {
      final y = 32768 + (scale * s).clamp(-32768.0, 32767.0).toDouble();
      return height - 1 - y * height / 65536;
    } else {
      final y = 128 + (scale * s).clamp(-128.0, 127.0).toDouble();
      return height - 1 - y * height / 256;
    }
  }
}