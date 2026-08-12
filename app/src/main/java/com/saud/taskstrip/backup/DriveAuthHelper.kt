package com.saud.taskstrip.backup

import android.content.Context
import android.content.Intent
import com.google.android.gms.auth.GoogleAuthUtil
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInAccount
import com.google.android.gms.auth.api.signin.GoogleSignInClient
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Uses the least-privilege `drive.file` scope: the app can only see/manage files *it* creates in
 * Drive, never the user's other files, so this never needs Google's app-verification review.
 */
object DriveAuthHelper {
    private const val SCOPE_DRIVE_FILE = "https://www.googleapis.com/auth/drive.file"

    fun signInClient(context: Context): GoogleSignInClient {
        val options = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestScopes(Scope(SCOPE_DRIVE_FILE))
            .requestEmail()
            .build()
        return GoogleSignIn.getClient(context, options)
    }

    fun signedInAccount(context: Context): GoogleSignInAccount? {
        val account = GoogleSignIn.getLastSignedInAccount(context) ?: return null
        val hasScope = GoogleSignIn.hasPermissions(account, Scope(SCOPE_DRIVE_FILE))
        return if (hasScope) account else null
    }

    fun signInIntent(context: Context): Intent = signInClient(context).signInIntent

    fun accountFromSignInResult(context: Context, data: Intent?): GoogleSignInAccount? {
        return try {
            GoogleSignIn.getSignedInAccountFromIntent(data).result
        } catch (e: Exception) {
            null
        }
    }

    /** Blocking token fetch — always call from a background dispatcher. */
    suspend fun getAccessToken(context: Context, account: GoogleSignInAccount): String? =
        withContext(Dispatchers.IO) {
            try {
                GoogleAuthUtil.getToken(context, account.account!!, "oauth2:$SCOPE_DRIVE_FILE")
            } catch (e: Exception) {
                null
            }
        }

    fun signOut(context: Context) {
        signInClient(context).signOut()
    }
}
