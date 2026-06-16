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

#import <UIKit/UIKit.h>

#import <LindChain/ProcEnvironment/kbdportal.h>
#import <LindChain/Utils/Swizzle.h>

/* MARK: THIS IS A EXPERIMENTAL FIX FOR THE IOS27 KEYBOARD ISSUE */

@implementation UIResponder (ProcEnvironment)

- (BOOL)hook_becomeFirstResponder {
    if([self isKindOfClass:[UITextField class]] || [self isKindOfClass:[UITextView class]])
    {
        /* as a test */
        exit(0);
    }

    return [self hook_becomeFirstResponder];
}

@end

void environment_kbdportal_init(void)
{
    swizzle_objc_method(@selector(becomeFirstResponder), [UIResponder class], @selector(hook_becomeFirstResponder), nil);
}
