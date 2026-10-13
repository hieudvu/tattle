// libTattleNowPlaying: reads macOS's Now Playing state and prints one JSON line
// whenever it changes ("null" when nothing is playing).
//
// WHY THIS IS LOADED BY /usr/bin/perl: since macOS 15.4 the private MediaRemote
// framework only answers Apple-signed processes (a third-party process gets nil).
// /usr/bin/perl is Apple-signed and can dlopen a helper, so Tattle launches
//     perl -MDynaLoader -e '...dl_install_xsub...' libTattleNowPlaying.dylib
// and reads this output. Private API: it can break on any macOS update, so Tattle
// treats "no output" as "no titles", never as an error.
//
// The entry point is called by perl as an XSUB; it loops until its parent dies.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

typedef void (^InfoCallback)(CFDictionaryRef);
typedef void (^ClientCallback)(void *);

// MRCommand values: 0 play, 1 pause, 2 toggle, 4 next, 5 previous.
static void ReadCommands(void *mr) {
    BOOL (*send)(int, CFDictionaryRef) = dlsym(mr, "MRMediaRemoteSendCommand");
    if (!send) return;
    char buf[64];
    while (fgets(buf, sizeof buf, stdin)) {
        NSString *c = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        int cmd = -1;
        if ([c isEqualToString:@"play"]) cmd = 0;
        else if ([c isEqualToString:@"pause"]) cmd = 1;
        else if ([c isEqualToString:@"toggle"]) cmd = 2;
        else if ([c isEqualToString:@"next"]) cmd = 4;
        else if ([c isEqualToString:@"previous"]) cmd = 5;
        if (cmd >= 0) send(cmd, NULL);
    }
}

static NSString *Str(CFStringRef s) { return s ? (__bridge NSString *)s : nil; }

void tattle_nowplaying_stream(void) {
    @autoreleasepool {
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (!mr) { fputs("tattle-nowplaying: cannot load MediaRemote\n", stderr); return; }
        void (*getInfo)(dispatch_queue_t, InfoCallback) = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        void (*getClient)(dispatch_queue_t, ClientCallback) = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
        CFStringRef (*clientBundle)(void *) = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
        CFStringRef (*clientParent)(void *) = dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
        if (!getInfo) { fputs("tattle-nowplaying: MediaRemote has no GetNowPlayingInfo\n", stderr); return; }

        setvbuf(stdout, NULL, _IOLBF, 0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ ReadCommands(mr); });
        pid_t parent = getppid();
        NSString *last = nil;
        dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);

        while (getppid() == parent) {
            @autoreleasepool {
                __block NSDictionary *info = nil;
                dispatch_semaphore_t done = dispatch_semaphore_create(0);
                getInfo(queue, ^(CFDictionaryRef d) {
                    if (d) info = [(__bridge NSDictionary *)d copy];
                    dispatch_semaphore_signal(done);
                });
                dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));

                __block NSString *bundleID = nil, *parentID = nil;
                if (info.count && getClient && clientBundle) {
                    dispatch_semaphore_t got = dispatch_semaphore_create(0);
                    getClient(queue, ^(void *client) {
                        if (client) {
                            bundleID = Str(clientBundle(client));
                            if (clientParent) parentID = Str(clientParent(client));
                        }
                        dispatch_semaphore_signal(got);
                    });
                    dispatch_semaphore_wait(got, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
                }

                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
                if ([title isKindOfClass:NSString.class] && title.length) {
                    out[@"title"] = title;
                    id artist = info[@"kMRMediaRemoteNowPlayingInfoArtist"];
                    id album = info[@"kMRMediaRemoteNowPlayingInfoAlbum"];
                    id rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                    if ([artist isKindOfClass:NSString.class]) out[@"artist"] = artist;
                    if ([album isKindOfClass:NSString.class]) out[@"album"] = album;
                    if ([rate isKindOfClass:NSNumber.class]) out[@"rate"] = rate;
                    if (bundleID) out[@"bundleID"] = bundleID;
                    if (parentID) out[@"parentBundleID"] = parentID;
                }

                NSString *line = @"null";
                if (out.count) {
                    NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
                    if (json) line = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
                }
                if (![line isEqualToString:last]) {
                    printf("%s\n", line.UTF8String);
                    last = line;
                }
            }
            usleep(400000);
        }
    }
}
