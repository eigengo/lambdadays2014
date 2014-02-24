#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

#define FRAMES_PER_SECOND_MOD 7

@implementation ViewController {
	CVServerTransactionConnection *serverTransactionConnection;
	id<CVServerConnectionInput> serverConnectionInput;
    CGRect landscapeVideoRect;
	
#if !(TARGET_IPHONE_SIMULATOR)
	AVCaptureSession *captureSession;
	AVCaptureVideoPreviewLayer *previewLayer;
	int frameMod;
	bool capturing;
#endif
    AVPlayer* player;
    AVPlayerLayer *predefPreviewLayer;
}

#pragma mark - Housekeeping

- (void)viewDidLoad {
    [super viewDidLoad];
    landscapeVideoRect = CGRectMake(0, 0, 568, 320); //CGRectMake(30, 100, 400, 200);
#if !(TARGET_IPHONE_SIMULATOR)
	capturing = false;
#endif
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (CVServerConnection*)serverConnection {
    [self.ip resignFirstResponder];
	NSString* server = [NSString stringWithFormat:@"http://%@:8080/recog", self.ip.text];
	NSURL *serverBaseUrl = [NSURL URLWithString:server];
	return [CVServerConnection connection:serverBaseUrl];
}

#pragma mark - Video capture (using the back camera)

- (void)startCapture {
#if !(TARGET_IPHONE_SIMULATOR)
	// Video capture session; without a device attached to it.
	captureSession = [[AVCaptureSession alloc] init];
	
	// Preview layer that will show the video
	previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
	previewLayer.frame = landscapeVideoRect;
	previewLayer.contentsGravity = kCAGravityResizeAspectFill;
	previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    previewLayer.zPosition = -1;
	[self.view.layer addSublayer:previewLayer];
	
	// begin the capture
	AVCaptureDevice *videoCaptureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
	NSError *error = nil;
	
	// video output is the callback
	AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
	videoOutput.alwaysDiscardsLateVideoFrames = YES;
	videoOutput.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
	dispatch_queue_t queue = dispatch_queue_create("VideoCaptureQueue", NULL);
	[videoOutput setSampleBufferDelegate:self queue:queue];
	
	// video input is the camera
	AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoCaptureDevice error:&error];
	
	// capture session connects the input with the output (camera -> self.captureOutput)
	[captureSession addInput:videoInput];
	[captureSession addOutput:videoOutput];
	
	// start the capture session
	[captureSession startRunning];
    previewLayer.connection.videoOrientation = UIInterfaceOrientationLandscapeLeft;
	
	// begin a transaction
	serverTransactionConnection = [[self serverConnection] begin:nil];
	
	// (a) using static images
	//serverConnectionInput = [serverTransactionConnection staticInput:self];
	
	// (b) using MJPEG stream
	serverConnectionInput = [serverTransactionConnection mjpegInput:self];
	
	// (c) using H.264 stream
	//serverConnectionInput = [serverTransactionConnection h264Input:self];

	// (d) using RTSP server
	//NSURL *url;
	//serverConnectionInput = [serverTransactionConnection rtspServerInput:self url:&url];
	//[self.statusLabel setText:[url absoluteString]];
#endif
}

- (void)stopCapture {
#if !(TARGET_IPHONE_SIMULATOR)
	[captureSession stopRunning];
	[serverConnectionInput stopRunning];
	
	[previewLayer removeFromSuperlayer];
	
	previewLayer = nil;
	captureSession = nil;
	serverConnectionInput = nil;
	serverTransactionConnection = nil;
#endif
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
#if !(TARGET_IPHONE_SIMULATOR)
	frameMod++;
	if (frameMod % FRAMES_PER_SECOND_MOD == 0) {
		[serverConnectionInput submitFrame:sampleBuffer];
		NSLog(@"Network bytes %ld", [serverConnectionInput getStats].networkBytes);
	}
#endif
}

#pragma mark - UI

- (IBAction)startStop:(id)sender {
#if !(TARGET_IPHONE_SIMULATOR)
	if (capturing) {
		[self stopCapture];
		[self.startStopButton setTitle:@"Record" forState:UIControlStateNormal];
		[self.startStopButton setTintColor:[UIColor greenColor]];
		capturing = false;
		self.predefButton.enabled = true;
	} else {
		[self startCapture];
		[self.startStopButton setTitle:@"Stop" forState:UIControlStateNormal];
		[self.startStopButton setTintColor:[UIColor redColor]];
		capturing = true;
	}
#endif
}

- (IBAction)predefStopStart:(id)sender {
	self.startStopButton.enabled = false;
    self.predefButton.enabled = false;
	serverTransactionConnection = [[self serverConnection] begin:nil];
	serverConnectionInput = [serverTransactionConnection h264Input:self];
    
    [NSThread detachNewThreadSelector:@selector(predefPlay:) toTarget:self withObject:nil];
    [NSThread detachNewThreadSelector:@selector(predefSubmit:) toTarget:self withObject:nil];
}

- (void)predefSubmit:(id)_unused {
	dispatch_queue_t queue = dispatch_queue_create("Predef", NULL);
	dispatch_sync(queue, ^{
        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"coins2" ofType:@"mp4"];
		NSFileHandle* fileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
		while (true) {
			NSData *data = [fileHandle readDataOfLength:16000];
			[serverConnectionInput submitFrameRaw:data];
			[NSThread sleepForTimeInterval:.25];		// 16000 * 4 Bps ~ 64 kB/s
			if (data.length == 0) break;
		}
		[serverConnectionInput stopRunning];
		[fileHandle closeFile];
	});
}

- (void)predefPlay:(id)_unused {
    NSString *filePath = [[NSBundle mainBundle] pathForResource:@"coins2" ofType:@"mp4"];
    player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:filePath]];
    predefPreviewLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    predefPreviewLayer.drawsAsynchronously = true;
	predefPreviewLayer.frame = landscapeVideoRect;
	predefPreviewLayer.contentsGravity = kCAGravityResizeAspectFill;
	predefPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    predefPreviewLayer.zPosition = -1;
	[self.view.layer addSublayer:predefPreviewLayer];
    [NSThread sleepForTimeInterval:2.0];
    player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    [player addObserver:self forKeyPath:@"rate" options:0 context:0];
    [player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == 0) {
        if (player.rate == 0.0) {
            [player removeObserver:self forKeyPath:@"rate"];
            [predefPreviewLayer removeFromSuperlayer];
            self.startStopButton.enabled = true;
            self.predefButton.enabled = true;
        }
    }
}

#pragma mark - CVServerConnectionDelegate methods

- (void)cvServerConnectionOk:(id)response {
	NSLog(@":))");
}

- (void)cvServerConnectionAccepted:(id)response {
	NSLog(@":)");
}

- (void)cvServerConnectionRejected:(id)response {
	NSLog(@":(");
}

- (void)cvServerConnectionFailed:(NSError *)reason {
	NSLog(@":(( %@", reason);
}

@end
