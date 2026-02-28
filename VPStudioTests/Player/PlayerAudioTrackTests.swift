import Testing
import Foundation
@preconcurrency import AVFoundation

@MainActor
final class PlayerAudioTrackTests {
    
    // MARK: - VPPlayerEngine Audio Track Tests
    
    @Test
    func audioTrackInitializationHasDefaultValues() {
        let engine = VPPlayerEngine()
        
        #expect(engine.audioTracks.isEmpty)
        #expect(engine.selectedAudioTrack == 0)
    }
    
    @Test
    func selectAudioTrackUpdatesIndex() {
        let engine = VPPlayerEngine()
        
        engine.audioTracks = [
            .init(id: 0, name: "Track 1", language: "en", codec: "aac"),
            .init(id: 1, name: "Track 2", language: "es", codec: "aac"),
            .init(id: 2, name: "Track 3", language: "fr", codec: "aac"),
        ]
        
        engine.selectAudioTrack(2)
        
        #expect(engine.selectedAudioTrack == 2)
    }
    
    @Test
    func selectAudioTrackOutOfBoundsIsIgnored() {
        let engine = VPPlayerEngine()
        
        engine.audioTracks = [
            .init(id: 0, name: "Track 1", language: "en", codec: "aac"),
        ]
        
        // Should be ignored - out of bounds
        engine.selectAudioTrack(5)
        
        #expect(engine.selectedAudioTrack == 0)
    }
    
    @Test
    func audioTrackInfoStoresAllFields() {
        let track = VPPlayerEngine.TrackInfo(
            id: 1,
            name: "English Dolby Atmos",
            language: "en",
            codec: "eac3"
        )
        
        #expect(track.id == 1)
        #expect(track.name == "English Dolby Atmos")
        #expect(track.language == "en")
        #expect(track.codec == "eac3")
    }
    
    // MARK: - Track Selection Edge Cases
    
    @Test
    func selectAudioTrackNegativeIndexIsIgnored() {
        let engine = VPPlayerEngine()
        
        engine.audioTracks = [
            .init(id: 0, name: "Track 1", language: "en", codec: "aac"),
        ]
        
        // Negative index should be ignored
        engine.selectAudioTrack(-1)
        
        #expect(engine.selectedAudioTrack == 0)
    }
}
