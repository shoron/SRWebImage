//
//  ViewController.m
//  SRWebImage
//
//  Created by shoron on 16/2/17.
//  Copyright © 2016年 YSR. All rights reserved.
//

#import "ViewController.h"
#import "UIImageView+AnimatedImage.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIImageView *imageView1;
@property (weak, nonatomic) IBOutlet UIImageView *imageView2;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self test];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)test {
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"rock" withExtension:@"gif"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    SRAnimatedImage *image = [[SRAnimatedImage alloc] initWithAnimatedImageData:data cachedToDisk:NO];
    self.imageView.animatedImage = image;

    NSURL *url2 = [NSURL URLWithString:@"https://cloud.githubusercontent.com/assets/1567433/10417835/1c97e436-7052-11e5-8fb5-69373072a5a0.gif"];
    [self loadAnimatedImageWithURL:url2 completion:^(SRAnimatedImage *animatedImage) {
        self.imageView2.animatedImage = animatedImage;
        self.imageView2.userInteractionEnabled = YES;
    }];
    
    NSURL *url3 = [NSURL URLWithString:@"https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif"];
    [self loadAnimatedImageWithURL:url3 completion:^(SRAnimatedImage *animatedImage) {
        self.imageView1.animatedImage = animatedImage;
        self.imageView1.userInteractionEnabled = YES;
    }];
}

- (IBAction)stopAnimating:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)loadAnimatedImageWithURL:(NSURL *const)url completion:(void (^)(SRAnimatedImage *animatedImage))completion {
    NSString *const filename = url.lastPathComponent;
    NSString *const diskPath = [NSHomeDirectory() stringByAppendingPathComponent:filename];
    
    NSData * __block animatedImageData = [[NSFileManager defaultManager] contentsAtPath:diskPath];
    SRAnimatedImage * __block animatedImage = [[SRAnimatedImage alloc] initWithAnimatedImageData:animatedImageData cachedToDisk:YES];
    
    if (animatedImage) {
        if (completion) {
            completion(animatedImage);
        }
    } else {
        [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            animatedImageData = data;
            animatedImage = [[SRAnimatedImage alloc] initWithAnimatedImageData:animatedImageData cachedToDisk:YES];
            if (animatedImage) {
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(animatedImage);
                    });
                }
                [data writeToFile:diskPath atomically:YES];
            }
        }] resume];
    }
}

@end

