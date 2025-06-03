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
  // 页面标题样式
  static const _titleStyle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  
  // 协议内容样式
  static const _contentTitleStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.bold);
  static const _sectionTitleStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
  static const _contentTextStyle = TextStyle(fontSize: 16, height: 1.5);
  
  // 容器最大宽度
  static const _maxContainerWidth = 800.0;
  
  // 加载状态
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _agreementData;
  
  // 滚动控制器
  final ScrollController _scrollController = ScrollController();
  
  // TV导航焦点节点
  late final FocusNode _scrollFocusNode;
  
  @override
  void initState() {
    super.initState();
    _scrollFocusNode = FocusNode();
    _loadAgreement();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _scrollFocusNode.dispose();
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
      // 使用统一的HttpUtil进行网络请求
      return await HttpUtil().getRequest<Map<String, dynamic>>(
        url,
      );
    } catch (e) {
      LogUtil.e('从 $url 获取协议失败: $e');
      return null;
    }
  }
  
  // 处理按键事件（TV遥控器）
  void _handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent && _scrollController.hasClients) {
      const scrollAmount = 100.0;
      
      switch (event.logicalKey.keyLabel) {
        case 'Arrow Up':
          _scrollController.animateTo(
            (_scrollController.offset - scrollAmount).clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
          break;
        case 'Arrow Down':
          _scrollController.animateTo(
            (_scrollController.offset + scrollAmount).clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
          break;
        case 'Page Up':
          _scrollController.animateTo(
            (_scrollController.offset - MediaQuery.of(context).size.height * 0.8).clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          break;
        case 'Page Down':
          _scrollController.animateTo(
            (_scrollController.offset + MediaQuery.of(context).size.height * 0.8).clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            ),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          break;
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isTV = themeProvider.isTV;
    final screenWidth = MediaQuery.of(context).size.width;
    
    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: AppBar(
        leading: isTV ? const SizedBox.shrink() : null,
        title: Text(
          S.of(context).userAgreement,
          style: _titleStyle,
        ),
        backgroundColor: isTV ? const Color(0xFFDFA02A) : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _loadAgreement();
                        },
                        child: Text(S.of(context).retry),
                      ),
                    ],
                  ),
                )
              : FocusScope(
                  child: TvKeyNavigation(
                    focusNodes: [_scrollFocusNode],
                    isFrame: isTV,
                    frameType: isTV ? "child" : null,
                    child: RawKeyboardListener(
                      focusNode: _scrollFocusNode,
                      onKey: _handleKeyEvent,
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: screenWidth > _maxContainerWidth ? _maxContainerWidth : double.infinity,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _buildAgreementContent(),
                        ),
                      ),
                    ),
                  ),
                ),
    );
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
        child: Text(
          'No agreement content available',
          style: _contentTextStyle,
        ),
      );
    }
    
    final agreementInfo = _agreementData!['agreement_info'] as Map<String, dynamic>?;
    
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
          if (agreementInfo != null) ...[
            _buildInfoRow(S.of(context).updateDate, agreementInfo['update_date'] ?? ''),
            _buildInfoRow(S.of(context).effectiveDate, agreementInfo['effective_date'] ?? ''),
            const SizedBox(height: 16),
          ],
          
          // 欢迎信息
          if (languageData['welcome_message'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                languageData['welcome_message'],
                style: _contentTextStyle.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          
          // 应用描述
          if (languageData['app_description'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                languageData['app_description'],
                style: _contentTextStyle,
              ),
            ),
          
          // 协议章节
          if (languageData['sections'] != null)
            ..._buildSections(languageData['sections'] as Map<String, dynamic>),
        ],
      ),
    );
  }
  
  // 构建信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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
  
  // 构建协议章节
  List<Widget> _buildSections(Map<String, dynamic> sections) {
    final widgets = <Widget>[];
    
    // 按数字顺序排序章节（处理字符串数字排序问题）
    final sortedKeys = sections.keys.toList()
      ..sort((a, b) {
        // 尝试将键转换为数字进行排序
        final aNum = int.tryParse(a) ?? 0;
        final bNum = int.tryParse(b) ?? 0;
        return aNum.compareTo(bNum);
      });
    
    for (final key in sortedKeys) {
      final section = sections[key] as Map<String, dynamic>;
      
      // 章节标题
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Text(
            '${key}. ${section['title'] ?? ''}',
            style: _sectionTitleStyle,
          ),
        ),
      );
      
      // 章节内容
      if (section['content'] != null) {
        final content = section['content'] as Map<String, dynamic>;
        // 对内容键进行自然排序（处理如 "1.1", "1.2", "1.10" 的排序）
        final contentKeys = content.keys.toList()
          ..sort((a, b) {
            // 分割成数字部分进行比较
            final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
            final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
            
            for (int i = 0; i < aParts.length && i < bParts.length; i++) {
              if (aParts[i] != bParts[i]) {
                return aParts[i].compareTo(bParts[i]);
              }
            }
            return aParts.length.compareTo(bParts.length);
          });
        
        for (final contentKey in contentKeys) {
          final contentText = content[contentKey] ?? '';
          
          // 处理包含换行符的文本
          if (contentText.contains('\n')) {
            // 分割文本并为每个段落创建单独的 Widget
            final paragraphs = contentText.split('\n');
            for (int i = 0; i < paragraphs.length; i++) {
              if (paragraphs[i].trim().isNotEmpty) {
                widgets.add(
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: i == paragraphs.length - 1 ? 12 : 6,
                      left: 16,
                    ),
                    child: Text(
                      paragraphs[i].trim(),
                      style: _contentTextStyle,
                    ),
                  ),
                );
              }
            }
          } else {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 16),
                child: Text(
                  contentText,
                  style: _contentTextStyle,
                ),
              ),
            );
          }
        }
      }
    }
    
    return widgets;
  }
}
