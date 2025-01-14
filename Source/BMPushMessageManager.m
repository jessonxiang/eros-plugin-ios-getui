//
//  BMPushMessageManager.m
//  BM-JYT
//
//  Created by XHY on 2017/3/2.
//  Copyright © 2017年 XHY. All rights reserved.
//

#import "BMPushMessageManager.h"
#import "BMGlobalEventManager.h"
#import "BMConfigManager.h"
#import "BMMediatorManager.h"

// iOS10 及以上需导入 UserNotifications.framework
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
#import <UserNotifications/UserNotifications.h>
#endif

@interface BMPushMessageManager () <UNUserNotificationCenterDelegate>
{
    NSString *_cid;
    NSString *_deviceToken;
    NSDictionary *_pushMessage;
}

@end

@implementation BMPushMessageManager

#pragma mark - Setter / Getter

#pragma mark - Private Method

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)shareInstance
{
    static BMPushMessageManager *_instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[BMPushMessageManager alloc] init];
    });
    
    return _instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)appDidEnterBackground
{
    self.isLaunchedByNotification = YES;
}

- (void)appDidBecomeActive
{
    self.isLaunchedByNotification = NO;
}

/**
 解析push消息、透传消息
 
 @param userInfo 消息体
 */
- (void)analysisRemoteNotification:(NSDictionary *)userInfo
{
    if (![BMMediatorManager shareInstance].currentWXInstance) {
        [[self class] addPushNotification:userInfo];
        return;
    }
    
    [BMGlobalEventManager pushMessage:userInfo appLaunchedByNotification:self.isLaunchedByNotification];
}

/** 当首屏渲染完毕通知响应方法 */
- (void)firstScreenDidFinished:(NSNotification *)not
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isLaunchedByNotification = YES;
        [self analysisRemoteNotification:_pushMessage];
        _pushMessage = nil;
    });
    [[NSNotificationCenter defaultCenter] removeObserver:[BMPushMessageManager shareInstance] name:BMFirstScreenDidFinish object:nil];
}

/* 注册push推送服务 */
- (void)registerRemoteNotification
{
    /*
     警告：Xcode8 需要手动开启"TARGETS -> Capabilities -> Push Notifications"
     */
    
    /*
     警告：该方法需要开发者自定义，以下代码根据 APP 支持的 iOS 系统不同，代码可以对应修改。
     以下为演示代码，注意根据实际需要修改，注意测试支持的 iOS 系统都能获取到 DeviceToken
     */
    if ([[UIDevice currentDevice].systemVersion floatValue] >= 10.0) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0 // Xcode 8编译会调用
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        center.delegate = self;
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert | UNAuthorizationOptionCarPlay) completionHandler:^(BOOL granted, NSError *_Nullable error) {
            if (!error) {
                WXLogInfo(@"request authorization succeeded!");
            }
        }];
        
        [[UIApplication sharedApplication] registerForRemoteNotifications];
#else // Xcode 7编译会调用
        UIUserNotificationType types = (UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge);
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
#endif
    } else if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
        UIUserNotificationType types = (UIUserNotificationTypeAlert | UIUserNotificationTypeSound | UIUserNotificationTypeBadge);
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
        [[UIApplication sharedApplication] registerForRemoteNotifications];
        [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    }
}

#pragma mark - Api Request

#pragma mark - Custom Delegate & DataSource

- (void)GeTuiSdkDidRegisterClient:(NSString *)clientId
{
    /* 将cid保存 */
    _cid = clientId;
    
    WXLogInfo(@"GE TUI CID:%@",clientId);
    
    if (_deviceToken) {
        [GeTuiSdk registerDeviceToken:_deviceToken];
    }
}

- (void)GeTuiSdkDidOccurError:(NSError *)error
{
    WXLogInfo(@"GETUI OCCUR ERROR: %@",error);
}

- (void)GeTuiSDkDidNotifySdkState:(SdkStatus)aStatus
{
    NSString *status = @"正在启动";
    if (aStatus == SdkStatusStarted) {
        status = @"正常运行";
    } else if (aStatus == SdkStatusStoped)
    {
        status = @"暂停运行";
    }
    WXLogInfo(@"个推SDK状态变化：%@",status);
}

/** SDK收到透传消息回调 */
- (void)GeTuiSdkDidReceivePayloadData:(NSData *)payloadData andTaskId:(NSString *)taskId andMsgId:(NSString *)msgId andOffLine:(BOOL)offLine fromGtAppId:(NSString *)appId {
    //收到个推消息
    NSString *payloadMsg = nil;
    if (payloadData) {
        payloadMsg = [[NSString alloc] initWithBytes:payloadData.bytes length:payloadData.length encoding:NSUTF8StringEncoding];
    }
    
    if (offLine || !payloadMsg || payloadMsg.length == 0) {
        return;
    }
    
    /* 解析消息内容 */
    NSData *data = [payloadMsg dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    NSString *payloadStr = dic[@"payload"];
    data = [payloadStr dataUsingEncoding:NSUTF8StringEncoding];
    dic = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
    [self analysisRemoteNotification:dic];
    
}

#pragma mark - System Delegate & DataSource

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0

//  iOS 10: App在前台获取到通知
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    
    WXLogInfo(@"willPresentNotification：%@", notification.request.content.userInfo);
    
    NSDictionary *userInfo = notification.request.content.userInfo;
    
    [self analysisRemoteNotification:userInfo];
    
    // [ GTSdk ]：将收到的APNs信息传给个推统计
    [GeTuiSdk handleRemoteNotification:userInfo];
    
    // 根据APP需要，判断是否要提示用户Badge、Sound、Alert
//    completionHandler(UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionAlert);
}

//  iOS 10: 点击通知进入App时触发，在该方法内统计有效用户点击数
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler {
    
    WXLogInfo(@"didReceiveNotification：%@", response.notification.request.content.userInfo);
    
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    
    [self analysisRemoteNotification:userInfo];
    
    // [ GTSdk ]：将收到的APNs信息传给个推统计
    [GeTuiSdk handleRemoteNotification:userInfo];
    
    completionHandler();
}

#endif

#pragma mark - Public Method

- (void)configPushService:(NSDictionary *)info
{
    [GeTuiSdk startSdkWithAppId:info[@"appId"]?:@""
                         appKey:info[@"appKey"]?:@""
                      appSecret:info[@"appSecret"]?:@""
                       delegate:self];
    
//    [GeTuiSdk runBackgroundEnable:YES];
    
    [self registerRemoteNotification];
}

+ (void)registerForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    NSString *token = [self hexadecimalString:deviceToken];
    [BMPushMessageManager shareInstance]->_deviceToken = [token stringByReplacingOccurrencesOfString:@" " withString:@""];
    WXLogInfo(@"deviceToken:%@", [BMPushMessageManager shareInstance]->_deviceToken);
    
    // [3]:向个推服务器注册deviceToken
    [GeTuiSdk registerDeviceToken:[BMPushMessageManager shareInstance]->_deviceToken];
}

+ (NSString *)hexadecimalString:(NSData *)data 
{
    const unsigned char *dataBuffer = (const unsigned char *)[data bytes];

    if (!dataBuffer) {
        return [NSString string];
    }

    NSUInteger dataLength  = [data length];
    NSMutableString *hexString  = [NSMutableString stringWithCapacity:(dataLength * 2)];

    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", (unsigned int)dataBuffer[i]];
    }

    return [NSString stringWithString:hexString];
}

+ (void)performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    [GeTuiSdk resume];
    completionHandler(UIBackgroundFetchResultNewData);
}

+ (void)receiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    [[BMPushMessageManager shareInstance] analysisRemoteNotification:userInfo];
    
    // 将收到的APNs信息传给个推统计
    [GeTuiSdk handleRemoteNotification:userInfo];
    completionHandler(UIBackgroundFetchResultNewData);
}

+ (NSString *)getCid
{
    return [BMPushMessageManager shareInstance]->_cid;
}

+ (void)addPushNotification:(NSDictionary *)pushMessage
{
    [BMPushMessageManager shareInstance]->_pushMessage = pushMessage;
    
    [[NSNotificationCenter defaultCenter] addObserver:[BMPushMessageManager shareInstance] selector:@selector(firstScreenDidFinished:) name:BMFirstScreenDidFinish object:nil];
}

@end