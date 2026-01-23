package com.jhomlala.better_player

import android.net.Uri
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DataSpec
import com.google.android.exoplayer2.upstream.DefaultHttpDataSource
import com.google.android.exoplayer2.upstream.ResolvingDataSource

internal object DataSourceUtils {
    private const val USER_AGENT = "User-Agent"
    private const val USER_AGENT_PROPERTY = "http.agent"
    private const val HLS_TOKEN_HEADER = "X-HLS-Token"
    private const val HLS_EXP_HEADER = "X-HLS-Exp"
    private const val HLS_TOKEN_QUERY = "token"
    private const val HLS_EXP_QUERY = "exp"

    object HlsTokenStore {
        @Volatile
        var token: String? = null

        @Volatile
        var exp: String? = null

        fun update(newToken: String?, newExp: String?) {
            token = newToken
            exp = newExp
        }

        fun hasToken(): Boolean {
            return !token.isNullOrBlank() && !exp.isNullOrBlank()
        }
    }

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

    @JvmStatic
    fun getDataSourceFactory(
        userAgent: String?,
        headers: Map<String, String>?
    ): DataSource.Factory {
        val baseFactory: DataSource.Factory = DefaultHttpDataSource.Factory()
            .setUserAgent(userAgent)
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(DefaultHttpDataSource.DEFAULT_CONNECT_TIMEOUT_MILLIS)
            .setReadTimeoutMs(DefaultHttpDataSource.DEFAULT_READ_TIMEOUT_MILLIS)
        if (headers != null) {
            val token = headers[HLS_TOKEN_HEADER]
            val exp = headers[HLS_EXP_HEADER]
            val notNullHeaders = mutableMapOf<String, String>()
            headers.forEach { entry ->
                if (entry.key != HLS_TOKEN_HEADER && entry.key != HLS_EXP_HEADER) {
                    notNullHeaders[entry.key] = entry.value
                }
            }
            (baseFactory as DefaultHttpDataSource.Factory).setDefaultRequestProperties(
                notNullHeaders
            )
            val shouldResolve = HlsTokenStore.hasToken() ||
                (!token.isNullOrBlank() && !exp.isNullOrBlank())
            if (shouldResolve) {
                return ResolvingDataSource.Factory(baseFactory) { dataSpec ->
                    resolveHlsTokenQuery(dataSpec, token, exp)
                }
            }
        }
        return baseFactory
    }

    private fun resolveHlsTokenQuery(
        dataSpec: DataSpec,
        tokenFromHeaders: String?,
        expFromHeaders: String?
    ): DataSpec {
        val token = HlsTokenStore.token ?: tokenFromHeaders
        val exp = HlsTokenStore.exp ?: expFromHeaders
        if (token.isNullOrBlank() || exp.isNullOrBlank()) {
            return dataSpec
        }
        val uri = dataSpec.uri
        if (!isHTTP(uri)) {
            return dataSpec
        }
        val builder = uri.buildUpon().clearQuery()
        val queryNames = uri.queryParameterNames
        for (name in queryNames) {
            if (name == HLS_TOKEN_QUERY || name == HLS_EXP_QUERY) {
                continue
            }
            val values = uri.getQueryParameters(name)
            for (value in values) {
                builder.appendQueryParameter(name, value)
            }
        }
        builder.appendQueryParameter(HLS_TOKEN_QUERY, token)
        builder.appendQueryParameter(HLS_EXP_QUERY, exp)
        val updatedUri = builder.build()
        return dataSpec.buildUpon().setUri(updatedUri).build()
    }

    @JvmStatic
    fun isHTTP(uri: Uri?): Boolean {
        if (uri == null || uri.scheme == null) {
            return false
        }
        val scheme = uri.scheme
        return scheme == "http" || scheme == "https"
    }
}