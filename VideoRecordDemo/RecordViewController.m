//
//  RecordViewController.m
//  VideoRecordDemo
//
//  Created by dqh on 2018/5/9.
//  Copyright © 2018年 dqh. All rights reserved.
//

#import "RecordViewController.h"
#import "PlayViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>

@interface RecordViewController ()<AVCaptureFileOutputRecordingDelegate>

//负责输入和输出设备之间的数据传递
@property (nonatomic, strong) AVCaptureSession *captureSession;
//负责从AVCaptureDevice获得输入数据
@property (nonatomic, strong) AVCaptureDeviceInput *captureDeviceInput;
//视频输出流
@property (nonatomic, strong) AVCaptureMovieFileOutput *captureMovieFileOutput;
//相机拍摄预览图层
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;
//设备方向
@property (nonatomic, assign) AVCaptureVideoOrientation videoOrientation;
//运动管理器
@property (nonatomic, strong) CMMotionManager *motionManager;


//聚焦光标
@property (nonatomic, strong) UIImageView *focusImage;
//录屏时间显示标签
@property (nonatomic, strong) UILabel *recoderTipsLabel;
//录屏定时器
@property (nonatomic, strong) NSTimer *recordTimer;
//视频保存的文件地址
@property (nonatomic, strong) NSURL *fileUrl;


@end

@implementation RecordViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    self.title = @"双击切换摄像头，单点聚焦";
    [self clearFile];
    [self setUp];
    
    //切换摄像头 双击
    UITapGestureRecognizer *switchTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(switchCameraClicked:)];
    switchTap.numberOfTapsRequired = 2;
    [self.view addGestureRecognizer:switchTap];
    
    //摄像头聚焦 单机
    UITapGestureRecognizer *focuseTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focuseAction:)];
    focuseTap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:focuseTap];
    
    //当switchTap生效时，focuseTap不生效
    [focuseTap requireGestureRecognizerToFail:switchTap];
    
    //开始/结束录制按钮
    UIButton *startOrEndButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [startOrEndButton setTitle:@"开始录制" forState:UIControlStateNormal];
    [startOrEndButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    [startOrEndButton addTarget:self action:@selector(startOrEndAction:) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *rightItem = [[UIBarButtonItem alloc] initWithCustomView:startOrEndButton];
    self.navigationItem.rightBarButtonItem = rightItem;
    
    //进度条
    UILabel *stepLabel = [UILabel new];
    stepLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stepLabel];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[label]-0-|"
                                                                      options:0
                                                                      metrics:nil
                                                                        views:@{@"label":stepLabel}]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-120-[label]"
                                                                      options:0
                                                                      metrics:nil
                                                                        views:@{@"label":stepLabel}]];
    stepLabel.text = @"00:00";
    stepLabel.textAlignment = NSTextAlignmentCenter;
    stepLabel.textColor = [UIColor grayColor];
    _recoderTipsLabel = stepLabel;
    
    //设置聚焦的图片
    self.focusImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"video_icon_all focusing"]];
    self.focusImage.frame = CGRectMake(0, 0, 92, 60);
    self.focusImage.alpha = 0.;
    [self.view addSubview:self.focusImage];
    
    //运动管理器
    self.motionManager = [[CMMotionManager alloc] init];
    //加速器每2秒采集一次数据
    self.motionManager.accelerometerUpdateInterval = 2.;
    //避免循环引用
    __weak typeof(self) weakSelf = self;
    [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue currentQueue] withHandler:^(CMAccelerometerData * _Nullable accelerometerData, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        
        if (!error) {
            [strongSelf outputData:accelerometerData.acceleration];
        } else {
            NSLog(@"error = %@",error);
        }
    }];
}

- (void)clearFile
{
    [[NSFileManager defaultManager] removeItemAtPath:self.fileUrl.absoluteString error:nil];
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.captureSession startRunning];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    // 防止锁屏
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [[UIApplication sharedApplication] setIdleTimerDisabled:NO];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    AVCaptureConnection *captureConnection = [self.captureVideoPreviewLayer connection];
    captureConnection.videoOrientation = toInterfaceOrientation;
}

//旋转后重新设置大小
-(void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    _captureVideoPreviewLayer.frame=self.view.bounds;
}

-(void)dealloc
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
}

- (void)setUp
{
    //获得输入设备
    //取得后置摄像头
    AVCaptureDevice *captureDevice = [self getCameraDeviceWithPosition:AVCaptureDevicePositionBack];
    if (!captureDevice) {
        NSLog(@"取得后置摄像头时出现问题");
        return;
    }
    // 视频 HDR (高动态范围图像)
    // videoCaptureDevice.videoHDREnabled = YES;
    // 设置最大，最小帧速率
    //videoCaptureDevice.activeVideoMinFrameDuration = CMTimeMake(1, 60);
    
    
    NSError *error=nil;
    //根据输入设备初始化设备输入对象，用于获得输入数据
    _captureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:captureDevice error:&error];
    if (error) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",error.localizedDescription);
        return;
    }
    //将视频输入添加到会话中
    if ([self.captureSession canAddInput:_captureDeviceInput]) {
        [_captureSession addInput:_captureDeviceInput];
    }
    
    //获取音频输入设备
    AVCaptureDevice *audioCaptureDevice = [[AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio] firstObject];
    
    //创建音频输入源
    NSError *tError;
    AVCaptureDeviceInput *audioCaptureDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:audioCaptureDevice error:&tError];
    if (tError) {
        NSLog(@"取得设备输入对象时出错，错误原因：%@",tError.localizedDescription);
        return;
    }
    //将音频输入源添加到会话中
    if ([self.captureSession canAddInput:audioCaptureDeviceInput]) {
        [_captureSession addInput:audioCaptureDeviceInput];
    }
    
    //初始化设备输出对象，用于获得输出数据
    _captureMovieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
    //需要设置movieFragmentInterval，不然视频超过十秒就会没有声音
    _captureMovieFileOutput.movieFragmentInterval = kCMTimeInvalid;
    
    AVCaptureConnection *captureConnection = [_captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
    //视频防抖 是在 iOS 6 和 iPhone 4S 发布时引入的功能。到了 iPhone 6，增加了更强劲和流畅的防抖模式，被称为影院级的视频防抖动。相关的 API 也有所改动 (目前为止并没有在文档中反映出来，不过可以查看头文件）。防抖并不是在捕获设备上配置的，而是在 AVCaptureConnection 上设置。由于不是所有的设备格式都支持全部的防抖模式，所以在实际应用中应事先确认具体的防抖模式是否支持
    if ([captureConnection isVideoStabilizationSupported ]) {
        captureConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
    }
    //将设备输出添加到会话中
    if ([_captureSession canAddOutput:_captureMovieFileOutput]) {
        [_captureSession addOutput:_captureMovieFileOutput];
    }
    
    //创建视频预览层，用于实时展示摄像头状态
    //将视频预览层添加到界面中
    [self.view.layer insertSublayer:self.captureVideoPreviewLayer atIndex:0];
    //预览图层和视频方向保持一致
    [_captureVideoPreviewLayer connection].videoOrientation = (AVCaptureVideoOrientation)[[UIApplication sharedApplication] statusBarOrientation];
    captureConnection.videoOrientation = (AVCaptureVideoOrientation)[[UIApplication sharedApplication] statusBarOrientation];
    
    
    [self addNotificationToCaptureDevice:captureDevice];
}

#pragma mark - 计时器
- (void)startTimeLabel
{
    _recoderTipsLabel.text = @"00:00";
    _recordTimer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(toSetRecFlags) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_recordTimer forMode:NSRunLoopCommonModes];
    [_recordTimer setFireDate:[NSDate distantPast]];
}

- (void)stopTimeLabel
{
    [_recordTimer setFireDate:[NSDate distantFuture]];
    [_recordTimer invalidate];
    _recordTimer = nil;
    _recoderTipsLabel.text = @"00:00";
}

- (void)toSetRecFlags
{
    NSInteger value = [[[_recoderTipsLabel.text componentsSeparatedByString:@":"] objectAtIndex:0] integerValue]*60 + [[[_recoderTipsLabel.text componentsSeparatedByString:@":"] objectAtIndex:1] integerValue];
    
    value++;
    NSString *minute = [NSString stringWithFormat:@"%02ld",value/60];
    NSString *second= [NSString stringWithFormat:@"%02ld",value%60];
    
    [_recoderTipsLabel setTextColor:[UIColor redColor]];//RGBA(32, 192, 227, 1)//RGBA(201, 201, 201, 1)
    [_recoderTipsLabel setText:[NSString stringWithFormat:@"%@:%@",minute,second]];
}



#pragma mark - AVCaptureFileOutputRecordingDelegate

-(void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
    NSLog(@"开始录制...");
}

-(void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
    NSLog(@"视频录制完成");
    
    [self stopTimeLabel];
    
    NSFileManager *fileManager = [[NSFileManager alloc] init] ;
    float filesize = -1.0;
    if ([fileManager fileExistsAtPath:self.fileUrl.path]) {
        NSDictionary *fileDic = [fileManager attributesOfItemAtPath:self.fileUrl.path error:nil];//获取文件的属性
        unsigned long long size = fileDic.fileSize;
        filesize = 1*size;
    }

    NSLog(@"视频大小 %lfM", filesize / 1024 / 1024);
    
    PlayViewController *vc = [[PlayViewController alloc] initWithFileUrl:self.fileUrl];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Notification

-(void)addNotificationToCaptureDevice:(AVCaptureDevice *)captureDevice
{
//    //注意添加区域改变捕获通知必须首先设置设备允许捕获
//    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
//        captureDevice.subjectAreaChangeMonitoringEnabled = YES;
//    }];
//    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
//    //捕获区域发生改变
//    [notificationCenter addObserver:self selector:@selector(areaChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
//    [notificationCenter addObserver:self selector:@selector(deviceConnected:) name:AVCaptureDeviceWasConnectedNotification object:captureDevice];
//    [notificationCenter addObserver:self selector:@selector(deviceDisconnected:) name:AVCaptureDeviceWasDisconnectedNotification object:captureDevice];
}
-(void)removeNotificationFromCaptureDevice:(AVCaptureDevice *)captureDevice
{
//    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
//    [notificationCenter removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:captureDevice];
//    [notificationCenter removeObserver:self name:AVCaptureDeviceWasConnectedNotification object:captureDevice];
//    [notificationCenter removeObserver:self name:AVCaptureDeviceWasDisconnectedNotification object:captureDevice];
}

-(void)addNotificationToCaptureSession:(AVCaptureSession *)captureSession
{
//    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
//    //会话出错
//    [notificationCenter addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:captureSession];
}

/**
 *  设备连接成功
 *
 *  @param notification 通知对象
 */
-(void)deviceConnected:(NSNotification *)notification
{
    NSLog(@"设备已连接...");
}
/**
 *  设备连接断开
 *
 *  @param notification 通知对象
 */
-(void)deviceDisconnected:(NSNotification *)notification
{
    NSLog(@"设备已断开.");
}
/**
 *  捕获区域改变
 *
 *  @param notification 通知对象
 */
-(void)areaChange:(NSNotification *)notification
{
    NSLog(@"捕获区域改变...");
}

/**
 *  会话出错
 *
 *  @param notification 通知对象
 */
-(void)sessionRuntimeError:(NSNotification *)notification
{
    NSLog(@"会话发生错误.");
}

#pragma mark - Helper


/**
 更新设备方向

 @param data 加速器
 */
-(void)outputData:(CMAcceleration)data
{
    UIInterfaceOrientation orientation;
    if(data.x >= 0.75){
        orientation = UIInterfaceOrientationLandscapeLeft;
    }
    else if (data.x<= -0.75){
        orientation = UIInterfaceOrientationLandscapeRight;
    }
    else if (data.y <= -0.75){
        orientation = UIInterfaceOrientationPortrait;
    }
    else if (data.y >= 0.75){
        orientation = UIInterfaceOrientationPortraitUpsideDown;
    }
    else{
        return;
    }
    self.videoOrientation = orientation;
}

/**
 *  取得指定位置的摄像头
 *
 *  @param position 摄像头位置
 *
 *  @return 摄像头设备
 */
-(AVCaptureDevice *)getCameraDeviceWithPosition:(AVCaptureDevicePosition )position
{
    NSArray *cameras = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice *camera in cameras) {
        if ([camera position] == position) {
            return camera;
        }
    }
    return nil;
}

/**
 *  改变设备属性的统一操作方法
 *
 *  @param propertyChange 属性改变操作
 */
-(void)changeDeviceProperty:(void(^)(AVCaptureDevice *captureDevice))propertyChange
{
    AVCaptureDevice *captureDevice = [self.captureDeviceInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}

/**
 *  设置闪光灯模式
 *
 *  @param flashMode 闪光灯模式
 */
-(void)setFlashMode:(AVCaptureFlashMode )flashMode
{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFlashModeSupported:flashMode]) {
            [captureDevice setFlashMode:flashMode];
        }
    }];
}
/**
 *  设置聚焦模式
 *
 *  @param focusMode 聚焦模式
 */
-(void)setFocusMode:(AVCaptureFocusMode )focusMode
{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}
/**
 *  设置曝光模式
 *
 *  @param exposureMode 曝光模式
 */
-(void)setExposureMode:(AVCaptureExposureMode)exposureMode
{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}
/**
 *  设置聚焦点
 *
 *  @param point 聚焦点
 */
-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point
{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}

#pragma mark - Target Event

//开始结束录制
- (void)startOrEndAction:(UIButton *)sender
{
    sender.selected = !sender.selected;
    
    if (sender.selected) {
        //录制状态
        if (!self.captureMovieFileOutput.isRecording) {
            //开始定时器
            [self startTimeLabel];
            [sender setTitle:@"结束录制" forState:UIControlStateNormal];
            
            //将视频的输出方向与设备方向保持一致
            AVCaptureConnection *connection = [self.captureMovieFileOutput connectionWithMediaType:AVMediaTypeVideo];
            connection.videoOrientation = self.videoOrientation;
            
            [self.captureMovieFileOutput startRecordingToOutputFileURL:self.fileUrl recordingDelegate:self];
        }
    } else {
        //结束录制状态
        [sender setTitle:@"开始录制" forState:UIControlStateNormal];
        //停止录制
        [self.captureMovieFileOutput stopRecording];
        //关闭定时器
        [self.recordTimer invalidate];
        self.recordTimer = nil;
    }
}


/**
 切换摄像头

 @param sender 按钮
 */
- (void)switchCameraClicked:(UIButton *)sender
{
    AVCaptureDevice *currentDevice = [self.captureDeviceInput device];
    AVCaptureDevicePosition currentPosition = [currentDevice position];
    [self removeNotificationFromCaptureDevice:currentDevice];
    
    AVCaptureDevice *toChangeDevice;
    AVCaptureDevicePosition toChangePosition = AVCaptureDevicePositionFront;
    if (currentPosition==AVCaptureDevicePositionUnspecified || currentPosition==AVCaptureDevicePositionFront) {
        toChangePosition=AVCaptureDevicePositionBack;
    }
    toChangeDevice = [self getCameraDeviceWithPosition:toChangePosition];
    if (!toChangeDevice) {
        NSLog(@"切换摄像头失败");
        return;
    }
    [self addNotificationToCaptureDevice:toChangeDevice];
    //获得要调整的设备输入对象
    AVCaptureDeviceInput *toChangeDeviceInput = [[AVCaptureDeviceInput alloc]initWithDevice:toChangeDevice error:nil];
    
    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
    [self.captureSession beginConfiguration];
    //移除原有输入对象
    [self.captureSession removeInput:self.captureDeviceInput];
    //添加新的输入对象
    if ([self.captureSession canAddInput:toChangeDeviceInput]) {
        [self.captureSession addInput:toChangeDeviceInput];
        self.captureDeviceInput = toChangeDeviceInput;
    }else{
        [self.captureSession addInput:self.captureDeviceInput];
    }
    
    //提交会话配置
    [self.captureSession commitConfiguration];
}

-(void)focuseAction:(UITapGestureRecognizer *)tapGesture
{
    CGPoint point = [tapGesture locationInView:self.view];
    //将UI坐标转化为摄像头坐标
    CGPoint cameraPoint= [self.captureVideoPreviewLayer captureDevicePointOfInterestForPoint:point];
    [self setFocusCursorWithPoint:point];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

/**
 *  设置聚焦光标位置
 *
 *  @param point 光标位置
 */
-(void)setFocusCursorWithPoint:(CGPoint)point
{
    self.focusImage.center = point;
    self.focusImage.transform = CGAffineTransformMakeScale(1.5, 1.5);
    self.focusImage.alpha = 1.0;
    [UIView animateWithDuration:.2 animations:^{
        self.focusImage.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:1.0 animations:^{
            self.focusImage.alpha = 0;
        }];
    }];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark - Properties

- (AVCaptureSession *)captureSession
{
    // 录制5秒钟视频 高画质10M,压缩成中画质 0.5M
    // 录制5秒钟视频 中画质0.5M,压缩成中画质 0.5M
    // 录制5秒钟视频 低画质0.1M,压缩成中画质 0.1M
    if (_captureSession == nil) {
        //设置分辨率
        _captureSession = [[AVCaptureSession alloc] init];
        if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
            _captureSession.sessionPreset =AVCaptureSessionPresetHigh;
        }
    }
    return _captureSession;
}

- (AVCaptureVideoPreviewLayer *)captureVideoPreviewLayer
{
    if (_captureVideoPreviewLayer == nil) {
        _captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.captureSession];
        //填充模式
        _captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        _captureVideoPreviewLayer.frame = self.view.bounds;
    }
    return _captureVideoPreviewLayer;
}

- (NSURL *)fileUrl
{
    if (_fileUrl == nil) {
        _fileUrl = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"myMovie.mp4"]];
    }
    return _fileUrl;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
