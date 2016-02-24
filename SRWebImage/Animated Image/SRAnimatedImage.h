//
//  SRAnimatedImage.h
//  SRWebImage
//
//  Created by shoron on 16/2/17.
//  Copyright © 2016年 YSR. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern const NSTimeInterval kSRAnimatedImageDelayTimeIntervalMinimum;

@interface SRAnimatedImage : NSObject

// if the data is gif image data, the coverImage is the first image.
// if the data is normal image, the coverImage is the image
@property (strong, nonatomic) UIImage *coverImage;
@property (assign, nonatomic) NSUInteger coverImageIndex;

@property (assign, nonatomic) NSUInteger imagesCount;

// 0:means animate forever
@property (assign, nonatomic) NSUInteger loopCount;

// the key is NSNumber with image index
// the value is NSTimeInterval
@property (strong, nonatomic) NSDictionary *delayTimesForImageIndex;

// the animated image is dynamic image (eg: gif...) or not
@property (assign, nonatomic, readonly) BOOL isDynamicImage;

// the next effective index image
- (NSUInteger)effectiveIndexAfterIndex:(NSUInteger)index;

// get the image cached at index
- (UIImage *)cachedImageAtIndex:(NSUInteger)index;

// init the animated image with data.
- (instancetype)initWithAnimatedImageData:(NSData *)data cachedToDisk:(BOOL)isCachedToDisk;

// need to pre draw the image in memory
- (instancetype)initWithAnimatedImageData:(NSData *)data predrawingEnabled:(BOOL)isPredrawingEnabled cachedToDisk:(BOOL)isCachedToDisk;

@end

@interface SRWeakProxy : NSProxy

+ (instancetype)weakProxyForObject:(id)targetObject;

@end

