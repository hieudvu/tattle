/// Fixed identities the native side and the extensions must agree on.
public enum ExtensionIdentity {
    /// Chromium extension id, derived from the public `key` in
    /// `Extensions/chromium/manifest.json` (the private key lives in
    /// `~/.tattle-secrets`, never in the repo). Native-messaging manifests
    /// allow exactly this origin.
    public static let chromiumID = "bghfplclpgjikclebjcgpojhcpfoflag"
    /// Public key (base64 DER) for the Chromium manifest's `key` field.
    public static let chromiumPublicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApMdY7FChyHNKR9xIQUBaD5z1j98ym4vsqt6KJEFqp6FammKVYHp4I51S/QCVGA5ffo7FkfhelT8+pPoSyMjd4sK9FlpuAaMPzauwtO2mbPvOEIuE100vteIvJspPVhBJNcSCfGkE2YscSSmUQiejUiLw8FdF6LUUZRwoc/pM/7crriJPBIZmGIS2xLo4O2vFYL7jzsuscCjtv+R0JL0Bk2vMsq0gC4uNyP02CPCr7r3B745IPY/o1kl0m7nT+bbG4YJwJsX35kXz0Lm6iUhKHc/Qm9F4dAAjxQsCD4vQ1ILy/X5p1r7oYkxUfPAapSNME8iA9HpU6ZJUni8jT3V0BQIDAQAB"
    public static let firefoxID = "tattle@hieuvd.dev"

    /// Native-messaging host names. Dev and production never share one.
    public static let hostNameProduction = "dev.hieuvd.tattle"
    public static let hostNameDev = "dev.hieuvd.tattle.dev"
}
