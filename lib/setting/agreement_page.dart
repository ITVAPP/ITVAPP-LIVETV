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
  
  // TV导航焦点节点 - 只有一个节点
  late final FocusNode _contentFocusNode; // 内容焦点节点（用于滚动）
  late final FocusNode _retryButtonFocusNode; // 重试按钮焦点节点
  
  @override
  void initState() {
    super.initState();
    // 创建焦点节点
    _contentFocusNode = FocusNode(debugLabel: 'agreement_content_focus');
    _retryButtonFocusNode = FocusNode(debugLabel: 'retry_button_focus');
    
    // 加载协议
    _loadAgreement();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _contentFocusNode.dispose();
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
        // 添加调试日志
        LogUtil.d('响应数据类型: ${response.data.runtimeType}');
        
        // 如果已经是Map类型，直接使用（修复：不使用Map.from避免类型丢失）
        if (response.data is Map<String, dynamic>) {
          LogUtil.d('响应数据已经是Map<String, dynamic>类型');
          return response.data as Map<String, dynamic>;
        }
        
        // 如果是通用Map类型，进行类型转换
        if (response.data is Map) {
          LogUtil.d('响应数据是Map类型，进行类型转换');
          // 使用递归方式确保所有嵌套Map都是正确类型
          return _convertToTypedMap(response.data as Map);
        }
        
        // 如果是字符串，尝试解析
        if (response.data is String) {
          LogUtil.d('响应数据是String类型，尝试JSON解析');
          final parsed = jsonDecode(response.data as String);
          if (parsed is Map) {
            return _convertToTypedMap(parsed);
          }
        }
        
        LogUtil.e('响应数据格式不支持: ${response.data.runtimeType}');
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
  
  // 递归转换Map类型，确保所有嵌套Map都是Map<String, dynamic>
  Map<String, dynamic> _convertToTypedMap(Map map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is Map) {
        result[key.toString()] = _convertToTypedMap(value);
      } else if (value is List) {
        result[key.toString()] = value.map((item) {
          if (item is Map) {
            return _convertToTypedMap(item);
          }
          return item;
        }).toList();
      } else {
        result[key.toString()] = value;
      }
    });
    return result;
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
    
    // 根据当前状态决定使用哪个焦点节点
    final currentFocusNode = _errorMessage != null ? _retryButtonFocusNode : _contentFocusNode;
    
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
      body: TvKeyNavigation(
        focusNodes: [currentFocusNode], // 只有一个焦点节点
        scrollController: _errorMessage == null && !_isLoading ? _scrollController : null, // 只在显示内容时传递滚动控制器
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
              valueColor: AlwaysStoppedAnimation<Color>(selectedColor),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).loading,
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
                  S.of(context).retry,
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // 用 Group 和 FocusableItem 包装内容，让 TvKeyNavigation 处理滚动
    return Group(
      groupIndex: 0,
      children: [
        FocusableItem(
          focusNode: _contentFocusNode,
          child: Container(
            color: Colors.transparent, // 添加透明背景确保可聚焦
            child: _buildAgreementContent(),
          ),
        ),
      ],
    );
  }
  
  // 构建协议内容
  Widget _buildAgreementContent() {
    if (_agreementData == null) return const SizedBox.shrink();
    
    final languageCode = _getCurrentLanguageCode();
    
    // 添加调试日志
    LogUtil.d('当前语言代码: $languageCode');
    LogUtil.d('协议数据keys: ${_agreementData!.keys.toList()}');
    
    // 安全获取languages字段
    final languagesField = _agreementData!['languages'];
    if (languagesField == null) {
      LogUtil.e('协议数据中没有languages字段');
      return _buildNoContentWidget();
    }
    
    // 确保languages是Map类型
    if (languagesField is! Map) {
      LogUtil.e('languages字段不是Map类型: ${languagesField.runtimeType}');
      return _buildNoContentWidget();
    }
    
    // 获取对应语言的协议内容
    Map<String, dynamic>? languageData;
    try {
      // 尝试获取当前语言的内容
      final currentLangData = languagesField[languageCode];
      if (currentLangData != null && currentLangData is Map) {
        languageData = Map<String, dynamic>.from(currentLangData);
        LogUtil.d('找到语言数据: $languageCode');
      } else {
        // 尝试获取英文内容作为后备
        final enData = languagesField['en'];
        if (enData != null && enData is Map) {
          languageData = Map<String, dynamic>.from(enData);
          LogUtil.d('使用英文后备数据');
        }
      }
    } catch (e) {
      LogUtil.e('获取语言数据失败: $e');
    }
    
    if (languageData == null) {
      LogUtil.e('没有找到可用的语言数据');
      return _buildNoContentWidget();
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
              _buildInfoRow(S.of(context).updateDate, updateDate),
            if (effectiveDate != null)
              _buildInfoRow(S.of(context).effectiveDate, effectiveDate),
            const SizedBox(height: 24),
          ],
          
          // 协议内容（解析并优化显示）
          if (languageData['content'] != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildParsedContent(languageData['content']),
            ),
        ],
      ),
    );
  }
  
  // 构建无内容提示Widget
  Widget _buildNoContentWidget() {
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
  
  // 解析并构建内容，优化换行显示和章节标题
  Widget _buildParsedContent(String content) {
    // 分割内容为段落
    final paragraphs = content.split('\n');
    final List<Widget> widgets = [];
    
    // 正则表达式匹配章节标题（如 "1. 导言", "1.1 xxx", "(1) xxx" 等）
    final titlePattern = RegExp(r'^(\d+\.[\d.]*\s+|（\d+）|[(]\d+[)])\s*(.+)$');
    
    for (int i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      
      if (paragraph.isEmpty) {
        // 空行用较小的间距
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      
      // 检查是否是章节标题
      final match = titlePattern.firstMatch(paragraph);
      if (match != null) {
        // 章节标题使用加粗样式
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              paragraph,
              style: _contentTextStyle.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ),
        );
      } else {
        // 普通段落
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              paragraph,
              style: _contentTextStyle,
            ),
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
