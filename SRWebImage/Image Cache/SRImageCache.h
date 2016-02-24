//
//  SRImageCache.h
//  SRWebImage
//
//  Created by shoron on 2/23/16.
//  Copyright © 2016 YSR. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SDImageCacheType) {
    /**
     * The image wasn't available the SRWebImage caches, but was downloaded from the web.
     */
    SDImageCacheTypeNone,
    /**
     * The image was obtained from the disk cache.
     */
    SDImageCacheTypeDisk,
    /**
     * The image was obtained from the memory cache.
     */
    SDImageCacheTypeMemory
};

@interface SRImageCache : NSObject

/**
 * Returns global shared cache instance
 *
 * @return SRImageCache global instance
 */
+(instancetype)sharedImageCache;

/**
 * Store an image into memory and optionally disk cache at the given key.
 *
 * @param image  The image to store
 * @param key    The unique image cache key, usually it's image absolute URL
 * @param toDisk Store the image to disk cache if YES
 */
- (void)storeImageData:(NSData *)data forKey:(NSString *)key toDisk:(BOOL)toDisk;

- (BOOL)imageHasCachedForKey:(NSString *)key;

/**
 *  return the cached image for the current key
 *
 *  @param key image key
 *
 *  @return if the image is gif, return SRAnimatedImage otherwhise return UIImage
 */
- (id)cachedImageForKey:(NSString *)key;

- (NSUInteger)imageCachedSize;
- (void)clearMemoryCache;
- (void)clearDiskCache;

@end
