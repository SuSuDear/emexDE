/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.
*/

#import <LindChain/ProcEnvironment/Surface/surface.h>

static BOOL NXIsValidHostname(NSString *hostname)
{
    if(hostname.length == 0 || hostname.length > 253)
    {
        return NO;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-."];
    return [hostname rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}

int ksurface_sethostname(NSString *hostname)
{
    if(hostname == nil || !NXIsValidHostname(hostname))
    {
        return -1;
    }

    [NSUserDefaults.standardUserDefaults setObject:hostname forKey:@"LDEHostname"];
    return 0;
}

void ksurface_kinit(void)
{
}
