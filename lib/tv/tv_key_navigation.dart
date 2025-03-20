import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/channel_drawer_page.dart';

/// 用于将颜色变暗的函数
Color darkenColor(Color color, [double amount = 0.3]) {
  final hsl = HSLColor.fromColor(color); // 将颜色转换为 HSL 格式
  final darkened = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)); // 调整亮度并限制范围
  return darkened.toColor(); // 返回变暗后的颜色
}

/// TV 按键导航组件类
class TvKeyNavigation extends StatefulWidget {
  final Widget child; // 包裹的子组件
  final List<FocusNode> focusNodes; // 需要导航的焦点节点列表
  final Map<int, Map<String, FocusNode>>? groupFocusCache; // 分组焦点缓存，可选
  final Function(int index)? onSelect; // 焦点选择时的回调
  final Function(LogicalKeyboardKey key)? onKeyPressed; // 按键按下时的回调
  final bool isFrame; // 是否启用框架模式切换焦点
  final String? frameType; // 页面类型（父或子页面）
  final int? initialIndex; // 初始焦点索引，空则自动聚焦
  final bool isHorizontalGroup; // 是否启用横向分组
  final bool isVerticalGroup; // 是否启用竖向分组
  final Function(TvKeyNavigationState state)? onStateCreated; // 状态创建时的回调
  final String? cacheName; // 自定义缓存名称

  const TvKeyNavigation({
    Key? key,
    required this.child,
    required this.focusNodes,
    this.groupFocusCache,
    this.onSelect,
    this.onKeyPressed,
    this.isFrame = false,
    this.frameType,
    this.initialIndex,
    this.isHorizontalGroup = false,
    this.isVerticalGroup = false,
    this.onStateCreated,
    this.cacheName,
  }) : super(key: key);

  @override
  TvKeyNavigationState createState() => TvKeyNavigationState(); // 创建状态对象
}

/// TV 按键导航的状态管理类
class TvKeyNavigationState extends State<TvKeyNavigation> with WidgetsBindingObserver {
  FocusNode? _currentFocus; // 当前焦点节点
  Map<int, Map<String, FocusNode>> _groupFocusCache = {}; // 分组焦点缓存
  static Map<String, Map<int, Map<String, FocusNode>>> _namedCaches = {}; // 按页面名称存储的缓存
  bool _isFocusManagementActive = false; // 是否激活焦点管理
  int? _lastParentFocusIndex; // 父页面最后焦点索引
  DateTime? _lastKeyProcessedTime; // 上次按键处理时间
  static const Duration _throttleDuration = Duration(milliseconds: 500); // 按键节流间隔改为 500 毫秒
  
  /// 判断是否为导航相关按键
  bool _isNavigationKey(LogicalKeyboardKey key) {
    return _isDirectionKey(key) || _isSelectKey(key); // 检查是否为方向键或选择键
  }

  @override
  void didUpdateWidget(TvKeyNavigation oldWidget) {
    super.didUpdateWidget(oldWidget); // 调用父类方法
    if (oldWidget.focusNodes != widget.focusNodes || oldWidget.groupFocusCache != widget.groupFocusCache) { // 检查焦点节点或缓存是否变化
      LogUtil.i('TvKeyNavigation: focusNodes 或 groupFocusCache 变化，同步状态');
      
      bool isCurrentFocusValid = _currentFocus != null && widget.focusNodes.contains(_currentFocus) && _currentFocus!.canRequestFocus; // 验证当前焦点有效性
      if (!isCurrentFocusValid) _currentFocus = null; // 重置无效焦点
      
      if (widget.groupFocusCache != null && oldWidget.groupFocusCache != widget.groupFocusCache) { // 检查是否需要同步缓存
        _groupFocusCache = Map.from(widget.groupFocusCache!); // 更新缓存
      }
      
      if (_isFocusManagementActive && !isCurrentFocusValid) { // 检查是否需要重新初始化焦点
        int initialIndex = widget.initialIndex ?? 0; // 获取初始索引
        if (widget.focusNodes.isNotEmpty && initialIndex >= 0 && initialIndex < widget.focusNodes.length) { // 验证索引有效性
          initializeFocusLogic(initialIndexOverride: initialIndex); // 初始化焦点
        } else {
          initializeFocusLogic(); // 使用默认初始化
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) { // 处理按键事件
        if (event is KeyDownEvent) { // 检查是否为按下事件
          if (_isNavigationKey(event.logicalKey)) { // 检查是否为导航键
            final result = _handleKeyEvent(node, event); // 处理导航键事件
            return result == KeyEventResult.ignored ? KeyEventResult.handled : result; // 返回处理结果
          }
        }
        return KeyEventResult.ignored; // 非导航键则忽略
      },
      child: widget.child, // 渲染子组件
    );
  }

  @override
  void initState() {
    super.initState(); // 调用父类方法
    widget.onStateCreated?.call(this); // 执行状态创建回调
    _isFocusManagementActive = !widget.isFrame || widget.frameType == "parent"; // 根据框架类型设置焦点管理状态
    if (_isFocusManagementActive) initializeFocusLogic(); // 若激活则初始化焦点逻辑
    WidgetsBinding.instance.addObserver(this); // 添加生命周期观察者
  }

  /// 激活焦点管理
  void activateFocusManagement({int? initialIndexOverride}) {
    setState(() { _isFocusManagementActive = true; }); // 更新焦点管理状态
    if (widget.cacheName != null) { // 检查是否使用缓存名称
      String cacheName = 'groupCache-${widget.cacheName}'; // 生成缓存键
      if (_namedCaches.containsKey(cacheName)) { // 检查缓存是否存在
        _groupFocusCache = Map.from(_namedCaches[cacheName]!); // 恢复缓存
        LogUtil.i('使用 ${widget.cacheName} 的缓存');
        _requestFocus(_lastParentFocusIndex ?? 0); // 恢复焦点位置
      } else {
        LogUtil.i('未找到 ${widget.cacheName} 的缓存');
      }
    } else if (widget.frameType == "child") { // 检查是否为子页面
      initializeFocusLogic(); // 初始化子页面焦点逻辑
    }
    LogUtil.i('激活页面的焦点管理');
  }

  /// 停用焦点管理
  void deactivateFocusManagement() {
    setState(() {
      _isFocusManagementActive = false; // 停用焦点管理
      if (widget.frameType == "parent" && _currentFocus != null) { // 检查是否为父页面且有焦点
        _lastParentFocusIndex = widget.focusNodes.indexOf(_currentFocus!); // 保存焦点位置
        LogUtil.i('保存父页面焦点位置: $_lastParentFocusIndex');
      }
    });
    LogUtil.i('停用页面的焦点管理');
  }
  
  @override
  void dispose() {
    releaseResources(); // 释放资源
    super.dispose(); // 调用父类方法
  }

  /// 释放组件使用的资源
  void releaseResources() {
    if (!mounted) return; // 检查组件是否已卸载

    // 释放焦点
    if (_currentFocus != null && _currentFocus!.canRequestFocus) { // 检查当前焦点是否有效
      try {
        if (widget.frameType == "parent") { // 检查是否为父页面
          _lastParentFocusIndex = widget.focusNodes.indexOf(_currentFocus!); // 保存焦点索引
        }
        if (_currentFocus!.hasFocus) _currentFocus!.unfocus(); // 移除焦点
        _currentFocus = null; // 清空焦点
      } catch (e) {
        LogUtil.i('释放焦点失败: $e');
      }
    }

    // 清理缓存
    try {
      if (widget.frameType == "child" || !widget.isFrame) { // 检查是否为子页面或非框架模式
        _groupFocusCache.clear(); // 清空分组缓存
        if (widget.cacheName != null) { // 检查是否使用缓存名称
          String cacheName = 'groupCache-${widget.cacheName}'; // 生成缓存键
          _namedCaches.remove(cacheName); // 清理命名缓存
          LogUtil.i('清理 $cacheName 的缓存');
        }
      }
    } catch (e) {
      LogUtil.i('清理缓存失败: $e');
    }

    // 重置状态
    _isFocusManagementActive = !widget.isFrame;

    // 移除观察者
    try {
      WidgetsBinding.instance.removeObserver(this); // 移除观察者
    } catch (e) {
      LogUtil.i('移除 WidgetsBindingObserver 失败: $e');
    }
  }

  /// 初始化焦点逻辑
  void initializeFocusLogic({int? initialIndexOverride}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (widget.focusNodes.isEmpty) { // 检查焦点节点是否为空
          LogUtil.i('focusNodes 为空，无法设置焦点');
          return;
        } else {
          LogUtil.i('正在初始化焦点逻辑，共 ${widget.focusNodes.length} 个节点');
        }
        if (widget.groupFocusCache != null) { // 检查是否传入分组缓存
          _groupFocusCache = Map.from(widget.groupFocusCache!); // 使用传入缓存
          LogUtil.i('使用传入的 groupFocusCache: ${_groupFocusCache.map((key, value) => MapEntry(key, "{first: ${widget.focusNodes.indexOf(value['firstFocusNode']!)}, last: ${widget.focusNodes.indexOf(value['lastFocusNode']!)}}"))}');
        } else {
          if (widget.cacheName == "ChannelDrawerPage") { // 检查是否为特定页面
            final channelDrawerState = context.findAncestorStateOfType<ChannelDrawerStateInterface>(); // 获取页面状态
            if (channelDrawerState != null) { // 检查状态是否存在
              channelDrawerState.initializeData(); // 初始化数据
              channelDrawerState.updateFocusLogic(true); // 更新焦点逻辑
              LogUtil.i('cacheName 为 ChannelDrawerPage，调用 initializeData 和 updateFocusLogic');
            } else {
              LogUtil.i('未找到 ChannelDrawerPage 的状态，无法调用 initializeData 和 updateFocusLogic');
            }
          } else {
            LogUtil.i('未传入 groupFocusCache，执行分组查找逻辑');
            _cacheGroupFocusNodes(); // 缓存分组焦点信息
          }
        }
        int initialIndex = initialIndexOverride ?? widget.initialIndex ?? 0; // 获取初始索引
        if (initialIndex != -1 && widget.focusNodes.isNotEmpty) _requestFocus(initialIndex); // 设置初始焦点
      } catch (e) {
        LogUtil.i('初始焦点设置失败: $e');
      }
    });
  }

  /// 封装错误处理逻辑
  void _handleError(String message, dynamic error, StackTrace stackTrace) {
    LogUtil.i('$message: $error\n位置: $stackTrace'); // 记录错误信息
  }
  
  /// 查找子页面导航状态
  TvKeyNavigationState? _findChildNavigation() {
    TvKeyNavigationState? childNavigation; // 子页面导航状态
    void visitChild(Element element) { // 递归访问子元素
      if (element.widget is TvKeyNavigation) { // 检查是否为导航组件
        final navigationWidget = element.widget as TvKeyNavigation;
        if (navigationWidget.frameType == "child") { // 检查是否为子页面
          childNavigation = (element as StatefulElement).state as TvKeyNavigationState; // 获取状态
          LogUtil.i('找到可用的子页面导航组件');
          return;
        }
      }
      element.visitChildren(visitChild); // 继续递归
    }
    context.visitChildElements(visitChild); // 开始遍历
    if (childNavigation == null) LogUtil.i('未找到可用的子页面导航组件'); // 未找到时记录日志
    return childNavigation; // 返回子页面状态
  }

  /// 查找父页面导航状态
  TvKeyNavigationState? _findParentNavigation() {
    TvKeyNavigationState? parentNavigation; // 父页面导航状态
    void findInContext(BuildContext context) { // 递归查找上下文
      context.visitChildElements((element) {
        if (element.widget is TvKeyNavigation) { // 检查是否为导航组件
          final navigationWidget = element.widget as TvKeyNavigation;
          if (navigationWidget.frameType == "parent") { // 检查是否为父页面
            parentNavigation = (element as StatefulElement).state as TvKeyNavigationState; // 获取状态
            LogUtil.i('找到可用的父页面导航组件');
            return;
          }
        }
        findInContext(element); // 继续递归
      });
    }
    final rootElement = context.findRootAncestorStateOfType<NavigatorState>()?.context; // 获取根元素
    if (rootElement != null) findInContext(rootElement); // 从根部查找
    if (parentNavigation == null) LogUtil.i('未找到可用的父页面导航组件'); // 未找到时记录日志
    return parentNavigation; // 返回父页面状态
  }
  
  /// 请求将焦点切换到指定索引
  void _requestFocus(int index, {int? groupIndex}) {
    if (widget.focusNodes.isEmpty) { // 检查焦点节点是否为空
      LogUtil.i('焦点节点列表为空，无法设置焦点');
      return;
    }
    try {
      if (index < 0 || index >= widget.focusNodes.length) { // 检查索引是否越界
        LogUtil.i('焦点索引越界: $index');
        return;
      }
      groupIndex ??= _getGroupIndex(widget.focusNodes[index]); // 获取分组索引
      if (groupIndex == -1 || !_groupFocusCache.containsKey(groupIndex)) { // 检查分组有效性
        FocusNode firstValidFocusNode = widget.focusNodes.firstWhere((node) => node.canRequestFocus, orElse: () => widget.focusNodes[0]); // 寻找首个有效节点
        firstValidFocusNode.requestFocus(); // 设置焦点
        _currentFocus = firstValidFocusNode; // 更新当前焦点
        LogUtil.i('无效的 Group，设置到第一个可用焦点节点');
        return;
      }
      var groupCache = _groupFocusCache[groupIndex]; // 获取分组缓存
      if (groupCache == null || !groupCache.containsKey('firstFocusNode') || !groupCache.containsKey('lastFocusNode')) { // 检查缓存完整性
        LogUtil.i('Group $groupIndex 的缓存不完整');
        FocusNode firstValidFocusNode = widget.focusNodes.firstWhere((node) => node.canRequestFocus, orElse: () => widget.focusNodes[0]); // 寻找首个有效节点
        firstValidFocusNode.requestFocus(); // 设置焦点
        _currentFocus = firstValidFocusNode; // 更新当前焦点
        return;
      }
      FocusNode firstFocusNode = groupCache['firstFocusNode']!; // 首个焦点节点
      FocusNode lastFocusNode = groupCache['lastFocusNode']!; // 最后焦点节点
      int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode); // 首个焦点索引
      int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode); // 最后焦点索引
      if (index < firstFocusIndex) index = lastFocusIndex; // 若小于首个则循环到最后
      else if (index > lastFocusIndex) index = firstFocusIndex; // 若大于最后则循环到首个
      FocusNode focusNode = widget.focusNodes[index]; // 获取目标焦点节点
      if (!focusNode.canRequestFocus) { // 检查焦点是否可请求
        LogUtil.i('焦点节点不可请求，索引: $index');
        return;
      }
      if (!focusNode.hasFocus) { // 检查是否已有焦点
        focusNode.requestFocus(); // 设置焦点
        _currentFocus = focusNode; // 更新当前焦点
        LogUtil.i('切换焦点到索引: $index, 当前Group: $groupIndex');
      }
    } catch (e, stackTrace) {
      LogUtil.i('设置焦点时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
  }
  
  /// 缓存分组的焦点信息
  void _cacheGroupFocusNodes() {
    if (widget.groupFocusCache != null) { // 检查是否已有缓存
      LogUtil.i('groupFocusCache 已传入，不执行 _cacheGroupFocusNodes');
      return;
    }
    _groupFocusCache.clear(); // 清空缓存
    final groups = _getAllGroups(); // 获取所有分组
    LogUtil.i('缓存分组：找到的总组数: ${groups.length}');
    if (groups.isEmpty || groups.length == 1) _cacheDefaultGroup(); // 无分组或单一分组时缓存默认分组
    else _cacheMultipleGroups(groups); // 多个分组时缓存所有分组
    final cacheName = 'groupCache-${widget.cacheName ?? "TvKeyNavigation"}'; // 生成缓存名称
    _namedCaches[cacheName] = Map.from(_groupFocusCache); // 保存缓存
    LogUtil.i('保存 $cacheName 的缓存');
  }
  
  /// 缓存默认分组的焦点节点
  void _cacheDefaultGroup() {
    final firstFocusNode = _findFirstFocusableNode(widget.focusNodes); // 查找首个可聚焦节点
    final lastFocusNode = _findLastFocusableNode(widget.focusNodes); // 查找最后可聚焦节点
    _groupFocusCache[0] = {'firstFocusNode': firstFocusNode, 'lastFocusNode': lastFocusNode}; // 缓存默认分组
    LogUtil.i('缓存了默认分组的焦点节点 - 首个焦点节点: ${_formatFocusNodeDebugLabel(firstFocusNode)}, 最后焦点节点: ${_formatFocusNodeDebugLabel(lastFocusNode)}');
  }

  /// 缓存多个分组的焦点节点
  void _cacheMultipleGroups(List<Group> groups) {
    for (var group in groups) { // 遍历所有分组
      final groupWidgets = _getWidgetsInGroup(group); // 获取分组中的组件
      final groupFocusNodes = _getFocusNodesInGroup(groupWidgets); // 获取分组中的焦点节点
      if (groupFocusNodes.isNotEmpty) { // 检查是否存在焦点节点
        _groupFocusCache[group.groupIndex] = {'firstFocusNode': groupFocusNodes.first, 'lastFocusNode': groupFocusNodes.last}; // 缓存分组焦点
        LogUtil.i('分组 ${group.groupIndex}: 首个焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.first)}, 最后焦点节点: ${_formatFocusNodeDebugLabel(groupFocusNodes.last)}');
      } else {
        LogUtil.i('警告：分组 ${group.groupIndex} 没有可聚焦的节点');
      }
    }
  }
  
  /// 查找首个可聚焦节点
  FocusNode _findFirstFocusableNode(List<FocusNode> nodes) {
    return nodes.firstWhere((node) => node.canRequestFocus, orElse: () => FocusNode(debugLabel: '空焦点节点')); // 返回首个可聚焦节点或默认节点
  }

  /// 查找最后可聚焦节点
  FocusNode _findLastFocusableNode(List<FocusNode> nodes) {
    return nodes.lastWhere((node) => node.canRequestFocus, orElse: () => FocusNode(debugLabel: '空焦点节点')); // 返回最后可聚焦节点或默认节点
  }

  /// 格式化焦点节点调试标签
  String _formatFocusNodeDebugLabel(FocusNode focusNode) {
    return focusNode.debugLabel ?? '索引: ${widget.focusNodes.indexOf(focusNode)}'; // 返回调试标签或索引
  }

  /// 获取分组中的组件
  List<Widget> _getWidgetsInGroup(Group group) {
    return group.children ?? (group.child != null ? [group.child!] : []); // 返回分组的子组件或单子组件
  }

  /// 从组件列表中获取可聚焦节点
  List<FocusNode> _getFocusNodesInGroup(List<Widget> widgets) {
    List<FocusNode> focusNodes = []; // 初始化焦点节点列表
    void processWidget(Widget widget) { // 递归处理组件
      if (widget is FocusableItem) focusNodes.add(widget.focusNode); // 添加焦点节点
      else if (widget is MultiChildRenderObjectWidget) widget.children.forEach(processWidget); // 处理多子组件
      else if (widget is SingleChildRenderObjectWidget && widget.child != null) processWidget(widget.child!); // 处理单子组件
    }
    widgets.forEach(processWidget); // 遍历所有组件
    return focusNodes.where((node) => node.canRequestFocus).toList(); // 返回可聚焦节点列表
  }

  /// 获取当前焦点所属分组索引
  int _getGroupIndex(FocusNode focusNode) {
    try {
      for (var entry in _groupFocusCache.entries) { // 遍历缓存条目
        FocusNode firstFocusNode = entry.value['firstFocusNode']!; // 首个焦点节点
        FocusNode lastFocusNode = entry.value['lastFocusNode']!; // 最后焦点节点
        if (widget.focusNodes.indexOf(focusNode) >= widget.focusNodes.indexOf(firstFocusNode) && widget.focusNodes.indexOf(focusNode) <= widget.focusNodes.indexOf(lastFocusNode)) { // 检查焦点是否在范围内
          return entry.key; // 返回分组索引
        }
      }
      return -1; // 未找到则返回 -1
    } catch (e, stackTrace) {
      _handleError('从缓存中获取分组索引失败', e, stackTrace); // 处理错误
      return -1; // 返回无效索引
    }
  }

  /// 获取总分组数
  int _getTotalGroups() {
    return _groupFocusCache.length; // 返回缓存中的分组数
  }

  /// 获取所有分组
  List<Group> _getAllGroups() {
    List<Group> groups = []; // 初始化分组列表
    void searchGroups(Element element) { // 递归查找分组
      if (element.widget is Group) groups.add(element.widget as Group); // 添加分组
      element.visitChildren((child) { searchGroups(child); }); // 继续递归
    }
    if (context != null) context.visitChildElements((element) { searchGroups(element); }); // 开始遍历
    return groups; // 返回分组列表
  }

  /// 在组内导航焦点
  void _navigateInGroup(LogicalKeyboardKey key, int currentIndex, int groupIndex, bool forward) {
    FocusNode firstFocusNode = _groupFocusCache[groupIndex]!['firstFocusNode']!; // 首个焦点节点
    FocusNode lastFocusNode = _groupFocusCache[groupIndex]!['lastFocusNode']!; // 最后焦点节点
    int firstFocusIndex = widget.focusNodes.indexOf(firstFocusNode); // 首个焦点索引
    int lastFocusIndex = widget.focusNodes.indexOf(lastFocusNode); // 最后焦点索引
    String action = ''; // 操作描述
    int nextIndex = 0; // 下个焦点索引
    if (forward) { // 前进导航
      if (currentIndex == lastFocusIndex) { // 检查是否为最后焦点
        nextIndex = firstFocusIndex; // 循环到首个焦点
        action = "循环到第一个焦点 (索引: $nextIndex)";
      } else {
        nextIndex = currentIndex + 1; // 切换到下个焦点
        action = "切换到下一个焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
      }
    } else { // 后退导航
      if (currentIndex == firstFocusIndex) { // 检查是否为首个焦点
        if (widget.frameType == "child") { // 检查是否为子页面
          final parentNavigation = _findParentNavigation(); // 查找父页面导航
          if (parentNavigation != null) { // 检查父页面是否存在
            deactivateFocusManagement(); // 停用子页面焦点
            parentNavigation.activateFocusManagement(); // 激活父页面焦点
            LogUtil.i('返回父页面');
          } else {
            LogUtil.i('尝试返回父页面但失败');
          }
          return;
        } else {
          nextIndex = lastFocusIndex; // 循环到最后焦点
          action = "循环到最后一个焦点 (索引: $nextIndex)";
        }
      } else {
        nextIndex = currentIndex - 1; // 切换到前个焦点
        action = "切换到前一个焦点 (当前索引: $currentIndex -> 新索引: $nextIndex)";
      }
    }
    _requestFocus(nextIndex, groupIndex: groupIndex); // 请求焦点切换
    LogUtil.i('操作: $action (组: $groupIndex)');
  }

  /// 处理导航逻辑
  KeyEventResult _handleNavigation(LogicalKeyboardKey key) {
    final now = DateTime.now(); // 获取当前时间
    if (_lastKeyProcessedTime != null) { // 检查是否已有上次处理时间
      final timeSinceLastKey = now.difference(_lastKeyProcessedTime!); // 计算时间差
      if (timeSinceLastKey < _throttleDuration) { // 检查是否在节流时间内
        LogUtil.i('按键事件被节流，距离上一次处理未满 ${_throttleDuration.inMilliseconds} 毫秒');
        return KeyEventResult.handled; // 忽略事件
      }
    }
    _lastKeyProcessedTime = now; // 更新处理时间
    FocusNode? currentFocus = _currentFocus; // 获取当前焦点
    if (currentFocus == null) { // 检查焦点是否为空
      LogUtil.i('当前无焦点，尝试设置初始焦点');
      _requestFocus(0); // 设置初始焦点
      return KeyEventResult.handled;
    }
    int currentIndex = widget.focusNodes.indexOf(currentFocus); // 获取当前焦点索引
    if (currentIndex == -1) { // 检查索引是否有效
      LogUtil.i('找不到当前焦点的索引');
      return KeyEventResult.ignored;
    }
    int groupIndex = _getGroupIndex(currentFocus); // 获取分组索引
    try {
      if (widget.isFrame) { // 检查是否为框架模式
        if (widget.frameType == "parent") { // 检查是否为父页面
          if (key == LogicalKeyboardKey.arrowRight) { // 右键切换到子页面
            final childNavigation = _findChildNavigation(); // 查找子页面导航
            if (childNavigation != null) { // 检查子页面是否存在
              deactivateFocusManagement(); // 停用父页面焦点
              childNavigation.activateFocusManagement(); // 激活子页面焦点
              LogUtil.i('切换到子页面');
              return KeyEventResult.handled;
            }
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowUp) { // 左上键后退
            _navigateInGroup(key, currentIndex, groupIndex, false); // 组内后退
          } else if (key == LogicalKeyboardKey.arrowDown) { // 下键前进
            _navigateInGroup(key, currentIndex, groupIndex, true); // 组内前进
          }
        } else if (widget.frameType == "child") { // 检查是否为子页面
          if (key == LogicalKeyboardKey.arrowLeft) { // 左键后退
            _navigateInGroup(key, currentIndex, groupIndex, false); // 组内后退或回父页面
          } else if (key == LogicalKeyboardKey.arrowRight) { // 右键前进
            _navigateInGroup(key, currentIndex, groupIndex, true); // 组内前进
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) { // 上下键跳转分组
            _jumpToOtherGroup(key, currentIndex, groupIndex); // 跳转到其他分组
          }
        }
      } else { // 非框架模式
        if (widget.isHorizontalGroup) { // 检查是否启用横向分组
          if (key == LogicalKeyboardKey.arrowLeft) { // 左键后退
            _navigateInGroup(key, currentIndex, groupIndex, false); // 组内后退
          } else if (key == LogicalKeyboardKey.arrowRight) { // 右键前进
            _navigateInGroup(key, currentIndex, groupIndex, true); // 组内前进
          } else if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) { // 上下键跳转分组
            _jumpToOtherGroup(key, currentIndex, groupIndex); // 跳转到其他分组
          }
        } else if (widget.isVerticalGroup) { // 检查是否启用竖向分组
          if (key == LogicalKeyboardKey.arrowUp) { // 上键后退
            _navigateInGroup(key, currentIndex, groupIndex, false); // 组内后退
          } else if (key == LogicalKeyboardKey.arrowDown) { // 下键前进
            _navigateInGroup(key, currentIndex, groupIndex, true); // 组内前进
          } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) { // 左右键跳转分组
            _jumpToOtherGroup(key, currentIndex, groupIndex); // 跳转到其他分组
          }
        } else { // 默认导航逻辑
          if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) { // 左上键后退
            _navigateInGroup(key, currentIndex, groupIndex, false); // 组内后退
          } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) { // 右下键前进
            _navigateInGroup(key, currentIndex, groupIndex, true); // 组内前进
          }
        }
      }
    } catch (e) {
      LogUtil.i('焦点切换错误: $e');
    }
    FocusNode? currentFocusNode = _currentFocus; // 获取当前焦点节点
    if (currentFocusNode != null) { // 检查焦点是否有效
      int newIndex = widget.focusNodes.indexOf(currentFocusNode); // 获取新焦点索引
      if (widget.onSelect != null && newIndex != -1 && newIndex != currentIndex) widget.onSelect!(newIndex); // 调用选择回调
    }
    return KeyEventResult.handled; // 返回处理结果
  }
  
  /// 处理键盘事件
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {    
    if (event is KeyEvent && event is! KeyUpEvent) { // 检查是否为按下事件
      LogicalKeyboardKey key = event.logicalKey; // 获取按键
      if (!_isFocusManagementActive) { // 检查焦点管理是否激活
        LogUtil.i('焦点管理未激活，不处理按键事件');
        return KeyEventResult.ignored;
      }
      if (_isDirectionKey(key)) return _handleNavigation(key); // 处理方向键
      if (_isSelectKey(key)) { // 处理选择键
        try {
          _triggerButtonAction(); // 触发按钮操作
        } catch (e) {
          LogUtil.i('执行按钮操作时发生错误: $e');
        }
        return KeyEventResult.handled;
      }
      if (widget.onKeyPressed != null) widget.onKeyPressed!(key); // 执行自定义按键回调
    }
    return KeyEventResult.ignored; // 未处理的事件
  }
  
  /// 判断是否为方向键
  bool _isDirectionKey(LogicalKeyboardKey key) {
    return {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight}.contains(key); // 检查是否为方向键
  }

  /// 判断是否为选择键
  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter; // 检查是否为选择键
  }
  
  /// 执行当前焦点控件点击操作
  void _triggerButtonAction() { 
    final focusNode = _currentFocus; // 获取当前焦点
    if (focusNode != null && focusNode.context != null) { // 检查焦点和上下文是否有效
      final BuildContext? context = focusNode.context; // 获取上下文
      if (context == null) { // 检查上下文是否为空
        LogUtil.i('焦点上下文为空，无法操作');
        return;
      }
      try {
        final focusableItem = context.findAncestorWidgetOfExactType<FocusableItem>(); // 查找焦点项
        if (focusableItem != null) _triggerActionsInFocusableItem(context); // 触发焦点项操作
        else LogUtil.i('未找到 FocusableItem 包裹的控件'); // 未找到焦点项
      } catch (e, stackTrace) {
        LogUtil.i('执行操作时发生错误: $e, 堆栈信息: $stackTrace');
      }
    }
  }

  /// 在焦点项下触发交互控件操作
  void _triggerActionsInFocusableItem(BuildContext context) {
    _visitAllElements(context, (element) { return _triggerWidgetAction(element.widget); }); // 遍历并触发操作
  }

  /// 遍历元素并执行操作
  bool _visitAllElements(BuildContext context, bool Function(Element) visitor) {
    bool stop = false; // 控制是否停止递归
    context.visitChildElements((element) { // 遍历子元素
      if (stop) return; // 若已停止则退出
      stop = visitor(element); // 执行访问并检查是否停止
      if (!stop) stop = _visitAllElements(element, visitor); // 递归遍历
    });
    return stop; // 返回是否停止
  }

  /// 触发特定控件操作
  bool _triggerWidgetAction(Widget widget) {
    final highPriorityWidgets = [ElevatedButton, TextButton, OutlinedButton, IconButton, FloatingActionButton, GestureDetector, ListTile]; // 高优先级组件
    final lowPriorityWidgets = [Container, Padding, SizedBox, Align, Center]; // 低优先级组件
    if (lowPriorityWidgets.contains(widget.runtimeType)) return false; // 跳过低优先级组件
    for (var type in highPriorityWidgets) { // 检查高优先级组件
      if (widget.runtimeType == type) return _triggerSpecificWidgetAction(widget); // 触发操作
    }
    return _triggerSpecificWidgetAction(widget); // 检查其他组件
  }
  
  /// 触发特定组件的操作
  bool _triggerSpecificWidgetAction(Widget widget) {
    if (widget is SwitchListTile && widget.onChanged != null) { // 开关列表项
      Function.apply(widget.onChanged!, [!widget.value]); // 切换状态
      return true;
    } else if (widget is ElevatedButton && widget.onPressed != null) { // 提升按钮
      Function.apply(widget.onPressed!, []); // 点击操作
      return true;
    } else if (widget is TextButton && widget.onPressed != null) { // 文本按钮
      Function.apply(widget.onPressed!, []); // 点击操作
      return true;
    } else if (widget is OutlinedButton && widget.onPressed != null) { // 轮廓按钮
      Function.apply(widget.onPressed!, []); // 点击操作
      return true;
    } else if (widget is IconButton && widget.onPressed != null) { // 图标按钮
      Function.apply(widget.onPressed!, []); // 点击操作
      return true;
    } else if (widget is FloatingActionButton && widget.onPressed != null) { // 浮动按钮
      Function.apply(widget.onPressed!, []); // 点击操作
      return true;
    } else if (widget is ListTile && widget.onTap != null) { // 列表项
      Function.apply(widget.onTap!, []); // 点击操作
      return true;
    } else if (widget is GestureDetector && widget.onTap != null) { // 手势检测器
      Function.apply(widget.onTap!, []); // 点击操作
      return true;
    } else if (widget is PopupMenuButton && widget.onSelected != null) { // 弹出菜单按钮
      Function.apply(widget.onSelected!, [null]); // 选择操作
      return true;
    } else if (widget is ChoiceChip && widget.onSelected != null) { // 选择芯片
      Function.apply(widget.onSelected!, [true]); // 选择操作
      return true;
    } else {
      LogUtil.i('找到控件，但无法触发操作');
      return false; // 未触发操作
    }
  }
  
  /// 处理组间跳转逻辑
  bool _jumpToOtherGroup(LogicalKeyboardKey key, int currentIndex, int? groupIndex) {
    if (_groupFocusCache.isEmpty) { // 检查缓存是否为空
      LogUtil.i('没有缓存的分组信息，无法跳转');
      return false;
    }
    try {
      List<int> groupIndices = _groupFocusCache.keys.toList()..sort(); // 获取并排序分组索引
      int currentGroupIndex = groupIndex ?? groupIndices.first; // 获取当前分组索引
      if (!groupIndices.contains(currentGroupIndex)) { // 检查当前分组是否有效
        LogUtil.i('当前 Group $currentGroupIndex 无法找到');
        return false;
      }
      int totalGroups = groupIndices.length; // 获取分组总数
      int nextGroupIndex; // 下个分组索引
      if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) { // 上或左键跳转
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) - 1 + totalGroups) % totalGroups]; // 计算上个分组
      } else { // 下或右键跳转
        nextGroupIndex = groupIndices[(groupIndices.indexOf(currentGroupIndex) + 1) % totalGroups]; // 计算下个分组
      }
      LogUtil.i('从 Group $currentGroupIndex 跳转到 Group $nextGroupIndex');
      final nextGroupFocus = _groupFocusCache[nextGroupIndex]; // 获取下个分组焦点信息
      if (nextGroupFocus != null && nextGroupFocus.containsKey('firstFocusNode')) { // 检查焦点信息是否有效
        FocusNode? nextFocusNode = nextGroupFocus['firstFocusNode']; // 获取下个焦点节点
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nextFocusNode != null && nextFocusNode.context != null && nextFocusNode.canRequestFocus) { // 检查节点是否可聚焦
            nextFocusNode.requestFocus(); // 设置焦点
            _currentFocus = nextFocusNode; // 更新当前焦点
            LogUtil.i('跳转到 Group $nextGroupIndex 的焦点节点: ${nextFocusNode.debugLabel ?? '未知'}');
          } else {
            LogUtil.i('目标焦点节点未挂载或不可请求');
          }
        });
        return true;
      } else {
        LogUtil.i('未找到 Group $nextGroupIndex 的焦点节点信息');
      }
    } catch (e, stackTrace) {
      LogUtil.i('跳转组时发生未知错误: $e\n堆栈信息: $stackTrace');
    }
    return false; // 跳转失败
  }
}

/// 分组组件类
class Group extends StatelessWidget {
  final int groupIndex; // 分组索引
  final Widget? child; // 单个子组件
  final List<Widget>? children; // 多个子组件

  const Group({
    Key? key,
    required this.groupIndex,
    this.child,
    this.children,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return child != null ? child! : (children != null ? Column(children: children!) : SizedBox.shrink()); // 返回子组件或列布局
  }
}

/// 可聚焦项组件类
class FocusableItem extends StatefulWidget { 
  final FocusNode focusNode; // 焦点节点
  final Widget child; // 子组件

  const FocusableItem({
    Key? key,
    required this.focusNode,
    required this.child,
  }) : super(key: key);

  @override
  _FocusableItemState createState() => _FocusableItemState(); // 创建状态对象
}

/// 可聚焦项的状态类
class _FocusableItemState extends State<FocusableItem> {
  @override
  Widget build(BuildContext context) {
    return Focus(focusNode: widget.focusNode, child: widget.child); // 渲染焦点包裹的子组件
  }
}
