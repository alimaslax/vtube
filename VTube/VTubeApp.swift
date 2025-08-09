//
//  VTubeApp.swift
//  VTube
//
//  Created by Maslax Ali on 8/9/25.
//

import SwiftUI
import AVFoundation
import MediaPlayer

@main
struct VTubeApp: App {
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    init() {
        configureAudioSession()
        setupBackgroundTask()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    startBackgroundTask()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    endBackgroundTask()
                }
        }
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [
                .allowAirPlay, 
                .allowBluetooth, 
                .allowBluetoothA2DP,
                .mixWithOthers,
                .duckOthers
            ])
            try audioSession.setActive(true)
            
            // Enable remote control events
            UIApplication.shared.beginReceivingRemoteControlEvents()
            
            // Configure Now Playing Info
            setupNowPlayingInfo()
            
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func setupNowPlayingInfo() {
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "VTube"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "YouTube Player"
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
        
        // Setup remote command center
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { _ in
            NotificationCenter.default.post(name: Notification.Name("RemotePlay"), object: nil)
            return .success
        }
        commandCenter.pauseCommand.addTarget { _ in
            NotificationCenter.default.post(name: Notification.Name("RemotePause"), object: nil)
            return .success
        }
    }
    
    private func setupBackgroundTask() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.startBackgroundTask()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            self.endBackgroundTask()
        }
    }
    
    private func startBackgroundTask() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AudioPlayback") {
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
}
