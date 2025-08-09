//
//  ContentView.swift
//  VTube
//
//  Created by Maslax Ali on 8/9/25.
//

import SwiftUI
import WebKit

struct ContentView: View {
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var webView: WKWebView?
    
    var body: some View {
        YouTubeWebView(
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            isLoading: $isLoading,
            webView: $webView
        )
    }
}

struct YouTubeWebView: UIViewRepresentable {
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var webView: WKWebView?
    
    private let youtubeURL = URL(string: "https://www.youtube.com")!
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Enable media playback
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Store reference to webView
        DispatchQueue.main.async {
            self.webView = webView
        }
        
        // Load YouTube
        let request = URLRequest(url: youtubeURL)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Don't reload - just update state
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: YouTubeWebView
        
        init(_ parent: YouTubeWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            
            let host = url.host?.lowercased() ?? ""
            
            // Allow YouTube, Google authentication, and essential domains
            if host.contains("youtube.com") || host.contains("youtu.be") || 
               host.contains("ytimg.com") || host.contains("ggpht.com") ||
               host.contains("googlevideo.com") || host.contains("gstatic.com") ||
               host.contains("accounts.google.com") || host.contains("myaccount.google.com") ||
               host.contains("signin.google.com") || host.contains("oauth.google.com") ||
               host.contains("googleapis.com") || host.contains("google.com") {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
            
            // Simple ad skipping script
            let adBlockScript = """
                setInterval(function() {
                    // Skip video ads
                    const skipButton = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button');
                    if (skipButton) {
                        skipButton.click();
                    }
                    
                    // Hide banner ads
                    const bannerAds = document.querySelectorAll('.ytd-display-ad-renderer');
                    bannerAds.forEach(ad => ad.style.display = 'none');
                }, 1000);
            """
            
            webView.evaluateJavaScript(adBlockScript, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}

#Preview {
    ContentView()
}
