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
import 'package:itvapp_live_tv/widget/common_widgets.dart';
import 'package:itvapp_live_tv/generated/l10n.dart';
import 'package:itvapp_live_tv/config.dart';

/// 用户协议页面，展示协议内容
class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key});

  /// 创建用户协议页面状态
  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

/// 用户协议页面状态，管理协议加载和TV导航
class _AgreementPageState extends State<AgreementPage> {
  /// 页面标题样式，保持一致性
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  
  /// 协议内容样式常量，统一调整
  static const double _contentTextFontSize = 14;   // 正文字体大小
  static const double _chapterTitleFontSize = 16;  // 章节标题字体大小
  static const double _contentLineHeight = 1.5;    // 正文行高
  static const double _paragraphSpacing = 5.0;     // 段落间距
  static const double _chapterSpacing = 5.0;       // 章节标题上方间距
  static const double _emptyLineSpacing = 2.0;     // 空行间距
  
  /// 协议内容文本样式
  static const _contentTextStyle = TextStyle(fontSize: _contentTextFontSize, height: _contentLineHeight);
  
  /// 容器最大宽度，保持一致性
  static const double _maxContainerWidth = 580;
  
  /// 加载动画颜色
  final Color selectedColor = const Color(0xFFEB144C);
  
  /// 缓存正则表达式，避免重复编译
  static final _titlePattern = RegExp(r'^(\d+)\.\s+(.+)');
  
  /// 协议加载状态
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _agreementData;
  
  /// 滚动控制器，用于手机端滚动
  final ScrollController _scrollController = ScrollController();
  
  /// TV导航焦点节点
  late final FocusNode _tvNavigationFocusNode; // TV导航焦点节点
  
  /// 初始化状态，设置焦点和加载协议
  @override
  void initState() {
    super.initState();
    
    // 创建TV导航焦点节点
    _tvNavigationFocusNode = FocusNode(debugLabel: 'tv_navigation_focus');
    
    // 加载协议内容
    _loadAgreement();
  }
  
  /// 清理资源，释放控制器和焦点
  @override
  void dispose() {
    _scrollController.dispose();
    _tvNavigationFocusNode.dispose();
    super.dispose();
  }
  
  /// 获取当前语言代码（如zh-CN、en）
  String _getCurrentLanguageCode() {
    final locale = context.read<LanguageProvider>().currentLocale;
    final languageCode = locale.languageCode;
    final countryCode = locale.countryCode;
    
    // 构建语言代码
    String result;
    if (languageCode == 'zh' && countryCode != null) {
      result = '$languageCode-$countryCode';
    } else {
      result = languageCode;
    }
    LogUtil.d('当前语言代码: $result');
    return result;
  }
  
  /// 加载协议内容，尝试主地址和备用地址
  Future<void> _loadAgreement() async {
    try {
      // 尝试主地址
      var response = await _fetchAgreement(Config.agreementUrl);
      
      // 如果主地址失败，尝试备用地址
      if (response == null) {
        LogUtil.w('主地址加载失败，尝试备用地址: ${Config.backupagreementUrl}');
        response = await _fetchAgreement(Config.backupagreementUrl);
      }
      
      if (response != null) {
        setState(() {
          _agreementData = response;
          _isLoading = false;
        });
      } else {
        LogUtil.e('用户协议加载失败');
        setState(() {
          _errorMessage = S.of(context).loadFailed;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      LogUtil.e('加载协议失败: $e');
      setState(() {
        _errorMessage = S.of(context).loadFailed;
        _isLoading = false;
      });
    }
  }
  
  /// 从URL获取协议数据并解析
  Future<Map<String, dynamic>?> _fetchAgreement(String url) async {
    try {
      // 添加时间戳避免CDN缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithTimestamp = '$url${url.contains('?') ? '&' : '?'}t=$timestamp';
      LogUtil.d('请求用户协议URL: $urlWithTimestamp');
      
      // 获取原始响应
      final response = await HttpUtil().getRequestWithResponse(urlWithTimestamp);
      
      if (response == null) {
        LogUtil.e('响应为null');
        return null;
      }
      
      if (response.data == null) {
        LogUtil.e('响应数据为null');
        return null;
      }
      
      // 处理响应数据
      try {
        // 如果已经是Map类型，直接使用
        if (response.data is Map<String, dynamic>) {
          final data = response.data as Map<String, dynamic>;
          return data;
        }
        
        // 如果是通用Map类型，进行类型转换
        if (response.data is Map) {
          final convertedData = _convertToTypedMap(response.data as Map);
          return convertedData;
        }
        
        // 如果是字符串，尝试解析
        if (response.data is String) {
          final parsed = jsonDecode(response.data as String);
          
          if (parsed is Map) {
            final convertedData = _convertToTypedMap(parsed);
            return convertedData;
          } else {
            LogUtil.e('JSON解析结果不是Map类型: ${parsed.runtimeType}');
            return null;
          }
        }
        return null;
      } catch (e, stackTrace) {
        LogUtil.e('JSON解析失败，原始数据类型: ${response.data.runtimeType}');
        return null;
      }
    } catch (e, stackTrace) {
      return null;
    }
  }
  
  /// 递归转换Map为Map<String, dynamic>
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
  
  /// 构建页面UI，包含加载、错误和协议内容
  @override
  Widget build(BuildContext context) {
    
    final MediaQueryData mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    double maxContainerWidth = _maxContainerWidth;
    
    final themeProvider = context.watch<ThemeProvider>();
    final isTV = themeProvider.isTV;
    
    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: CommonSettingAppBar(
        title: S.of(context).userAgreement,
        isTV: isTV,
        titleStyle: _titleStyle,
      ),
      body: FocusScope(
        child: TvKeyNavigation(
          focusNodes: [_tvNavigationFocusNode], // 始终提供焦点节点
          scrollController: _scrollController, // 始终提供滚动控制器
          isFrame: isTV ? true : false,
          frameType: isTV ? "child" : null,
          child: FocusableItem(
            focusNode: _tvNavigationFocusNode, // 将焦点绑定到整个内容容器
            child: Align(
              alignment: Alignment.center,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: screenWidth > _maxContainerWidth ? maxContainerWidth : double.infinity,
                ),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ), 
    );
  }
  
  /// 构建页面内容，处理加载、错误和协议显示
  Widget _buildContent() {
    if (_isLoading) {
      // 加载动画
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
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      // 错误状态显示（无重试按钮）
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 50,
              color: Colors.grey,
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    // 显示协议内容
    return _buildAgreementContent();
  }
  
  /// 构建协议内容，包含日期和正文
  Widget _buildAgreementContent() {
    
    if (_agreementData == null) {
      LogUtil.e('_agreementData 为 null，返回空Widget');
      return const SizedBox.shrink();
    }
    
    final languageCode = _getCurrentLanguageCode();
    
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
    
    LogUtil.d('languages包含的语言: ${languagesField.keys.toList()}');
    
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
    } catch (e, stackTrace) {
      LogUtil.e('获取语言数据失败: $e');
    }
    
    if (languageData == null) {
      LogUtil.e('没有找到可用的语言数据');
      return _buildNoContentWidget();
    }
    
    // 获取更新日期和生效日期
    final updateDate = _agreementData!['update_date'] as String?;
    final effectiveDate = _agreementData!['effective_date'] as String?;
    
    // 构建可滚动内容 - 使用 AnimatedBuilder 监听焦点变化
    return AnimatedBuilder(
      animation: _tvNavigationFocusNode,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            scrollbarTheme: ScrollbarThemeData(
              thumbColor: MaterialStateProperty.all(
                _tvNavigationFocusNode.hasFocus 
                  ? selectedColor  // 聚焦时显示红色
                  : Colors.grey.withOpacity(0.5), // 非聚焦时使用灰色
              ),
            ),
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: child!,
          ),
        );
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // 更新日期和生效日期
            if (updateDate != null || effectiveDate != null) ...[
              if (updateDate != null)
                _buildInfoRow(S.of(context).updateDate, updateDate),
              if (effectiveDate != null)
                _buildInfoRow(S.of(context).effectiveDate, effectiveDate),
              const SizedBox(height: 12), // 日期信息下方间距
            ],
            
            // 协议正文
            if (languageData['content'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildParsedContent(languageData['content']),
              ),
          ],
        ),
      ),
    );
  }
  
  /// 构建无内容提示
  Widget _buildNoContentWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.info_outline, size: 50, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            'No agreement content available',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }
  
  /// 构建信息行，显示日期等信息
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
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
  
  /// 解析协议内容
  Widget _buildParsedContent(String content) {
    // 分割内容为段落
    final paragraphs = content.split('\n');
    final List<Widget> widgets = [];
    
    for (int i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      
      if (paragraph.isEmpty) {
        // 空行间距
        widgets.add(const SizedBox(height: _emptyLineSpacing));
        continue;
      }
      
      // 检查章节标题
      final match = _titlePattern.firstMatch(paragraph);
      if (match != null) {
        // 章节标题
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: _chapterSpacing, bottom: _paragraphSpacing),
            child: Text(
              paragraph,
              style: _contentTextStyle.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: _chapterTitleFontSize,
              ),
            ),
          ),
        );
      } else {
        // 普通段落
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: _paragraphSpacing),
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
