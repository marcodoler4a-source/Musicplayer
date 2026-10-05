import Foundation
import AVFoundation
import MediaPlayer
import UIKit
@MainActor final class PlayerModel: ObservableObject {
 @Published var tracks:[Track]=[]; @Published var current:Track?; @Published var isPlaying=false; @Published var time:Double=0; @Published var duration:Double=0; @Published var shuffle=false; @Published var repeatMode:RepeatMode = .off; @Published var speed:Float=1; @Published var sleepMinutes=0; @Published var floatingLyrics=false; @Published var lyricSearchResults:[LRCLIBTrack]=[]; @Published var lyricsSearching=false; @Published var lyricsError:String?
 private var player:AVAudioPlayer?; private var timer:Timer?; private var sleepTimer:Timer?
 init(){ configureAudio(); configureRemote() }
 func add(urls:[URL]) { Task { for u in urls { let access=u.startAccessingSecurityScopedResource(); defer{if access{u.stopAccessingSecurityScopedResource()}}; let dst=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(UUID().uuidString+"-"+u.lastPathComponent); try? FileManager.default.copyItem(at:u,to:dst); let t=await loadTrack(url:dst); tracks.append(t) } } }
 func play(_ t:Track){ current=t; do { player=try AVAudioPlayer(contentsOf:t.url); player?.enableRate=true; player?.rate=speed; player?.prepareToPlay(); duration=player?.duration ?? 0; player?.play(); isPlaying=true; tick(); publish() } catch{} }
 func toggle(){ guard let p=player else { if let t=current ?? tracks.first { play(t) }; return }; if p.isPlaying { p.pause(); isPlaying=false } else { p.play(); isPlaying=true }; publish() }
 func seek(_ v:Double){ player?.currentTime=v; time=v; publish() }
 func next(){ guard !tracks.isEmpty else{return}; if repeatMode == .one, let c=current { play(c); return }; if shuffle { play(tracks.randomElement()!); return }; let i=current.flatMap{tracks.firstIndex(of:$0)} ?? -1; play(tracks[(i+1)%tracks.count]) }
 func previous(){ guard !tracks.isEmpty else{return}; let i=current.flatMap{tracks.firstIndex(of:$0)} ?? 0; play(tracks[(i-1+tracks.count)%tracks.count]) }
 func setRate(_ r:Float){ speed=r; player?.enableRate=true; player?.rate=r }
 func setSleep(_ mins:Int){ sleepMinutes=mins; sleepTimer?.invalidate(); guard mins>0 else{return}; sleepTimer=Timer.scheduledTimer(withTimeInterval:Double(mins*60),repeats:false){[weak self]_ in Task{@MainActor in self?.player?.pause(); self?.isPlaying=false} } }
 func attachLRC(url:URL){ guard var c=current, let s=try? String(contentsOf:url,encoding:.utf8) else{return}; c.lyrics=LRCParser.parse(s); current=c; if let i=tracks.firstIndex(where:{$0.id==c.id}){tracks[i]=c} }
 func searchSyncedLyrics() async { guard let c=current else{return}; lyricsSearching=true; lyricsError=nil; defer{lyricsSearching=false}; do { lyricSearchResults = try await LyricsService.search(title:c.title,artist:c.artist); if lyricSearchResults.isEmpty { lyricsError="No timestamped lyrics found." } } catch { lyricSearchResults=[]; lyricsError="Could not search synced lyrics. Check your internet connection." } }
 func applyLyrics(_ result:LRCLIBTrack){ guard var c=current, let raw=result.syncedLyrics else{return}; let parsed=LRCParser.parse(raw); guard !parsed.isEmpty else{return}; c.lyrics=parsed; current=c; if let i=tracks.firstIndex(where:{$0.id==c.id}){tracks[i]=c} }
 var activeLyric:LyricLine? { current?.lyrics.last(where:{$0.time <= time}) }
 private func tick(){ timer?.invalidate(); timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true){[weak self]_ in Task{@MainActor in guard let self, let p=self.player else{return}; self.time=p.currentTime; self.duration=p.duration; if !p.isPlaying && self.isPlaying && p.currentTime >= p.duration-0.2 { self.next() } } } }
 private func configureAudio(){ try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.allowAirPlay]); try? AVAudioSession.sharedInstance().setActive(true) }
 private func configureRemote(){ let c=MPRemoteCommandCenter.shared(); c.playCommand.addTarget{[weak self]_ in Task{@MainActor in self?.toggle()}; return .success}; c.pauseCommand.addTarget{[weak self]_ in Task{@MainActor in self?.toggle()}; return .success}; c.nextTrackCommand.addTarget{[weak self]_ in Task{@MainActor in self?.next()}; return .success}; c.previousTrackCommand.addTarget{[weak self]_ in Task{@MainActor in self?.previous()}; return .success} }
 private func publish(){ guard let t=current else{return}; var n:[String:Any]=[MPMediaItemPropertyTitle:t.title,MPMediaItemPropertyArtist:t.artist,MPMediaItemPropertyAlbumTitle:t.album,MPMediaItemPropertyPlaybackDuration:duration,MPNowPlayingInfoPropertyElapsedPlaybackTime:time,MPNowPlayingInfoPropertyPlaybackRate:isPlaying ? speed:0]; if let d=t.artworkData, let im=UIImage(data:d){n[MPMediaItemPropertyArtwork]=MPMediaItemArtwork(boundsSize:im.size){_ in im}}; MPNowPlayingInfoCenter.default().nowPlayingInfo=n }
}
