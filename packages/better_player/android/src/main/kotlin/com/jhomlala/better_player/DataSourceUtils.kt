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
     */
    @JvmStatic
    fun isHTTP(uri: Uri?): Boolean {
        if (uri == null || uri.scheme == null) {
            return false
        }
        val scheme = uri.scheme?.lowercase()
        return scheme == "http" || scheme == "https"
    }

    /**
     * 检查URI是否为RTMP协议
     * 支持rtmp、rtmps、rtmpe、rtmpt等变体
     */
    @JvmStatic
    fun isRTMP(uri: Uri?): Boolean {
        if (uri == null || uri.scheme == null) {
            return false
        }
        val scheme = uri.scheme?.lowercase()
        return scheme == "rtmp" || 
               scheme == "rtmps" || 
               scheme == "rtmpe" || 
               scheme == "rtmpt" ||
               scheme == "rtmpte" ||
               scheme == "rtmpts"
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
     * 根据URI类型自动选择合适的数据源工厂
     * 简化调用代码，自动处理协议检测
     */
    @JvmStatic
    fun getDataSourceFactoryForUri(
        uri: Uri?,
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        return when {
            isRTMP(uri) -> {
                // RTMP流不支持自定义headers和UserAgent
                getRtmpDataSourceFactory()
            }
            isHTTP(uri) -> {
                // HTTP/HTTPS流支持完整配置
                getDataSourceFactory(userAgent, headers)
            }
            else -> {
                // 本地文件或其他协议，使用基础HTTP工厂
                getDataSourceFactory(userAgent, headers)
            }
        }
    }

    /**
     * 检查URI是否支持缓存
     * RTMP流不支持缓存，HTTP流支持缓存
     */
    @JvmStatic
    fun supportsCaching(uri: Uri?): Boolean {
        return isHTTP(uri) // 只有HTTP/HTTPS流支持缓存
    }

    /**
     * 获取协议类型描述字符串
     * 用于日志输出和调试
     */
    @JvmStatic
    fun getProtocolDescription(uri: Uri?): String {
        return when {
            uri == null -> "Unknown"
            isRTMP(uri) -> "RTMP Stream"
            isHTTP(uri) -> "HTTP Stream"
            uri.scheme == "file" -> "Local File"
            else -> "Other (${uri.scheme})"
        }
    }
}
