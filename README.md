# SRWebImage

## 展示动图
本文做的这个展示动图的这个库是根据 FLAnimatedImage 修改而来。性能方面和 FLAnimatedImage 相差不大。

## 大体思路

1. 拿到动图的相关信息。图片数，每张图片展示的时长以及循环播放的次数等。
2. 然后根据CADisplayLink来刷新ImageView。
3. 当加载第i张图片时，开启一个线程从动图的Data中取出第i＋1，i＋1张图，缓存起来，并把i－1张图从内存中清掉。
4. 另外处理了一下，setHidden，setAlpha，moveToWindow，moveToSuperView等情况。
