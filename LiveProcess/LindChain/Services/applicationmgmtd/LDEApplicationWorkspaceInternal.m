/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#import "LDEApplicationWorkspaceInternal.h"
#import <LindChain/ProcEnvironment/environment.h>
#import <LindChain/ProcEnvironment/syscall.h>
#import <LindChain/Utils/Zip.h>
#import <Security/Security.h>
#import <LindChain/ProcEnvironment/Object/FDMapObject.h>
#import <LindChain/Services/applicationmgmtd/LDEApplicationWorkspaceProtocol.h>
#import <LindChain/LiveContainer/LCMachOUtils.h>

@interface LDEApplicationWorkspaceInternal ()

@property (nonatomic,strong) NSURL *applicationsURL;
@property (nonatomic,strong) NSURL *containersURL;
@property (nonatomic,strong) NSURL *binaryURL;
@property (nonatomic,strong) NSURL *homeURL;
@property (nonatomic, strong) dispatch_queue_t workspaceQueue;

@end

@implementation LDEApplicationWorkspaceInternal

- (instancetype)init
{
    self = [super init];
    
    // Setting up paths
    NSString *documentsDir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    self.applicationsURL = [NSURL fileURLWithPath:[documentsDir stringByAppendingPathComponent:@"Bundle/Application"]];
    self.containersURL   = [NSURL fileURLWithPath:[documentsDir stringByAppendingPathComponent:@"Data/Application"]];
    self.binaryURL   = [NSURL fileURLWithPath:[documentsDir stringByAppendingPathComponent:@"usr/bin"]];
    self.homeURL = [NSURL fileURLWithPath:[documentsDir stringByAppendingPathComponent:@"var/mobile"]];
    
    // Creating paths if they dont exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:self.applicationsURL.path])
        [fileManager createDirectoryAtURL:self.applicationsURL
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:nil];
    
    if(![fileManager fileExistsAtPath:self.containersURL.path])
        [fileManager createDirectoryAtURL:self.containersURL
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:nil];
    
    if(![fileManager fileExistsAtPath:self.binaryURL.path])
        [fileManager createDirectoryAtURL:self.binaryURL
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:nil];
    
    if(![fileManager fileExistsAtPath:self.homeURL.path])
        [fileManager createDirectoryAtURL:self.homeURL
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:nil];
    
    // Enumerating all app bundles
    NSArray<NSURL*> *uuidURLs = [fileManager contentsOfDirectoryAtURL:self.applicationsURL includingPropertiesForKeys:nil options:0 error:nil];
    self.bundles = [[NSMutableDictionary alloc] init];
    for(NSURL *uuidURL in uuidURLs)
    {
        NSArray<NSString *> *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[uuidURL path] error:nil];

        for(NSString *item in contents)
        {
            if([[item pathExtension] isEqualToString:@"app"])
            {
                NSString *fullPath = [[uuidURL path] stringByAppendingPathComponent:item];
                NSBundle *bundle = [NSBundle bundleWithPath:fullPath];
                [self.bundles setObject:bundle forKey:bundle.bundleIdentifier];
            }
            else
            {
                /* what the user cant manage the user cant manage */
                [[NSFileManager defaultManager] removeItemAtURL:uuidURL error:nil];
            }
        }
    }
    
    self.workspaceQueue = dispatch_queue_create("com.cr4zy.installd.workspace", DISPATCH_QUEUE_SERIAL);
    
    return self;
}

+ (LDEApplicationWorkspaceInternal*)shared
{
    static LDEApplicationWorkspaceInternal *applicationWorkspaceSingleton = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        applicationWorkspaceSingleton = [[LDEApplicationWorkspaceInternal alloc] init];
    });
    return applicationWorkspaceSingleton;
}

/*
 Action
 */
- (BOOL)doWeTrustThatBundle:(NSBundle*)bundle
{
    /*
     * checking for obvious thing lol, and checking for
     * info dictionary, every iOS app needs to have one.
     */
    if(bundle == nil ||
       bundle.infoDictionary == nil)
    {
        return NO;
    }
    
    /* checking if needed info keys exist */
    if(bundle.infoDictionary[@"CFBundleExecutable"] == nil ||
       bundle.infoDictionary[@"CFBundleIdentifier"] == nil)
    {
        return NO;
    }
    
    /* checking if info keys match the correct class type */
    if(![bundle.infoDictionary[@"CFBundleExecutable"] isKindOfClass:[NSString class]] ||
       ![bundle.infoDictionary[@"CFBundleIdentifier"] isKindOfClass:[NSString class]])
    {
        return NO;
    }
    
    /* now extracting key values */
    NSString *bundleIdentifier = bundle.infoDictionary[@"CFBundleIdentifier"];
    NSString *minimumVersion = bundle.infoDictionary[@"MinimumOSVersion"];
    
    /* executable path validation */
    NSString *executableName = bundle.infoDictionary[@"CFBundleExecutable"];
    NSString *lastPathComponent = bundle.executableURL.lastPathComponent;

    if(lastPathComponent == nil ||
       ![executableName isEqualToString:lastPathComponent] ||
       ![[NSFileManager defaultManager] isReadableFileAtPath:bundle.executablePath])
    {
        return NO;
    }
    
    /* code signature check */
    LCMachO *machO = LCMapMachO([bundle.executablePath UTF8String], true);
    bool cs_valid = LCCheckCodeSignature(machO);
    LCUnmapMachO(machO);
    if(!cs_valid)
    {
        return NO;
    }
    
    /* bundle identifier validation */
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z][a-zA-Z0-9-]*(\\.[a-zA-Z0-9-]+)+$" options:0 error:nil];

    if(regex == nil)
    {
        return NO;
    }

    NSUInteger matches = [regex numberOfMatchesInString:bundleIdentifier options:0 range:NSMakeRange(0, bundleIdentifier.length)];

    if(matches == 0)
    {
        return NO;
    }
    
    /* minimum version validation */
    if(bundle.infoDictionary[@"MinimumOSVersion"] == nil &&
       ![bundle.infoDictionary[@"MinimumOSVersion"] isKindOfClass:[NSString class]])
    {
        /* some apps like cocoatop dont have that key */
        return YES;
    }
    
    NSArray *components = [minimumVersion componentsSeparatedByString:@"."];
    
    if(components == nil)
    {
        return NO;
    }
    
    NSOperatingSystemVersion requiredVersion = {
        components.count > 0 ? [components[0] integerValue] : 0,
        components.count > 1 ? [components[1] integerValue] : 0,
        components.count > 2 ? [components[2] integerValue] : 0
    };

    if(![[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:requiredVersion])
    {
        return NO;
    }
    
    return YES;
}

- (NSBundle*)applicationBundleForBundleID:(NSString *)bundleID
{
    __block NSBundle *result = nil;
    dispatch_sync(self.workspaceQueue, ^{
        result = [self.bundles objectForKey:bundleID];
    });
    return result;
}

@end

@implementation LDEApplicationWorkspaceProxy

- (void)ping
{
    return;
}

- (void)utilityHomePathWithReply:(void (^)(NSString*))reply
{
    NSString *homePath = [NSHomeDirectory() stringByAppendingPathComponent:@"/Documents/var/mobile"];
    
    NSURL *homeURL = [NSURL fileURLWithPath:homePath];
    
    if(homeURL == nil)
    {
        reply(nil);
        return;
    }
    
    /* checking if homepath is indeed existing */
    BOOL isDirectory = NO;
    if(![[NSFileManager defaultManager] fileExistsAtPath:[homeURL path] isDirectory:&isDirectory])
create_home:
    {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtURL:homeURL withIntermediateDirectories:YES attributes:nil error:&error];
        
        if(error != nil)
        {
            reply(nil);
            return;
        }
        
        /* bootstrapping home path */
        [[NSFileManager defaultManager] createDirectoryAtURL:[homeURL URLByAppendingPathComponent:@"Tmp"] withIntermediateDirectories:YES attributes:nil error:&error];
        
        if(error != nil)
        {
            [[NSFileManager defaultManager] removeItemAtURL:homeURL error:nil];
            reply(nil);
            return;
        }
    }
    else
    {
        /* it shall only be a directory */
        if(!isDirectory)
        {
            [[NSFileManager defaultManager] removeItemAtURL:homeURL error:nil];
            goto create_home;
        }
    }
    
    reply(homePath);
}

- (void)applicationObjectForBundleID:(NSString *)bundleID
                           withReply:(void (^)(LDEApplicationObject *))reply
{
    NSBundle *bundle = [[LDEApplicationWorkspaceInternal shared] applicationBundleForBundleID:bundleID];
    
    if(!bundle)
    {
        reply(nil);
        return;
    }
    
    reply([[LDEApplicationObject alloc] initWithNSBundle:bundle]);
}

- (void)fastpathUtility:(FDObject*)object
               withName:(NSString*)name
              withReply:(void (^)(NSString*,BOOL))reply;
{
    // Write out
    NSString *fastPath = [[[[LDEApplicationWorkspaceInternal shared] binaryURL] path] stringByAppendingPathComponent:name];
    [object writeOut:[[[[LDEApplicationWorkspaceInternal shared] binaryURL] path] stringByAppendingPathComponent:name]];
    void refreshFile(const char* path);
    refreshFile(fastPath.fileSystemRepresentation);
    LCMachO *machO = LCMapMachO(fastPath.fileSystemRepresentation, true);
    bool cs_valid = LCCheckCodeSignature(machO);
    LCUnmapMachO(machO);
    if(!cs_valid)
    {
        [[NSFileManager defaultManager] removeItemAtPath:fastPath error:nil];
    }
    reply(fastPath, cs_valid);
}

- (void)applicationObjectForExecutablePath:(NSString*)executablePath
                                 withReply:(void (^)(LDEApplicationObject*))reply
{
    NSString *potentialBundlePath = [executablePath stringByDeletingLastPathComponent];
    NSBundle *bundle = [NSBundle bundleWithURL:[NSURL fileURLWithPath:potentialBundlePath]];
    if(bundle == nil)
    {
        reply(nil);
        return;
    }
    
    LDEApplicationObject *application = [[LDEApplicationObject alloc] initWithNSBundle:bundle];
    reply(application);
}

+ (NSString*)servcieIdentifier
{
    return @"com.cr4zy.installd";
}

+ (Protocol*)serviceProtocol
{
    return @protocol(LDEApplicationWorkspaceProxyProtocol);
}

+ (Protocol *)observerProtocol { 
    return @protocol(LDEApplicationWorkspaceProtocol);
}

@end
