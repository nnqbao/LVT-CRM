# Add project-specific ProGuard rules here.
-keepattributes *Annotation*
-keepclassmembers class ** {
    @androidx.lifecycle.Keep *;
}

# Credential Manager loads the Play services provider reflectively.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}
