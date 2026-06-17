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

#include <LindChain/ProcEnvironment/Surface/sys/compat/kbdctl.h>

#include <LindChain/Private/mach/fileport.h>

#include <LindChain/ProcEnvironment/Utils/klog.h>

#import <LindChain/WindowServer/NXWindowServer.h>

#include <sys/socket.h>
#include <sys/stat.h>

DEFINE_SYSCALL_HANDLER(kbdctl)
{
    if(!@available(iOS 27.0, *))
    {
        sys_return_failure(ENOSYS);
    }
    
    klog_log("kbdctl", "process %d pawed at me grrr >:3", proc_getpid(sys_proc_snapshot_));
    
    kvo_wrlock(sys_proc_);
    
    /*
     * validating if we got a file descriptor,
     * if not the client wants to invalidate
     * it's focus.
     */
    if(in_ports.address == VM_MIN_ADDRESS ||
       in_ports.count < 1 ||
       in_ports.disposition != MACH_MSG_TYPE_MOVE_SEND)
    {
        klog_log("kbdctl", "wants to invalidate da portal huh :3");
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[NXWindowServer shared] unregisterClientKeyboardDescriptorWithProcessIdentifier:proc_getpid(sys_proc_)];
        });
        kvo_unlock(sys_proc_);
        sys_return;
    }
    else
    {
        klog_log("kbdctl", "received mach port");
    }
    
    /* validate received file descriptor */
    int fd = fileport_makefd(sys_in_ports[0]);
    if(fd < 0)
    {
        kvo_unlock(sys_proc_);
        sys_return_failure(EBADF);
    }
    
    struct stat fd_stat;
    if(fstat(fd, &fd_stat) != 0)
    {
        close(fd);
        kvo_unlock(sys_proc_);
        sys_return_failure(EBADF);
    }
    
    if(!S_ISSOCK(fd_stat.st_mode))
    {
        close(fd);
        kvo_unlock(sys_proc_);
        sys_return_failure(ENOTSOCK);
    }
    
    int optval;
    socklen_t optlen = sizeof(optval);
    if(getsockopt(fd, SOL_SOCKET, SO_TYPE, &optval, &optlen) != 0)
    {
        close(fd);
        kvo_unlock(sys_proc_);
        sys_return_failure(ENOTSOCK);
    }
    
    /* registering portal */
    klog_log("kbdctl", "trigger pulled! portal registered, meow. ;3");
    
    dispatch_sync(dispatch_get_main_queue(), ^{
        [[NXWindowServer shared] registerClientKeyboardDescriptor:fd processIdentifier:proc_getpid(sys_proc_)];
    });
    kvo_unlock(sys_proc_);
    sys_return;
}
