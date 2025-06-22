import 'dart:async';
import 'package:iapp_player/iapp_player.dart';
import 'package:iapp_player/src/subtitles/iapp_player_subtitle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class IAppPlayerSubtitlesDrawer extends StatefulWidget {
  final List<IAppPlayerSubtitle> subtitles;
  final IAppPlayerController iappPlayerController;
  final IAppPlayerSubtitlesConfiguration? iappPlayerSubtitlesConfiguration;
  final Stream<bool> playerVisibilityStream;

  const IAppPlayerSubtitlesDrawer({
    Key? key,
    required this.subtitles,
    required this.iappPlayerController,
    this.iappPlayerSubtitlesConfiguration,
    required this.playerVisibilityStream,
  }) : super(key: key);

  @override
  _IAppPlayerSubtitlesDrawerState createState() =>
      _IAppPlayerSubtitlesDrawerState();
}

class _IAppPlayerSubtitlesDrawerState
    extends State<IAppPlayerSubtitlesDrawer> {
  // 移除未使用的正则表达式
  TextStyle? _innerTextStyle;
  TextStyle? _outerTextStyle;

  VideoPlayerValue? _latestValue;
  IAppPlayerSubtitlesConfiguration? _configuration;
  bool _playerVisible = false;
  
  // 添加标志位追踪监听器状态
  bool _isListenerAdded = false;
  
  // 优化：缓存当前字幕索引，避免每次遍历
  int _lastSubtitleIndex = -1;
  // 添加标志检查字幕是否已排序
  bool _subtitlesSorted = false;

  ///Stream used to detect if play controls are visible or not
  StreamSubscription? _visibilityStreamSubscription;

  @override
  void initState() {
    super.initState();
    
    _visibilityStreamSubscription =
        widget.playerVisibilityStream.listen((state) {
      if (mounted) {
        setState(() {
          _playerVisible = state;
        });
      }
    });

    // 初始化配置
    _initializeConfiguration();
    
    // 尝试添加监听器
    _tryAddListener();
    
    // 初始化文本样式
    _initializeTextStyles();
    
    // 检查字幕是否已排序
    _checkSubtitlesSorted();
  }
  
  // 检查字幕是否按时间排序
  void _checkSubtitlesSorted() {
    final subtitles = widget.iappPlayerController.subtitlesLines;
    _subtitlesSorted = true;
    
    for (int i = 1; i < subtitles.length; i++) {
      final prev = subtitles[i - 1];
      final curr = subtitles[i];
      
      if (prev.start != null && curr.start != null && 
          prev.start!.compareTo(curr.start!) > 0) {
        _subtitlesSorted = false;
        break;
      }
    }
  }
  
  // 初始化配置
  void _initializeConfiguration() {
    if (widget.iappPlayerSubtitlesConfiguration != null) {
      _configuration = widget.iappPlayerSubtitlesConfiguration;
    } else {
      _configuration = setupDefaultConfiguration();
    }
  }
  
  // 初始化文本样式
  void _initializeTextStyles() {
    if (_configuration == null) return;
    
    _outerTextStyle = TextStyle(
        fontSize: _configuration!.fontSize,
        fontFamily: _configuration!.fontFamily,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _configuration!.outlineSize
          ..color = _configuration!.outlineColor);

    _innerTextStyle = TextStyle(
        fontFamily: _configuration!.fontFamily,
        color: _configuration!.fontColor,
        fontSize: _configuration!.fontSize);
  }
  
  // 尝试添加监听器
  void _tryAddListener() {
    final videoPlayerController = widget.iappPlayerController.videoPlayerController;
    if (videoPlayerController != null && !_isListenerAdded) {
      videoPlayerController.addListener(_updateState);
      _isListenerAdded = true;
      // 立即获取当前状态
      _updateState();
    }
  }
  
  // 尝试移除监听器
  void _tryRemoveListener() {
    final videoPlayerController = widget.iappPlayerController.videoPlayerController;
    if (videoPlayerController != null && _isListenerAdded) {
      videoPlayerController.removeListener(_updateState);
      _isListenerAdded = false;
    }
  }

  @override
  void didUpdateWidget(IAppPlayerSubtitlesDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果控制器改变，更新监听器
    if (oldWidget.iappPlayerController != widget.iappPlayerController) {
      _tryRemoveListener();
      _tryAddListener();
      // 重新检查排序
      _checkSubtitlesSorted();
    }
    
    // 如果配置改变，重新初始化
    if (oldWidget.iappPlayerSubtitlesConfiguration != 
        widget.iappPlayerSubtitlesConfiguration) {
      _initializeConfiguration();
      _initializeTextStyles();
    }
  }

  @override
  void dispose() {
    _tryRemoveListener();
    _visibilityStreamSubscription?.cancel();
    super.dispose();
  }

  ///Called when player state has changed, i.e. new player position, etc.
  void _updateState() {
    if (!mounted) return;
    
    final videoPlayerController = widget.iappPlayerController.videoPlayerController;
    if (videoPlayerController != null) {
      final newValue = videoPlayerController.value;
      // 只在值真正改变时才更新状态
      if (_latestValue != newValue) {
        setState(() {
          _latestValue = newValue;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果还没有添加监听器，尝试添加（处理延迟初始化的情况）
    if (!_isListenerAdded) {
      _tryAddListener();
    }
    
    // 安全检查：如果必要的组件未初始化，返回空容器
    if (widget.iappPlayerController.videoPlayerController == null ||
        _configuration == null ||
        _innerTextStyle == null ||
        _outerTextStyle == null) {
      return const SizedBox.shrink();
    }
    
    // 如果字幕被禁用，返回空容器
    if (widget.iappPlayerController.iappPlayerControlsConfiguration
            .enableSubtitles == false) {
      return const SizedBox.shrink();
    }
    
    final IAppPlayerSubtitle? subtitle = _getSubtitleAtCurrentPosition();
    widget.iappPlayerController.renderedSubtitle = subtitle;
    
    final List<String> subtitles = subtitle?.texts ?? [];
    if (subtitles.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final List<Widget> textWidgets =
        subtitles.map((text) => _buildSubtitleTextWidget(text)).toList();

    return Container(
      height: double.infinity,
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: _playerVisible
                ? (_configuration?.bottomPadding ?? 0) + 30
                : (_configuration?.bottomPadding ?? 0),
            left: _configuration?.leftPadding ?? 0,
            right: _configuration?.rightPadding ?? 0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: textWidgets,
        ),
      ),
    );
  }

  // 优化：根据字幕是否排序选择查找算法
  IAppPlayerSubtitle? _getSubtitleAtCurrentPosition() {
    if (_latestValue == null || _latestValue!.position == null) {
      return null;
    }

    final Duration position = _latestValue!.position;
    final subtitles = widget.iappPlayerController.subtitlesLines;
    
    if (subtitles.isEmpty) {
      return null;
    }

    // 如果字幕已排序，使用优化的查找
    if (_subtitlesSorted) {
      return _getSubtitleOptimized(position, subtitles);
    } else {
      // 否则使用原始的线性查找
      return _getSubtitleLinear(position, subtitles);
    }
  }
  
  // 优化的查找（要求字幕已排序）
  IAppPlayerSubtitle? _getSubtitleOptimized(Duration position, List<IAppPlayerSubtitle> subtitles) {
    try {
      // 先检查上次的字幕是否仍然有效（优化连续播放场景）
      if (_lastSubtitleIndex >= 0 && _lastSubtitleIndex < subtitles.length) {
        final lastSubtitle = subtitles[_lastSubtitleIndex];
        if (lastSubtitle.start != null && 
            lastSubtitle.end != null &&
            lastSubtitle.start! <= position && 
            lastSubtitle.end! >= position) {
          return lastSubtitle;
        }
      }

      // 使用二分查找定位字幕
      int left = 0;
      int right = subtitles.length - 1;
      
      while (left <= right) {
        int mid = left + ((right - left) >> 1);
        final subtitle = subtitles[mid];
        
        if (subtitle.start == null || subtitle.end == null) {
          // 跳过无效字幕
          left = mid + 1;
          continue;
        }
        
        if (subtitle.start! <= position && subtitle.end! >= position) {
          _lastSubtitleIndex = mid;
          return subtitle;
        } else if (subtitle.end! < position) {
          left = mid + 1;
        } else {
          right = mid - 1;
        }
      }
      
      _lastSubtitleIndex = -1;
    } catch (e) {
      debugPrint('Error in optimized subtitle search: $e');
      _lastSubtitleIndex = -1;
    }
    
    return null;
  }
  
  // 原始的线性查找（保持兼容性）
  IAppPlayerSubtitle? _getSubtitleLinear(Duration position, List<IAppPlayerSubtitle> subtitles) {
    try {
      for (int i = 0; i < subtitles.length; i++) {
        final subtitle = subtitles[i];
        if (subtitle.start != null && 
            subtitle.end != null &&
            subtitle.start! <= position && 
            subtitle.end! >= position) {
          _lastSubtitleIndex = i;
          return subtitle;
        }
      }
      _lastSubtitleIndex = -1;
    } catch (e) {
      debugPrint('Error in linear subtitle search: $e');
      _lastSubtitleIndex = -1;
    }
    
    return null;
  }

  Widget _buildSubtitleTextWidget(String subtitleText) {
    if (_configuration == null) {
      return const SizedBox.shrink();
    }
    
    return Row(children: [
      Expanded(
        child: Align(
          alignment: _configuration?.alignment ?? Alignment.bottomCenter,
          child: _getTextWithStroke(subtitleText),
        ),
      ),
    ]);
  }

  Widget _getTextWithStroke(String subtitleText) {
    if (_configuration == null || 
        _innerTextStyle == null || 
        _outerTextStyle == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      color: _configuration?.backgroundColor ?? Colors.transparent,
      child: Stack(
        children: [
          if (_configuration?.outlineEnabled == true)
            _buildHtmlWidget(subtitleText, _outerTextStyle!)
          else
            const SizedBox(),
          _buildHtmlWidget(subtitleText, _innerTextStyle!)
        ],
      ),
    );
  }

  Widget _buildHtmlWidget(String text, TextStyle textStyle) {
    try {
      return HtmlWidget(
        text,
        textStyle: textStyle,
      );
    } catch (e) {
      // 如果HTML解析失败，使用普通文本
      return Text(
        text,
        style: textStyle,
      );
    }
  }

  IAppPlayerSubtitlesConfiguration setupDefaultConfiguration() {
    return const IAppPlayerSubtitlesConfiguration();
  }
}
