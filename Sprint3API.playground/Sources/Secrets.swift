// Fill these in before running the pages (README steps 1–4).
// Don't push real keys to GitHub: see "Keeping keys out of GitHub" in the README.

public enum Secrets {
    public static let firebase = FirebaseConfig(
        projectID: "YOUR_PROJECT_ID",                         // Project settings → General → Project ID
        webAPIKey: "YOUR_WEB_API_KEY",                        // Project settings → General → Web API Key
        storageBucket: "YOUR_PROJECT_ID.firebasestorage.app"  // Storage → bucket name, or "" to skip uploads
    )

    public static let geminiAPIKey = "YOUR_GEMINI_API_KEY"    // aistudio.google.com → Get API key
    public static let geminiModel = "gemini-3.5-flash-lite"
}
