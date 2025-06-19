package com.jhomlala.better_player

/// 有问题的解码器列表
object ProblematicDecodersConfig {
    val decoders = listOf(
        // Samsung Exynos 系列
        "OMX.Exynos.avc.dec",               // Samsung Exynos 芯片的 AVC 解码器，多个 GitHub issues 报告初始化失败
        "OMX.SEC.avc.dec",                  // Samsung 旧设备的解码器，稳定性问题
        
        // MediaTek (MTK) 系列  
        "OMX.MTK.VIDEO.DECODER.HEVC",       // MTK 芯片的 HEVC 解码器，某些设备上有问题
        "OMX.MTK.VIDEO.DECODER.AVC",        // MTK 芯片的 AVC 解码器，特别是在 DRM 内容上有问题
        
        // Qualcomm 系列
        "OMX.qcom.video.decoder.avc",       // Qualcomm AVC 解码器，在某些设备上初始化失败
        "OMX.qcom.video.decoder.hevc",      // Qualcomm HEVC 解码器，某些旧设备上有问题
        "OMX.qcom.video.decoder.avc.secure", // Qualcomm 安全 AVC 解码器，资源占用和初始化问题
        "OMX.qcom.video.decoder.hevc.secure", // Qualcomm 安全 HEVC 解码器
        
        // Amlogic 系列
        "OMX.amlogic.avc.decoder.awesome",  // Amlogic 解码器，稳定性问题，大文件解码失败
        
        // Rockchip 系列
        "c2.rk.hevc.decoder",               // Rockchip HEVC 解码器，Android 12+ 上有绿屏问题
        
        // Spreadtrum/Unisoc 系列
        "OMX.sprd.h264.decoder",            // Spreadtrum H264 解码器，颜色异常
        "OMX.sprd.h265.decoder",            // Spreadtrum H265 解码器
        
        // Allwinner 系列
        "OMX.allwinner.video.decoder.avc",  // Allwinner AVC 解码器
        
        // 其他有问题的解码器
        "OMX.google.h264.decoder",          // 某些情况下 Google 软解码也可能有问题（设备资源不足时）
        "c2.android.avc.decoder"            // Android Codec2 软解码在某些低端设备上性能问题
    )
}
