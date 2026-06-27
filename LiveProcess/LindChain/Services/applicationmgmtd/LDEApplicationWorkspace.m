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

#import "LDEApplicationWorkspace.h"
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <LindChain/ProcEnvironment/Process/PELaunchServiceRegistry.h>

@implementation LDEApplicationWorkspace

- (instancetype)init
{
    return [super init];
}

+ (instancetype)shared
{
    static LDEApplicationWorkspace *applicationWorkspaceSingleton = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        applicationWorkspaceSingleton = [[LDEApplicationWorkspace alloc] init];
    });
    return applicationWorkspaceSingleton;
}

- (BOOL)connect
{
    if(self.connection)
    {
        return YES;
    }
    
    __weak typeof(self) weakSelf = self;
    _connection = nil;
    PELaunchServiceRegistry *serviceRegistry = [PELaunchServiceRegistry shared];
    
    if(serviceRegistry != nil)
    {
        _connection = [serviceRegistry connectToService:@"com.cr4zy.installd" protocol:@protocol(LDEApplicationWorkspaceProxyProtocol) observer:nil observerProtocol:nil];
        _connection.invalidationHandler = ^{
            __strong typeof(self) strongSelf = weakSelf;
            if(!strongSelf) return;
            strongSelf.connection = nil;
        };
        
        return _connection != nil;
    }
    
    return NO;
}

- (void)ping
{
    [self connect];
    
    [_connection.remoteObjectProxy ping];
}

- (NSString*)fastpathUtility:(NSString*)utilityPath
{
    [self connect];
    
    __block NSString *fastpath = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy fastpathUtility:[FDObject objectForFileAtPath:utilityPath] withName:[utilityPath lastPathComponent] withReply:^(NSString *fastPathRet, BOOL fastSigned){
            fastpath = fastSigned ? fastPathRet : nil;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return fastpath;
}

- (NSString*)utilityHomePath
{
    [self connect];
    
    __block NSString *utilityHomePath = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    id proxy = [_connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }];
    
    if(proxy == NULL)
    {
        /* semaphores remember the signal, it doesnt have to catch them in time */
        dispatch_semaphore_signal(sema);
    }
    else
    {
        [_connection.remoteObjectProxy utilityHomePathWithReply:^(NSString *reply){
            utilityHomePath = reply;
            dispatch_semaphore_signal(sema);
        }];
    }
    
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
    return utilityHomePath;
}

@end
