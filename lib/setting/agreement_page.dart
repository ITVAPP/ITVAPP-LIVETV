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

// 用户协议页面
class AgreementPage extends StatefulWidget {
  const AgreementPage({super.key});

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  // 页面标题样式 - 与 setting_log_page 保持一致
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  
  // 协议内容样式常量 - 便于统一调整
  static const double _contentTextFontSize = 14;   // 正文字体大小
  static const double _chapterTitleFontSize = 16;  // 章节标题字体大小
  static const double _contentLineHeight = 1.5;    // 正文行高
  static const double _paragraphSpacing = 5.0;     // 段落间距
  static const double _chapterSpacing = 5.0;      // 章节标题上方间距
  static const double _emptyLineSpacing = 2.0;     // 空行间距
  
  // 协议内容样式
  static const _contentTextStyle = TextStyle(fontSize: _contentTextFontSize, height: _contentLineHeight);
  
  // 容器最大宽度 - 与 setting_log_page 保持一致
  static const double _maxContainerWidth = 580;
  
  // 按钮样式 - 与 setting_log_page 保持一致
  final _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final Color selectedColor = const Color(0xFFEB144C);
  final Color unselectedColor = const Color(0xFFDFA02A);
  
  // 缓存正则表达式，避免重复编译
  static final _titlePattern = RegExp(r'^(\d+)\.\s+(.+)');
  
  // 加载状态
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _agreementData;
  
  // 滚动控制器 - 用于手机端滚动
  final ScrollController _scrollController = ScrollController();
  
  // TV导航焦点节点 - 只需要一个用于TV导航
  late final FocusNode _tvNavigationFocusNode; // TV导航焦点节点
  
  @override
  void initState() {
    super.initState();
    
    // 创建TV导航焦点节点
    _tvNavigationFocusNode = FocusNode(debugLabel: 'tv_navigation_focus');
    
    // 加载协议
    _loadAgreement();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _tvNavigationFocusNode.dispose();
    super.dispose();
  }
  
  // 获取当前语言代码
  String _getCurrentLanguageCode() {
    final locale = context.read<LanguageProvider>().currentLocale;
    final languageCode = locale.languageCode;
    final countryCode = locale.countryCode;
    
    // 构建语言代码，如 zh-CN, zh-TW, en
    String result;
    if (languageCode == 'zh' && countryCode != null) {
      result = '$languageCode-$countryCode';
    } else {
      result = languageCode;
    }
    return result;
  }
  
  // 加载协议内容
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
  
  // 从URL获取协议数据
  Future<Map<String, dynamic>?> _fetchAgreement(String url) async {
    try {
      // 添加时间戳参数避免CDN缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithTimestamp = '$url${url.contains('?') ? '&' : '?'}t=$timestamp';
      LogUtil.d('请求用户协议URL: $urlWithTimestamp');
      
      // 获取原始响应以便处理JSON解析错误
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
          // 使用递归方式确保所有嵌套Map都是正确类型
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
    } finally {
    }
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
      appBar: CommonSettingAppBar(
        title: S.of(context).userAgreement,
        isTV: isTV,
        titleStyle: _titleStyle,
      ),
      body: FocusScope(
        child: TvKeyNavigation(
        focusNodes: (!_isLoading && _errorMessage != null) ? [_tvNavigationFocusNode] : [],
        scrollController: (!_isLoading && _errorMessage == null) ? _scrollController : null,
        isFrame: isTV ? true : false,
        frameType: isTV ? "child" : null,
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
    );
  }
  
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
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      // 错误状态显示
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
            // 重试按钮使用焦点管理
            FocusableItem(
              focusNode: _tvNavigationFocusNode,
              child: _buildRetryButton(),
            ),
          ],
        ),
      );
    }
    
    // 显示协议内容
    return _buildAgreementContent();
  }
  
  // 构建重试按钮
  Widget _buildRetryButton() {
    return ListenableBuilder(
      listenable: _tvNavigationFocusNode,
      builder: (context, child) {
        return ElevatedButton(
          onPressed: () {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
            _loadAgreement();
          },
          style: ElevatedButton.styleFrom(
            shape: _buttonShape,
            backgroundColor: _tvNavigationFocusNode.hasFocus 
              ? darkenColor(unselectedColor) 
              : unselectedColor,
            side: BorderSide.none,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            S.of(context).retry,
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
        );
      },
    );
  }
  
  // 构建协议内容
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
    
    // 获取更新日期和生效日期（从根级别获取）
    final updateDate = _agreementData!['update_date'] as String?;
    final effectiveDate = _agreementData!['effective_date'] as String?;
    
    // 构建可滚动的内容
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
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
            
            // 协议内容
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
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8), // 减少垂直间距从4到2
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
    
    for (int i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      
      if (paragraph.isEmpty) {
        // 空行用更小的间距
        widgets.add(SizedBox(height: _emptyLineSpacing));
        continue;
      }
      
      // 检查是否是章节标题 - 使用缓存的正则表达式
      final match = _titlePattern.firstMatch(paragraph);
      if (match != null) {
        // 章节标题使用加粗样式
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: _chapterSpacing, bottom: _paragraphSpacing),
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
            padding: EdgeInsets.only(bottom: _paragraphSpacing),
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
