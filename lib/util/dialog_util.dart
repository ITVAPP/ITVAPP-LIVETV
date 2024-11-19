import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:itvapp_live_tv/provider/download_provider.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:itvapp_live_tv/tv/tv_key_navigation.dart';
import '../generated/l10n.dart';

class DialogUtil {
  // 优化焦点节点管理，使用 final 提升性能
  static final List<FocusNode> _focusNodes = [];
  static int focusIndex = 0;

  // 颜色定义
  static const Color selectedColor = Color(0xFFEB144C);
  static const Color unselectedColor = Color(0xFFDFA02A);

  // 初始化焦点节点的方法
  static void _initFocusNodes(int count) {
    _focusNodes.clear();
    focusIndex = 1;
    _focusNodes = List.generate(count, (index) => FocusNode());
  }

  // 优化日志处理逻辑
  static String _processLogs(String content) {
    if (content == "showlog") {
      var logs = LogUtil.getLogs().reversed.toList();
      return logs.map((log) => 
        '${log['time']}\n${LogUtil.parseLogMessage(log['message']!)}')
        .join('\n\n');
    }
    return content;
  }
  
  // 显示通用的弹窗方法
 static Future<bool?> showCustomDialog(
   BuildContext context, {
   String? title,
   String? content,
   String? positiveButtonLabel,
   VoidCallback? onPositivePressed,
   String? negativeButtonLabel,
   VoidCallback? onNegativePressed,
   String? closeButtonLabel,
   VoidCallback? onClosePressed, 
   bool isDismissible = true,
   bool isCopyButton = false,
   String? ShowUpdateButton,
   Widget? child,
 }) {
   // 处理日志内容
   content = content != null ? _processLogs(content) : null;
   
   // 计算所需焦点节点数量
   int focusNodeCount = 1;
   if (positiveButtonLabel != null) focusNodeCount++;
   if (negativeButtonLabel != null) focusNodeCount++;
   if (isCopyButton) focusNodeCount++;
   if (ShowUpdateButton != null) focusNodeCount++;
   if (child != null) focusNodeCount++;
   if (closeButtonLabel != null) focusNodeCount++;
   
   // 初始化焦点节点
   _initFocusNodes(focusNodeCount);

   return showDialog<bool>(
     context: context,
     barrierDismissible: isDismissible,
     builder: (context) {
       return LayoutBuilder(
         builder: (context, constraints) {
           final screenWidth = constraints.maxWidth;
           final screenHeight = constraints.maxHeight;
           final isPortrait = screenHeight > screenWidth;
           final dialogWidth = isPortrait ? screenWidth * 0.8 : screenWidth * 0.6;
           final maxDialogHeight = screenHeight * 0.8;

           return Center(
             child: Container(
               width: dialogWidth,
               constraints: BoxConstraints(maxHeight: maxDialogHeight),
               decoration: const BoxDecoration(
                 color: Color(0xFF2B2D30),
                 borderRadius: BorderRadius.all(Radius.circular(8)),
                 gradient: LinearGradient(
                   colors: [Color(0xff6D6875), Color(0xffB4838D), Color(0xffE5989B)],
                   begin: Alignment.topCenter,
                   end: Alignment.bottomCenter,
                 ),
               ),
               child: TvKeyNavigation(
                 focusNodes: _focusNodes,
                 initialIndex: 1,
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     _buildDialogHeader(context, title: title, closeFocusNode: _focusNodes[0]),
                     if (content != null || child != null)
                       Flexible(
                         child: SingleChildScrollView(
                           child: Padding(
                             padding: const EdgeInsets.symmetric(horizontal: 25),
                             child: Column(
                               crossAxisAlignment: CrossAxisAlignment.center,
                               children: [
                                 if (content != null) _buildDialogContent(content: content),
                                 const SizedBox(height: 10),
                                 if (child != null) 
                                   FocusableItem(
                                     focusNode: _focusNodes[focusIndex++],
                                     child: child,
                                   ),
                               ],
                             ),
                           ),
                         ),
                       ),
                     const SizedBox(height: 10),
                     if (child == null)
                       if (ShowUpdateButton != null)
                         _buildUpdateDownloadBtn(ShowUpdateButton)
                       else
                         _buildActionButtons(
                           context,
                           positiveButtonLabel: positiveButtonLabel,
                           onPositivePressed: onPositivePressed,
                           negativeButtonLabel: negativeButtonLabel,
                           onNegativePressed: onNegativePressed,
                           closeButtonLabel: closeButtonLabel,
                           onClosePressed: onClosePressed,
                           content: content,
                           isCopyButton: isCopyButton,
                         ),
                     const SizedBox(height: 20),
                   ],
                 ),
               ),
             ),
           );
         },
       );
     },
   );
 }
 
 // 封装的 UpdateDownloadBtn 方法
static Widget _buildUpdateDownloadBtn(String apkUrl) {
 return Consumer<DownloadProvider>(
   builder: (BuildContext context, DownloadProvider provider, Widget? child) {
     final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
     final btnWidth = isLandscape ? 380.0 : 220.0;

     return provider.isDownloading
         ? _buildDownloadProgress(provider, btnWidth)
         : _buildDownloadButton(
             context: context,
             focusNode: _focusNodes[focusIndex++],
             label: S.current.update,
             onPressed: () => _handleDownload(context, apkUrl),
             width: btnWidth,
           );
   },
 );
}

// 抽取下载进度显示逻辑为独立方法
static Widget _buildDownloadProgress(DownloadProvider provider, double width) {
 return ClipRRect(
   borderRadius: BorderRadius.circular(16),
   child: SizedBox(
     height: 48,
     width: width,
     child: Stack(
       alignment: Alignment.center,
       children: [
         Positioned.fill(
           child: LinearProgressIndicator(
             value: provider.progress,
             backgroundColor: const Color(0xFFEB144C).withOpacity(0.2),
             color: const Color(0xFFEB144C),
           ),
         ),
         Text(
           '${S.current.downloading} ${(provider.progress * 100).toStringAsFixed(1)}%',
           style: const TextStyle(
             color: Colors.white,
             fontWeight: FontWeight.bold,
             fontSize: 16,
           ),
         ),
       ],
     ),
   ),
 );
}

// 优化后的可聚焦按钮构建方法
static Widget _buildDownloadButton({
 required BuildContext context,
 required FocusNode focusNode,
 required String label,
 required VoidCallback onPressed,
 required double width,
}) {
 return FocusableItem(
   focusNode: focusNode,
   child: Builder(
     builder: (BuildContext context) {
       bool hasFocus = Focus.of(context).hasFocus;
       return ElevatedButton(
         style: _DownloadBtnStyle(hasFocus, width),
         onPressed: onPressed,
         child: Text(
           label,
           style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
         ),
       );
     },
   ),
 );
}

// 提取按钮样式设置为独立方法
static ButtonStyle _DownloadBtnStyle(bool hasFocus, double width) {
 return ElevatedButton.styleFrom(
   fixedSize: Size(width, 48),
   backgroundColor: hasFocus ? selectedColor : unselectedColor,
   elevation: 10,
   foregroundColor: Colors.white,
   shadowColor: hasFocus ? selectedColor : unselectedColor,
 );
}

// 提取下载逻辑处理为独立方法
static void _handleDownload(BuildContext context, String apkUrl) {
 if (Platform.isAndroid) {
   try {
     context.read<DownloadProvider>().downloadApk(apkUrl);
   } catch (e, stackTrace) {
     LogUtil.logError('下载时发生错误', e, stackTrace);
   }
 } else {
   try {
     Navigator.of(context).pop(true);
   } catch (e, stackTrace) {
     LogUtil.logError('关闭对话框时发生错误', e, stackTrace);
   }
 }
}

// 封装的标题部分，包含右上角关闭按钮
static Widget _buildDialogHeader(BuildContext context, {String? title, FocusNode? closeFocusNode}) {
 return Stack(
   children: [
     Container(
       width: double.infinity,
       padding: const EdgeInsets.all(20),
       alignment: Alignment.center,
       child: Text(
         title ?? 'Notification 🔔',
         style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
       ),
     ),
     Positioned(
       right: 0,
       child: FocusableItem(
         focusNode: closeFocusNode!,
         child: Builder(
           builder: (BuildContext context) {
             final bool hasFocus = Focus.of(context).hasFocus;
             return IconButton(
               icon: const Icon(Icons.close),
               iconSize: 26,
               color: _closeIconColor(hasFocus),
               onPressed: () {
                 Navigator.of(context).pop();
               },
             );
           },
         ),
       ),
     ),
   ],
 );
}

// 封装的内容部分，允许选择和复制功能
static Widget _buildDialogContent({String? content}) {
 return Column(
   crossAxisAlignment: CrossAxisAlignment.start,
   mainAxisSize: MainAxisSize.min,
   children: [
     TextField(
       controller: TextEditingController(text: content ?? ''),
       readOnly: true,
       maxLines: null,
       textAlign: TextAlign.start,
       decoration: const InputDecoration(
         border: InputBorder.none,
       ),
       style: const TextStyle(fontSize: 18),
       enableInteractiveSelection: true,
     ),
   ],
 );
}

// 动态生成按钮，并增加点击效果
static Widget _buildActionButtons(
 BuildContext context, {
 String? positiveButtonLabel,
 VoidCallback? onPositivePressed,
 String? negativeButtonLabel,
 VoidCallback? onNegativePressed,
 String? closeButtonLabel,
 VoidCallback? onClosePressed,
 String? content,
 bool isCopyButton = false,
}) {
 return Row(
   mainAxisAlignment: MainAxisAlignment.center,
   children: [
     if (negativeButtonLabel != null)
       _buildFocusableButton(
         focusNode: _focusNodes[focusIndex++],
         onPressed: onNegativePressed,
         label: negativeButtonLabel,
       ),
     if (positiveButtonLabel != null)
       const SizedBox(width: 20),
     if (positiveButtonLabel != null)
       _buildFocusableButton(
         focusNode: _focusNodes[focusIndex++],
         onPressed: onPositivePressed,
         label: positiveButtonLabel,
       ),
     if (isCopyButton && content != null)
       _buildFocusableButton(
         focusNode: _focusNodes[focusIndex++],
         onPressed: () {
           Clipboard.setData(ClipboardData(text: content));
           CustomSnackBar.showSnackBar(
             context,
             S.current.copyok,
             duration: Duration(seconds: 4),
           );
         },
         label: S.current.copy,
       ),
     if (closeButtonLabel != null)
       _buildFocusableButton(
         focusNode: _focusNodes[focusIndex++],
         onPressed: onClosePressed ?? () => Navigator.of(context).pop(),
         label: closeButtonLabel,
         autofocus: true,
       ),
   ],
 );
}

// 构建可聚焦按钮的方法
static Widget _buildFocusableButton({
 required FocusNode focusNode,
 required VoidCallback? onPressed,
 required String label,
 bool autofocus = false,
}) {
 return FocusableItem(
   focusNode: focusNode,
   child: Builder(
     builder: (BuildContext context) {
       final bool hasFocus = Focus.of(context).hasFocus;
       return ElevatedButton(
         style: _buttonStyle(hasFocus),
         onPressed: onPressed,
         autofocus: autofocus,
         child: Text(label),
       );
     },
   ),
 );
}

// 动态设置按钮样式
static ButtonStyle _buttonStyle(bool hasFocus) {
 return ElevatedButton.styleFrom(
   backgroundColor: hasFocus ? darkenColor(selectedColor) : unselectedColor,
   foregroundColor: Colors.white,
   padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
   shape: RoundedRectangleBorder(
     borderRadius: BorderRadius.circular(16),
   ),
   textStyle: TextStyle(
     fontSize: 18,
     fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal,
   ),
   alignment: Alignment.center,
 );
}

// 获取关闭按钮的颜色，动态设置焦点状态  
static Color _closeIconColor(bool hasFocus) {
 return hasFocus ? selectedColor : Colors.white;
}

// 释放焦点节点资源
static void disposeFocusNodes() {
 for (var node in _focusNodes) {
   node.dispose();
 }
 _focusNodes.clear();
}

}
