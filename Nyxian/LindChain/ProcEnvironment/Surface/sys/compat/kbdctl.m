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
    
    sys_need_in_ports(1, MACH_MSG_TYPE_MOVE_SEND);
    
    fileport_t port = sys_in_ports[0];
    
    int fd = fileport_makefd(port);
    if(fd < 0)
    {
        sys_return_failure(EBADF);
    }
    
    struct stat fd_stat;
    if(fstat(fd, &fd_stat) != 0)
    {
        close(fd);
        sys_return_failure(EBADF);
    }
    
    if(!S_ISSOCK(fd_stat.st_mode))
    {
        close(fd);
        sys_return_failure(ENOTSOCK);
    }
    
    int optval;
    socklen_t optlen = sizeof(optval);
    if(getsockopt(fd, SOL_SOCKET, SO_TYPE, &optval, &optlen) != 0)
    {
        close(fd);
        sys_return_failure(ENOTSOCK);
    }
    
    klog_log("kbdctl", "trigger pulled! ;3");
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NXWindowServer shared] registerClientKeyboardDescriptor:fd];
    });
    
    sys_return;
}
