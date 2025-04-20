/// 定义请求头规则的静态配置类
class HeaderRules {
  const HeaderRules._();

  /// 域名到Referer的映射规则
  static const String rulesString = '''
googlevideo|www.youtube.com
tcdn.itouchtv.cn|www.gdtv.cn
lanosso.com|lanzoux.com
wwentua.com|lanzoux.com
btime.com|www.btime.com
kksmg.com|live.kankanews.com
iqilu|v.iqilu.com
cditvcn|www.cditv.cn
candocloud.cn|www.cditv.cn
hwapi.yntv.net|cloudxyapi.yntv.net
tvlive.yntv.cn|www.yntv.cn
api.yntv.ynradio.com|www.ynradio.cn
i0834.cn|www.ls666.com
dzxw.net|www.dzrm.cn
zyrb.com.cn|www.sczytv.com
ningxiahuangheyun.com|www.nxtv.com.cn
quklive.com|www.qukanvideo.com
yuexitv|www.yuexitv.com
ahsxrm|www.ahsxrm.cn
liangtv.cn|tv.gxtv.cn
gxtv.cn|www.gxtv.cn
lcxw.cn|www.lcxw.cn
sxtygdy.com|www.sxtygdy.com
sxrtv.com|www.sxrtv.com
tv_radio_47447|live.lzgd.com.cn
51742.hlsplay.aodianyun.com|www.yltvb.com
pubmod.hntv.tv|static.hntv.tv
tvcdn.stream3.hndt.com|static.hntv.tv
jiujiang|www.jjntv.cn
sztv.com.cn|www.sztv.com.cn
jxtvcn.com.cn|www.jxntv.cn
ahtv.cn|www.ahtv.cn
zjcn-live-play|api.chinaaudiovisual.cn
cloudvdn.com|*.jstv.com
hoolo.tv|tv.hoolo.tv
liveplus.lzr.com.cn|www.lzr.com.cn
cztv.com|www.cztv.com
cztvcloud.com|www.cztv.com
wuxue-|m.hbwuxue.com
luotian-|m-api.cjyun.org/v2
jiangling-|m-jiangling.cjyun.org
songzi-|m-songzi.cjyun.org
ezhou-|m-ezhou.cjyun.org
wufeng-|m-wufeng.cjyun.org
gucheng-|wap.guchengnews.com
cjyun.org|app.cjyun.org.cn
cjy.hbtv.com.cn|news.hbtv.com.cn
liveplay-srs.voc.com.cn|xhncloud.voc.com.cn
mapi.ldntv.cn|www.ldntv.cn
xiangtanxian_tv|wap.xtxnews.cn
hengnan_tv|wap.hnxrmt.com
zixin_tv|zixing-wap.rednet.cn
chaling-telev|wap.clnews.cn
liveplay-yongshun|yongshun-wap.rednet.cn
146_f067fe|xhncloud.voc.com.cn
live.ngcz.tv|www.ngcz.tv
cctvnews.cctv.com|m-live.cctvnews.cctv.com
live1.kxm.xmtv.cn|seexm2024.kxm.xmtv.cn
qztv.cn|www.qztv.cn
gzstv.com|www.gzstv.com
lasdieny.com|www.lasatv.cn
p8.vzan.com|npwhyavzb.vzan.com
xishuirm.cn|www.xishuirm.cn
xatv-gl.xiancity.cn|gl.xiancity.cn
lqtv.sn.cn|www.lqtv.sn.cn
hplayer1.juyun.tv|ylrb.com
zatvs.cn|zasjt.zatvs.cn
zjwtv.com|app.zjwtv.com
qhbtv.com|www.qhbtv.com
qhtb.cn|www.qhtb.cn
hdhhy.cn|www.hdhhy.cn
''';

  /// 需要添加CORS头的域名列表
  static const String corsRulesString = '''
itvapp.net
file.lcxw.cn
51742.hlsplay.aodianyun.com
pubmod.hntv.tv
tvlive.yntv.cn
jxtvcn.com.cn
hls-api.sztv.com.cn
sttv2-api.sztv.com.cn
yun-live.jxtvcn.com.cn
mapi.ahtv.cn
tytv-hls.sxtygdy.com
mapi.hoolo.tv
liveplus.lzr.com.cn
cjyun.org
cjy.hbtv.com.cn
''';

  /// 使用通用播放器请求头的域名列表
  static const String excludeDomainsString = '''
loulannews
chinamobile.com
hwapi.yunshicloud.com
live.nctv.top
cbg.cn
jingzhou-
gongan-
yangxin-
zztv.tv
dspull.ijntv.cn
hlss.gstv.com.cn
kankanlive.com
yumentv.cn
chinashishi.net
tv.vtibet.cn
chayutv.com
218.207.233.111
tvshow.scgchc.com
hlsplay.aodianyun.com
player4.juyun.tv
gbtv-rtmp.zjwtv.com
pili-live-rtmp.akrt.cn
''';

  /// 使用BetterPlayer默认请求头的域名列表
  static const String defaultHeadersDomainsString = '''
pili-live-rtmp.akrt.cn
''';

  /// 域名特定的自定义请求头规则
  static const String customHeadersRulesString = '''
[idclive.hljtv.com]
Host: {host}
User-Agent: product jushi.4.5.4 ( Android.31 Mobile)
Accept: */*
Connection: keep-alive

[tv.youku.com]
Host: {host}
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36
Accept: */*
Connection: keep-alive
''';
}
