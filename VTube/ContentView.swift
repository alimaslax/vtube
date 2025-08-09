//
//  ContentView.swift
//  VTube
//
//  Created by Maslax Ali on 8/9/25.
//

import SwiftUI
import WebKit
import AVFoundation
import MediaPlayer
import Combine

struct ContentView: View {
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var webView: WKWebView?
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        YouTubeWebView(
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            isLoading: $isLoading,
            webView: $webView
        )
        .onAppear {
            configureAudioSession()
            setupRemoteControlHandlers()
            setupAppLifecycleObservers()
        }
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [
                .allowAirPlay, 
                .allowBluetooth, 
                .allowBluetoothA2DP,
                .mixWithOthers
            ])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func setupRemoteControlHandlers() {
        NotificationCenter.default.publisher(for: Notification.Name("RemotePlay"))
            .sink { _ in
                webView?.evaluateJavaScript("document.querySelector('video')?.play()")
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: Notification.Name("RemotePause"))
            .sink { _ in
                webView?.evaluateJavaScript("document.querySelector('video')?.pause()")
            }
            .store(in: &cancellables)
    }
    
    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { _ in
                // Keep audio session active when entering background
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("Failed to maintain audio session in background: \(error)")
                }
                
                // Ensure video continues playing in background
                webView?.evaluateJavaScript("""
                    const video = document.querySelector('video');
                    if (video && !video.paused) {
                        video.play().catch(() => {});
                    }
                """)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { _ in
                // Reconfigure audio session when returning to foreground
                configureAudioSession()
            }
            .store(in: &cancellables)
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
        
        // Enable media playback and background audio
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = false
        
        // Configure user content controller for better media handling
        let userController = WKUserContentController()
        config.userContentController = userController
        
        // Add preferences for better media support
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        config.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = true
        
        // Important: Enable background processing
        webView.configuration.processPool = WKProcessPool()
        
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
            
            // Enhanced background playback and ad blocking script
            let enhancementScript = """
                (function() {
                    let lastVideoElement = null;
                    let wasPlayingBeforeHidden = false;
                    
                    // Function to find and setup video element
                    function setupVideoElement() {
                        const video = document.querySelector('video');
                        if (video && video !== lastVideoElement) {
                            lastVideoElement = video;
                            
                            // Remove existing listeners to avoid duplicates
                            video.removeEventListener('pause', handlePause);
                            video.removeEventListener('play', handlePlay);
                            
                            // Add event listeners
                            video.addEventListener('pause', handlePause);
                            video.addEventListener('play', handlePlay);
                            
                            // Ensure video can play in background
                            video.setAttribute('playsinline', 'true');
                            video.setAttribute('webkit-playsinline', 'true');
                        }
                        return video;
                    }
                    
                    function handlePause(event) {
                        // If page is hidden and video was paused, try to resume
                        if (document.hidden && event.target.currentTime > 0) {
                            setTimeout(() => {
                                if (document.hidden && event.target.paused) {
                                    event.target.play().catch(() => {});
                                }
                            }, 100);
                        }
                    }
                    
                    function handlePlay(event) {
                        wasPlayingBeforeHidden = true;
                    }
                    
                    // Handle visibility changes
                    function handleVisibilityChange() {
                        const video = document.querySelector('video');
                        if (video) {
                            if (document.hidden) {
                                wasPlayingBeforeHidden = !video.paused;
                                // Don't pause - let it continue playing
                            } else {
                                // Page became visible again
                                if (wasPlayingBeforeHidden && video.paused) {
                                    video.play().catch(() => {});
                                }
                            }
                        }
                    }
                    
                    // Override YouTube's pause behavior for background
                    const originalPause = HTMLMediaElement.prototype.pause;
                    HTMLMediaElement.prototype.pause = function() {
                        // Only allow pause if page is visible or user explicitly paused
                        if (!document.hidden || this.dataset.userPaused === 'true') {
                            originalPause.call(this);
                        }
                    };
                    
                    // Track user-initiated pauses
                    document.addEventListener('click', function(e) {
                        const video = document.querySelector('video');
                        if (video && e.target.closest('.ytp-play-button')) {
                            video.dataset.userPaused = video.paused ? 'false' : 'true';
                        }
                });
                    
                    // Main interval for ad blocking and video setup
                    setInterval(function() {
                        // Skip video ads
                        const skipButton = document.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, [class*="skip"][class*="button"]');
                        if (skipButton && skipButton.offsetParent !== null) {
                            skipButton.click();
                        }
                        
                        // Hide banner ads
                        const bannerAds = document.querySelectorAll('.ytd-display-ad-renderer, .ytd-promoted-sparkles-web-renderer');
                        bannerAds.forEach(ad => ad.style.display = 'none');
                        
                        // Setup video element if found
                        setupVideoElement();
                        
                        // Ensure video continues in background
                        const video = document.querySelector('video');
                        if (video && document.hidden && video.paused && video.currentTime > 0 && video.dataset.userPaused !== 'true') {
                            video.play().catch(() => {});
                        }
                    }, 1000);
                    
                    // Add visibility change listener
                    document.addEventListener('visibilitychange', handleVisibilityChange);
                    
                    // Prevent YouTube from detecting background state
                    Object.defineProperty(document, 'hidden', {
                        get: function() { return false; },
                        configurable: true
                    });
                    
                    Object.defineProperty(document, 'visibilityState', {
                        get: function() { return 'visible'; },
                        configurable: true
                    });
                })();
            """
            
            webView.evaluateJavaScript(enhancementScript, completionHandler: nil)
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
