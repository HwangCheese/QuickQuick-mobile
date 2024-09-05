import 'dart:convert';

import 'package:flutter/material.dart';
import 'write_memo_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:io';
import 'package:flutter_pdfview/flutter_pdfview.dart';

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
  bool _isVideo = false;
  bool _isImage = false;
  bool _isPdf = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  PDFViewController? _pdfViewController;
  String _summary = '';

  @override
  void initState() {
    super.initState();
    _isAudio =
        widget.filePath.endsWith('.m4a') || widget.filePath.endsWith('.aac');
    _isVideo = widget.filePath.endsWith('.mp4') ||
        widget.filePath.endsWith('.MOV') ||
        widget.filePath.endsWith('.mov');
    _isImage = widget.filePath.endsWith('.png') ||
        widget.filePath.endsWith('.jpg') ||
        widget.filePath.endsWith('.jpeg');
    _isPdf = widget.filePath.endsWith('.pdf');

    if (_isAudio) {
      _initializeAudioPlayer();
    } else if (_isVideo) {
      _initializeVideoPlayer();
    }
  }

  void _initializeAudioPlayer() {
    _audioPlayer = AudioPlayer();

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
  }

  void _initializeVideoPlayer() {
    _videoController = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() {
          _duration = _videoController.value.duration;
        });
        _videoController.play();
      });

    _videoController.addListener(() {
      setState(() {
        _position = _videoController.value.position;
        _isPlaying = _videoController.value.isPlaying;
      });
    });
  }

  @override
  void dispose() {
    if (_isAudio) {
      _audioPlayer.dispose();
    } else if (_isVideo) {
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

  void _toggleVideoPlayback() {
    setState(() {
      if (_isPlaying) {
        _videoController.pause();
      } else {
        _videoController.play();
      }
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
      backgroundColor: Colors.black.withOpacity(0.7),
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: _isAudio
                      ? _buildAudioPlayer()
                      : _isVideo
                          ? _buildVideoPlayer()
                          : _isImage
                              ? _buildImageView()
                              : _isPdf
                                  ? _buildPdfViewer()
                                  : Container(),
                ),
              ),
            ),
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isAudio) ...[
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context, 'transcribe');
                          },
                          child: Text('텍스트 변환'),
                        ),
                        SizedBox(width: 10),
                      ],
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onDelete();
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: _videoController.value.aspectRatio,
            child: VideoPlayer(_videoController),
          ),
        ),
        Slider(
          value: _position.inSeconds.toDouble(),
          max: _duration.inSeconds.toDouble(),
          onChanged: (value) async {
            final position = Duration(seconds: value.toInt());
            await _videoController.seekTo(position);
            if (!_isPlaying) {
              _videoController.play();
            }
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
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 64,
          ),
          onPressed: _toggleVideoPlayback,
        ),
      ],
    );
  }

  Widget _buildImageView() {
    return Image.file(
      File(widget.filePath),
      fit: BoxFit.contain,
    );
  }

  Widget _buildPdfViewer() {
    return PDFView(
      filePath: widget.filePath,
      enableSwipe: true,
      swipeHorizontal: false, // 위아래로 스크롤하게 설정
      autoSpacing: true,
      pageFling: true, // 자연스러운 스크롤을 위해 설정
      fitEachPage: false, // 페이지가 전체 화면에 맞도록 조정
      fitPolicy: FitPolicy.BOTH, // 페이지를 가로와 세로 모두 맞춤
      onRender: (_pages) {
        setState(() {
          _totalPages = _pages ?? 0;
          _isReady = true;
        });
      },
      onViewCreated: (PDFViewController pdfViewController) {
        _pdfViewController = pdfViewController;
        _pdfViewController!.setPage(0); // 첫 번째 페이지로 설정
      },
      onPageChanged: (int? page, int? total) {
        setState(() {
          _currentPage = page ?? 0;
        });
      },
      onError: (error) {
        print("Error loading PDF: $error");
        setState(() {
          _isReady = false;
        });
      },
      onPageError: (page, error) {
        print("Page error on page $page: $error");
        setState(() {
          _isReady = false;
        });
      },
    );
  }
}
