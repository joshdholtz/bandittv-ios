//
//  ViewController.m
//  BanditTV
//
//  Created by Josh Holtz on 11/1/14.
//  Copyright (c) 2014 RokkinCat. All rights reserved.
//

#import "ViewController.h"

#import "ALAssetsLibrary+CustomPhotoAlbum.h"

#import <GPUImage/GPUImage.h>

#define kAlbumName @"BanditTV"

@interface ViewController ()

@property (nonatomic, strong) GPUImageView *filterView;

@property (nonatomic, strong) GPUImageVideoCamera *videoCamera;
@property (nonatomic, strong) GPUImageMotionDetector *motionDetector;

@property (nonatomic, strong) GPUImageFilter *imageFilter;
@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;
@property (nonatomic, strong) NSString *pathToMovie;

@property (nonatomic, assign) BOOL canStartRecording;

@property (nonatomic, assign) CGFloat startMotionSenstivity;
@property (nonatomic, assign) CGFloat endMotionSenstivity;
@property (nonatomic, assign) CGFloat recordingTimeAfterMotionStopped;
@property (nonatomic, assign) CGFloat minimumMotionTime;

@property (nonatomic, strong) NSDate *recordingStartedAt;
@property (nonatomic, strong) NSTimer *endRecordingTimer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _filterView = [[GPUImageView alloc] initWithFrame:self.view.bounds];
    [_filterView setAutoresizingMask:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight];
    [self.view addSubview:_filterView];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    _pathToMovie = [documentsDirectory stringByAppendingPathComponent:@"movie.mp4"];
    
    _startMotionSenstivity = 0.02f;
    _endMotionSenstivity = 0.00001f;
    _recordingTimeAfterMotionStopped = 2.0f;
    _minimumMotionTime = 2.0f;
    [self setup];
}

- (void)viewWillDisappear:(BOOL)animated {
    [_videoCamera stopCameraCapture];
    [super viewWillDisappear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_videoCamera startCameraCapture];
}

#pragma mark - Private

- (void)setup {
    
    // Setup video camera
    _videoCamera = [[GPUImageVideoCamera alloc] initWithSessionPreset:AVCaptureSessionPreset640x480 cameraPosition:AVCaptureDevicePositionBack];
    _videoCamera.outputImageOrientation = UIInterfaceOrientationLandscapeRight;
    
    // Image filter
    _imageFilter = [[GPUImageFilter alloc] init];
    
    // Setup motion detector
    _motionDetector = [[GPUImageMotionDetector alloc] init];
    [_motionDetector setLowPassFilterStrength:0.5f];
    
    __block __weak ViewController *weakSelf = self;
    [_motionDetector setMotionDetectionBlock:^(CGPoint motionCentroid, CGFloat motionIntensity, CMTime frameTime) {
        if (!weakSelf.canStartRecording) return;
//        NSLog(@"motionIntensity - %f", motionIntensity);
        
        if (motionIntensity > weakSelf.startMotionSenstivity) {
            
            [weakSelf.endRecordingTimer invalidate];
            weakSelf.endRecordingTimer = nil;
            
            if (!weakSelf.recordingStartedAt) {
                
                NSLog(@"Starting recording");
                [weakSelf removeFile:@"movie.mp4"];
                weakSelf.recordingStartedAt = [NSDate date];
                
                weakSelf.movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:[NSURL fileURLWithPath:weakSelf.pathToMovie] size:CGSizeMake(640.0f, 480.0f)];
                [weakSelf.movieWriter setEncodingLiveVideo:YES];
                weakSelf.movieWriter.shouldPassthroughAudio = YES;
                [weakSelf.imageFilter addTarget:weakSelf.movieWriter];
                weakSelf.videoCamera.audioEncodingTarget = weakSelf.movieWriter;
                
                [weakSelf.movieWriter startRecording];
                
            }
            
        } else if (motionIntensity < weakSelf.endMotionSenstivity && weakSelf.recordingStartedAt != nil) {
            
            if (weakSelf.endRecordingTimer == nil) {
                
                [weakSelf.endRecordingTimer invalidate];
                weakSelf.endRecordingTimer = nil;
                
                NSLog(@"Setting timer to stop");
                dispatch_sync(dispatch_get_main_queue(), ^{
                    weakSelf.endRecordingTimer = [NSTimer scheduledTimerWithTimeInterval:weakSelf.recordingTimeAfterMotionStopped target:weakSelf selector:@selector(stopAndSave) userInfo:nil repeats:NO];
                });
                
            }
            
            

        }
        
    }];
    
    [_imageFilter addTarget:_motionDetector];
    [_videoCamera addTarget:_imageFilter];
    [_videoCamera addTarget:_filterView];
    
    [self start];
}

- (void)stop {
    NSLog(@"Stopping");
    [_movieWriter finishRecording];
    
    [_videoCamera stopCameraCapture];
    _recordingStartedAt = nil;
    _canStartRecording = NO;
}

- (void)stopAndSave {
    [self stop];
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    [library saveVideo:[NSURL fileURLWithPath:_pathToMovie] toAlbum:kAlbumName completion:^(NSURL *assetURL, NSError *error) {
        NSLog(@"Saved");
        [self restart];
    } failure:^(NSError *error) {
        NSLog(@"Failed to save to album - %@", error);
        [self restart];
    }];
}

- (void)restart {
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, 1.5f * NSEC_PER_SEC);
    dispatch_after(startTime, dispatch_get_main_queue(), ^(void){
        [_imageFilter removeTarget:_movieWriter];
        _movieWriter = nil;
        
        NSLog(@"Restarting");
        [self start];
    });
}

- (void)start {
    [_videoCamera startCameraCapture];
    
    double delayToStartRecording = 1.5;
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, delayToStartRecording * NSEC_PER_SEC);
    dispatch_after(startTime, dispatch_get_main_queue(), ^(void){
        self.canStartRecording = YES;
    });
}

#pragma mark - Private - File Stuff

- (void)removeFile:(NSString *)fileName {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    
    NSString *filePath = [documentsPath stringByAppendingPathComponent:fileName];
    NSError *error;
    BOOL success = [fileManager removeItemAtPath:filePath error:&error];
    if (success) {

    } else {
        NSLog(@"Could not delete file -:%@ ",[error localizedDescription]);
    }
}

@end
