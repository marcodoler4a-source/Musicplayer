import Foundation
import AVFoundation
import MediaPlayer
import UIKit
@MainActor final class PlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
 @Published var tracks:[Track]=[]; @Published var favoriteIDs:Set<UUID>=[]; @Published var current:Track?; @Published var isPlaying=false; @Published var time:Double=0; @Published var duration:Double=0; @Published var shuffle=false; @Published var repeatMode:RepeatMode = .off; @Published var speed:Float=1; @Published var sleepMinutes=0; @Published var floatingLyrics=false; @Published var lyricSearchResults:[LRCLIBTrack]=[]; @Published var lyricsSearching=false; @Published var lyricsError:String?
 private var player:AVAudioPlayer?; private var timer:Timer?; private var sleepTimer:Timer?
 init(){ super.init(); configureAudio(); configureRemote() }
 func add(urls: [URL]) {
   Task {
     let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"]
     let audioURLs = urls.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
     let lrcURLs = urls.filter { $0.pathExtension.lowercased() == "lrc" }

     // Read selected LRC files first and index them by filename, e.g. Song.lrc -> "song".
     var lrcByBaseName: [String: String] = [:]
     for lrcURL in lrcURLs {
       let access = lrcURL.startAccessingSecurityScopedResource()
       defer { if access { lrcURL.stopAccessingSecurityScopedResource() } }
       if let raw = try? String(contentsOf: lrcURL, encoding: .utf8) {
         let key = lrcURL.deletingPathExtension().lastPathComponent.lowercased()
         lrcByBaseName[key] = raw
       }
     }

     for sourceURL in audioURLs {
       let access = sourceURL.startAccessingSecurityScopedResource()
       defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }

       let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
       let destination = documents.appendingPathComponent(UUID().uuidString + "-" + sourceURL.lastPathComponent)
       try? FileManager.default.copyItem(at: sourceURL, to: destination)

       var track = await loadTrack(url: destination)
       let audioBaseName = sourceURL.deletingPathExtension().lastPathComponent.lowercased()
       if let rawLRC = lrcByBaseName[audioBaseName] {
         track.lyrics = LRCParser.parse(rawLRC)
       }
       tracks.append(track)
     }
   }
 }

 func isFavorite(_ t:Track)->Bool { favoriteIDs.contains(t.id) }
 func toggleFavorite(_ t:Track){ if favoriteIDs.contains(t.id){ favoriteIDs.remove(t.id) } else { favoriteIDs.insert(t.id) } }
 func applyMusicInfo(to track: Track, info: OnlineMusicInfo, artwork: Data?) {
   guard let i=tracks.firstIndex(where:{$0.id==track.id}) else{return}
   tracks[i].title=info.title; tracks[i].artist=info.artist; tracks[i].album=info.album
   tracks[i].releaseDate=info.releaseDate; tracks[i].genre=info.genre; tracks[i].trackNumber=info.trackNumber
   if let artwork { tracks[i].artworkData=artwork }
   if current?.id==track.id { current=tracks[i]; publish() }
 }
 func setArtwork(for track: Track, data: Data) {
   guard let i=tracks.firstIndex(where:{$0.id==track.id}) else{return}
   tracks[i].artworkData=data
   if current?.id==track.id { current=tracks[i]; publish() }
 }
 func remove(_ t:Track){ tracks.removeAll{$0.id==t.id}; favoriteIDs.remove(t.id); if current?.id==t.id { player?.stop(); current=nil; isPlaying=false } }
 func play(_ t:Track){ current=t; do { player=try AVAudioPlayer(contentsOf:t.url); player?.delegate=self; player?.enableRate=true; player?.rate=speed; player?.prepareToPlay(); duration=player?.duration ?? 0; player?.play(); isPlaying=true; tick(); publish() } catch{} }
 func toggle(){ guard let p=player else { if let t=current ?? tracks.first { play(t) }; return }; if p.isPlaying { p.pause(); isPlaying=false } else { p.play(); isPlaying=true }; publish() }
 func seek(_ v:Double){ player?.currentTime=v; time=v; publish() }
 func next() {
   guard !tracks.isEmpty else { return }

   if repeatMode == .one, let c = current {
     play(c)
     return
   }

   if shuffle {
     if tracks.count == 1 {
       play(tracks[0])
       return
     }
     let choices = tracks.filter { $0.id != current?.id }
     if let randomTrack = choices.randomElement() { play(randomTrack) }
     return
   }

   guard let currentID = current?.id,
         let index = tracks.firstIndex(where: { $0.id == currentID }) else {
     play(tracks[0])
     return
   }

   let nextIndex = index + 1
   if nextIndex < tracks.count {
     play(tracks[nextIndex])
   } else if repeatMode == .all {
     play(tracks[0])
   } else {
     player?.stop()
     player?.currentTime = duration
     time = duration
     isPlaying = false
     publish()
   }
 }

 func previous() {
   guard !tracks.isEmpty else { return }

   if let p = player, p.currentTime > 3 {
     seek(0)
     p.play()
     isPlaying = true
     publish()
     return
   }

   guard let currentID = current?.id,
         let index = tracks.firstIndex(where: { $0.id == currentID }) else {
     play(tracks[0])
     return
   }

   let previousIndex = index - 1
   if previousIndex >= 0 {
     play(tracks[previousIndex])
   } else if repeatMode == .all {
     play(tracks[tracks.count - 1])
   } else {
     play(tracks[0])
   }
 }
 func setRate(_ r:Float){ speed=r; player?.enableRate=true; player?.rate=r }
 func setSleep(_ mins:Int){ sleepMinutes=mins; sleepTimer?.invalidate(); guard mins>0 else{return}; sleepTimer=Timer.scheduledTimer(withTimeInterval:Double(mins*60),repeats:false){[weak self]_ in Task{@MainActor in self?.player?.pause(); self?.isPlaying=false} } }
 func attachLRC(url:URL){ guard var c=current, let s=try? String(contentsOf:url,encoding:.utf8) else{return}; c.lyrics=LRCParser.parse(s); current=c; if let i=tracks.firstIndex(where:{$0.id==c.id}){tracks[i]=c} }
 func searchSyncedLyrics() async { guard let c=current else{return}; lyricsSearching=true; lyricsError=nil; defer{lyricsSearching=false}; do { lyricSearchResults = try await LyricsService.search(title:c.title,artist:c.artist,album:c.album,duration:duration); if lyricSearchResults.isEmpty { lyricsError="No timestamped lyrics found." } } catch { lyricSearchResults=[]; lyricsError="Could not search synced lyrics. Check your internet connection." } }
 func applyLyrics(_ result:LRCLIBTrack){ guard var c=current, let raw=result.syncedLyrics else{return}; let parsed=LRCParser.parse(raw); guard !parsed.isEmpty else{return}; c.lyrics=parsed; current=c; if let i=tracks.firstIndex(where:{$0.id==c.id}){tracks[i]=c} }
 var activeLyric:LyricLine? { current?.lyrics.last(where:{$0.time <= time}) }
 private func tick(){ timer?.invalidate(); timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true){[weak self]_ in Task{@MainActor in guard let self, let p=self.player else{return}; self.time=p.currentTime; self.duration=p.duration } } }
 nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
   Task { @MainActor [weak self] in
     guard let self else { return }
     self.time = self.duration
     self.next()
   }
 }
 private func configureAudio(){ try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.allowAirPlay]); try? AVAudioSession.sharedInstance().setActive(true) }
 private func configureRemote(){ let c=MPRemoteCommandCenter.shared(); c.playCommand.addTarget{[weak self]_ in Task{@MainActor in self?.toggle()}; return .success}; c.pauseCommand.addTarget{[weak self]_ in Task{@MainActor in self?.toggle()}; return .success}; c.nextTrackCommand.addTarget{[weak self]_ in Task{@MainActor in self?.next()}; return .success}; c.previousTrackCommand.addTarget{[weak self]_ in Task{@MainActor in self?.previous()}; return .success} }
 private func publish(){ guard let t=current else{return}; var n:[String:Any]=[MPMediaItemPropertyTitle:t.title,MPMediaItemPropertyArtist:t.artist,MPMediaItemPropertyAlbumTitle:t.album,MPMediaItemPropertyPlaybackDuration:duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:time,MPNowPlayingInfoPropertyPlaybackRate:isPlaying ? speed:0]; if let d=t.artworkData, let im=UIImage(data:d){n[MPMediaItemPropertyArtwork]=MPMediaItemArtwork(boundsSize:im.size){_ in im}}; MPNowPlayingInfoCenter.default().nowPlayingInfo=n }
}
