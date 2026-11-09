package lvt.crm.data.auth

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.InvalidKeyException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * AndroidKeyStore EC secp256r1 signing keys usable only after a strong biometric check
 * (one per alias). A new fingerprint enrolment invalidates them.
 */
class AndroidDeviceKeys : DeviceKeys {
    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    override fun exists(alias: String): Boolean = runCatching { keyStore().containsAlias(alias) }.getOrDefault(false)

    override fun create(alias: String): ByteArray {
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        }
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER)
        generator.initialize(builder.build())
        return generator.generateKeyPair().public.encoded
    }

    override fun signer(alias: String): Signature {
        val key = runCatching { keyStore().getKey(alias, null) as? PrivateKey }.getOrNull()
            ?: throw DeviceKeyInvalidatedException()
        return try {
            Signature.getInstance("SHA256withECDSA").apply { initSign(key) }
        } catch (e: KeyPermanentlyInvalidatedException) {
            throw DeviceKeyInvalidatedException(e)
        } catch (e: InvalidKeyException) {
            throw DeviceKeyInvalidatedException(e)
        }
    }

    override fun delete(alias: String) {
        runCatching { keyStore().deleteEntry(alias) }
    }

    private companion object {
        const val PROVIDER = "AndroidKeyStore"
    }
}

/**
 * Credential id + account email/name of the fingerprint sign-in, in its own encrypted file so
 * signing out (which wipes the token store) keeps it.
 */
class EncryptedDeviceCredentialStore(context: Context) : DeviceCredentialStore {
    private val prefs = EncryptedSharedPreferences.create(
        context,
        "lvt_crm_device_auth",
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    override fun load(): SavedDeviceCredential? = synchronized(this) {
        val credentialId = prefs.getString(KEY_CREDENTIAL, null)?.takeIf { it.isNotBlank() } ?: return null
        val userId = prefs.getString(KEY_USER, null)?.takeIf { it.isNotBlank() } ?: return null
        val alias = prefs.getString(KEY_ALIAS, null)?.takeIf { it.isNotBlank() } ?: return null
        SavedDeviceCredential(
            credentialId = credentialId,
            userId = userId,
            email = prefs.getString(KEY_EMAIL, null).orEmpty(),
            name = prefs.getString(KEY_NAME, null).orEmpty(),
            keyAlias = alias,
        )
    }

    override fun save(credential: SavedDeviceCredential) = synchronized(this) {
        check(
            prefs.edit()
                .putString(KEY_CREDENTIAL, credential.credentialId)
                .putString(KEY_USER, credential.userId)
                .putString(KEY_EMAIL, credential.email)
                .putString(KEY_NAME, credential.name)
                .putString(KEY_ALIAS, credential.keyAlias)
                .commit(),
        ) { "DEVICE_CREDENTIAL_PERSIST_FAILED" }
    }

    override fun clear() = synchronized(this) {
        prefs.edit().clear().commit()
        Unit
    }

    private companion object {
        const val KEY_CREDENTIAL = "credential_id"
        const val KEY_USER = "user_id"
        const val KEY_EMAIL = "email"
        const val KEY_NAME = "name"
        const val KEY_ALIAS = "key_alias"
    }
}
