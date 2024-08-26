import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

class MediaViewer extends StatefulWidget {
  final String filePath;
  final VoidCallback onDelete;

  MediaViewer({required this.filePath, required this.onDelete});

  @override
  _MediaViewerState createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late AudioPlayer _audioPlayer;
  late VideoPlayerController _videoController;
  bool _isPlaying = false;
  bool _isAudio = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _isAudio =
        widget.filePath.endsWith('.m4a') || widget.filePath.endsWith('.aac');

    if (_isAudio) {
      _audioPlayer = AudioPlayer();

      // 오디오 파일의 길이 가져오기
      _audioPlayer.setSource(DeviceFileSource(widget.filePath)).then((_) {
        _audioPlayer.getDuration().then((duration) {
          setState(() {
            _duration = duration ?? Duration.zero;
          });
        });
      });

      _audioPlayer.onDurationChanged.listen((Duration duration) {
        setState(() {
          _duration = duration;
        });
      });

      _audioPlayer.onPositionChanged.listen((Duration position) {
        setState(() {
          _position = position;
        });
      });

      _audioPlayer.onPlayerComplete.listen((event) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      });
    } else {
      _videoController = VideoPlayerController.file(File(widget.filePath))
        ..initialize().then((_) {
          setState(() {});
          _videoController.play();
        });
    }
  }

  @override
  void dispose() {
    if (_isAudio) {
      _audioPlayer.dispose();
    } else {
      _videoController.dispose();
    }
    super.dispose();
  }

  void _toggleAudioPlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(DeviceFileSource(widget.filePath));
    }
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(), // 클릭 시 닫기
        child: Stack(
          children: [
            Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.6,
                child: _isAudio ? _buildAudioPlayer() : _buildVideoPlayer(),
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 다이얼로그 닫기
                      widget.onDelete(); // 삭제 콜백 실행
                    },
                    child: Text('삭제'),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('닫기'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioPlayer() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 64,
          ),
          onPressed: _toggleAudioPlayback,
        ),
        Slider(
          value: _position.inSeconds.toDouble(),
          max: _duration.inSeconds.toDouble(),
          onChanged: (value) async {
            final position = Duration(seconds: value.toInt());
            await _audioPlayer.seek(position);
            await _audioPlayer.resume();
          },
          activeColor: Colors.white,
          inactiveColor: Colors.grey,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(color: Colors.white),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer() {
    return _videoController.value.isInitialized
        ? AspectRatio(
            aspectRatio: _videoController.value.aspectRatio,
            child: VideoPlayer(_videoController),
          )
        : Center(child: CircularProgressIndicator());
  }
}
