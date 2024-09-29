import 'dart:convert';
import 'dart:io';

import 'package:itvapp_live_tv/tv/html_string.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart';
import 'package:itvapp_live_tv/util/env_util.dart';
import 'package:itvapp_live_tv/util/custom_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:sp_util/sp_util.dart';
import 'package:provider/provider.dart';
import '../provider/theme_provider.dart';
import '../entity/subScribe_model.dart';
import '../generated/l10n.dart';

class SubScribePage extends StatefulWidget {
  const SubScribePage({super.key});

  @override
  State<SubScribePage> createState() => _SubScribePageState();
}

class _SubScribePageState extends State<SubScribePage> {
  AppLifecycleListener? _appLifecycleListener;  // 监听应用生命周期变化

  List<SubScribeModel> _m3uList = <SubScribeModel>[];  // 本地M3U订阅列表

  HttpServer? _server;  // 本地HTTP服务器，用于处理TV端推送

  String? _address;  // 本地推送服务地址
  String? _ip;  // 当前设备的IP地址
  final _port = 8828;  // 本地服务端口

  @override
  void initState() {
    super.initState();
    LogUtil.safeExecute(() {
      _localNet();  // 初始化本地网络服务
      _getData();  // 加载本地M3U列表
      _pasteClipboard();  // 检查剪贴板数据
      _addLifecycleListen();  // 添加生命周期监听（仅限非TV端）
    }, '初始化页面时发生错误');  // 捕获初始化阶段的异常
  }

  // 添加应用生命周期监听，仅适用于非TV模式
  _addLifecycleListen() {
    bool isTV = context.read<ThemeProvider>().isTV;  // 获取是否为TV端状态
    if (isTV) return;

    // 当应用恢复时，重新检查剪贴板内容
    _appLifecycleListener = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.resumed) {
        _pasteClipboard();  // 恢复后检查剪贴板是否有可处理的内容
      }
    });
  }

  // 获取剪贴板数据并检查是否为URL（仅非TV端）
  _pasteClipboard() async {
    try {
      bool isTV = context.read<ThemeProvider>().isTV;  // 检查是否为TV端
      if (isTV) return;

      // 获取剪贴板中的纯文本数据
      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clipData?.text;
      if (clipText != null && clipText.startsWith('http')) {
        // 如果剪贴板内容为HTTP链接，提示用户是否要处理
        final res = await showDialog<bool>(
            context: context,
            barrierDismissible: false,  // 用户必须选择一个操作
            builder: (BuildContext context) {
              return AlertDialog(
                backgroundColor: const Color(0xff3C3F41),
                title: Text(S.current.dialogTitle),  // 弹窗标题
                content: Text('${S.current.dataSourceContent}\n$clipText'),  // 显示剪贴板内容
                actions: [
                  // 取消按钮
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: Text(S.current.dialogCancel),
                  ),
                  // 确认按钮
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: Text(S.current.dialogConfirm),
                  ),
                ],
              );
            });
        // 用户选择确认后，解析URL
        if (res == true) {
          await _pareUrl(clipText);
        }
        Clipboard.setData(const ClipboardData(text: ''));  // 清空剪贴板
      }
    } catch (e, stackTrace) {
      LogUtil.logError('粘贴板获取数据时发生错误', e, stackTrace);
      _showErrorSnackBar(context, S.of(context).clipboardDataFetchError);  // 捕获异常并提示用户
    }
  }

  // 初始化本地网络，用于TV推送
  _localNet() async {
    try {
      bool isTV = context.read<ThemeProvider>().isTV;  // 检查是否为TV端
      if (!isTV) return;

      // 获取当前设备的IP地址
      _ip = await NetworkService.getCurrentIP();
      if (_ip == null) return;

      // 在指定端口启动HTTP服务器
      _server = await HttpServer.bind(_ip, _port);
      _address = 'http://$_ip:$_port';  // 构建推送地址
      setState(() {});  // 更新UI

      // 处理HTTP请求
      await for (var request in _server!) {
        if (request.method == 'GET') {
          // 返回HTML页面内容
          request.response
            ..headers.contentType = ContentType.html
            ..write(getHtmlString(_address!))
            ..close();
        } else if (request.method == 'POST') {
          // 处理POST请求中的JSON数据
          String content = await utf8.decoder.bind(request).join();
          Map<String, dynamic> data = jsonDecode(content);
          String rMsg = S.current.tvParseParma;  // 默认的响应消息

          if (data.containsKey('url')) {
            final url = data['url'] as String?;
            // 检查URL是否合法
            if (url == '' || url == null || !url.startsWith('http')) {
              EasyLoading.showError(S.current.tvParsePushError);
              rMsg = S.current.tvParsePushError;
            } else {
              rMsg = S.current.tvParseSuccess;
              await _pareUrl(url);  // 解析并处理URL
            }
          } else {
            LogUtil.v('Missing parameters');
          }

          // 返回响应数据
          final responseData = {'message': rMsg};
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(json.encode(responseData))
            ..close();
        } else {
          // 处理不支持的HTTP方法
          request.response
            ..statusCode = HttpStatus.methodNotAllowed
            ..write('Unsupported request: ${request.method}. Only POST requests are allowed.')
            ..close();
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('本地网络配置时发生错误', e, stackTrace);
      _showErrorSnackBar(context, '本地网络配置失败');  // 捕获异常并提示用户
    }
  }

  // 获取本地存储的M3U数据
  _getData() async {
    try {
      final res = await M3uUtil.getLocalData();  // 获取本地存储的M3U数据
      setState(() {
        _m3uList = res;  // 更新列表数据并刷新UI
      });
    } catch (e, stackTrace) {
      LogUtil.logError('获取本地数据时发生错误', e, stackTrace);
      _showErrorSnackBar(context, '获取本地数据失败');  // 捕获异常并提示用户
    }
  }

  @override
  void dispose() {
    LogUtil.safeExecute(() {
      _server?.close(force: true);  // 关闭本地服务器
      _appLifecycleListener?.dispose();  // 释放生命周期监听资源
      super.dispose();
    }, '页面释放资源时发生错误');  // 捕获页面销毁时的异常
  }

  @override
  Widget build(BuildContext context) {
    // 通过Provider动态获取TV端状态
    bool isTV = context.watch<ThemeProvider>().isTV;

    return FocusTraversalGroup(
      policy: WidgetOrderTraversalPolicy(),  // 管理TV端的焦点切换顺序
      child: Scaffold(
        backgroundColor: isTV ? const Color(0xFF1E2022) : null,  // TV端背景色
        appBar: AppBar(
          backgroundColor: isTV ? const Color(0xFF1E2022) : null,
          title: Text(S.current.subscribe),  // 页面标题
          centerTitle: true,  // 标题居中
          leading: isTV ? const SizedBox.shrink() : null,  // TV端隐藏返回按钮
          actions: isTV
              ? null
              : [
                  IconButton(
                    onPressed: _addM3uSource,  // 添加新的M3U源
                    icon: const Icon(
                      Icons.add,
                      color: Colors.white,
                    ),
                  )
                ],
        ),
        body: Column(
          children: [
            Flexible(
              child: Row(
                children: [
                  // 左侧列表部分，显示M3U源
                  SizedBox(
                    width: isTV
                        ? MediaQuery.of(context).size.width * 0.3  // TV端调整宽度
                        : MediaQuery.of(context).size.width,
                    child: ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemBuilder: (context, index) {
                          final model = _m3uList[index];  // 获取每一项的M3U数据
                          return Card(
                            color: model.selected == true
                                ? Colors.redAccent.withOpacity(0.5)  // 已选中的源
                                : const Color(0xFF2B2D30),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  top: 20, left: 20, right: 10),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 显示M3U链接
                                  Text(
                                    model.link == 'default'
                                        ? model.link!
                                        : model.link!
                                            .split('?')
                                            .first
                                            .split('/')
                                            .last
                                            .toString(),
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                  const SizedBox(height: 20),
                                  // 显示创建时间
                                  Text(
                                    '${S.current.createTime}：${model.time}',
                                    style: TextStyle(
                                        color: Colors.white.withOpacity(0.5),
                                        fontSize: 12),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Spacer(),
                                      // 删除按钮
                                      if (model.selected != true &&
                                          model.link != 'default')
                                        TextButton(
                                            onPressed: () async {
                                              final isDelete = await showDialog(
                                                  context: context,
                                                  builder: (context) {
                                                    return AlertDialog(
                                                      shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      8)),
                                                      backgroundColor:
                                                          const Color(
                                                              0xFF393B40),
                                                      content: Text(
                                                        S.current
                                                            .dialogDeleteContent,
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 20),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () {
                                                              Navigator.pop(
                                                                  context,
                                                                  false);
                                                            },
                                                            child: Text(
                                                              S.current
                                                                  .dialogCancel,
                                                              style: const TextStyle(
                                                                  fontSize:
                                                                      17),
                                                            )),
                                                        TextButton(
                                                            onPressed: () {
                                                              Navigator.pop(
                                                                  context,
                                                                  true);
                                                            },
                                                            child: Text(
                                                                S.current
                                                                    .dialogConfirm,
                                                                style: const TextStyle(
                                                                    fontSize:
                                                                        17))),
                                                      ],
                                                    );
                                                  });
                                              // 确认删除后，更新本地数据并刷新UI
                                              if (isDelete == true) {
                                                _m3uList.removeAt(index);
                                                await M3uUtil.saveLocalData(
                                                    _m3uList);
                                                setState(() {});
                                              }
                                            },
                                            child: Text(S.current.delete)),
                                      // 设为默认按钮
                                      TextButton(
                                        onPressed: model.selected != true
                                            ? () async {
                                                // 设置为默认源
                                                for (var element in _m3uList) {
                                                  element.selected = false;
                                                }
                                                if (model.selected != true) {
                                                  model.selected = true;
                                                  await SpUtil.remove(
                                                      'm3u_cache');
                                                  await M3uUtil.saveLocalData(
                                                      _m3uList);
                                                  setState(() {});
                                                }
                                              }
                                            : null,
                                        child: Text(model.selected != true
                                            ? S.current.setDefault
                                            : S.current.inUse),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (context, index) {
                          return const SizedBox(height: 10);  // 列表项之间的间隔
                        },
                        itemCount: _m3uList.length),  // 列表长度
                  ),
                  if (isTV) const VerticalDivider(),  // TV端显示分割线
                  // 右侧显示二维码区域，TV端可通过扫描二维码推送源
                  if (isTV)
                    Expanded(
                        child: Container(
                      padding: const EdgeInsets.all(30.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            S.current.tvScanTip,  // 提示信息
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          // 动态调整二维码大小
                          Container(
                            decoration: const BoxDecoration(color: Colors.white),
                            margin: const EdgeInsets.all(10),
                            padding: const EdgeInsets.all(10),
                            width: MediaQuery.of(context).size.width * 0.15,  // 动态调整二维码大小
                            child: _address == null
                                ? null
                                : PrettyQrView.data(
                                    data: _address!,  // 显示推送地址的二维码
                                    decoration: const PrettyQrDecoration(
                                      image: PrettyQrDecorationImage(
                                        image: AssetImage(
                                            'assets/images/logo.png'),  // 嵌入logo
                                      ),
                                    ),
                                  ),
                          ),
                          if (_address != null)
                            Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                child: Text(S.current.pushAddress(_address ?? ''))),  // 显示推送地址
                          Text(S.current.tvPushContent),  // 提示推送功能
                        ],
                      ),
                    ))
                ],
              ),
            ),
            if (!isTV)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  S.current.pasterContent,  // 非TV端显示的提示信息
                  style: const TextStyle(color: Color(0xFF999999)),
                ),
              ),
            // 调整底部边距，防止UI遮挡
            SizedBox(height: MediaQuery.of(context).padding.bottom + 10)
          ],
        ),
      ),
    );
  }

  // 添加新的M3U源
  _addM3uSource() async {
    final _textController = TextEditingController();
    final res = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(10))),  // 圆角弹出框
        builder: (context) {
          return SingleChildScrollView(
            child: LayoutBuilder(builder: (context, _) {
              return SizedBox(
                height: 120 + MediaQuery.of(context).viewInsets.bottom,  // 根据输入法动态调整高度
                child: Column(
                  children: [
                    SizedBox.fromSize(
                      size: const Size.fromHeight(44),
                      child: AppBar(
                        elevation: 0,
                        backgroundColor: Colors.transparent,  // 透明背景
                        title: Text(S.current.addDataSource),  // 弹窗标题
                        centerTitle: true,
                        automaticallyImplyLeading: false,  // 不显示返回按钮
                        actions: [
                          TextButton(
                              onPressed: () {
                                Navigator.pop(context, _textController.text);  // 返回输入的M3U地址
                              },
                              child: Text(S.current.dialogConfirm))
                        ],
                      ),
                    ),
                    Flexible(
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 20),
                        child: TextField(
                          controller: _textController,  // 输入M3U源地址
                          autofocus: true,
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: S.current.addFiledHintText,  // 提示用户输入
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 20,  // 防止遮挡底部边距
                    )
                  ],
                ),
              );
            }),
          );
        });
    if (res == null || res == '') return;
    _pareUrl(res);  // 解析并添加新的M3U源
  }

  // 解析并处理新的M3U地址
  _pareUrl(String res) async {
    try {
      final hasIndex = _m3uList.indexWhere((element) => element.link == res);  // 检查是否已存在
      if (hasIndex != -1) {
        EasyLoading.showToast(S.current.addRepeat);  // 提示重复添加
        return;
      }
      if (res.startsWith('http') && hasIndex == -1) {
        final sub = SubScribeModel(
            time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full),  // 记录创建时间
            link: res,
            selected: false);  // 默认未选中
        _m3uList.add(sub);
        await M3uUtil.saveLocalData(_m3uList);  // 保存到本地
        setState(() {});
      } else {
        EasyLoading.showToast(S.current.addNoHttpLink);  // 提示不是合法的HTTP链接
      }
    } catch (e, stackTrace) {
      LogUtil.logError('解析 URL 时发生错误', e, stackTrace);
      _showErrorSnackBar(context, '解析 URL 失败');  // 捕获异常并提示用户
    }
  }

  // 显示错误提示
  void _showErrorSnackBar(BuildContext context, String message) {
      CustomSnackBar.showSnackBar(
        context,
        message,  // 直接传递字符串
        duration: Duration(seconds: 4),
      );
  }
}

// 网络服务类，提供IP地址获取功能
class NetworkService {
  static Future<String?> getCurrentIP() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          // 检查是否为局域网IP地址
          if (addr.type == InternetAddressType.IPv4 &&
              addr.address.startsWith('192')) {
            return addr.address;  // 返回符合条件的IP地址
          }
        }
      }
    } catch (e, stackTrace) {
      LogUtil.logError('获取当前IP时发生错误', e, stackTrace);
      return null;  // 捕获异常时返回null
    }
    return null;
  }
}
