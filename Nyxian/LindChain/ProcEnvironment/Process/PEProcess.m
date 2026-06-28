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

#import <LindChain/ProcEnvironment/Process/PEProcess.h>
#import <LindChain/ProcEnvironment/Process/PEProcessManager.h>
#import <LindChain/WindowServer/NXWindowServer.h>
#import <LindChain/ProcEnvironment/Utils/klog.h>

#import <LindChain/Services/containerd/PEContainer.h>
#import <LindChain/ProcEnvironment/Process/PEExtension.h>
#import <LindChain/ProcEnvironment/Syscall/mach_syscall_client.h>
#import <LindChain/ProcEnvironment/Object/PEMachPort.h>
#import <LindChain/ProcEnvironment/Server/Server.h>
#import <LindChain/ProcEnvironment/Surface/proc/counter.h>

@implementation PEProcess {
    dispatch_once_t _notifyWindowManagerOnce;
}

@dynamic pid;

- (instancetype)initWithItems:(NSDictionary*)items
     withKernelSurfaceProcess:(ksurface_proc_t*)proc
{
    if(!proc_count())
    {
        return nil;
    }

    self = [super init];

    self.executablePath = items[@"PEExecutablePath"];
    if(self.executablePath == nil)
    {
        return nil;
    }
    /* FIXME: before it was a isExecutableFileAtPath check, but since installd broke the permissions at install time we can forget that lol */
    if(![[PEContainer shared] isReadableFileAtPath:self.executablePath]) return nil;

    self.wid = (id_t)-1;

    NSString *potentialBundlePath = [self.executablePath stringByDeletingLastPathComponent];
    NSBundle *bundle = [NSBundle bundleWithURL:[NSURL fileURLWithPath:potentialBundlePath]];
    if(bundle == nil)
    {
        return nil;
    }

    self.bundleIdentifier = bundle.bundleIdentifier;
    NSString *localizedDisplayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if(!localizedDisplayName)
    {
        localizedDisplayName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    }
    self.displayName = localizedDisplayName ?: [self.executablePath lastPathComponent];

    __weak typeof(self) weakSelf = self;

    /* spawning process */
    self.process = PESpawnFBProcess(items);
    if(self.process == nil)
    {
        return nil;
    }

    [self.process addObserver:self];
    if(!self.process.running)
    {
        /*
         * prevents a race condition, when we add a observer
         * and it already died then we shall handle the exit.
         */
        FBProcessManager *manager = [PrivClass(FBProcessManager) sharedInstance];
        [manager _removeProcess:self.process];
        return nil;
    }

    ksurface_proc_t *child = proc_fork(proc, self.pid, [self.executablePath UTF8String]);
    if(child == NULL)
    {
        [self terminate];
        return nil;
    }
    else
    {
        self.proc = child;
    }

    return self;
}

- (void)sendSignal:(int)signal
{
    /*
     * those signals are not supported at all
     * (for now atleast).
     */
    if(signal == SIGTTIN ||
       signal == SIGTTOU)
    {
        return;
    }

    /*
     * for some reason apple doesnt support SIGTSTP on iOS
     * (maybe we just use it wrong lol)
     */
    if(signal == SIGTSTP)
    {
        signal = SIGSTOP;
    }

    if(signal == SIGSTOP)
    {
        _isSuspended = YES;
    }
    else if(signal == SIGCONT)
    {
        _isSuspended = NO;
    }

    [self.process.nsExtension _kill:signal];

    if(signal == SIGSTOP)
    {
        kvo_wrlock(_proc);
        _proc->bsd.kp_proc.p_stat = SSTOP;

        goto report_signal;
    }
    else if(signal == SIGCONT)
    {
        kvo_wrlock(_proc);
        _proc->bsd.kp_proc.p_stat = SRUN;

    report_signal:
        kvo_unlock(_proc);
        proc_state_change(_proc, W_STOPCODE(signal));
    }
}

- (BOOL)terminate
{
    [self sendSignal:SIGKILL];
    return YES;
}

- (void)setExitingCallback:(void(^)(void))callback
{
    _exitingCallback = callback;
}

- (void)processDidExit:(FBProcess *)arg1
{
    if(self.proc != NULL)
    {
        /* yep writing official wait4 code~~ */
        proc_state_change(self.proc, arg1.exitContext.underlyingContext.legacyCode);
        kern_return_t error = proc_zombify(self.proc);
        if(error != KERN_SUCCESS)
        {
            klog_log("LDEProcess", "failed to remove pid %d", self.pid);
        }
    }
    if(self.exitingCallback) self.exitingCallback();

    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.wid != -1)
        {
            [[NXWindowServer shared] closeWindowWithIdentifier:self.wid withCompletion:nil];
        }
    });

    [[PEProcessManager shared] unregisterProcessWithProcessIdentifier:self.pid];
}

- (void)processWillExit:(FBProcess *)arg1
{
    /* stub for when ever */
}

- (void)process:(FBProcess *)arg1 stateDidChangeFromState:(FBProcessState *)arg2 toState:(FBProcessState *)arg3
{
    /* stub for when ever */
}

- (void)processManager:(FBProcessManager *)arg1 didAddProcess:(FBProcess *)arg2
{
    [arg2 addObserver:self];
}

- (void)processManager:(FBProcessManager *)arg1 didRemoveProcess:(FBProcess *)arg2
{
    [arg2 removeObserver:self];
    [arg1 removeObserver:self];
}

- (id)forwardingTargetForSelector:(SEL)sel
{
    /* redirecting for pid */
    if([self.process respondsToSelector:sel])
    {
        return self.process;
    }
    return [super forwardingTargetForSelector:sel];
}

- (void)dealloc
{
    if(_proc != NULL)
    {
        kvo_release(_proc);
    }
    proc_uncount();
}

@end
