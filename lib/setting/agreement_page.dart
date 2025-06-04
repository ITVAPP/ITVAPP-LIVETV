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
  
  // 滚动控制器 - 用于手机端滚动
  final ScrollController _scrollController = ScrollController();
  
  // TV导航焦点节点 - 只需要一个用于TV导航
  late final FocusNode _tvNavigationFocusNode; // TV导航焦点节点
  
  @override
  void initState() {
    super.initState();
    LogUtil.d('=== AgreementPage initState 开始 ===');
    
    // 创建TV导航焦点节点
    _tvNavigationFocusNode = FocusNode(debugLabel: 'tv_navigation_focus');
    LogUtil.d('焦点节点创建完成');
    
    // 加载协议
    LogUtil.d('开始加载协议');
    _loadAgreement();
    
    LogUtil.d('=== AgreementPage initState 结束 ===');
  }
  
  @override
  void dispose() {
    LogUtil.d('=== AgreementPage dispose 开始 ===');
    _scrollController.dispose();
    _tvNavigationFocusNode.dispose();
    LogUtil.d('=== AgreementPage dispose 结束 ===');
    super.dispose();
  }
  
  // 获取当前语言代码
  String _getCurrentLanguageCode() {
    LogUtil.d('=== _getCurrentLanguageCode 被调用 ===');
    
    final locale = context.read<LanguageProvider>().currentLocale;
    final languageCode = locale.languageCode;
    final countryCode = locale.countryCode;
    
    LogUtil.d('locale信息: languageCode=$languageCode, countryCode=$countryCode');
    
    // 构建语言代码，如 zh-CN, zh-TW, en
    String result;
    if (languageCode == 'zh' && countryCode != null) {
      result = '$languageCode-$countryCode';
    } else {
      result = languageCode;
    }
    
    LogUtil.d('返回语言代码: $result');
    return result;
  }
  
  // 加载协议内容
  Future<void> _loadAgreement() async {
    LogUtil.d('=== _loadAgreement 开始执行 ===');
    try {
      // 尝试主地址
      LogUtil.d('尝试从主地址加载: ${Config.agreementUrl}');
      var response = await _fetchAgreement(Config.agreementUrl);
      
      // 如果主地址失败，尝试备用地址
      if (response == null) {
        LogUtil.w('主地址加载失败，尝试备用地址: ${Config.backupagreementUrl}');
        response = await _fetchAgreement(Config.backupagreementUrl);
      }
      
      if (response != null) {
        LogUtil.d('协议数据加载成功，准备更新状态');
        LogUtil.d('协议数据内容: ${response.keys.toList()}');
        setState(() {
          _agreementData = response;
          _isLoading = false;
          LogUtil.d('setState完成: _agreementData已设置, _isLoading=false');
        });
      } else {
        LogUtil.e('所有地址都加载失败');
        setState(() {
          _errorMessage = S.of(context).loadFailed;
          _isLoading = false;
          LogUtil.d('setState完成: 设置错误消息');
        });
      }
    } catch (e, stackTrace) {
      LogUtil.e('加载协议失败: $e');
      LogUtil.e('堆栈跟踪: $stackTrace');
      setState(() {
        _errorMessage = S.of(context).loadFailed;
        _isLoading = false;
      });
    }
    LogUtil.d('=== _loadAgreement 执行结束 ===');
  }
  
  // 从URL获取协议数据
  Future<Map<String, dynamic>?> _fetchAgreement(String url) async {
    LogUtil.d('=== _fetchAgreement 开始: $url ===');
    try {
      // 添加时间戳参数避免CDN缓存
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithTimestamp = '$url${url.contains('?') ? '&' : '?'}t=$timestamp';
      LogUtil.d('实际请求URL: $urlWithTimestamp');
      
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
        // 添加调试日志
        LogUtil.d('响应数据类型: ${response.data.runtimeType}');
        
        // 如果已经是Map类型，直接使用
        if (response.data is Map<String, dynamic>) {
          LogUtil.d('响应数据已经是Map<String, dynamic>类型');
          final data = response.data as Map<String, dynamic>;
          LogUtil.d('数据keys: ${data.keys.toList()}');
          return data;
        }
        
        // 如果是通用Map类型，进行类型转换
        if (response.data is Map) {
          LogUtil.d('响应数据是Map类型，进行类型转换');
          // 使用递归方式确保所有嵌套Map都是正确类型
          final convertedData = _convertToTypedMap(response.data as Map);
          LogUtil.d('转换后数据keys: ${convertedData.keys.toList()}');
          return convertedData;
        }
        
        // 如果是字符串，尝试解析
        if (response.data is String) {
          LogUtil.d('响应数据是String类型，尝试JSON解析');
          LogUtil.d('字符串长度: ${(response.data as String).length}');
          LogUtil.d('字符串前100字符: ${(response.data as String).substring(0, 100)}...');
          
          final parsed = jsonDecode(response.data as String);
          LogUtil.d('JSON解析后类型: ${parsed.runtimeType}');
          
          if (parsed is Map) {
            final convertedData = _convertToTypedMap(parsed);
            LogUtil.d('转换后数据keys: ${convertedData.keys.toList()}');
            return convertedData;
          } else {
            LogUtil.e('JSON解析结果不是Map类型: ${parsed.runtimeType}');
            return null;
          }
        }
        
        LogUtil.e('响应数据格式不支持: ${response.data.runtimeType}');
        return null;
      } catch (e, stackTrace) {
        LogUtil.e('JSON解析失败，原始数据类型: ${response.data.runtimeType}');
        LogUtil.e('JSON解析错误: $e');
        LogUtil.e('堆栈跟踪: $stackTrace');
        return null;
      }
    } catch (e, stackTrace) {
      LogUtil.e('从 $url 获取协议失败: $e');
      LogUtil.e('堆栈跟踪: $stackTrace');
      return null;
    } finally {
      LogUtil.d('=== _fetchAgreement 结束 ===');
    }
  }
  
  // 递归转换Map类型，确保所有嵌套Map都是Map<String, dynamic>
  Map<String, dynamic> _convertToTypedMap(Map map) {
    LogUtil.d('_convertToTypedMap: 开始转换Map，原始类型: ${map.runtimeType}');
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is Map) {
        LogUtil.d('  转换嵌套Map: key=$key');
        result[key.toString()] = _convertToTypedMap(value);
      } else if (value is List) {
        LogUtil.d('  转换List: key=$key, length=${value.length}');
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
    LogUtil.d('_convertToTypedMap: 转换完成，结果keys: ${result.keys.toList()}');
    return result;
  }
  
  // 颜色加深函数 - 与 setting_log_page 保持一致
  Color darkenColor(Color color, [double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    final result = hslDark.toColor();
    return result;
  }
  
  @override
  Widget build(BuildContext context) {
    LogUtil.d('=== build方法被调用 ===');
    LogUtil.d('当前状态: _isLoading=$_isLoading, _errorMessage=$_errorMessage, _agreementData是否为null=${_agreementData == null}');
    
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
      body: TvKeyNavigation(
        focusNodes: [_tvNavigationFocusNode],
        scrollController: (!_isLoading && _errorMessage == null) ? _scrollController : null,
        isFrame: isTV,
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
    LogUtil.d('=== _buildAgreementContent 被调用 ===');
    
    if (_agreementData == null) {
      LogUtil.e('_agreementData 为 null，返回空Widget');
      return const SizedBox.shrink();
    }
    
    final languageCode = _getCurrentLanguageCode();
    
    // 添加调试日志
    LogUtil.d('当前语言代码: $languageCode');
    LogUtil.d('协议数据keys: ${_agreementData!.keys.toList()}');
    
    // 安全获取languages字段
    final languagesField = _agreementData!['languages'];
    LogUtil.d('languages字段类型: ${languagesField.runtimeType}');
    
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
      LogUtil.d('当前语言数据类型: ${currentLangData.runtimeType}');
      
      if (currentLangData != null && currentLangData is Map) {
        languageData = Map<String, dynamic>.from(currentLangData);
        LogUtil.d('找到语言数据: $languageCode');
        LogUtil.d('语言数据keys: ${languageData.keys.toList()}');
      } else {
        LogUtil.w('当前语言无数据，尝试使用英文');
        // 尝试获取英文内容作为后备
        final enData = languagesField['en'];
        if (enData != null && enData is Map) {
          languageData = Map<String, dynamic>.from(enData);
          LogUtil.d('使用英文后备数据');
        }
      }
    } catch (e, stackTrace) {
      LogUtil.e('获取语言数据失败: $e');
      LogUtil.e('堆栈: $stackTrace');
    }
    
    if (languageData == null) {
      LogUtil.e('没有找到可用的语言数据');
      return _buildNoContentWidget();
    }
    
    // 获取更新日期和生效日期（从根级别获取）
    final updateDate = _agreementData!['update_date'] as String?;
    final effectiveDate = _agreementData!['effective_date'] as String?;
    LogUtil.d('更新日期: $updateDate, 生效日期: $effectiveDate');
    
    LogUtil.d('开始构建UI Widget');
    
    // 构建可滚动的内容
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 协议标题
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
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
              const SizedBox(height: 16),
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
    LogUtil.w('=== _buildNoContentWidget 被调用 - 显示无内容提示 ===');
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
    LogUtil.d('_buildInfoRow: $label = $value');
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
    LogUtil.d('=== _buildParsedContent 被调用 ===');
    LogUtil.d('内容长度: ${content.length}');
    LogUtil.d('内容前100字符: ${content.substring(0, content.length > 100 ? 100 : content.length)}...');
    
    // 分割内容为段落
    final paragraphs = content.split('\n');
    LogUtil.d('段落数量: ${paragraphs.length}');
    
    final List<Widget> widgets = [];
    
    // 正则表达式匹配章节标题（如 "1. 导言", "1.1 xxx", "(1) xxx" 等）
    final titlePattern = RegExp(r'^(\d+\.[\d.]*\s+|（\d+）|[(]\d+[)])\s*(.+)');
    
    for (int i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      
      if (paragraph.isEmpty) {
        // 空行用更小的间距
        widgets.add(const SizedBox(height: 4));
        continue;
      }
      
      // 检查是否是章节标题
      final match = titlePattern.firstMatch(paragraph);
      if (match != null) {
        LogUtil.d('发现章节标题: $paragraph');
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
        if (i < 3) { // 只记录前3个段落避免日志过长
          LogUtil.d('段落$i: ${paragraph.substring(0, paragraph.length > 50 ? 50 : paragraph.length)}...');
        }
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
    
    LogUtil.d('总共生成了 ${widgets.length} 个Widget');
    LogUtil.d('=== _buildParsedContent 执行完成 ===');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}
