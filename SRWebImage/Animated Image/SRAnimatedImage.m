//
//  SRAnimatedImage.m
//  SRWebImage
//
//  Created by shoron on 16/2/17.
//  Copyright © 2016年 YSR. All rights reserved.
//

#import "SRAnimatedImage.h"
#import <imageIO/imageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

// From vm_param.h, define for iOS 8.0 or higher to build on device.
#ifndef BYTE_SIZE
#define BYTE_SIZE 8 // byte size in bits
#endif


static const NSTimeInterval kDelayTimeIntervalDefault = 0.1;

// This is how the fastest browsers do it as per 2012: http://nullsleep.tumblr.com/post/16524517190/animated-gif-minimum-frame-delay-browser-compatibility
const NSTimeInterval kSRAnimatedImageDelayTimeIntervalMinimum = 0.02;

@interface SRAnimatedImage()

// the byte array's value is 0 or 1. 0: the imageRef of index can not tranform to UIImage. 1: can tranform to UIImage. means effective
@property (assign, nonatomic) Byte *flag;

// is the image data is dynamic image
@property (assign, nonatomic, readwrite) BOOL isDynamicImage;

// cached image
@property (strong, nonatomic) NSMutableDictionary *cachedImages;

// current displayed image index
@property (assign, nonatomic) NSUInteger currentDisplayedImageIndex;

@property (assign, nonatomic) CGImageSourceRef imageSource;

@property (strong, nonatomic) dispatch_queue_t serialQueueForCacheImage;

@end

@implementation SRAnimatedImage

#pragma mark - public methods

#pragma mark - Init

- (instancetype)initWithAnimatedImageData:(NSData *)data cachedToDisk:(BOOL)isCachedToDisk {
    return [[SRAnimatedImage alloc] initWithAnimatedImageData:data predrawingEnabled:YES cachedToDisk:isCachedToDisk];
}

- (instancetype)initWithAnimatedImageData:(NSData *)data predrawingEnabled:(BOOL)isPredrawingEnabled cachedToDisk:(BOOL)isCachedToDisk {
    // check data length
    BOOL hasData = ([data length] > 0);
    if (!hasData) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        //TODO: check data cache
        self.imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)data,
                                                       (__bridge CFDictionaryRef)@{(NSString *)kCGImageSourceShouldCache: @NO});
        
        // get image count
        NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyProperties(self.imageSource, NULL);
        self.loopCount = [[[imageProperties objectForKey:(id)kCGImagePropertyGIFDictionary] objectForKey:(id)kCGImagePropertyGIFLoopCount] unsignedIntegerValue];
        
        // check image source
        if (!self.imageSource) {
            return nil;
        }
        
        CFStringRef imageSourceContainerType = CGImageSourceGetType(_imageSource);
        self.isDynamicImage = UTTypeConformsTo(imageSourceContainerType, kUTTypeGIF);
        self.imagesCount = 0;
        NSUInteger skipImagesCount = 0;
        if (self.isDynamicImage) {
            self.imagesCount = CGImageSourceGetCount(self.imageSource);
            self.flag = (Byte *)malloc(self.imagesCount * sizeof(Byte));
            NSMutableDictionary *delayTimesForIndexesMutable = [NSMutableDictionary dictionaryWithCapacity:self.imagesCount];
            // init every image and it's property
            for (NSUInteger i = 0; i < self.imagesCount; i++) {
                CGImageRef imageRef = CGImageSourceCreateImageAtIndex(_imageSource, i, NULL);
                if (imageRef) {
                    UIImage *image = [UIImage imageWithCGImage:imageRef];
                    CFRelease(imageRef);
                    if (image) {
                        self.flag[i] = 1;
                        // init the cove image (default is the first image)
                        if (!self.coverImage) {
                            self.coverImage = image;
                            self.coverImageIndex = i;
                            [self cacheImage:image AtIndex:i];
                        }
                        
                        NSDictionary *imageProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(self.imageSource, i, NULL);
                        NSDictionary *gifImageProperties = [imageProperties objectForKey:(id)kCGImagePropertyGIFDictionary];
                        // Try to use the unclamped delay time; fall back to the normal delay time.
                        NSNumber *delayTime = [gifImageProperties objectForKey:(id)kCGImagePropertyGIFUnclampedDelayTime];
                        if (!delayTime) {
                            delayTime = [gifImageProperties objectForKey:(id)kCGImagePropertyGIFDelayTime];
                        }
                        // If we don't get a delay time from the properties, fall back to `kDelayTimeIntervalDefault` or carry over the preceding frame's value.
                        if (!delayTime) {
                            delayTime = [self imageDelayTimeBeforeImageIndex:i withImageDelayTimes:delayTimesForIndexesMutable];
                        }
                        
                        // Support frame delays as low as `kFLAnimatedImageDelayTimeIntervalMinimum`, with anything below being rounded up to `kDelayTimeIntervalDefault` for legacy compatibility.
                        // To support the minimum even when rounding errors occur, use an epsilon when comparing. We downcast to float because that's what we get for delayTime from ImageIO.
                        if ([delayTime floatValue] < ((float)kSRAnimatedImageDelayTimeIntervalMinimum - FLT_EPSILON)) {
                            delayTime = @(kDelayTimeIntervalDefault);
                        }
                        delayTimesForIndexesMutable[@(i)] = delayTime;
                        
                    } else {
                        skipImagesCount++;
                        self.flag[i] = 0;
                    }
                } else {
                    skipImagesCount++;
                    self.flag[i] = 0;
                }
            }
            self.delayTimesForImageIndex = [delayTimesForIndexesMutable copy];
            [self cacheImageAtIndex:[self effectiveIndexAfterIndex:self.coverImageIndex]];
        } else {
            self.coverImage = [UIImage imageWithData:data];
            if (self.coverImage) {
                self.imagesCount = 1;
            }
        }
    }
    return self;
}

- (NSNumber *)imageDelayTimeBeforeImageIndex:(NSUInteger)index withImageDelayTimes:(NSDictionary *)imageDelayTimesForIndex {
    if (index == 0 || index == 1) {
        return [NSNumber numberWithDouble:kDelayTimeIntervalDefault];
    } else {
        for (NSUInteger i = index - 1; i > 0; i--) {
            NSNumber *delayTime = [imageDelayTimesForIndex objectForKey:@(i)];
            if (delayTime) {
                return delayTime;
            } else {
                continue;
            }
        }
        return [NSNumber numberWithDouble:kDelayTimeIntervalDefault];
    }
}

// get the cached image for index
- (UIImage *)cachedImageAtIndex:(NSUInteger)index {
    // check the 'index' is available
    if (index >= self.imagesCount) {
        return nil;
    }
    
    if (self.flag[index] == 0) {
        return nil;
    }
    
    // get cached image && clear image for index: (index - 1)
    self.currentDisplayedImageIndex = index;
    UIImage *image = [self.cachedImages objectForKey:@(index)];
    if (image == nil) {
        image = [self imageAtIndex:index];
        [self cacheImage:image AtIndex:index];
    } else {
        [self clearImageAtIndex:[self effectiveIndexBeforeIndex:self.currentDisplayedImageIndex]];
    }
    
    [self cacheImagesIfNeed];
    return image;
}

#pragma mark - Memory Cache

- (void)cacheImageAtIndex:(NSUInteger)index {
    dispatch_async(self.serialQueueForCacheImage, ^(){
        if (index >= self.imagesCount) {
            return;
        }
        if (self.flag[index] == 0) {
            return;
        }
        UIImage *image = [self imageAtIndex:index];
        if (image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cacheImage:image AtIndex:index];
            });
        } else {
            self.flag[index] = 0;
        }
    });
}

- (UIImage *)imageAtIndex:(NSUInteger)index {
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(self.imageSource, index, NULL);
    if (!imageRef) {
        return nil;
    }
    
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    
    // http://stackoverflow.com/questions/14064336/arc-and-cfrelease
    CFRelease(imageRef);
    
    image = [[self class] predrawnImageFromImage:image];
    
    return image;
}

- (void)cacheImage:(UIImage *)image AtIndex:(NSUInteger)index {
    NSUInteger toBeCachedImageIndex1 = [self effectiveIndexAfterIndex:self.currentDisplayedImageIndex];
    NSUInteger toBeCachedImageIndex2 = [self effectiveIndexAfterIndex:toBeCachedImageIndex1];
    if (index == toBeCachedImageIndex1 || toBeCachedImageIndex2 || index) {
        [self.cachedImages setObject:image forKey:@(index)];
    }
}

- (void)clearImageAtIndex:(NSUInteger)index {
    [self.cachedImages removeObjectForKey:@(index)];
}

- (NSUInteger)effectiveIndexBeforeIndex:(NSUInteger)index {
    NSInteger tempIndex;
    if (index == 0) {
        tempIndex = self.imagesCount - 1;
        while (tempIndex > 0) {
            if (self.flag[tempIndex] == 1) {
                return tempIndex;
            }
            tempIndex--;
        }
        return 0;
    } else {
        tempIndex = index - 1;
        while (tempIndex >= 0) {
            if (self.flag[tempIndex] == 1) {
                return tempIndex;
            }
            tempIndex--;
        }
        if (tempIndex == 0) {
            tempIndex = [self effectiveIndexBeforeIndex:0];
        }
        return tempIndex;
    }
}

- (NSUInteger)effectiveIndexAfterIndex:(NSUInteger)index {
    NSUInteger tempIndex;
    if (index == self.imagesCount - 1) {
        tempIndex = 0;
        while (tempIndex < self.imagesCount) {
            if (self.flag[tempIndex] == 1) {
                break;
            }
            tempIndex++;
        }
        if (tempIndex == self.imagesCount) {
            tempIndex = self.imagesCount - 1;
        }
    } else {
        tempIndex = index + 1;
        while (tempIndex < self.imagesCount) {
            if (self.flag[tempIndex] == 1) {
                break;
            }
            tempIndex++;
        }
        if (tempIndex == self.imagesCount) {
            tempIndex = [self effectiveIndexAfterIndex:self.imagesCount - 1];
        }
    }
    return tempIndex;
}

// only cached two images
- (void)cacheImagesIfNeed {
    NSUInteger nextEffectiveIndex = [self effectiveIndexAfterIndex:self.currentDisplayedImageIndex];
    if (![self.cachedImages objectForKey:@(nextEffectiveIndex)]) {
        [self cacheImageAtIndex:nextEffectiveIndex];
    }
    nextEffectiveIndex = [self effectiveIndexAfterIndex:nextEffectiveIndex];
    if (![self.cachedImages objectForKey:@(nextEffectiveIndex)]) {
        [self cacheImageAtIndex:nextEffectiveIndex];
    }
}

// Decodes the image's data and draws it off-screen fully in memory; it's thread-safe and hence can be called on a background thread.
// On success, the returned object is a new `UIImage` instance with the same content as the one passed in.
// On failure, the returned object is the unchanged passed in one; the data will not be predrawn in memory though and an error will be logged.
// First inspired by & good Karma to: https://gist.github.com/steipete/1144242
+ (UIImage *)predrawnImageFromImage:(UIImage *)imageToPredraw
{
    // Always use a device RGB color space for simplicity and predictability what will be going on.
    CGColorSpaceRef colorSpaceDeviceRGBRef = CGColorSpaceCreateDeviceRGB();
    // Early return on failure!
    if (!colorSpaceDeviceRGBRef) {
        return imageToPredraw;
    }
    
    // Even when the image doesn't have transparency, we have to add the extra channel because Quartz doesn't support other pixel formats than 32 bpp/8 bpc for RGB:
    // kCGImageAlphaNoneSkipFirst, kCGImageAlphaNoneSkipLast, kCGImageAlphaPremultipliedFirst, kCGImageAlphaPremultipliedLast
    // (source: docs "Quartz 2D Programming Guide > Graphics Contexts > Table 2-1 Pixel formats supported for bitmap graphics contexts")
    size_t numberOfComponents = CGColorSpaceGetNumberOfComponents(colorSpaceDeviceRGBRef) + 1; // 4: RGB + A
    
    // "In iOS 4.0 and later, and OS X v10.6 and later, you can pass NULL if you want Quartz to allocate memory for the bitmap." (source: docs)
    void *data = NULL;
    size_t width = imageToPredraw.size.width;
    size_t height = imageToPredraw.size.height;
    size_t bitsPerComponent = CHAR_BIT;
    
    size_t bitsPerPixel = (bitsPerComponent * numberOfComponents);
    size_t bytesPerPixel = (bitsPerPixel / BYTE_SIZE);
    size_t bytesPerRow = (bytesPerPixel * width);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    
    CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageToPredraw.CGImage);
    // If the alpha info doesn't match to one of the supported formats (see above), pick a reasonable supported one.
    // "For bitmaps created in iOS 3.2 and later, the drawing environment uses the premultiplied ARGB format to store the bitmap data." (source: docs)
    if (alphaInfo == kCGImageAlphaNone || alphaInfo == kCGImageAlphaOnly) {
        alphaInfo = kCGImageAlphaNoneSkipFirst;
    } else if (alphaInfo == kCGImageAlphaFirst) {
        alphaInfo = kCGImageAlphaPremultipliedFirst;
    } else if (alphaInfo == kCGImageAlphaLast) {
        alphaInfo = kCGImageAlphaPremultipliedLast;
    }
    // "The constants for specifying the alpha channel information are declared with the `CGImageAlphaInfo` type but can be passed to this parameter safely." (source: docs)
    bitmapInfo |= alphaInfo;
    
    // Create our own graphics context to draw to; `UIGraphicsGetCurrentContext`/`UIGraphicsBeginImageContextWithOptions` doesn't create a new context but returns the current one which isn't thread-safe (e.g. main thread could use it at the same time).
    // Note: It's not worth caching the bitmap context for multiple frames ("unique key" would be `width`, `height` and `hasAlpha`), it's ~50% slower. Time spent in libRIP's `CGSBlendBGRA8888toARGB8888` suddenly shoots up -- not sure why.
    CGContextRef bitmapContextRef = CGBitmapContextCreate(data, width, height, bitsPerComponent, bytesPerRow, colorSpaceDeviceRGBRef, bitmapInfo);
    CGColorSpaceRelease(colorSpaceDeviceRGBRef);
    // Early return on failure!
    if (!bitmapContextRef) {
        return imageToPredraw;
    }
    
    // Draw image in bitmap context and create image by preserving receiver's properties.
    CGContextDrawImage(bitmapContextRef, CGRectMake(0.0, 0.0, imageToPredraw.size.width, imageToPredraw.size.height), imageToPredraw.CGImage);
    CGImageRef predrawnImageRef = CGBitmapContextCreateImage(bitmapContextRef);
    UIImage *predrawnImage = [UIImage imageWithCGImage:predrawnImageRef scale:imageToPredraw.scale orientation:imageToPredraw.imageOrientation];
    CGImageRelease(predrawnImageRef);
    CGContextRelease(bitmapContextRef);
    
    // Early return on failure!
    if (!predrawnImage) {        
        return imageToPredraw;
    }
    
    return predrawnImage;
}

#pragma mark - life cycle

- (void)dealloc {
    // free the memory
    free(self.flag);
    if (self.imageSource) {
        CFRelease(self.imageSource);
    }
}

#pragma mark - getters and setters

- (dispatch_queue_t)serialQueueForCacheImage {
    if (!_serialQueueForCacheImage) {
        _serialQueueForCacheImage = dispatch_queue_create("com.flipboard.framecachingqueue", DISPATCH_QUEUE_SERIAL);
    }
    return _serialQueueForCacheImage;
}

- (NSMutableDictionary *)cachedImages {
    if (!_cachedImages) {
        _cachedImages = [[NSMutableDictionary alloc] init];
    }
    return _cachedImages;
}

@end

#pragma mark - FLWeakProxy

@interface SRWeakProxy ()

@property (nonatomic, weak) id target;

@end


@implementation SRWeakProxy

#pragma mark Life Cycle

// This is the designated creation method of an `SRWeakProxy` and
// as a subclass of `NSProxy` it doesn't respond to or need `-init`.
+ (instancetype)weakProxyForObject:(id)targetObject {
    SRWeakProxy *weakProxy = [SRWeakProxy alloc];
    weakProxy.target = targetObject;
    return weakProxy;
}

#pragma mark Forwarding Messages

- (id)forwardingTargetForSelector:(SEL)selector {
    // Keep it lightweight: access the ivar directly
    return _target;
}


#pragma mark - NSWeakProxy Method Overrides
#pragma mark Handling Unimplemented Methods

- (void)forwardInvocation:(NSInvocation *)invocation
{
    // Fallback for when target is nil. Don't do anything, just return 0/NULL/nil.
    // The method signature we've received to get here is just a dummy to keep `doesNotRecognizeSelector:` from firing.
    // We can't really handle struct return types here because we don't know the length.
    void *nullPointer = NULL;
    [invocation setReturnValue:&nullPointer];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    // We only get here if `forwardingTargetForSelector:` returns nil.
    // In that case, our weak target has been reclaimed. Return a dummy method signature to keep `doesNotRecognizeSelector:` from firing.
    // We'll emulate the Obj-c messaging nil behavior by setting the return value to nil in `forwardInvocation:`, but we'll assume that the return value is `sizeof(void *)`.
    // Other libraries handle this situation by making use of a global method signature cache, but that seems heavier than necessary and has issues as well.
    // See https://www.mikeash.com/pyblog/friday-qa-2010-02-26-futures.html and https://github.com/steipete/PSTDelegateProxy/issues/1 for examples of using a method signature cache.
    return [NSObject instanceMethodSignatureForSelector:@selector(init)];
}

@end
