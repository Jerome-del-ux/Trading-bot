package ai.jetboomer.app
import android.app.Activity
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
class MainActivity: Activity() {
 override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); val w=WebView(this); w.webViewClient=WebViewClient(); w.settings.javaScriptEnabled=true; w.loadUrl("https://jerome-del-ux.github.io/Trading-bot/"); setContentView(w) }
}