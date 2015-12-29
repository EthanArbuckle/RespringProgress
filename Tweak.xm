#import <objc/runtime.h>
#import <libkern/OSAtomic.h>

@interface PUIProgressWindow : NSObject
- (void)setProgressValue:(float)arg1;
- (void)_createLayer;
- (void)setVisible:(BOOL)arg1;
@end

CFDataRef receiveProgress(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info);

PUIProgressWindow *window;

%hook PUIProgressWindow

- (id)initWithProgressBarVisibility:(BOOL)arg1 createContext:(BOOL)arg2 contextLevel:(float)arg3 appearance:(int)arg4 {

    window = %orig(YES, arg2, arg3, arg4);
    [window setProgressValue:0.01];

    CFMessagePortRef port = CFMessagePortCreateLocal(kCFAllocatorDefault, CFSTR("com.ethanarbuckle.launch-progress"), &receiveProgress, NULL, NULL);
    CFMessagePortSetDispatchQueue(port, dispatch_get_main_queue());

    return window;
}

CFDataRef receiveProgress(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {

    NSData *receivedData = (NSData *)data;
    int progressPointer;
    [receivedData getBytes:&progressPointer length:sizeof(progressPointer)];

    [window setProgressValue:(float)progressPointer / 100];
    [window _createLayer];
    [window setVisible:YES];

    return NULL;
}

%end

static volatile int64_t ping = 0;

//1 counts every init, but takes the longest. Higher the number, fast the loading, but less accurate. i like 8-12
int classSkipCount = 8;
int averageObjectCount = pow(10, 7); //assuming this is how many objects SB creates (9.0 on 6s+ will be close to this)

%hook SBMappedImageCache //first SB class called in SpringBoards entrypoint

+ (id)persistentCache {

    __block clock_t begin, end;
    __block double time_spent;
    begin = clock();

    static dispatch_once_t swizzleOnce;
    dispatch_once(&swizzleOnce, ^{

        NSDictionary *storedData = [[NSDictionary alloc] initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.abusing_sb.plist"];
        if (![storedData valueForKey:@"deviceInits"]) {
            classSkipCount = 1;
        } else {
            averageObjectCount = [[storedData valueForKey:@"deviceInits"] intValue];
        }

        dispatch_queue_t progressThread =  dispatch_queue_create("progressThread", DISPATCH_QUEUE_CONCURRENT);
        dispatch_async(progressThread, ^{

            CFMessagePortRef port = CFMessagePortCreateRemote(kCFAllocatorDefault, CFSTR("com.ethanarbuckle.launch-progress"));

            int32_t local = 0;
            while (ping <= (averageObjectCount / classSkipCount) && ping > -1) {

                int32_t currentProgress = ((float)100 / (averageObjectCount / classSkipCount)) * ping;

                if (currentProgress > local && (((currentProgress % 6) == 0) || currentProgress >= 95)) { //6 seems to be a good interval to prevent screen flashes

                    local = currentProgress;
                    if (port > 0) {

                        int progressPointer = local;
                        NSData *progressMessage = [NSData dataWithBytes:&local length:sizeof(progressPointer)];
                        CFMessagePortSendRequest(port, 0, (CFDataRef)progressMessage, 1000, 0, NULL, NULL);
                    }
                }

            }

        });

        uint32_t totalClasses = 0;
        Class *classBuffer = objc_copyClassList(&totalClasses);
        int jumpAhead = 0;

        for (int i = 0; i < totalClasses; i++) {

            if (strncmp(object_getClassName(classBuffer[i]), "SB", 2) == 0) {

                if ((jumpAhead++ % classSkipCount) == 0) { //save some resources and time by only swapping every nth class

                    Method originalMethod = class_getInstanceMethod(classBuffer[i], @selector(init));
                    if (originalMethod != NULL) {

                        IMP originalImp = class_getMethodImplementation(classBuffer[i], @selector(init));
                        IMP newImp = imp_implementationWithBlock(^(id _self, SEL selector) {

                            if (ping > -1) {
                                OSAtomicIncrement64(&ping);
                            }

                            return originalImp(_self, @selector(init));
                        });

                        method_setImplementation(originalMethod, newImp);

                    }
                }
            }
        }

        IMP originalFinishBlock = class_getMethodImplementation(objc_getClass("SBUIController"), @selector(finishLaunching));
        IMP newFinishBlock = imp_implementationWithBlock(^(id _self, SEL selector) {
            originalFinishBlock(_self, @selector(finishLaunching));
            int64_t finalObjectCount = ping;
            ping = -1;
            end = clock();
            time_spent = (double)(end - begin) / CLOCKS_PER_SEC;
            HBLogDebug(@"Springboard launched with %lld -init calls, estimation of %d off by %.2f%%, in %.2f seconds", finalObjectCount, averageObjectCount, (ABS(finalObjectCount - ((float)averageObjectCount / classSkipCount)) / ((finalObjectCount + ((float)averageObjectCount / classSkipCount)) / 2)) * 100, time_spent);

            if (![storedData valueForKey:@"deviceInits"]) {
                NSDictionary *newData = @{ @"deviceInits" : @(finalObjectCount) };
                [newData writeToFile:@"/var/mobile/Library/Preferences/com.abusing_sb.plist" atomically:YES];
            }

        });

        method_setImplementation(class_getInstanceMethod(objc_getClass("SBUIController"), @selector(finishLaunching)), newFinishBlock);

    });

    return %orig;

}

%end