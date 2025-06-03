import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/theme_provider.dart';
import 'package:itvapp_live_tv/provider/language_provider.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/http_util.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

// 用户协议页面
class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key});

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  // 页面标题样式 - 与 setting_log_page 保持一致
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  
  // 协议内容样式
  static const _contentTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  static const _contentTextStyle = TextStyle(fontSize: 16, height: 1.5);
  
  // 容器最大宽度 - 与 setting_log_page 保持一致
  static const double _maxContainerWidth = 580;
  
  // 按钮样式 - 与 setting_log_page 保持一致
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final Color selectedColor = const Color(0xFFEB144C);
  final Color unselectedColor = const Color(0xFFDFA02A);
  
  // 加载状态
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _agreementData;
  
  // 滚动控制器
  final ScrollController _scrollController = ScrollController();
  
  // TV导航焦点节点
  late final FocusNode _dummyFocusNode; // 虚拟焦点节点，用于满足TvKeyNavigation的需求
  late final FocusNode _retryButtonFocusNode;
  
  @override
  void initState() {
    super.initState();
    _dummyFocusNode = FocusNode(debugLabel: 'dummy_focus_for_scroll');
    _retryButtonFocusNode = FocusNode();
    _loadAgreement();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _dummyFocusNode.dispose();
    _retryButtonFocusNode.dispose();
    super.dispose();
  }
  
  // 获取当前语言代码
  String _getCurrentLanguageCode() {
    final locale = context.read<LanguageProvider>().currentLocale;
    final languageCode = locale.languageCode;
    final countryCode = locale.countryCode;
    
    // 构建语言代码，如 zh-CN, zh-TW, en
    if (languageCode == 'zh' && countryCode != null) {
      return '$languageCode-$countryCode';
    }
    return languageCode;
  }
  
  // 加载协议内容
  Future<void> _loadAgreement() async {
    try {
      // 尝试主地址
      var response = await _fetchAgreement(Config.agreementUrl);
      
      // 如果主地址失败，尝试备用地址
      if (response == null) {
        response = await _fetchAgreement(Config.backupagreementUrl);
      }
      
      if (response != null) {
        setState(() {
          _agreementData = response;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = S.of(context).loadFailed;
          _isLoading = false;
        });
      }
    } catch (e) {
      LogUtil.e('加载协议失败: $e');
      setState(() {
        _errorMessage = S.of(context).loadFailed;
        _isLoading = false;
      });
    }
  }
  
  // 从URL获取协议数据
  Future<Map<String, dynamic>?> _fetchAgreement(String url) async {
    try {
      // 添加时间戳参数避免CDN缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithTimestamp = '$url${url.contains('?') ? '&' : '?'}t=$timestamp';
      
      // 获取原始响应以便处理JSON解析错误
      final response = await HttpUtil().getRequestWithResponse(urlWithTimestamp);
      
      if (response == null || response.data == null) {
        return null;
      }
      
      // 处理响应数据
      try {
        // 如果已经是Map类型，直接返回
        if (response.data is Map) {
          return Map<String, dynamic>.from(response.data);
        }
        
        // 如果是字符串，尝试解析
        if (response.data is String) {
          return jsonDecode(response.data as String) as Map<String, dynamic>;
        }
        
        return null;
      } catch (e) {
        LogUtil.e('JSON解析失败，原始数据类型: ${response.data.runtimeType}');
        LogUtil.e('JSON解析错误: $e');
        return null;
      }
    } catch (e) {
      LogUtil.e('从 $url 获取协议失败: $e');
      return null;
    }
  }
  
  // 处理滚动（通过TvKeyNavigation的onKeyPressed回调）
  void _handleScrollKey(LogicalKeyboardKey key) {
    if (!_scrollController.hasClients) return;
    
    const scrollAmount = 100.0;
    final viewportHeight = MediaQuery.of(context).size.height * 0.8;
    
    switch (key) {
      case LogicalKeyboardKey.arrowUp:
        _scrollController.animateTo(
          (_scrollController.offset - scrollAmount).clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
        break;
      case LogicalKeyboardKey.arrowDown:
        _scrollController.animateTo(
          (_scrollController.offset + scrollAmount).clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
        break;
      case LogicalKeyboardKey.pageUp:
        _scrollController.animateTo(
          (_scrollController.offset - viewportHeight).clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        break;
      case LogicalKeyboardKey.pageDown:
        _scrollController.animateTo(
          (_scrollController.offset + viewportHeight).clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        break;
    }
  }
  
  // 颜色加深函数 - 与 setting_log_page 保持一致
  Color darkenColor(Color color, [double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
  
  @override
  Widget build(BuildContext context) {
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    double maxContainerWidth = _maxContainerWidth;
    
    final themeProvider = context.watch<ThemeProvider>();
    final isTV = themeProvider.isTV;
    
    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null,
        title: Text(
          S.of(context).userAgreement,
          style: _titleStyle,
        ),
        backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: _errorMessage != null ? [_retryButtonFocusNode] : [_dummyFocusNode],
          onKeyPressed: _errorMessage == null ? _handleScrollKey : null,
          isFrame: isTV,
          frameType: isTV ? "child" : null,
          child: Align(
            alignment: Alignment.center,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: screenWidth > _maxContainerWidth ? maxContainerWidth : double.infinity,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildContent() {
    final themeProvider = context.watch<ThemeProvider>();
    final isTV = themeProvider.isTV;
    
    if (_isLoading) {
      // 使用与 setting_log_page 一样的加载动画
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(unselectedColor),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).loading ?? '加载中...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 50,
              color: Colors.grey,
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FocusableItem(
              focusNode: _retryButtonFocusNode,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _loadAgreement();
                },
                style: ElevatedButton.styleFrom(
                  shape: _buttonShape,
                  backgroundColor: _retryButtonFocusNode.hasFocus 
                    ? darkenColor(unselectedColor) 
                    : unselectedColor,
                  side: BorderSide.none,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(
                  S.of(context).retry ?? '重试',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return _buildAgreementContent();
  }
  
  // 构建协议内容
  Widget _buildAgreementContent() {
    if (_agreementData == null) return const SizedBox.shrink();
    
    final languageCode = _getCurrentLanguageCode();
    final languages = _agreementData!['languages'] as Map<String, dynamic>?;
    
    // 获取对应语言的协议内容，如果没有则使用英文
    Map<String, dynamic>? languageData;
    if (languages != null) {
      languageData = languages[languageCode] ?? languages['en'];
    }
    
    if (languageData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 50, color: Colors.grey),
            SizedBox(height: 10),
            Text(
              'No agreement content available',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    // 获取更新日期和生效日期（从根级别获取）
    final updateDate = _agreementData!['update_date'] as String?;
    final effectiveDate = _agreementData!['effective_date'] as String?;
    
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // 协议标题
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              languageData['title'] ?? '',
              style: _contentTitleStyle,
              textAlign: TextAlign.center,
            ),
          ),
          
          // 更新日期和生效日期
          if (updateDate != null || effectiveDate != null) ...[
            if (updateDate != null)
              _buildInfoRow(S.of(context).updateDate ?? '更新日期', updateDate),
            if (effectiveDate != null)
              _buildInfoRow(S.of(context).effectiveDate ?? '生效日期', effectiveDate),
            const SizedBox(height: 24),
          ],
          
          // 协议内容（简化处理：直接显示content字段）
          if (languageData['content'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                languageData['content'],
                style: _contentTextStyle,
              ),
            ),
        ],
      ),
    );
  }
  
  // 构建信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: _contentTextStyle.copyWith(fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: _contentTextStyle,
          ),
        ],
      ),
    );
  }
}
