// Fill these in before running the pages (README steps 1–4).
// Don't push real keys to GitHub: see "Keeping keys out of GitHub" in the README.

public enum Secrets {
    public static let firebase = FirebaseConfig(
        projectID: "axolotls-d0d4f",                          // Project settings → General → Project ID
        webAPIKey: "YOUR_WEB_API_KEY",                        // Project settings → Your apps → Sprint3 playground → apiKey
        storageBucket: ""                                     // "axolotls-d0d4f.firebasestorage.app" once Storage is on (Blaze plan)
    )

    public static let geminiAPIKey = "YOUR_GEMINI_API_KEY"    // aistudio.google.com → Get API key
    public static let geminiModel = "gemini-3.5-flash-lite"
}
