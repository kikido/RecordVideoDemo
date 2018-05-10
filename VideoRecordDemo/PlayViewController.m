//
//  PlayViewController.m
//  VideoRecordDemo
//
//  Created by dqh on 2018/5/10.
//  Copyright © 2018年 dqh. All rights reserved.
//

#import "PlayViewController.h"
#import <MediaPlayer/MediaPlayer.h>

@interface PlayViewController ()
@property (nonatomic, strong) NSURL *fileUrl;
@property (nonatomic, strong) MPMoviePlayerController *moviePlayer;
@end

@implementation PlayViewController

- (instancetype)initWithFileUrl:(NSURL *)fileUrl
{
    if (self = [super init]) {
        self.fileUrl = fileUrl;
    }
    return self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.moviePlayer.isPreparedToPlay) {
        [self.moviePlayer play];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视频回顾";
    
    if (self.fileUrl) {
        MPMoviePlayerController *videoPlayer = [[MPMoviePlayerController alloc] initWithContentURL:self.fileUrl];
        videoPlayer.view.frame = self.view.bounds;
        [self.view addSubview:videoPlayer.view];
        self.moviePlayer = videoPlayer;
        [videoPlayer prepareToPlay];
    }
    // Do any additional setup after loading the view.
}

- (void)dealloc
{
    NSLog(@"PlayViewController dealloc");
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
