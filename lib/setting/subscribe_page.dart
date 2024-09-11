import 'dart:convert';
import 'dart:io';

import 'package:itvapp_live_tv/tv/html_string.dart';
import 'package:itvapp_live_tv/util/date_util.dart';
import 'package:itvapp_live_tv/util/log_util.dart';
import 'package:itvapp_live_tv/util/m3u_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:sp_util/sp_util.dart';
import 'package:provider/provider.dart';  // 引入 Provider
import '../provider/theme_provider.dart';  // 引入 ThemeProvider
import '../entity/subScribe_model.dart';
import '../generated/l10n.dart';
import '../util/env_util.dart';

class SubScribePage extends StatefulWidget {
  const SubScribePage({super.key});

  @override
  State<SubScribePage> createState() => _SubScribePageState();
}

class _SubScribePageState extends State<SubScribePage> {
  AppLifecycleListener? _appLifecycleListener;

  List<SubScribeModel> _m3uList = <SubScribeModel>[];

  HttpServer? _server;

  String? _address;
  String? _ip;
  final _port = 8828;

  @override
  void initState() {
    super.initState();
    LogUtil.safeExecute(() {
      _localNet();
      _getData();
      _pasteClipboard();
      _addLifecycleListen();
    }, '初始化页面时发生错误');
  }

  _addLifecycleListen() {
    // 通过 Provider 获取 isTV 的状态，判断是否添加生命周期监听
    bool isTV = context.read<ThemeProvider>().isTV;
    if (isTV) return;

    _appLifecycleListener = AppLifecycleListener(onStateChange: (state) {
      LogUtil.v('addLifecycleListen::::::$state');
      if (state == AppLifecycleState.resumed) {
        _pasteClipboard();
      }
    });
  }

  _pasteClipboard() async {
    try {
      // 通过 Provider 获取 isTV 的状态
      bool isTV = context.read<ThemeProvider>().isTV;
      if (isTV) return;

      final clipData = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clipData?.text;
      if (clipText != null && clipText.startsWith('http')) {
        final res = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                backgroundColor: const Color(0xff3C3F41),
                title: Text(S.current.dialogTitle),
                content: Text('${S.current.dataSourceContent}\n$clipText'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: Text(S.current.dialogCancel),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: Text(S.current.dialogConfirm),
                  ),
                ],
              );
            });
        if (res == true) {
          await _pareUrl(clipText);
        }
        Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (e) {
      LogUtil.logError('粘贴板获取数据时发生错误',  e, stackTrace);
    }
  }

  _localNet() async {
    try {
      // 通过 Provider 获取 isTV 的状态
      bool isTV = context.read<ThemeProvider>().isTV;
      if (!isTV) return;

      _ip = await getCurrentIP();
      LogUtil.v('_ip::::$_ip');
      if (_ip == null) return;
      _server = await HttpServer.bind(_ip, _port);
      _address = 'http://$_ip:$_port';
      setState(() {});
      await for (var request in _server!) {
        if (request.method == 'GET') {
          request.response
            ..headers.contentType = ContentType.html
            ..write(getHtmlString(_address!))
            ..close();
        } else if (request.method == 'POST') {
          String content = await utf8.decoder.bind(request).join();
          Map<String, dynamic> data = jsonDecode(content);
          String rMsg = S.current.tvParseParma;
          if (data.containsKey('url')) {
            final url = data['url'] as String?;
            if (url == '' || url == null || !url.startsWith('http')) {
              EasyLoading.showError(S.current.tvParsePushError);
              rMsg = S.current.tvParsePushError;
            } else {
              rMsg = S.current.tvParseSuccess;
              await _pareUrl(url);
            }
          } else {
            LogUtil.v('Missing parameters');
          }

          final responseData = {'message': rMsg};

          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(json.encode(responseData))
            ..close();
        } else {
          request.response
            ..statusCode = HttpStatus.methodNotAllowed
            ..write(
                'Unsupported request: ${request.method}. Only POST requests are allowed.')
            ..close();
        }
      }
    } catch (e) {
      LogUtil.logError('本地网络配置时发生错误',  e, stackTrace);
    }
  }

  _getData() async {
    try {
      final res = await M3uUtil.getLocalData();
      setState(() {
        _m3uList = res;
      });
    } catch (e) {
      LogUtil.logError('获取本地数据时发生错误',  e, stackTrace);
    }
  }

  Future<String> getCurrentIP() async {
    String currentIP = '';
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          LogUtil.v(
              'Name: ${interface.name}  IP Address: ${addr.address}  IPV4: ${InternetAddress.anyIPv4}');
          if (addr.type == InternetAddressType.IPv4 &&
              addr.address.startsWith('192')) {
            currentIP = addr.address;
          }
        }
      }
    } catch (e) {
      LogUtil.logError('获取当前IP时发生错误',  e, stackTrace);
    }
    return currentIP;
  }

  @override
  void dispose() {
    LogUtil.safeExecute(() {
      _server?.close(force: true);
      _appLifecycleListener?.dispose();
      super.dispose();
    }, '页面释放资源时发生错误');
  }

  @override
  Widget build(BuildContext context) {
    // 通过 Provider 获取 isTV 的状态
    bool isTV = context.watch<ThemeProvider>().isTV;

    return Scaffold(
      backgroundColor: isTV ? const Color(0xFF1E2022) : null,
      appBar: AppBar(
        backgroundColor: isTV ? const Color(0xFF1E2022) : null,
        title: Text(S.current.subscribe),
        centerTitle: true,
        leading: isTV ? const SizedBox.shrink() : null,
        actions: isTV
            ? null
            : [
                IconButton(
                  onPressed: _addM3uSource,
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
                SizedBox(
                  width: isTV
                      ? MediaQuery.of(context).size.width * 0.3
                      : MediaQuery.of(context).size.width,
                  child: ListView.separated(
                      padding: const EdgeInsets.all(10),
                      itemBuilder: (context, index) {
                        final model = _m3uList[index];
                        return Card(
                          color: model.selected == true
                              ? Colors.redAccent.withOpacity(0.5)
                              : const Color(0xFF2B2D30),
                          child: Padding(
                            padding: const EdgeInsets.only(
                                top: 20, left: 20, right: 10),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                    if (model.selected != true &&
                                        model.link != 'default')
                                      TextButton(
                                          onPressed: () async {
                                            final isDelete = await showDialog(
                                                context: context,
                                                builder: (context) {
                                                  return AlertDialog(
                                                    shape:
                                                        RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        8)),
                                                    backgroundColor:
                                                        const Color(0xFF393B40),
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
                                                                context, false);
                                                          },
                                                          child: Text(
                                                            S.current
                                                                .dialogCancel,
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        17),
                                                          )),
                                                      TextButton(
                                                          onPressed: () {
                                                            Navigator.pop(
                                                                context, true);
                                                          },
                                                          child: Text(
                                                              S.current
                                                                  .dialogConfirm,
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          17))),
                                                    ],
                                                  );
                                                });
                                            if (isDelete == true) {
                                              _m3uList.removeAt(index);
                                              await M3uUtil.saveLocalData(
                                                  _m3uList);
                                              setState(() {});
                                            }
                                          },
                                          child: Text(S.current.delete)),
                                    TextButton(
                                      onPressed: model.selected != true
                                          ? () async {
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
                        return const SizedBox(height: 10);
                      },
                      itemCount: _m3uList.length),
                ),
                if (isTV) const VerticalDivider(),
                if (isTV)
                  Expanded(
                      child: Container(
                    padding: const EdgeInsets.all(30.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          S.current.tvScanTip,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          decoration: const BoxDecoration(color: Colors.white),
                          margin: const EdgeInsets.all(10),
                          padding: const EdgeInsets.all(10),
                          width: 150,
                          child: _address == null
                              ? null
                              : PrettyQrView.data(
                                  data: _address!,
                                  decoration: const PrettyQrDecoration(
                                    image: PrettyQrDecorationImage(
                                      image:
                                          AssetImage('assets/images/logo.png'),
                                    ),
                                  ),
                                ),
                        ),
                        if (_address != null)
                          Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              child:
                                  Text(S.current.pushAddress(_address ?? ''))),
                        Text(S.current.tvPushContent),
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
                S.current.pasterContent,
                style: const TextStyle(color: Color(0xFF999999)),
              ),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 10)
        ],
      ),
    );
  }

  _addM3uSource() async {
    final _textController = TextEditingController();
    final res = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
        builder: (context) {
          return SingleChildScrollView(
            child: LayoutBuilder(builder: (context, _) {
              return SizedBox(
                height: 120 + MediaQuery.of(context).viewInsets.bottom,
                child: Column(
                  children: [
                    SizedBox.fromSize(
                      size: const Size.fromHeight(44),
                      child: AppBar(
                        elevation: 0,
                        backgroundColor: Colors.transparent,
                        title: Text(S.current.addDataSource),
                        centerTitle: true,
                        automaticallyImplyLeading: false,
                        actions: [
                          TextButton(
                              onPressed: () {
                                Navigator.pop(context, _textController.text);
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
                          controller: _textController,
                          autofocus: true,
                          maxLines: 1,
                          decoration: InputDecoration(
                            hintText: S.current.addFiledHintText,
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 20,
                    )
                  ],
                ),
              );
            }),
          );
        });
    if (res == null || res == '') return;
    _pareUrl(res);
  }

  _pareUrl(String res) async {
    LogUtil.v('添加::::：$res');
    try {
      final hasIndex = _m3uList.indexWhere((element) => element.link == res);
      LogUtil.v('添加:hasIndex:::：$hasIndex');
      if (hasIndex != -1) {
        EasyLoading.showToast(S.current.addRepeat);
        return;
      }
      if (res.startsWith('http') && hasIndex == -1) {
        LogUtil.v('添加：$res');
        final sub = SubScribeModel(
            time: DateUtil.formatDate(DateTime.now(), format: DateFormats.full),
            link: res,
            selected: false);
        _m3uList.add(sub);
        await M3uUtil.saveLocalData(_m3uList);
        setState(() {});
      } else {
        EasyLoading.showToast(S.current.addNoHttpLink);
      }
    } catch (e) {
      LogUtil.logError('解析 URL 时发生错误',  e, stackTrace);
    }
  }
}
