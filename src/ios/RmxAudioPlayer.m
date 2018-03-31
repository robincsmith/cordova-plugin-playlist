
#import "RmxAudioPlayer.h"
#import "AVBidirectionalQueuePlayer.h"

static char kAvQueuePlayerContext;
static char kAvQueuePlayerRateContext;
static char kPlayerItemStatusContext;
static char kPlayerItemDurationContext;
static char kPlayerItemTimeRangesContext;

@implementation RmxAudioPlayer {
  id _playbackTimeObserver;
  BOOL _wasPlayingInterrupted;
  BOOL _commandCenterRegistered;
  NSMutableDictionary* _updatedNowPlayingInfo;
  float _rate;
  float _volume;
}
@property () NSString* statusCallbackId;
@property (nonatomic, strong) AVBidirectionalQueuePlayer* avQueuePlayer;
@property (nonatomic) NSMutableArray* currentItems;
@property (nonatomic) NSUInteger* currentIndex;
@property () float rate;
@property () float volume;
@property (nonatomic) BOOL isAtEnd;
@property (nonatomic) BOOL isAtBeginning;
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) float estimatedDuration;
@property (nonatomic) float queuePosition;
@end


- (void) pluginInitialize
{
    _playbackTimeObserver = nil;
    _wasPlayingInterrupted = NO;
    _commandCenterRegistered = NO;
    _updatedNowPlayingInfo = nil;
    self.rate = 1.0f;
    self.volume = 0.5f;

    [self activateAudioSession];
    [self observeLifeCycle];
}


#pragma mark - Cordova interface

/**
 *
 * Cordova interface
 *
 * These are basically just passing through to the core functionality of the queue and this player.
 *
 * These functions don't really do anything interesting by themselves.
 *
 *
 *
 *
 *
 */

- (void) setPlaylistItems:(CDVInvokedUrlCommand *) command {
  NSMutableArray* items = [command.arguments objectAtIndex:0];

  [self insertOrReplaceTracks:items replace:YES];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) addItem:(CDVInvokedUrlCommand *) command {
  NSMutableDictionary* item = [command.arguments objectAtIndex:0];
  AudioTrack* newTrack = [AudioTrack initWithDictionary:item];
  if (newTrack) {
    [self addTracks:@[newTrack]];
  }

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) addAllItems:(CDVInvokedUrlCommand *) command {
  NSMutableArray* items = [command.arguments objectAtIndex:0];

  [self insertOrReplaceTracks:items replace:NO];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) removeItems:(CDVInvokedUrlCommand *) command {
  NSMutableArray* items = [command.arguments objectAtIndex:0];
  int removed = 0;

  if (items != nil || items.count > 0) {
    for (NSDictionary *item in items) {
        NSInteger *trackIndex = [item objectForKey:@"trackIndex"];
        NSString *trackId = [item objectForKey:@"trackId"];

        if ([self removeItem:trackIndex trackId:trackId]) {
          removed++;
        }
    }
  }

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:removed];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) removeItem:(CDVInvokedUrlCommand *) command {
  NSInteger* trackIndex = [command.arguments objectAtIndex:0];
  NSString* trackId = [command.arguments objectAtIndex:1];

  BOOL result = [self removeItem:trackIndex trackId:trackId];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:result];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) clearAllItems:(CDVInvokedUrlCommand*) command {
  [self removeAllTracks:NO];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) play:(CDVInvokedUrlCommand *) command {
  [self play:NO];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) playTrackByIndex:(CDVInvokedUrlCommand *) command {
  NSNumber* argVal = [command argumentAtIndex:0 withDefault:[NSNumber numberWithInt:0]];
  int index = argVal.intValue;

  if (index < 0 || index >= [self avQueuePlayer].itemsForPlayer.count) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Provided index is out of bounds"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  } else {
    [self avQueuePlayer].currentIndex = argVal.intValue;
    [self play:NO];
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  }
}


- (void) playTrackById:(CDVInvokedUrlCommand *) command {
  NSString* trackId = [command.arguments objectAtIndex:0];

  NSDictionary* result = [self findTrackById:trackId];
  NSInteger* idx = result[@"index"];
  AudioTrack* track = result[@"track"];

  if ([self avQueuePlayer].itemsForPlayer.count > 0) {
      if (idx >= 0) {
        [self avQueuePlayer].currentIndex = idx;
        [self play:NO];
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:indexes.firstIndex];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      } else {
        CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Track ID not found"];
        [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
      }
  } else {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"The playlist is empty!"];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  }
}


- (void) pause:(CDVInvokedUrlCommand *) command {
  [self pause:NO];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) skipForward:(CDVInvokedUrlCommand *) command {
  [self playNext:NO];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) skipBack:(CDVInvokedUrlCommand *) command {
  [self playPrevious:NO];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) seekTo:(CDVInvokedUrlCommand *) command {
  NSNumber* argVal = [command argumentAtIndex:0 withDefault:[NSNumber numberWithFloat:0.0]];
  float positionTime = argVal.floatValue;
  [self seekTo:positionTime isCommand:YES];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) seekToQueuePosition:(CDVInvokedUrlCommand *) command {
  //
  NSNumber* argVal = [command argumentAtIndex:0 withDefault:[NSNumber numberWithFloat:0.0]];
  float positionTime = argVal.floatValue;

  [[self avQueuePlayer] seekToTimeInQueue:CMTimeMakeWithSeconds(positionTime, NSEC_PER_SEC) completionHandler:^(BOOL complete) {
    // I guess we could check if the seek actually succeeded.
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
  }];
}


- (void) setPlaybackRate:(CDVInvokedUrlCommand *) command {
  NSNumber* argVal = [command argumentAtIndex:0 withDefault:[NSNumber numberWithFloat:1.0]];
  self.rate = argVal.floatValue;

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) setPlaybackVolume:(CDVInvokedUrlCommand *) command {
  NSNumber* argVal = [command argumentAtIndex:0 withDefault:[NSNumber numberWithFloat:self.volume]];
  self.volume = argVal.floatValue;

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) getPlaybackRate:(CDVInvokedUrlCommand *) command {
  float rate = self.rate;

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:rate];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) getPlaybackVolume:(CDVInvokedUrlCommand *) command {
  float volume = self.volume;

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:volume];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) getPlaybackPosition:(CDVInvokedUrlCommand *) command {
  float currentPosition = [self getTrackCurrentTime:nil];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:currentPosition];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) getCurrentBuffer:(CDVInvokedUrlCommand *) command {
  NSDictionary* trackStatus = [self getPlayerStatusItem:nil];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:trackStatus];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) getTotalDuration:(CDVInvokedUrlCommand *) command {
  float duration = self.estimatedDuration;

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:duration];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) getQueuePosition:(CDVInvokedUrlCommand *) command {
  float position = self.queuePosition;

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:position];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


- (void) release:(CDVInvokedUrlCommand*)command {
  [self releaseResources];

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
  [self.commandDelegate sendPluginResult:result callbackId:command.callbackId];
}


/* ****** */
/* Utilities for the above functions */

- (void) insertOrReplaceTracks:(NSArray*)tracks replace:(BOOL)replace {
  if (items == nil || items.count == 0) {
    return;
  }

  NSMutableArray* newList = [NSMutableArray arrayWithCapacity:items.count];
  for (NSDictionary *item in items) {
    AudioTrack* track = [AudioTrack initWithDictionary:item];
    if (track) {
      [newList addObject:track];
    }
  }

  if (replace) {
    [self setTracks:newList];
  } else {
    [self addTracks:newList];
  }
}

- (BOOL) removeItem:(NSInteger*)trackIndex trackId:(NSString*)trackId {
  if (trackIndex != nil && trackIndex > 0 && trackIndex < [self avQueuePlayer].itemsForPlayer.count) {
    (AudioPlayer*) item = [self avQueuePlayer].itemsForPlayer[trackIndex];
    [[self avQueuePlayer] removeItem:item];
    return YES;
  } else if (trackId != nil && ![trackId isEqualToString:@""]) {
    NSDictionary* result = [self findTrackById:trackId];
    NSInteger* idx = result[@"index"];
    AudioTrack* track = result[@"track"];

    if (idx >= 0) {
      (AudioPlayer*) item = [self avQueuePlayer].itemsForPlayer[idx];
      [[self avQueuePlayer] removeItem:item];
      return YES;
    } else {
      return NO;
    }
  } else {
    return NO;
  }
}


#pragma mark - player actions

/**
 *
 * Player actions.
 *
 * These are the public API for the player and wrap most of the complexity of the queue.
 *
 *
 *
 *
 *
 *
 *
 */

- (void) play:(BOOL)isCommand
{
    _wasPlayingInterrupted = NO;
    [self initializeMPCommandCenter];
    // [[self avQueuePlayer] play];
    [self avQueuePlayer].rate = self.rate;
    [self avQueuePlayer].volume = self.volume;

    if (isCommand) {
        NSString * action = @"music-controls-play";
        NSLog(@"%@", action);
    }
}

- (void) pause:(BOOL)isCommand
{
    _wasPlayingInterrupted = NO;
    [self initializeMPCommandCenter];
    [[self avQueuePlayer] pause];

    if (isCommand) {
        NSString * action = @"music-controls-pause";
        NSLog(@"%@", action);
    }
}

- (void) playPrevious:(BOOL)isCommand
{
    _wasPlayingInterrupted = NO;
    [self initializeMPCommandCenter];

    [[self avQueuePlayer] playPreviousItem];

    if (isCommand) {
        NSString * action = @"music-controls-previous";
        NSLog(@"%@", action);

        AudioTrack* playerItem = [self avQueuePlayer].currentItem;
        NSDictionary* param = @{
          @"currentIndex": [self avQueuePlayer].currentIndex,
          @"currentItem": playerItem
        };
        [self onStatus:RMX_STATUS_SKIP_BACK trackId:playerItem.trackId param:param];
    }
}

- (void) playNext:(BOOL)isCommand
{
    _wasPlayingInterrupted = NO;
    [self initializeMPCommandCenter];

    [[self avQueuePlayer] advanceToNextItem];

    if (isCommand) {
        NSString * action = @"music-controls-next";
        NSLog(@"%@", action);

        AudioTrack* playerItem = [self avQueuePlayer].currentItem;
        NSDictionary* param = @{
          @"currentIndex": [self avQueuePlayer].currentIndex,
          @"currentItem": playerItem
        };
        [self onStatus:RMX_STATUS_SKIP_FORWARD trackId:playerItem.trackId param:param];
    }
}

- (void) seekTo:(float)positionTime isCommand:(BOOL)isCommand
{
    //Handle seeking with the progress slider on lockscreen or control center
    _wasPlayingInterrupted = NO;
    [self initializeMPCommandCenter];

    CMTime seekToTime = CMTimeMakeWithSeconds(positionTime, 1000);
    [[self avQueuePlayer] seekToTime:seekToTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];

    NSString * action = @"music-controls-seek-to";
    NSLog(@"%@ %.3f", action, positionTime);

    if (isCommand) {
        AudioPlayer* playerItem = (AudioPlayer *)[self avQueuePlayer].currentItem;
        [self onStatus:RMXSTATUS_SEEK trackId:playerItem.trackId param:@{@"position": @(positionTime)}];
    }
}

- (float) rate
{
    return _rate;
}

- (void) setRate:(float)rate
{
    _rate = rate;
    [self avQueuePlayer].rate = rate;
}

- (float) volume
{
    return _volume;
}

- (void) setVolume:(float)volume
{
    _volume = volume;
    [self avQueuePlayer].volume = volume;
}

- (void) addTracks:(NSArray<AudioPlayer*>*)tracks
{
  for (AudioPlayer* playerItem in tracks) {
    [self addTrackObservers:playerItem];
  }

  [[self avQueuePlayer] insertAllItems:tracks];
}

- (void) setTracks:(NSArray<AudioPlayer*>*)tracks
{
  for (AudioPlayer* playerItem in tracks) {
    [self addTrackObservers:playerItem];
  }

  for (AudioTrack* item in [self avQueuePlayer].itemsForPlayer) {
      [self removeTrackObservers:item];
  }

  [[self avQueuePlayer] setItemsForPlayer:tracks];
}

- (void) removeAllTracks:(BOOL)isCommand
{
    for (AudioTrack* item in [self avQueuePlayer].itemsForPlayer) {
      [self removeTrackObservers:item];
    }

    [[self avQueuePlayer] removeAllItems];
    _wasPlayingInterrupted = NO;

    // a.t.m there's no way for this to be triggered from within the plugin,
    // but it might get added at some point.
    if (isCommand) {
        NSString * action = @"music-controls-clear";
        NSLog(@"%@", action);
        [self onStatus:RMXSTATUS_PLAYLIST_CLEARED trackId:@"INVALID" param:nil];
    }
}


#pragma mark - remote control events

/**
 *
 * Events - receive events from the iOS remote controls and command center.
 *
 *
 *
 *
 *
 *
 *
 *
 */

- (void) playEvent:(MPRemoteCommandEvent *)event {
    [self play:YES];
}

- (void) pauseEvent:(MPRemoteCommandEvent *)event {
    [self pause:YES];
}

- (void) togglePlayPauseTrackEvent:(MPRemoteCommandEvent *)event {
    if ([self avQueuePlayer].isPlaying) {
        [self pause:YES];
    } else {
        [self play:YES];
    }
}

- (void) prevTrackEvent:(MPRemoteCommandEvent *)event {
    [self playPrevious:YES];
}

- (void) nextTrackEvent:(MPRemoteCommandEvent *)event {
    [self playNext:YES];
}

- (MPRemoteCommandHandlerStatus) changedThumbSliderOnLockScreen:(MPChangePlaybackPositionCommandEvent *)event {
    [self seekTo:event.positionTime isCommand:YES];
    return MPRemoteCommandHandlerStatusSuccess;
}


#pragma mark - notifications

/**
 *
 * Notifications
 *
 * These handle the events raised by the queue and the player items.
 *
 *
 *
 *
 *
 *
 *
 */

- (void) itemStalledPlaying:(NSNotification *) notification {
    // This happens when the network is insufficient to continue playback.
    NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];
    [self onStatus:RMXSTATUS_STALLED trackId:playerItem.trackId param:trackStatus];
    [self onStatus:RMXSTATUS_PAUSE trackId:playerItem.trackId param:trackStatus];
}

- (void) playerItemDidReachEnd:(NSNotification *) notification {
    NSLog(@"Player item reached end: %@", notification.object);
    AudioTrack* playerItem = (AudioTrack*)notification.object;
    // When an item finishes, immediately scrub it back to the beginning
    // so that the visual indicators show you can "play again" or whatever.
    // Might make sense to have a flag for this behavior.
    [playerItem seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];

    NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];
    [self onStatus:RMXSTATUS_COMPLETED trackId:playerItem.trackId param:trackStatus];
}

- (void) handleAudioSessionInterruption:(NSNotification*)interruptionNotification
{
    NSLog(@"Audio session interruption received: %@", interruptionNotification);

    NSDictionary* userInfo = interruptionNotification.userInfo;
    AVAudioSessionInterruptionType interruptionType = [userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    switch (interruptionType) {
        case AVAudioSessionInterruptionTypeBegan: {
            BOOL suspended = [userInfo[AVAudioSessionInterruptionWasSuspendedKey] boolValue];
            NSLog(@"AVAudioSessionInterruptionTypeBegan. Was suspended: %d", suspended);
            if ([[self avQueuePlayer] isPlaying]) {
                _wasPlayingInterrupted = YES;
            }

            [[self avQueuePlayer] pause];
            break;
        }
        case AVAudioSessionInterruptionTypeEnded: {
            NSLog(@"AVAudioSessionInterruptionTypeEnded");
            AVAudioSessionInterruptionOptions interruptionOption = [userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
            if (interruptionOption == AVAudioSessionInterruptionOptionShouldResume) {
                if (_wasPlayingInterrupted) {
                    [[self avQueuePlayer] play];
                }
            }
            _wasPlayingInterrupted = NO;
            break;
        }
        default:
            break;
    }
}

/*
 * This method only executes while the queue is playing, so we can use the playback position event.
 */
- (void) executePeriodicUpdate:(CMTime)time {
    AudioTrack *playerItem = (AudioTrack *)[[self avQueuePlayer] currentItem];

    if (!CMTIME_IS_INDEFINITE(playerItem.currentTime)) {
        [self updateNowPlayingTrackInfo:playerItem updateTrackData:NO];

        NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];
        [self onStatus:RMXSTATUS_PLAYBACK_POSITION trackId:playerItem.trackId param:trackStatus];
        // NSLog(@" . %.5f / %.5f sec (%.1f %%) [%@]", currentTime, duration, (currentTime / duration)*100.0, name);
    }

    return;
}


- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"currentItem"] && context == &kAvQueuePlayerContext)
    {
        AudioTrack *item = ((AVBidirectionalQueuePlayer *)object).currentItem;
        [self handlePlayerCurrentItemChanged:item];
        return;
    }

    if ([keyPath isEqualToString:@"rate"] && context == &kAvQueuePlayerRateContext)
    {
        AVBidirectionalQueuePlayer *player = (AVBidirectionalQueuePlayer *)object;
        AudioTrack *playerItem = (AudioTrack *)player.currentItem;
        NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];
        NSLog(@"Playback rate changed: %f, is playing: %d", player.rate, player.isPlaying);

        if (player.isPlaying) {
          [self onStatus:RMXSTATUS_PLAYING trackId:playerItem.trackId param:trackStatus];
        } else {
          [self onStatus:RMXSTATUS_PAUSE trackId:playerItem.trackId param:trackStatus];
        }
        return;
    }

    if ([keyPath isEqualToString:@"status"] && context == &kPlayerItemStatusContext)
    {
        AudioTrack *playerItem = (AudioTrack *)object;
        [self handleTrackStatusEvent:playerItem];
        return;
    }

    if ([keyPath isEqualToString:@"duration"] && context == &kPlayerItemDurationContext)
    {
        AudioTrack *playerItem = (AudioTrack *)object;
        [self handleTrackDuration:playerItem];
        return;
    }

    if ([keyPath isEqualToString:@"loadedTimeRanges"] && context == &kPlayerItemTimeRangesContext)
    {
        AudioTrack *playerItem = (AudioTrack *)object;
        [self handleTrackBuffering:playerItem];
        return;
    }

    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
}


- (void) updateNowPlayingTrackInfo:(AVPlayerItem*)playerItem updateTrackData:(BOOL)updateTrackData
{
    AVPlayerItem* currentItem = playerItem;
    if (currentItem == nil) {
        currentItem = [[self avQueuePlayer] currentItem];
    }

    MPNowPlayingInfoCenter* nowPlayingInfoCenter =  [MPNowPlayingInfoCenter defaultCenter];
    if (_updatedNowPlayingInfo == nil) {
        NSDictionary* nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo;
        _updatedNowPlayingInfo = [NSMutableDictionary dictionaryWithDictionary:nowPlayingInfo];
    }

    for (NSString* val in _updatedNowPlayingInfo.allKeys) {
        NSLog(@"%@ ]] %@", val, _updatedNowPlayingInfo[val]);
    }

    float currentTime = CMTimeGetSeconds(currentItem.currentTime);
    float duration = CMTimeGetSeconds(currentItem.duration);

    if (updateTrackData) {
        _updatedNowPlayingInfo[MPMediaItemPropertyArtist] = @"Linkin Park";
        _updatedNowPlayingInfo[MPMediaItemPropertyTitle] = @"Numb";
        _updatedNowPlayingInfo[MPMediaItemPropertyAlbumTitle] = @"Hot Fuss";
    }

    _updatedNowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = [NSNumber numberWithFloat:duration];
    _updatedNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = [NSNumber numberWithFloat:currentTime];
    _updatedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = [NSNumber numberWithFloat:1.0];

    nowPlayingInfoCenter.nowPlayingInfo = _updatedNowPlayingInfo;
}

- (void) handlePlayerCurrentItemChanged:(AudioTrack*)playerItem
{
    NSLog(@"Queue changed current item to: %@", playerItem);
    // NSLog(@"New music name: %@", ((AVURLAsset*)playerItem.asset).URL.pathComponents.lastObject);
    NSLog(@"New item ID: %@", playerItem.trackId);
    NSLog(@"Queue is at end: %@", self.isAtEnd ? @"YES" : @"NO");

    // When an item starts, immediately scrub it back to the beginning
    [playerItem seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:nil];
    // Update the command center
    [self updateNowPlayingTrackInfo:playerItem updateTrackData:YES];

    NSDictionary* info = @{
      @"currentItem": playerItem,
      @"currentIndex": self.currentIndex,
      @"isAtEnd": self.isAtEnd,
      @"isAtBeginning": self.isAtBeginning
    };
    [self onStatus:RMXSTATUS_TRACK_CHANGED trackId:playerItem.trackId param:info];

    if ([[self avQueuePlayer] isAtEnd]) {
        [[self avQueuePlayer] seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];

        [self onStatus:RMXSTATUS_PLAYLIST_COMPLETED trackId:@"INVALID" param:nil];

        if (self.loop) {
            [[self avQueuePlayer] play];
        }
    }
}


- (void) handleTrackStatusEvent:(AudioTrack*)playerItem
{
    NSString* name = ((AVURLAsset*)playerItem.asset).URL.pathComponents.lastObject;
    AVPlayerItemStatus status = playerItem.status;

    // Switch over the status
    switch (status) {
        case AVPlayerItemStatusReadyToPlay: {
            NSLog(@"PlayerItem status changed to AVPlayerItemStatusReadyToPlay [%@]", name);
            NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];
            [self onStatus:RMXSTATUS_CANPLAY trackId:playerItem.trackId param:trackStatus];
            break;
        }
        case AVPlayerItemStatusFailed: {
            // Failed. Examine AVPlayerItem.error
            NSString* errorMsg = @"";
            if (playerItem.error) {
                errorMsg = [NSString stringWithFormat:@"Error playing audio track: %@", [playerItem.error localizedFailureReason]];
            }
            NSLog(@"AVPlayerItemStatusFailed: Error playing audio track: %@", errorMsg);
            NSDictionary* errorParam = [self createErrorWithCode:RMXERR_DECODE message:errorMsg];
            [self onStatus:RMXSTATUS_ERROR trackId:playerItem.trackId param:errorMsg];
            break;
        }
        case AVPlayerItemStatusUnknown:
            NSLog(@"PlayerItem status changed to AVPlayerItemStatusUnknown [%@]", name);
            // Not ready
            break;
        default:
            break;
    }
}

- (void) handleTrackDuration:(AudioTrack*)playerItem
{
  // This function isn't all that useful really in terms of state management.
  // It doesn't always fire, and it is not needed because the queue's periodic update can also
  // deliver this info.
  NSString* name = ((AVURLAsset*)playerItem.asset).URL.pathComponents.lastObject;
  if (!CMTIME_IS_INDEFINITE(playerItem.duration)) {
      float duration = CMTimeGetSeconds(playerItem.duration);
      NSLog(@"The track duration was changed [%@]: %f", name, duration);

      // We will still report the duration though.
      NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];
      [self onStatus:RMXSTATUS_DURATION trackId:playerItem.trackId param:trackStatus];
  } else {
      NSLog(@"Item duration is indefinite (unknown): %@", ((AVURLAsset*)playerItem.asset).URL);
  }
}

- (void) handleTrackBuffering:(AudioTrack*)playerItem
{
  NSString* name = ((AVURLAsset*)playerItem.asset).URL.pathComponents.lastObject;
  NSDictionary* trackStatus = [self getPlayerStatusItem:playerItem];

  NSLog(@" . . . %.5f -> %.5f (%.1f %%) [%@]",
        [trackStatus[@"bufferStart"] floatValue],
        [trackStatus[@"bufferStart"] floatValue] + [trackStatus[@"bufferEnd"] floatValue],
        [trackStatus[@"bufferPercent"] floatValue], name);

  [self onStatus:RMXSTATUS_BUFFERING trackId:playerItem.trackId param:trackStatus];

  if ([trackStatus[@"bufferPercent"] floatValue] >= 100.0) {
    [self onStatus:RMXSTATUS_LOADED trackId:playerItem.trackId param:trackStatus];
  }
}


/**
 *
 * Status utilities
 *
 * These provide the statis objects and data for the player items when they update.
 *
 * It is largely this data that is actually reported to the consumers.
 *
 *
 *
 *
 *
 */

- (NSDictionary*) getPlayerStatusItem:(AudioTrack*)playerItem
{
    AudioTrack* currentItem = playerItem;
    if (currentItem == nil) {
      currentItem = [self avQueuePlayer].currentItem;
    }

    NSString* status = @"";
    if (currentItem.status == AVPlayerItemStatusReadyToPlay) {
        status = @"ready";
    } else if (currentItem.status == AVPlayerItemStatusFailed) {
        status = @"error";
    } else {
        status = @"unknown";
    }

    if ([self avQueuePlayer].currentItem == currentItem) {
        if ([self avQueuePlayer].rate != 0.0f) {
            status = @"playing";

            if (position <= 0 && [bufferInfo[@"bufferPercent"] floatValue] == 0) {
                status = @"loading";
            }
        } else {
            status = @"paused";
        }
    }

    NSDictionary* bufferInfo = [self getTrackBufferInfo:currentItem];
    float position = [self getTrackCurrentTime:currentItem];
    float playbackPercent = (position / [bufferInfo[@"bufferPercent"] floatValue]) * 100.0;

    NSDictionary *info = @{
        @"status": status,
        @"currentPosition": @(position),
        @"duration": bufferInfo[@"duration"],
        @"playbackPercent": @(playbackPercent),
        @"bufferPercent": bufferInfo[@"bufferPercent"],
        @"bufferStart": bufferInfo[@"start"],
        @"bufferEnd": bufferInfo[@"end"]
    };
    return info;
}

- (float) getTrackCurrentTime:(AudioTrack*)playerItem
{
    AudioTrack* currentItem = playerItem;
    if (currentItem == nil) {
      currentItem = [self avQueuePlayer].currentItem;
    }

    if (!CMTIME_IS_INDEFINITE(currentItem.currentTime)) {
        return CMTimeGetSeconds(currentItem.currentTime);
    } else {
        return 0.0f;
    }
}

- (NSDictionary*) getTrackBufferInfo:(AudioTrack*)playerItem
{
  if (!CMTIME_IS_INDEFINITE(playerItem.duration)) {
      float duration = CMTimeGetSeconds(playerItem.duration);
      NSArray *timeRanges = [playerItem loadedTimeRanges];
      if (timeRanges && [timeRanges count]) {
          CMTimeRange timerange = [[timeRanges objectAtIndex:0] CMTimeRangeValue];
          float start = CMTimeGetSeconds(timerange.start);
          float rangeEnd = CMTimeGetSeconds(timerange.duration);
          float bufferPercent = (rangeEnd / duration) * 100.0;

          NSDictionary* bufferInfo = @{
            @"start": @(start),
            @"end": @(rangeEnd),
            @"bufferPercent": @(bufferPercent),
            @"duration": @(duration)
          };
          return bufferInfo;
      } else {
        NSDictionary* bufferInfo = @{@"start": @0.0, @"end": @0.0, @"bufferPercent": @0.0, @"duration": @(duration)};
        return bufferInfo;
      }
  }

  NSDictionary* bufferInfo = @{@"start": @0.0, @"end": @0.0, @"bufferPercent": @0.0, @"duration": @0.0};
  return bufferInfo;
}


#pragma mark - plugin initialization

/**
 *
 * Object initialization. Mostly boring plumbing to initialize the objects and wire everything up.
 *
 *
 *
 *
 *
 *
 *
 *
 */

- (void) initializeMPCommandCenter
{
  if (!_commandCenterRegistered) {
    [self.viewController becomeFirstResponder]; // supposedly this is no longer necessary.

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand setEnabled:true];
    [commandCenter.playCommand addTarget:self action:@selector(playEvent:)];
    [commandCenter.pauseCommand setEnabled:true];
    [commandCenter.pauseCommand addTarget:self action:@selector(pauseEvent:)];
    [commandCenter.nextTrackCommand setEnabled:true];
    [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrackEvent:)];
    [commandCenter.previousTrackCommand setEnabled:true];
    [commandCenter.previousTrackCommand addTarget:self action:@selector(prevTrackEvent:)];
    [commandCenter.togglePlayPauseCommand setEnabled:true];
    [commandCenter.togglePlayPauseCommand addTarget:self action:@selector(togglePlayPauseTrackEvent:)];

    if (@available(iOS 9.0, *)) {
        [commandCenter.changePlaybackPositionCommand setEnabled:true];
        [commandCenter.changePlaybackPositionCommand addTarget:self action:@selector(changedThumbSliderOnLockScreen:)];
    }

    _commandCenterRegistered = YES;
  }
}

- (NSMutableArray*) currentItems
{
    return [self avQueuePlayer].itemsForPlayer;
}

- (NSUInteger*) currentIndex {
  return [self avQueuePlayer].currentIndex;
}

- (BOOL) isAtEnd {
  return [self avQueuePlayer].isAtEnd;
}

- (BOOL) isAtBeginning {
  return [self avQueuePlayer].isAtBeginning;
}

- (BOOL) isPlaying {
  return [self avQueuePlayer].isPlaying;
}

- (float) estimatedDuration {
    return CMTimeGetSeconds([self avQueuePlayer].estimatedTotalDuration);
}

- (float) queuePosition {
    return CMTimeGetSeconds([self avQueuePlayer].currentTimeOffsetInQueue);
}

- (AVBidirectionalQueuePlayer *) avQueuePlayer
{
    if (!_avQueuePlayer) {
        NSArray* queue = @[];

        _avQueuePlayer = [[AVBidirectionalQueuePlayer alloc] initWithItems:queue];
        _avQueuePlayer.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;
        [_avQueuePlayer addObserver:self forKeyPath:@"currentItem" options:NSKeyValueObservingOptionNew context:&kAvQueuePlayerContext];
        [_avQueuePlayer addObserver:self forKeyPath:@"rate" options:options context:&kAvQueuePlayerRateContext];

        CMTime interval = CMTimeMakeWithSeconds(1.0, NSEC_PER_SEC);
         __weak typeof(self) weakSelf = self;
        dispatch_queue_t mainQueue = dispatch_get_main_queue();
        _playbackTimeObserver = [_avQueuePlayer addPeriodicTimeObserverForInterval:interval queue:mainQueue usingBlock:^(CMTime time) {
            __strong typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf executePeriodicUpdate:time];
            }
        }];

        // Put this behind a flag.
        _avQueuePlayer.automaticallyWaitsToMinimizeStalling = NO;
    }

    return _avQueuePlayer;
}

- (NSDictionary*) findTrackById:(NSString*)trackId {
  NSInteger idx = NSNotFound;
  AudioTrack* track = nil;

  if ([self avQueuePlayer].itemsForPlayer.count > 0) {
      NSMutableArray* arr = [self avQueuePlayer].itemsForPlayer;
      NSIndexSet *indexes = [arr indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
          return [((AudioTrack *)obj).trackId isEqualToString:trackId];
      }];

      if (indexes.count > 0) {
        idx = indexes.firstIndex;
        track = (AudioPlayer*)arr[idx];
      }
  }

  return @{
    @"track": track,
    @"index": idx,
  };
}

- (void) addTrackObservers(AudioTrack*)playerItem
{
  NSKeyValueObservingOptions options = NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew;
  [playerItem addObserver:self forKeyPath:@"status" options:options context:&kPlayerItemStatusContext];
  [playerItem addObserver:self forKeyPath:@"duration" options:options context:&kPlayerItemDurationContext];
  [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:options context:&kPlayerItemTimeRangesContext];

  // We don't need this one because we get the currentItem notification from the queue.
  // But we will wire it up anyway...
  NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];
  [listener addObserver:self selector:@selector(playerItemDidReachEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
  // Subscribe to the AVPlayerItem's PlaybackStalledNotification notification.
  [listener addObserver:self selector:@selector(itemStalledPlaying:) name:AVPlayerItemPlaybackStalledNotification object:playerItem];

  [self onStatus:RMXSTATUS_ITEM_ADDED trackId:playerItem.trackId param:playerItem];
  [self onStatus:RMXSTATUS_LOADING trackId:playerItem.trackId param:nil];
}

- (void) removeTrackObservers(AudioTrack*)playerItem
{
  [playerItem removeObserver:self forKeyPath:@"status"];
  [playerItem removeObserver:self forKeyPath:@"duration"];
  [playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
  [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:playerItem];

  [self onStatus:RMXSTATUS_ITEM_REMOVED trackId:playerItem.trackId param:playerItem];
}

- (void) activateAudioSession
{
    NSError *categoryError = nil;
    AVAudioSession* avSession = [AVAudioSession sharedInstance];
    AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionAllowBluetooth;

    if (@available(iOS 10.0, *)) {
        options |= AVAudioSessionCategoryOptionAllowBluetoothA2DP;
    }

    [avSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:options error:&categoryError];
    if (categoryError) {
        NSLog(@"Error setting category! %@", [categoryError description]);
    }

    NSError *activationError = nil;
    BOOL success = [[AVAudioSession sharedInstance] setActive:YES error:&activationError];

    if (!success) {
        if (activationError) {
            NSLog(@"Could not activate audio session. %@", [activationError localizedDescription]);
        } else {
            NSLog(@"audio session could not be activated!");
        }
    }
}

/**
 * Register the listener for pause and resume events.
 */
- (void) observeLifeCycle
{
    NSNotificationCenter* listener = [NSNotificationCenter defaultCenter];

    // These aren't really needed. the AVQueuePlayer handles this for us.
    // [listener addObserver:self selector:@selector(handleEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    // [listener addObserver:self selector:@selector(handleEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];

    // We do need these.
    [listener addObserver:self selector:@selector(handleAudioSessionInterruption:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    [listener addObserver:self selector:@selector(viewWillDisappear:) name:CDVViewWillDisappearNotification object:nil];
}

- (void) viewWillDisappear(NSNotification*)notification
{
  // For now, just capture it and log, and see when it triggers,
  // because that would seem to indicate the app closing in this case wouldn't it?
  NSLog(@"RmxAudioPlayer: viewWillDisappear");
  [self onStatus:RMXSTATUS_VIEWDISAPPEAR trackId:@"WINDOW" param:nil];
}

- (void) storeMessageChannel:(CDVInvokedUrlCommand*) command
{
    self.statusCallbackId = command.callbackId;
    [self onStatus:RMXSTATUS_REGISTER trackId:@"INIT" param:nil];
}

- (NSDictionary*)createErrorWithCode:(CDVMediaError)code message:(NSString*)message
{
    NSMutableDictionary* errorDict = [NSMutableDictionary dictionaryWithCapacity:2];

    NSString* finalMessage = message ? message : @"";
    [errorDict setObject:[NSNumber numberWithUnsignedInteger:code] forKey:@"code"];
    [errorDict setObject:finalMessage forKey:@"message"];
    return errorDict;
}

- (void) onStatus:(RmxAudioStatusMessage)what trackId:(NSString*)trackId param:(NSObject*)param
{
    if (self.statusCallbackId != nil) {
      NSMutableDictionary* status = [NSMutableDictionary dictionary];
      status[@"msgType"] = @(what);
      // in the error case contains a dict with "code" and "message", otherwise a NSNumber
      status[@"value"] = param;
      status[@"trackId"] = trackId;

      NSMutableDictionary* dict = [NSMutableDictionary dictionary];
      dict[@"action"] = @"status";
      dict[@"status"] = status;

      CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dict];
      [result setKeepCallbackAsBool:YES]; // hold on to this.
      [self.commandDelegate sendPluginResult:result callbackId:self.statusCallbackId];
    }
}

/**
 *
 * Cleanup
 *
 *
 *
 *
 *
 *
 *
 *
 */

- (void) deregisterMusicControlsEventListener {
    // We don't use the remote control, and no need to remove observer on
    // NSNotificationCenter, that is done automatically
    // [[UIApplication sharedApplication] endReceivingRemoteControlEvents];
    // [[NSNotificationCenter defaultCenter] removeObserver:self name:@"receivedEvent" object:nil];

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:self];
    [commandCenter.pauseCommand removeTarget:self];
    [commandCenter.nextTrackCommand removeTarget:self];
    [commandCenter.previousTrackCommand removeTarget:self];
    [commandCenter.togglePlayPauseCommand removeTarget:self];

    // if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_9_0) {
    if (@available(iOS 9.0, *)) {
        [commandCenter.changePlaybackPositionCommand setEnabled:false];
        [commandCenter.changePlaybackPositionCommand removeTarget:self action:NULL];
    }

    _commandCenterRegistered = NO;
}

- (void) onMemoryWarning
{
  // override to remove caches, etc
  [super onMemoryWarning];

  // Well, we've just destroyed everything, but ok.
  [self removeAllTracks:YES];
  [self onStatus:RMXSTATUS_PLAYLIST_CLEARED trackId:@"INVALID" param:@{@"reason": @"memory-warning"}];
}

- (void) onReset
{
  // Override to cancel any long-running requests when the WebView navigates or refreshes.
  [super onReset];
  [self releaseResources];
}

- (void) dealloc {
    [super dealloc];
    [self releaseResources];
}

- (void) releaseResources {
    [_avQueuePlayer removeTimeObserver:_playbackTimeObserver];
    [_avQueuePlayer removeObserver:self forKeyPath:@"currentItem"];
    [_avQueuePlayer removeObserver:self forKeyPath:@"rate"];
    [self deregisterMusicControlsEventListener];

    // onReset or when killing app:
    if ([self.viewController isFirstResponder]) {
       [self.viewController resignFirstResponder];
    }
    [self removeAllTracks:NO];
    _avQueuePlayer = nil;

    _playbackTimeObserver = nil;
}

@end
