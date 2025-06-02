package com.jhomlala.better_player

import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.rtmp.RtmpDataSource

/**
 * 数据源工具类，用于处理不同类型的媒体数据源
 * 支持HTTP/HTTPS、RTMP协议和本地文件
 */
internal object DataSourceUtils {
    private const val USER_AGENT = "User-Agent"
    private const val USER_AGENT_PROPERTY = "http.agent"
    
    // 预定义协议常量，避免重复字符串创建
    private val HTTP_SCHEMES = setOf("http", "https")
    private val RTMP_SCHEMES = setOf("rtmp", "rtmps", "rtmpe", "rtmpt", "rtmpte", "rtmpts")

    /**
     * 获取用户代理字符串
     * 优先使用headers中的User-Agent，其次使用系统属性
     */
    @JvmStatic
    fun getUserAgent(headers: Map<String, String>?): String? {
        var userAgent = System.getProperty(USER_AGENT_PROPERTY)
        if (headers != null && headers.containsKey(USER_AGENT)) {
            val userAgentHeader = headers[USER_AGENT]
            if (userAgentHeader != null) {
                userAgent = userAgentHeader
            }
        }
        return userAgent
    }

    /**
     * 创建HTTP数据源工厂
     * 支持自定义User-Agent和请求头
     */
    @JvmStatic
    fun getDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        val dataSourceFactory: DataSource.Factory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS)
            .setReadTimeoutMs(DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS)

        // 设置自定义请求头
        if (headers != null) {
            val notNullHeaders = mutableMapOf<String, String>()
            headers.forEach { entry ->
                entry.value?.let { value ->
                    notNullHeaders[entry.key] = value
                }
            }
            if (notNullHeaders.isNotEmpty()) {
                (dataSourceFactory as DefaultHttpDataSource.Factory).setDefaultRequestProperties(
                    notNullHeaders
                )
            }
        }
        return dataSourceFactory
    }

    /**
     * 检查URI是否为HTTP/HTTPS协议
     * 使用预定义Set提高查找效率
     */
    @JvmStatic
    fun isHTTP(uri: Uri?): Boolean {
        val scheme = uri?.scheme?.lowercase() ?: return false
        return HTTP_SCHEMES.contains(scheme)
    }

    /**
     * 检查URI是否为RTMP协议
     * 支持rtmp、rtmps、rtmpe、rtmpt等变体
     * 使用预定义Set提高查找效率
     */
    @JvmStatic
    fun isRTMP(uri: Uri?): Boolean {
        val scheme = uri?.scheme?.lowercase() ?: return false
        return RTMP_SCHEMES.contains(scheme)
    }

    /**
     * 创建RTMP数据源工厂
     * 专门用于处理RTMP流媒体
     */
    @JvmStatic
    fun getRtmpDataSourceFactory(): DataSource.Factory {
        return RtmpDataSource.Factory()
    }

    /**
     * 批量检测URI协议类型，避免重复计算
     * 用于需要多次判断同一URI协议的场景
     */
    data class ProtocolInfo(
        val isHttp: Boolean,
        val isRtmp: Boolean,
        val scheme: String?
    )

    @JvmStatic
    fun getProtocolInfo(uri: Uri?): ProtocolInfo {
        val scheme = uri?.scheme?.lowercase()
        return ProtocolInfo(
            isHttp = scheme != null && HTTP_SCHEMES.contains(scheme),
            isRtmp = scheme != null && RTMP_SCHEMES.contains(scheme),
            scheme = scheme
        )
    }
}
