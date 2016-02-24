//
//  UIImageView+AnimatedImage.m
//  SRWebImage
//
//  Created by shoron on 2/22/16.
//  Copyright © 2016 YSR. All rights reserved.
//

#import "UIImageView+AnimatedImage.h"
#import <objc/runtime.h>

static const void *kAnimatedImage = &kAnimatedImage;
static const void *kCurrentImage = &kCurrentImage;
static const void *kCurrentImageIndex = &kCurrentImageIndex;
static const void *kAccumulator = &kAccumulator;
static const void *kDisplayLink = &kDisplayLink;
static const void *kShouldAniate = &kShouldAniate;
static const void *kLoopCountRemaining = &kLoopCountRemaining;
static const void *kRunLoopMode = &kRunLoopMode;
static const void *kNeedsDisplayWhenImageBecomesAvailable = &kNeedsDisplayWhenImageBecomesAvailable;

@interface UIImageView ()

// current displayed image and it's index
@property (nonatomic, strong) UIImage *currentImage;
@property (nonatomic, assign) NSUInteger currentImageIndex;

// time accumulator
@property (nonatomic, assign) NSTimeInterval accumulator;

@property (nonatomic, strong) CADisplayLink *displayLink;

@property (nonatomic, assign) BOOL shouldAnimate;

// the remaining loop count
@property (nonatomic, assign) NSUInteger loopCountRemaining;

@property (nonatomic, assign) BOOL needsDisplayWhenImageBecomesAvailable;

// The animation runloop mode. Enables playback during scrolling by allowing timer events (i.e. animation) with NSRunLoopCommonModes.
// To keep scrolling smooth on single-core devices such as iPhone 3GS/4 and iPod Touch 4th gen, the default run loop mode is NSDefaultRunLoopMode. Otherwise, the default is NSDefaultRunLoopMode.
@property (nonatomic, copy) NSString *runLoopMode;

@end

@implementation UIImageView (AnimatedImage)

@dynamic animatedImage;

#pragma mark - Initializers

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.runLoopMode = [[self class] defaultRunLoopMode];
}

#pragma mark - Life Cycle

- (void)dealloc {
    // Removes the display link from all run loop modes.
    [self.displayLink invalidate];
}

#pragma mark - animate

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimatingForAnimatedImage];
    } else {
        [self stopAnimatingForAnimatedImage];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimatingForAnimatedImage];
    } else {
        [self stopAnimatingForAnimatedImage];
    }
}

- (void)setAlpha:(CGFloat)alpha {
    [super setAlpha:alpha];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimatingForAnimatedImage];
    } else {
        [self stopAnimatingForAnimatedImage];
    }
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    
    [self updateShouldAnimate];
    if (self.shouldAnimate) {
        [self startAnimatingForAnimatedImage];
    } else {
        [self stopAnimatingForAnimatedImage];
    }
}

- (NSTimeInterval)frameDelayGreatestCommonDivisor {
    // Presision is set to half of the `kSRAnimatedImageDelayTimeIntervalMinimum` in order to minimize frame dropping.
    const NSTimeInterval kGreatestCommonDivisorPrecision = 2.0 / kSRAnimatedImageDelayTimeIntervalMinimum;
    
    NSArray *delays = self.animatedImage.delayTimesForImageIndex.allValues;
    
    // Scales the frame delays by `kGreatestCommonDivisorPrecision`
    // then converts it to an UInteger for in order to calculate the GCD.
    NSUInteger scaledGCD = lrint([delays.firstObject floatValue] * kGreatestCommonDivisorPrecision);
    for (NSNumber *value in delays) {
        scaledGCD = gcd(lrint([value floatValue] * kGreatestCommonDivisorPrecision), scaledGCD);
    }
    
    // Reverse to scale to get the value back into seconds.
    return scaledGCD / kGreatestCommonDivisorPrecision;
}

static NSUInteger gcd(NSUInteger a, NSUInteger b) {
    // http://en.wikipedia.org/wiki/Greatest_common_divisor
    if (a < b) {
        return gcd(b, a);
    } else if (a == b) {
        return b;
    }
    
    while (true) {
        NSUInteger remainder = a % b;
        if (remainder == 0) {
            return b;
        }
        a = b;
        b = remainder;
    }
}

- (void)startAnimatingForAnimatedImage {
    if (self.animatedImage && self.animatedImage.isDynamicImage) {
        // Lazily create the display link.
        if (!self.displayLink) {
            // It is important to note the use of a weak proxy here to avoid a retain cycle. `-displayLinkWithTarget:selector:`
            // will retain its target until it is invalidated. We use a weak proxy so that the image view will get deallocated
            // independent of the display link's lifetime. Upon image view deallocation, we invalidate the display
            // link which will lead to the deallocation of both the display link and the weak proxy.
            SRWeakProxy *weakProxy = [SRWeakProxy weakProxyForObject:self];
            self.displayLink = [CADisplayLink displayLinkWithTarget:weakProxy selector:@selector(displayDidRefresh:)];
            [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:self.runLoopMode];
        }
        
        // Note: The display link's `.frameInterval` value of 1 (default) means getting callbacks at the refresh rate of the display (~60Hz).
        // Setting it to 2 divides the frame rate by 2 and hence calls back at every other display refresh.
        const NSTimeInterval kDisplayRefreshRate = 60.0; // 60Hz
        self.displayLink.frameInterval = MAX([self frameDelayGreatestCommonDivisor] * kDisplayRefreshRate, 1);
        
        self.displayLink.paused = NO;
    } else {
        [self startAnimating];
    }
}

- (void)stopAnimatingForAnimatedImage {
    if (self.animatedImage && self.animatedImage.isDynamicImage) {
        self.displayLink.paused = YES;
    } else {
        [self stopAnimating];
    }
}

- (BOOL)isAnimatingForAnimatedImage {
    BOOL isAnimating = NO;
    if (self.animatedImage && self.animatedImage.isDynamicImage) {
        isAnimating = self.displayLink && !self.displayLink.isPaused;
    } else {
        isAnimating = [self isAnimating];
    }
    return isAnimating;
}

- (void)updateShouldAnimate {
    BOOL isVisible = self.window && self.superview && ![self isHidden] && self.alpha > 0.0;
    self.shouldAnimate = self.animatedImage != nil && self.animatedImage.isDynamicImage && isVisible;
}

- (void)displayDidRefresh:(CADisplayLink *)displayLink {
    // If for some reason a wild call makes it through when we shouldn't be animating, bail.
    // Early return!
    [self updateShouldAnimate];
    if (!self.shouldAnimate) {
        return;
    }
    
    NSNumber *delayTimeNumber = [self.animatedImage.delayTimesForImageIndex objectForKey:@(self.currentImageIndex)];
    // If we don't have a frame delay (e.g. corrupt frame), don't update the view but skip the playhead to the next frame (in else-block).
    if (delayTimeNumber) {
        NSTimeInterval delayTime = [delayTimeNumber floatValue];
        // If we have a nil image (e.g. waiting for frame), don't update the view nor playhead.
        UIImage *image = [self.animatedImage cachedImageAtIndex:self.currentImageIndex];
        if (image) {
            self.currentImage = image;
            if (self.needsDisplayWhenImageBecomesAvailable) {
                [self.layer setNeedsDisplay];
                self.needsDisplayWhenImageBecomesAvailable = NO;
            }
            
            self.accumulator += displayLink.duration * displayLink.frameInterval;
            
            // While-loop first inspired by & good Karma to: https://github.com/ondalabs/OLImageView/blob/master/OLImageView.m
            while (self.accumulator >= delayTime) {
                self.accumulator -= delayTime;
                self.currentImageIndex = [self.animatedImage effectiveIndexAfterIndex:self.currentImageIndex];
                
                if (self.currentImageIndex == self.animatedImage.coverImageIndex) {
                    self.loopCountRemaining--;
                    if (self.loopCountRemaining == 0) {
                        [self stopAnimatingForAnimatedImage];
                        return;
                    }
                }
                
                // Calling `-setNeedsDisplay` will just paint the current frame, not the new frame that we may have moved to.
                // Instead, set `needsDisplayWhenImageBecomesAvailable` to `YES` -- this will paint the new image once loaded.
                self.needsDisplayWhenImageBecomesAvailable = YES;
            }
        } else {
            self.currentImageIndex = [self.animatedImage effectiveIndexAfterIndex:self.currentImageIndex];
        }
    } else {
        self.currentImageIndex = [self.animatedImage effectiveIndexAfterIndex:self.currentImageIndex];
    }
}

#pragma mark - Auto Layout

- (CGSize)intrinsicContentSize {
    // Default to let UIImageView handle the sizing of its image, and anything else it might consider.
    CGSize intrinsicContentSize = [super intrinsicContentSize];
    
    // If we have have an animated image, use its image size.
    // UIImageView's intrinsic content size seems to be the size of its image. The obvious approach, simply calling `-invalidateIntrinsicContentSize` when setting an animated image, results in UIImageView steadfastly returning `{UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric}` for its intrinsicContentSize.
    // (Perhaps UIImageView bypasses its `-image` getter in its implementation of `-intrinsicContentSize`, as `-image` is not called after calling `-invalidateIntrinsicContentSize`.)
    if (self.animatedImage) {
        intrinsicContentSize = self.image.size;
    }
    
    return intrinsicContentSize;
}

#pragma mark - run loop

+ (NSString *)defaultRunLoopMode {
    // Key off `activeProcessorCount` (as opposed to `processorCount`) since the system could shut down cores in certain situations.
    return [NSProcessInfo processInfo].activeProcessorCount > 1 ? NSRunLoopCommonModes : NSDefaultRunLoopMode;
}

#pragma mark - getters and setters

- (SRAnimatedImage *)animatedImage {
    return objc_getAssociatedObject(self, kAnimatedImage);
}

- (void)setAnimatedImage:(SRAnimatedImage *)animatedImage {
    self.runLoopMode = [[self class] defaultRunLoopMode];
    if (![self.animatedImage isEqual:animatedImage] || animatedImage != nil) {
        if (animatedImage) {
            objc_setAssociatedObject(self, kAnimatedImage, animatedImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            // Ensure disabled highlighting; it's not supported (see `-setHighlighted:`).
            self.highlighted = NO;
            // UIImageView seems to bypass some accessors when calculating its intrinsic content size, so this ensures its intrinsic content size comes from the animated image.
            [self invalidateIntrinsicContentSize];
            
            if (!animatedImage.isDynamicImage) {
                self.image = animatedImage.coverImage;
            } else {
                self.currentImage = animatedImage.coverImage;
                self.currentImageIndex = animatedImage.coverImageIndex;
                self.accumulator = 0.0;
                if (animatedImage.loopCount == 0) {
                    self.loopCountRemaining = NSUIntegerMax;
                } else {
                    self.loopCountRemaining = animatedImage.loopCount + 1;
                }
                
                [self.layer setNeedsDisplay];
                
                // Start animating after the new animated image has been set.
                // TODO: add
                [self updateShouldAnimate];
                if (self.shouldAnimate) {
                    [self startAnimatingForAnimatedImage];
                }
                
                [self.layer setNeedsDisplay];
            }
        } else {
            
        }
    }
}


- (void)setRunLoopMode:(NSString *)runLoopMode {
    if (![@[NSDefaultRunLoopMode, NSRunLoopCommonModes] containsObject:runLoopMode]) {
        NSAssert(NO, @"Invalid run loop mode: %@", runLoopMode);
        objc_setAssociatedObject(self, kRunLoopMode, [[self class] defaultRunLoopMode], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        objc_setAssociatedObject(self, kRunLoopMode, runLoopMode, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (NSString *)runLoopMode {
    return objc_getAssociatedObject(self, kRunLoopMode);
}



- (UIImage *)image {
    UIImage *image = nil;
    if (self.animatedImage) {
        // Initially set to the poster image.
        image = self.currentImage;
    } else {
        image = self.image;
    }
    return image;
}

- (void)setImage:(UIImage *)image {
    if (image) {
        // Clear out the animated image and implicitly pause animation playback.
        self.animatedImage = nil;
    }
    self.image = image;
}

- (void)setCurrentImage:(UIImage *)currentImage {
    objc_setAssociatedObject(self, kCurrentImage, currentImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIImage *)currentImage {
    return objc_getAssociatedObject(self, kCurrentImage);
}

- (void)setCurrentImageIndex:(NSUInteger)currentImageIndex {
    objc_setAssociatedObject(self, kCurrentImageIndex, [NSNumber numberWithUnsignedInteger:currentImageIndex], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSUInteger)currentImageIndex {
    return [objc_getAssociatedObject(self, kCurrentImageIndex) unsignedIntegerValue];
}

- (NSTimeInterval)accumulator {
    return (NSTimeInterval)[objc_getAssociatedObject(self, kAccumulator) doubleValue];
}

- (void)setAccumulator:(NSTimeInterval)accumulator {
    objc_setAssociatedObject(self, kAccumulator, [NSNumber numberWithDouble:accumulator], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setDisplayLink:(CADisplayLink *)displayLink {
    objc_setAssociatedObject(self, kDisplayLink, displayLink, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CADisplayLink *)displayLink {
    return objc_getAssociatedObject(self, kDisplayLink);
}

- (BOOL)shouldAnimate {
    NSNumber *animate = objc_getAssociatedObject(self, kShouldAniate);
    if (animate) {
        return animate.boolValue;
    } else {
        return NO;
    }
}

- (void)setShouldAnimate:(BOOL)shouldAnimate {
    objc_setAssociatedObject(self, kShouldAniate, [NSNumber numberWithBool:shouldAnimate], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setLoopCountRemaining:(NSUInteger)loopCountRemaining {
    objc_setAssociatedObject(self, kLoopCountRemaining, [NSNumber numberWithUnsignedInteger:loopCountRemaining], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSUInteger)loopCountRemaining {
    return [objc_getAssociatedObject(self, kLoopCountRemaining) unsignedIntegerValue];
}

- (BOOL)needsDisplayWhenImageBecomesAvailable {
    NSNumber *needDisplay = (objc_getAssociatedObject(self, kNeedsDisplayWhenImageBecomesAvailable));
    if (needDisplay) {
        return needDisplay.boolValue;
    } else {
        return NO;
    }
}

- (void)setNeedsDisplayWhenImageBecomesAvailable:(BOOL)needsDisplayWhenImageBecomesAvailable {
    objc_setAssociatedObject(self, kNeedsDisplayWhenImageBecomesAvailable, [NSNumber numberWithBool:needsDisplayWhenImageBecomesAvailable], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - CALayerDelegate (Informal)
#pragma mark Providing the Layer's Content

- (void)displayLayer:(CALayer *)layer {
    layer.contents = (__bridge id)self.image.CGImage;
}

@end