// Gzowo Concierge for macOS - now playing bridge: loaded into /usr/bin/perl (macOS still lets it read MediaRemote), prints one JSON line per change and runs commands read from stdin.
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*ClientStringFn)(id);
typedef Boolean (*SendFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

static RegisterFn registerFn;
static GetInfoFn getInfo;
static GetPlayingFn getPlaying;
static GetClientFn getClient;
static ClientStringFn clientBundle, clientParent, clientName;
static SendFn sendCommand;
static SetElapsedFn setElapsed;
static dispatch_queue_t queue;
static NSString *sentArt;
static uint64_t generation;

static id clean(id v) { return v && v != [NSNull null] ? v : nil; }

static void write_line(NSDictionary *d) {
  NSData *json = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
  if (!json) return;
  fwrite(json.bytes, 1, json.length, stdout);
  fputc('\n', stdout);
  fflush(stdout);
}

static void emit(BOOL forceArt) {
  getInfo(queue, ^(CFDictionaryRef ref) {
    NSDictionary *info = [(__bridge NSDictionary *)ref copy];
    getClient(queue, ^(id client) {
      NSString *bundle = nil, *parent = nil, *name = nil;
      if (client) {
        if (clientBundle) bundle = (__bridge NSString *)clientBundle(client);
        if (clientParent) parent = (__bridge NSString *)clientParent(client);
        if (clientName) name = (__bridge NSString *)clientName(client);
      }
      getPlaying(queue, ^(Boolean playing) {
        NSString *title = clean(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
        if (!info || title.length == 0) { sentArt = nil; write_line(@{ @"type": @"np", @"empty": @YES }); return; }
        NSMutableDictionary *o = [@{ @"type": @"np", @"title": title, @"playing": @(playing) } mutableCopy];
        NSString *artist = clean(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
        NSString *album = clean(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
        if (artist.length) o[@"artist"] = artist;
        if (album.length) o[@"album"] = album;
        NSNumber *duration = clean(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
        NSNumber *elapsed = clean(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
        NSNumber *rate = clean(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
        NSDate *ts = clean(info[@"kMRMediaRemoteNowPlayingInfoTimestamp"]);
        if (duration) o[@"duration"] = duration;
        if (elapsed) o[@"elapsed"] = elapsed;
        if (rate) o[@"rate"] = rate;
        o[@"ts"] = @((ts ?: [NSDate date]).timeIntervalSince1970);
        NSString *app = parent.length ? parent : bundle;
        if (app.length) o[@"bundle"] = app;
        if (name.length) o[@"client"] = name;
        NSData *art = clean(info[@"kMRMediaRemoteNowPlayingInfoArtworkData"]);
        NSString *artId = clean(info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"]);
        if (art.length) {
          NSString *key = artId.length ? artId : [NSString stringWithFormat:@"%@|%lu", title, (unsigned long)art.length];
          o[@"artId"] = key;
          if (forceArt || ![key isEqualToString:sentArt]) { o[@"art"] = [art base64EncodedStringWithOptions:0]; sentArt = key; }
        } else {
          sentArt = nil;
        }
        write_line(o);
      });
    });
  });
}

static void schedule(void) {
  uint64_t mine = ++generation;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_MSEC), queue, ^{ if (mine == generation) emit(NO); });
}

static void run_command(NSString *line) {
  NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
  NSString *cmd = parts.firstObject;
  NSDictionary<NSString *, NSNumber *> *codes = @{ @"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"prev": @5 };
  if (codes[cmd]) { sendCommand(codes[cmd].intValue, NULL); return; }
  if ([cmd isEqualToString:@"seek"] && parts.count > 1 && setElapsed) { setElapsed(parts[1].doubleValue); dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), queue, ^{ emit(NO); }); return; }
  if ([cmd isEqualToString:@"refresh"]) dispatch_async(queue, ^{ emit(YES); });
}

static void read_commands(void) {
  [NSThread detachNewThreadWithBlock:^{
    char buf[512];
    while (fgets(buf, sizeof buf, stdin)) {
      NSString *line = [[NSString stringWithUTF8String:buf] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (line.length) run_command(line);
    }
    exit(0);
  }];
}

void np_run(void *a, void *b) {
  void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
  if (!h) { write_line(@{ @"type": @"error", @"message": @"no MediaRemote" }); exit(1); }
  registerFn = (RegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
  getInfo = (GetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
  getPlaying = (GetPlayingFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
  getClient = (GetClientFn)dlsym(h, "MRMediaRemoteGetNowPlayingClient");
  clientBundle = (ClientStringFn)dlsym(h, "MRNowPlayingClientGetBundleIdentifier");
  clientParent = (ClientStringFn)dlsym(h, "MRNowPlayingClientGetParentAppBundleIdentifier");
  clientName = (ClientStringFn)dlsym(h, "MRNowPlayingClientGetDisplayName");
  sendCommand = (SendFn)dlsym(h, "MRMediaRemoteSendCommand");
  setElapsed = (SetElapsedFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
  if (!registerFn || !getInfo || !getPlaying || !getClient || !sendCommand) { write_line(@{ @"type": @"error", @"message": @"missing symbols" }); exit(1); }
  queue = dispatch_queue_create("fun.gzowo.concierge.nowplaying", DISPATCH_QUEUE_SERIAL);
  registerFn(queue);
  for (NSString *name in @[ @"kMRMediaRemoteNowPlayingInfoDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification", @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange", @"kMRMediaRemotePlaybackStateDidChangeNotification" ]) {
    [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) { schedule(); }];
  }
  write_line(@{ @"type": @"ready" });
  read_commands();
  dispatch_async(queue, ^{ emit(YES); });
  CFRunLoopRun();
}
