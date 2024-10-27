import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

// Constants
class UIConstants {
  static const double defaultMinHeight = 42.0;
  static const Color defaultBackgroundColor = Colors.black38;
  static const EdgeInsets defaultPadding = EdgeInsets.all(6.0);
  static const Color selectedColor = Color(0xFFEB144C);
  static const Color unselectedColor = Color(0xFFDFA02A);
  
  static const TextStyle defaultTextStyle = TextStyle(fontSize: 16);
  static const TextStyle selectedTextStyle = TextStyle(
    fontWeight: FontWeight.bold,
    color: Colors.white,
    shadows: [
      Shadow(
        offset: Offset(1.0, 1.0),
        blurRadius: 3.0,
        color: Colors.black54,
      ),
    ],
  );
  
  static final verticalDivider = VerticalDivider(
    width: 0.1,
    color: Colors.white.withOpacity(0.1),
  );
}

// Item Decoration Builder
BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    color: hasFocus
        ? UIConstants.unselectedColor
        : (isSelected ? UIConstants.selectedColor : Colors.transparent),
  );
}

// Focus Management Mixin
mixin FocusManagerMixin<T extends StatefulWidget> on State<T> {
  Map<int, bool> _localFocusStates = {};
  
  void initializeFocus(int startIndex, int length, Function() onFocusChange) {
    // Initialize focus states for this range
    for (var i = startIndex; i < startIndex + length; i++) {
      _localFocusStates[i] = false;
    }
    
    // Add focus listeners
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      if (index < FocusNodeProvider.nodes.length) {
        FocusNodeProvider.nodes[index].removeListener(() {});
        FocusNodeProvider.nodes[index].addListener(() {
          final currentFocus = FocusNodeProvider.nodes[index].hasFocus;
          if (_localFocusStates[index] != currentFocus) {
            _localFocusStates[index] = currentFocus;
            onFocusChange();
          }
        });
      }
    }
  }
  
  void disposeFocus(int startIndex, int length) {
    for (var i = startIndex; i < startIndex + length; i++) {
      if (i < FocusNodeProvider.nodes.length) {
        FocusNodeProvider.nodes[i].removeListener(() {});
      }
      _localFocusStates.remove(i);
    }
  }
  
  @override
  void dispose() {
    _localFocusStates.clear();
    super.dispose();
  }
}

// Scroll Manager
class ScrollManager {
  static void scrollToTop(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }
  
  static void scrollToPosition(
    ScrollController controller,
    int index,
    double itemHeight,
    double viewportHeight,
  ) {
    if (!controller.hasClients) return;
    final maxScrollExtent = controller.position.maxScrollExtent;
    final shouldOffset = index * itemHeight - viewportHeight + itemHeight * 0.5;
    controller.jumpTo(shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent);
  }
}

// Reusable List Container
class ListContainer extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  final Color? backgroundColor;
  
  const ListContainer({
    required this.child,
    this.controller,
    this.backgroundColor = UIConstants.defaultBackgroundColor,
    Key? key,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: SingleChildScrollView(
        controller: controller,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height
          ),
          child: IntrinsicHeight(
            child: child,
          ),
        ),
      ),
    );
  }
}

// Focus Node Provider
class FocusNodeProvider {
  static List<FocusNode> _focusNodes = [];
  static Map<int, bool> _focusStates = {};
  
  static void initialize(int totalCount) {
    if (_focusNodes.length != totalCount) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = List.generate(totalCount, (index) => FocusNode());
      _focusStates.clear();
      LogUtil.v('初始化焦点节点数量: $totalCount');
    }
  }
  
  static List<FocusNode> get nodes => _focusNodes;
  static Map<int, bool> get states => _focusStates;
  
  static void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
  }
}

// State Manager for Channel Drawer
class ChannelDrawerState {
  List<String> categories = [];
  List<String> keys = [];
  List<Map<String, PlayModel>> values = [];
  int categoryIndex = -1;
  int groupIndex = -1;
  int channelIndex = -1;
  int categoryStartIndex = 0;
  int groupStartIndex = 0;
  int channelStartIndex = 0;
  
  void reset() {
    keys = [];
    values = [];
    groupIndex = -1;
    channelIndex = -1;
  }
  
  int get totalFocusNodes {
    return categories.length +
           (keys.isNotEmpty ? keys.length : 0) +
           (values.isNotEmpty && groupIndex >= 0 && groupIndex < values.length 
            ? values[groupIndex].length : 0);
  }

  void updateStartIndexes({bool includeGroupsAndChannels = true}) {
    categoryStartIndex = 0;
    groupStartIndex = categoryStartIndex + categories.length;
    channelStartIndex = includeGroupsAndChannels
        ? groupStartIndex + (keys.isNotEmpty ? keys.length : 0)
        : groupStartIndex;
  }
}

// Widget Builder Utilities
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true,
  double minHeight = UIConstants.defaultMinHeight,
  EdgeInsets padding = UIConstants.defaultPadding,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
}) {
  FocusNode? focusNode = (index != null && index >= 0 && index < FocusNodeProvider.nodes.length)
      ? FocusNodeProvider.nodes[index]
      : null;

  Widget listItemContent = GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: buildItemDecoration(
        isSelected: isSelected,
        hasFocus: focusNode?.hasFocus ?? false
      ),
      child: Align(
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          title,
          style: (focusNode?.hasFocus ?? false)
              ? UIConstants.defaultTextStyle.merge(UIConstants.selectedTextStyle)
              : (isSelected ? UIConstants.defaultTextStyle.merge(UIConstants.selectedTextStyle) 
                           : UIConstants.defaultTextStyle),
          softWrap: true,
          maxLines: null,
          overflow: TextOverflow.visible,
        ),
      ),
    ),
  );

  return useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/util/epg_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'entity/playlist_model.dart';
import 'generated/l10n.dart';
import 'config.dart';

// Constants
class UIConstants {
  static const double defaultMinHeight = 42.0;
  static const Color defaultBackgroundColor = Colors.black38;
  static const EdgeInsets defaultPadding = EdgeInsets.all(6.0);
  static const Color selectedColor = Color(0xFFEB144C);
  static const Color unselectedColor = Color(0xFFDFA02A);
  
  static const TextStyle defaultTextStyle = TextStyle(fontSize: 16);
  static const TextStyle selectedTextStyle = TextStyle(
    fontWeight: FontWeight.bold,
    color: Colors.white,
    shadows: [
      Shadow(
        offset: Offset(1.0, 1.0),
        blurRadius: 3.0,
        color: Colors.black54,
      ),
    ],
  );
  
  static final verticalDivider = VerticalDivider(
    width: 0.1,
    color: Colors.white.withOpacity(0.1),
  );
}

// Item Decoration Builder
BoxDecoration buildItemDecoration({bool isSelected = false, bool hasFocus = false}) {
  return BoxDecoration(
    color: hasFocus
        ? UIConstants.unselectedColor
        : (isSelected ? UIConstants.selectedColor : Colors.transparent),
  );
}

// Focus Management Mixin
mixin FocusManagerMixin<T extends StatefulWidget> on State<T> {
  Map<int, bool> _localFocusStates = {};
  
  void initializeFocus(int startIndex, int length, Function() onFocusChange) {
    // Initialize focus states for this range
    for (var i = startIndex; i < startIndex + length; i++) {
      _localFocusStates[i] = false;
    }
    
    // Add focus listeners
    for (var i = 0; i < length; i++) {
      final index = startIndex + i;
      if (index < FocusNodeProvider.nodes.length) {
        FocusNodeProvider.nodes[index].removeListener(() {});
        FocusNodeProvider.nodes[index].addListener(() {
          final currentFocus = FocusNodeProvider.nodes[index].hasFocus;
          if (_localFocusStates[index] != currentFocus) {
            _localFocusStates[index] = currentFocus;
            onFocusChange();
          }
        });
      }
    }
  }
  
  void disposeFocus(int startIndex, int length) {
    for (var i = startIndex; i < startIndex + length; i++) {
      if (i < FocusNodeProvider.nodes.length) {
        FocusNodeProvider.nodes[i].removeListener(() {});
      }
      _localFocusStates.remove(i);
    }
  }
  
  @override
  void dispose() {
    _localFocusStates.clear();
    super.dispose();
  }
}

// Scroll Manager
class ScrollManager {
  static void scrollToTop(ScrollController controller) {
    if (controller.hasClients) {
      controller.jumpTo(0);
    }
  }
  
  static void scrollToPosition(
    ScrollController controller,
    int index,
    double itemHeight,
    double viewportHeight,
  ) {
    if (!controller.hasClients) return;
    final maxScrollExtent = controller.position.maxScrollExtent;
    final shouldOffset = index * itemHeight - viewportHeight + itemHeight * 0.5;
    controller.jumpTo(shouldOffset < maxScrollExtent ? max(0.0, shouldOffset) : maxScrollExtent);
  }
}

// Reusable List Container
class ListContainer extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  final Color? backgroundColor;
  
  const ListContainer({
    required this.child,
    this.controller,
    this.backgroundColor = UIConstants.defaultBackgroundColor,
    Key? key,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: SingleChildScrollView(
        controller: controller,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height
          ),
          child: IntrinsicHeight(
            child: child,
          ),
        ),
      ),
    );
  }
}

// Focus Node Provider
class FocusNodeProvider {
  static List<FocusNode> _focusNodes = [];
  static Map<int, bool> _focusStates = {};
  
  static void initialize(int totalCount) {
    if (_focusNodes.length != totalCount) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = List.generate(totalCount, (index) => FocusNode());
      _focusStates.clear();
      LogUtil.v('初始化焦点节点数量: $totalCount');
    }
  }
  
  static List<FocusNode> get nodes => _focusNodes;
  static Map<int, bool> get states => _focusStates;
  
  static void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes.clear();
    _focusStates.clear();
  }
}

// State Manager for Channel Drawer
class ChannelDrawerState {
  List<String> categories = [];
  List<String> keys = [];
  List<Map<String, PlayModel>> values = [];
  int categoryIndex = -1;
  int groupIndex = -1;
  int channelIndex = -1;
  int categoryStartIndex = 0;
  int groupStartIndex = 0;
  int channelStartIndex = 0;
  
  void reset() {
    keys = [];
    values = [];
    groupIndex = -1;
    channelIndex = -1;
  }
  
  int get totalFocusNodes {
    return categories.length +
           (keys.isNotEmpty ? keys.length : 0) +
           (values.isNotEmpty && groupIndex >= 0 && groupIndex < values.length 
            ? values[groupIndex].length : 0);
  }

  void updateStartIndexes({bool includeGroupsAndChannels = true}) {
    categoryStartIndex = 0;
    groupStartIndex = categoryStartIndex + categories.length;
    channelStartIndex = includeGroupsAndChannels
        ? groupStartIndex + (keys.isNotEmpty ? keys.length : 0)
        : groupStartIndex;
  }
}

// Widget Builder Utilities
Widget buildListItem({
  required String title,
  required bool isSelected,
  required Function() onTap,
  required BuildContext context,
  bool isCentered = true,
  double minHeight = UIConstants.defaultMinHeight,
  EdgeInsets padding = UIConstants.defaultPadding,
  bool isTV = false,
  int? index,
  bool useFocusableItem = true,
}) {
  FocusNode? focusNode = (index != null && index >= 0 && index < FocusNodeProvider.nodes.length)
      ? FocusNodeProvider.nodes[index]
      : null;

  Widget listItemContent = GestureDetector(
    onTap: onTap,
    child: Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: padding,
      decoration: buildItemDecoration(
        isSelected: isSelected,
        hasFocus: focusNode?.hasFocus ?? false
      ),
      child: Align(
        alignment: isCentered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          title,
          style: (focusNode?.hasFocus ?? false)
              ? UIConstants.defaultTextStyle.merge(UIConstants.selectedTextStyle)
              : (isSelected ? UIConstants.defaultTextStyle.merge(UIConstants.selectedTextStyle) 
                           : UIConstants.defaultTextStyle),
          softWrap: true,
          maxLines: null,
          overflow: TextOverflow.visible,
        ),
      ),
    ),
  );

  return useFocusableItem && focusNode != null
      ? FocusableItem(focusNode: focusNode, child: listItemContent)
      : listItemContent;
}

// Main Channel Drawer Page
class ChannelDrawerPage extends StatefulWidget {
  final PlaylistModel? videoMap;
  final PlayModel? playModel;
  final bool isLandscape;
  final Function(PlayModel? newModel)? onTapChannel;
  final VoidCallback onCloseDrawer;

  const ChannelDrawerPage({
    super.key,
    this.videoMap,
    this.playModel,
    this.onTapChannel,
    this.isLandscape = true,
    required this.onCloseDrawer,
  });

  @override
  State<ChannelDrawerPage> createState() => _ChannelDrawerPageState();
}

class _ChannelDrawerPageState extends State<ChannelDrawerPage> 
    with WidgetsBindingObserver, FocusManagerMixin {
  final ChannelDrawerState _state = ChannelDrawerState();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _scrollChannelController = ScrollController();
  final ItemScrollController _epgItemScrollController = ItemScrollController();
  final GlobalKey _viewPortKey = GlobalKey();
  
  TvKeyNavigationState? _tvKeyNavigationState;
  List<EpgData>? _epgData;
  int _selEPGIndex = 0;
  double? _viewPortHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeState();
  }

  void _initializeState() {
    _initializeCategoryData();
    _initializeChannelData();
    FocusNodeProvider.initialize(_state.totalFocusNodes);
    _calculateViewportHeight();
    if (_state.keys.isNotEmpty && 
        _state.values.isNotEmpty && 
        _state.values[_state.groupIndex].isNotEmpty) {
      _loadEPGMsg(widget.playModel);
    }
  }

  void _calculateViewportHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderBox = _viewPortKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        setState(() {
          _viewPortHeight = renderBox.size.height * 0.5;
          _adjustScrollPositions();
        });
      }
    });
  }

  void _initializeCategoryData() {
    _state.categories = widget.videoMap?.playList?.keys.toList() ?? [];
    _state.categoryIndex = -1;
    _state.groupIndex = -1;
    _state.channelIndex = -1;

    // Find current channel's category and group
    for (int i = 0; i < _state.categories.length; i++) {
      final category = _state.categories[i];
      final categoryMap = widget.videoMap?.playList[category];

      if (categoryMap is Map<String, Map<String, PlayModel>>) {
        for (int groupIndex = 0; groupIndex < categoryMap.keys.length; groupIndex++) {
          final group = categoryMap.keys.toList()[groupIndex];
          final channelMap = categoryMap[group];

          if (channelMap != null && channelMap.containsKey(widget.playModel?.title)) {
            _state.categoryIndex = i;
            _state.groupIndex = groupIndex;
            _state.channelIndex = channelMap.keys.toList().indexOf(widget.playModel?.title ?? '');
            return;
          }
        }
      }
    }

    // If channel not found, select first non-empty category
    if (_state.categoryIndex == -1) {
      for (int i = 0; i < _state.categories.length; i++) {
        final categoryMap = widget.videoMap?.playList[_state.categories[i]];
        if (categoryMap != null && categoryMap.isNotEmpty) {
          _state.categoryIndex = i;
          _state.groupIndex = 0;
          _state.channelIndex = 0;
          break;
        }
      }
    }
  }

  void _initializeChannelData() {
    if (_state.categoryIndex < 0 || _state.categoryIndex >= _state.categories.length) {
      _state.reset();
      return;
    }

    final selectedCategory = _state.categories[_state.categoryIndex];
    final categoryMap = widget.videoMap?.playList[selectedCategory];

    _state.keys = categoryMap?.keys.toList() ?? [];
    _state.values = categoryMap?.values.toList() ?? [];

    // Sort channels by name
    for (int i = 0; i < _state.values.length; i++) {
      _state.values[i] = Map<String, PlayModel>.fromEntries(
        _state.values[i].entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
    }

    _state.groupIndex = _state.keys.indexOf(widget.playModel?.group ?? '');
    _state.channelIndex = _state.groupIndex != -1
        ? _state.values[_state.groupIndex].keys.toList().indexOf(widget.playModel?.title ?? '')
        : 0;

    if (_state.groupIndex == -1) _state.groupIndex = 0;
    if (_state.channelIndex == -1) _state.channelIndex = 0;

    _state.updateStartIndexes(
      includeGroupsAndChannels: _state.keys.isNotEmpty && _state.values.isNotEmpty
    );
  }

  void _onCategoryTap(int index) {
    if (_state.categoryIndex == index) return;

    setState(() {
      _state.categoryIndex = index;
      
      final selectedCategory = _state.categories[_state.categoryIndex];
      final categoryMap = widget.videoMap?.playList[selectedCategory];

      if (categoryMap == null || categoryMap.isEmpty) {
        _state.reset();
        FocusNodeProvider.initialize(_state.categories.length);
        _state.updateStartIndexes(includeGroupsAndChannels: false);
      } else {
        _initializeChannelData();
        FocusNodeProvider.initialize(_state.totalFocusNodes);
        _state.updateStartIndexes(includeGroupsAndChannels: true);
        ScrollManager.scrollToTop(_scrollController);
        ScrollManager.scrollToTop(_scrollChannelController);
      }
    });

    _reInitializeFocusSystem(index);
  }

  void _onGroupTap(int index) {
    setState(() {
      _state.groupIndex = index;
      _state.channelIndex = 0;

      FocusNodeProvider.initialize(_state.totalFocusNodes);
      _state.updateStartIndexes(includeGroupsAndChannels: true);
      ScrollManager.scrollToTop(_scrollChannelController);
    });

    _reInitializeFocusSystem(_state.categories.length + _state.groupIndex);
  }

  void _onChannelTap(PlayModel? newModel) {
    if (newModel?.title == widget.playModel?.title) return;
    
    widget.onTapChannel?.call(newModel);
    _loadEPGMsg(newModel);
  }

  void _reInitializeFocusSystem(int initialIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tvKeyNavigationState != null) {
        _tvKeyNavigationState?.releaseResources();
        _tvKeyNavigationState?.initializeFocusLogic(initialIndexOverride: initialIndex);
        _reInitializeFocusListeners();
      }
    });
  }

  void _reInitializeFocusListeners() {
    initializeFocus(0, _state.categories.length, () {
      setState(() {});
    });

    if (_state.keys.isNotEmpty) {
      initializeFocus(_state.categories.length, _state.keys.length, () {
        setState(() {});
      });

      if (_state.values.isNotEmpty && _state.groupIndex >= 0) {
        initializeFocus(
          _state.categories.length + _state.keys.length,
          _state.values[_state.groupIndex].length,
          () {
            setState(() {});
          },
        );
      }
    }
  }

  Future<void> _loadEPGMsg(PlayModel? playModel) async {
    if (playModel == null) return;

    setState(() {
      _epgData = null;
      _selEPGIndex = 0;
    });

    try {
      final res = await EpgUtil.getEpg(playModel);
      if (res?.epgData?.isEmpty ?? true) return;

      final epgRangeTime = DateUtil.formatDate(DateTime.now(), format: 'HH:mm');
      final selectTimeData = res!.epgData!.lastWhere(
        (element) => element.start!.compareTo(epgRangeTime) < 0,
        orElse: () => res.epgData!.first,
      ).start;
      final selectedIndex = res.epgData!.indexWhere((element) => element.start == selectTimeData);

      setState(() {
        _epgData = res.epgData;
        _selEPGIndex = selectedIndex;
      });

      if (_epgData!.isNotEmpty && _selEPGIndex < _epgData!.length) {
        _epgItemScrollController.scrollTo(
          index: _selEPGIndex,
          duration: Duration.zero,
        );
      }
    } catch (e, stackTrace) {
      LogUtil.logError('加载EPG数据时出错', e, stackTrace);
    }
  }

  void _adjustScrollPositions() {
    if (_viewPortHeight == null) return;
    
    ScrollManager.scrollToPosition(
      _scrollController,
      _state.groupIndex,
      UIConstants.defaultMinHeight,
      _viewPortHeight!
    );
    
    ScrollManager.scrollToPosition(
      _scrollChannelController,
      _state.channelIndex,
      UIConstants.defaultMinHeight,
      _viewPortHeight!
    );
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    
    final newHeight = MediaQuery.of(context).size.height * 0.5;
    if (newHeight != _viewPortHeight) {
      setState(() {
        _viewPortHeight = newHeight;
        _adjustScrollPositions();
        _state.updateStartIndexes(
          includeGroupsAndChannels: _state.keys.isNotEmpty && _state.values.isNotEmpty,
        );
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _scrollChannelController.dispose();
    FocusNodeProvider.dispose();
    super.dispose();
  }

  Widget _buildOpenDrawer(bool isTV) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    const categoryWidth = 110.0;
    final groupWidth = _state.keys.isNotEmpty ? 120.0 : 0.0;
    
    final channelListWidth = (_state.keys.isNotEmpty && _state.values.isNotEmpty)
        ? (isPortrait ? MediaQuery.of(context).size.width - categoryWidth - groupWidth : 160.0)
        : 0.0;

    final epgListWidth = (_state.keys.isNotEmpty && 
                         _state.values.isNotEmpty && 
                         _epgData != null)
        ? MediaQuery.of(context).size.width - categoryWidth - groupWidth - channelListWidth
        : 0.0;

    return Container(
      key: _viewPortKey,
      padding: EdgeInsets.only(left: MediaQuery.of(context).padding.left),
      width: widget.isLandscape
          ? categoryWidth + groupWidth + channelListWidth + epgListWidth
          : MediaQuery.of(context).size.width,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent]),
      ),
      child: Row(
        children: [
          SizedBox(
            width: categoryWidth,
            child: CategoryList(
              categories: _state.categories,
              selectedCategoryIndex: _state.categoryIndex,
              onCategoryTap: _onCategoryTap,
              isTV: isTV,
              startIndex: _state.categoryStartIndex,
            ),
          ),
          UIConstants.verticalDivider,
          if (_state.keys.isNotEmpty) ...[
            SizedBox(
              width: groupWidth,
              child: GroupList(
                keys: _state.keys,
                selectedGroupIndex: _state.groupIndex,
                onGroupTap: _onGroupTap,
                isTV: isTV,
                scrollController: _scrollController,
                isFavoriteCategory: _state.categories[_state.categoryIndex] == Config.myFavoriteKey,
                startIndex: _state.groupStartIndex,
              ),
            ),
            UIConstants.verticalDivider,
          ],
          if (_state.values.isNotEmpty && _state.groupIndex >= 0) ...[
            SizedBox(
              width: channelListWidth,
              child: ChannelList(
                channels: _state.values[_state.groupIndex],
                selectedChannelName: widget.playModel?.title,
                onChannelTap: _onChannelTap,
                isTV: isTV,
                scrollController: _scrollChannelController,
                startIndex: _state.channelStartIndex,
              ),
            ),
            if (_epgData != null) ...[
              UIConstants.verticalDivider,
              SizedBox(
                width: epgListWidth,
                child: EPGList(
                  epgData: _epgData,
                  selectedIndex: _selEPGIndex,
                  isTV: isTV,
                  epgScrollController: _epgItemScrollController,
                  onCloseDrawer: widget.onCloseDrawer,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTV = context.read<ThemeProvider>().isTV;

    return TvKeyNavigation(
      focusNodes: FocusNodeProvider.nodes,
      isVerticalGroup: true,
      initialIndex: 0,
      onStateCreated: (state) {
        _tvKeyNavigationState = state;
      },
      child: _buildOpenDrawer(isTV),
    );
  }
}
