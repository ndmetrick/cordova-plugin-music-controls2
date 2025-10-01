//
//  MusicControls.m
//
//
//  Created by Juan Gonzalez on 12/16/16.
//  Updated by Gaven Henry on 11/7/17 for iOS 11 compatibility & new features
//  Updated by Eugene Cross on 14/10/19 for iOS 13 compatibility
//
//

#import "MusicControls.h"
#import "MusicControlsInfo.h"

//save the passed in info globally so we can configure the enabled/disabled commands and skip intervals
MusicControlsInfo * musicControlsSettings;

@implementation MusicControls

- (void) create: (CDVInvokedUrlCommand *) command {
    NSDictionary * musicControlsInfoDict = [command.arguments objectAtIndex:0];
    MusicControlsInfo * musicControlsInfo = [[MusicControlsInfo alloc] initWithDictionary:musicControlsInfoDict];
    musicControlsSettings = musicControlsInfo;



    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) {
        return;
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *setCategoryError = nil;


    [session setCategory:AVAudioSessionCategoryPlayback error:&setCategoryError];

    if (setCategoryError) {
        NSLog(@"AudioSession category error: %@", setCategoryError);
    }
    [session setActive:YES error:nil];

    [self.commandDelegate runInBackground:^{
        MPNowPlayingInfoCenter * nowPlayingInfoCenter =  [MPNowPlayingInfoCenter defaultCenter];
        NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];

        [nowPlayingInfo setObject:[musicControlsInfo track] forKey:MPMediaItemPropertyTitle];
        [nowPlayingInfo setObject:[musicControlsInfo artist] forKey:MPMediaItemPropertyArtist];
        [nowPlayingInfo setObject:[musicControlsInfo album] forKey:MPMediaItemPropertyAlbumTitle];
        [nowPlayingInfo setObject:@([musicControlsInfo duration]) forKey:MPMediaItemPropertyPlaybackDuration];
        [nowPlayingInfo setObject:@([musicControlsInfo elapsed]) forKey:MPNowPlayingInfoPropertyElapsedPlaybackTime];
        [nowPlayingInfo setObject:@([musicControlsInfo isPlaying] ? 1.0 : 0.0) forKey:MPNowPlayingInfoPropertyPlaybackRate];
        MPMediaItemArtwork *artwork = [self createCoverArtwork:[musicControlsInfo cover]];
        if (artwork) {
          nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
}

        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nowPlayingInfo;
    }];

    [self registerMusicControlsEventListener];
}

- (void) updateIsPlaying: (CDVInvokedUrlCommand *) command {

    NSDictionary * musicControlsInfoDict = [command.arguments objectAtIndex:0];
    MusicControlsInfo * musicControlsInfo = [[MusicControlsInfo alloc] initWithDictionary:musicControlsInfoDict];

    NSNumber *elapsed = [NSNumber numberWithDouble:[musicControlsInfo elapsed]];
    NSNumber *playbackRate = [NSNumber numberWithFloat:([musicControlsInfo isPlaying] ? 1.0 : 0.0)];

    if (!NSClassFromString(@"MPNowPlayingInfoCenter")) {
        return;
    }

    MPNowPlayingInfoCenter *nowPlayingCenter = [MPNowPlayingInfoCenter defaultCenter];


    // Merge: copy the existing dictionary or start with an empty one
    NSMutableDictionary *updatedNowPlayingInfo =
        [NSMutableDictionary dictionaryWithDictionary:nowPlayingCenter.nowPlayingInfo ?: @{}];

    // Update only the fields that change dynamically
    updatedNowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed;
    updatedNowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate;

    nowPlayingCenter.nowPlayingInfo = updatedNowPlayingInfo;
}

// this was performing the full function of updateIsPlaying and just adding elapsed time update as well
// moved the elapsed update into updateIsPlaying and made this just pass through to reduce code duplication
- (void) updateElapsed: (CDVInvokedUrlCommand *) command {
    [self updateIsPlaying:(command)];
}

- (void) destroy: (CDVInvokedUrlCommand *) command {
    [self deregisterMusicControlsEventListener];
}

- (void) watch: (CDVInvokedUrlCommand *) command {
    [self setLatestEventCallbackId:command.callbackId];
}

- (MPMediaItemArtwork *) createCoverArtwork: (NSString *) coverUri {
    UIImage * coverImage = nil;

    if (coverUri == nil) {
        return nil;
    }

    if ([coverUri hasPrefix:@"http://"] || [coverUri hasPrefix:@"https://"]) {
        NSURL * coverImageUrl = [NSURL URLWithString:coverUri];
        NSData * coverImageData = [NSData dataWithContentsOfURL: coverImageUrl];

        coverImage = [UIImage imageWithData: coverImageData];
    }
    else if ([coverUri hasPrefix:@"file://"]) {
        NSString * fullCoverImagePath = [coverUri stringByReplacingOccurrencesOfString:@"file://" withString:@""];

        if ([[NSFileManager defaultManager] fileExistsAtPath: fullCoverImagePath]) {
            coverImage = [[UIImage alloc] initWithContentsOfFile: fullCoverImagePath];
        }
    }
    else if (![coverUri isEqual:@""]) {
        NSString * baseCoverImagePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString * fullCoverImagePath = [NSString stringWithFormat:@"%@%@", baseCoverImagePath, coverUri];

        if ([[NSFileManager defaultManager] fileExistsAtPath:fullCoverImagePath]) {
            coverImage = [UIImage imageNamed:fullCoverImagePath];
        }
    }
    else {
        coverImage = [UIImage imageNamed:@"none"];
    }

    return [self isCoverImageValid:coverImage] ? [[MPMediaItemArtwork alloc] initWithImage:coverImage] : nil;
}

- (bool) isCoverImageValid: (UIImage *) coverImage {
    return coverImage != nil && ([coverImage CIImage] != nil || [coverImage CGImage] != nil);
}

//Handle seeking with the progress slider on lockscreen or control center
- (MPRemoteCommandHandlerStatus)changedThumbSliderOnLockScreen:(MPChangePlaybackPositionCommandEvent *)event {
    NSString * seekTo = [NSString stringWithFormat:@"{\"message\":\"music-controls-seek-to\",\"position\":\"%f\"}", event.positionTime];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:seekTo];
    pluginResult.associatedObject = @{@"position":[NSNumber numberWithDouble: event.positionTime]};
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

//Handle the skip forward event
- (MPRemoteCommandHandlerStatus) skipForwardEvent:(MPSkipIntervalCommandEvent *)event {
    NSString * action = @"music-controls-skip-forward";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

//Handle the skip backward event
- (MPRemoteCommandHandlerStatus) skipBackwardEvent:(MPSkipIntervalCommandEvent *)event {
    NSString * action = @"music-controls-skip-backward";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) nextTrackEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-next";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;
}

- (MPRemoteCommandHandlerStatus) prevTrackEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-previous";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;

}

- (MPRemoteCommandHandlerStatus) pauseEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-pause";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;

}

- (MPRemoteCommandHandlerStatus) playEvent:(MPRemoteCommandEvent *)event {
    NSString * action = @"music-controls-play";
    NSString * jsonAction = [NSString stringWithFormat:@"{\"message\":\"%@\"}", action];
    CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:jsonAction];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:[self latestEventCallbackId]];
    return MPRemoteCommandHandlerStatusSuccess;

}

//There are only 3 button slots available so next/prev track and skip forward/back cannot both be enabled
//skip forward/back will take precedence if both are enabled
- (void) registerMusicControlsEventListener {

    //register required event handlers for standard controls
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

    [commandCenter.playCommand setEnabled:true];
    [commandCenter.playCommand addTarget:self action:@selector(playEvent:)];
    [commandCenter.pauseCommand setEnabled:true];
    [commandCenter.pauseCommand addTarget:self action:@selector(pauseEvent:)];
    if(musicControlsSettings.hasNext){
        [commandCenter.nextTrackCommand setEnabled:true];
        [commandCenter.nextTrackCommand addTarget:self action:@selector(nextTrackEvent:)];
    }
    if(musicControlsSettings.hasPrev){
        [commandCenter.previousTrackCommand setEnabled:true];
        [commandCenter.previousTrackCommand addTarget:self action:@selector(prevTrackEvent:)];
    }
}

- (void) deregisterMusicControlsEventListener {

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.nextTrackCommand removeTarget:self];
    [commandCenter.previousTrackCommand removeTarget:self];

    [self setLatestEventCallbackId:nil];
}

- (void) dealloc {
    [self deregisterMusicControlsEventListener];
}

@end
